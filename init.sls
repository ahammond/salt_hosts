#!pydsl

from logging import getLogger

try:
    from ipaddress import IPv4Address
except ImportError:
    from salt.util.socket_util import IPv4Address

TIMEOUT = 35


class ReceiptIPv4(IPv4Address):
  @property
  def is_vpn(self):
    return IPv4Address(u'10.8.0.0') <= self <= IPv4Address(u'10.8.255.255')

l = getLogger('hosts')


datacenters = __salt__['publish.publish']('*', 'grains.item', 'datacenter', 'glob', TIMEOUT)
l.debug('datacenters: %r', datacenters)
ip_addrs = __salt__['publish.publish']('*', 'network.ip_addrs', '', 'glob', TIMEOUT)
l.debug('ip_addrs: %r', ip_addrs)

localhost = __grains__['id']
localhost_ip6 = '{0}_ip6'.format(localhost)
local_datacenter = __grains__['datacenter']
localhost_additional_names = __pillar__.get('hosts', {}).get(localhost, {}).get('names', [])

l.debug('localhost: %s, datacenter: %s', localhost, local_datacenter)

# we'll handle localhost as a special case
if localhost in ip_addrs:
    del ip_addrs[localhost]

if localhost in datacenters:
    del datacenters[localhost]

state(localhost).host.present(ip='127.0.0.1')
local_names = ['localhost', 'localhost.localdomain']
local_names.extend(localhost_additional_names)
state('localhost')\
    .host.present(
        ip='127.0.0.1',
        names=local_names)\
    .require(host=localhost)

# IPv6 localhost information
state(localhost_ip6).host.present(ip='::1', names=(localhost,))
local_names_ip6 = ['ip6-localhost', 'ip6-loopback']
local_names_ip6.extend(localhost_additional_names)
state('localhost_ip6')\
    .host.present(
        ip='::1',
        names=local_names_ip6)\
    .require(host=localhost_ip6)

# Apparently these are good to have on IPv6 capable hosts.
state('ip6-localnet').host.present(ip='fe00::0')
state('ip6-mcastprefix').host.present(ip='ff00::0')
state('ip6-allnodes').host.present(ip='ff02::1')
state('ip6-allrouters').host.present(ip='ff02::2')

# include name references for all the other ips that belong to this host.
counter = 0
for extra_ip in __grains__.get('ipv4', []):
    counter += 1
    state('localhost_{}'.format(counter))\
        .host.present(
            ip=extra_ip,
            names=local_name)\
        .require(host='localhost')

for hostname in sorted(ip_addrs.keys()):
    l.info('setting hostname for %s', hostname)
    # Start by assuming we don't have any IPs, provide almost useless Link Local addresses.
    public_ips = [IPv4Address(u'169.254.0.1'),]
    # And don't include _any_ other ips until we get some
    private_ips = []
    vpn_ips = []
    for ip in sorted([ReceiptIPv4(unicode(x)) for x in ip_addrs.get(hostname, [])]):
        if ip.is_vpn:
            vpn_ips.append(ip)
        elif ip.is_private:
            private_ips.append(ip)
        else:
            public_ips.append(ip)

    l.debug('public_ips: %r', public_ips)
    l.debug('private_ips: %r', private_ips)
    l.debug('vpn_ips: %r', vpn_ips)

    other_datacenter = datacenters.get(hostname, {}).get('datacenter', None)
    l.debug('datacenter: %r', other_datacenter)
    if local_datacenter == other_datacenter:
        l.debug('local: %r == other: %r', local_datacenter, other_datacenter)
        localized_ip = private_ips.pop() if private_ips else public_ips.pop()
    else:
        l.debug('local: %r != other: %r', local_datacenter, other_datacenter)
        localized_ip = vpn_ips.pop() if vpn_ips else public_ips.pop()
    l.debug('localized_ip: %s', hostname, localized_ip)

    names = [hostname, ]
    names.extend(__pillar__.get('hosts', {}).get(hostname, {}).get('names', []))
    names.reverse()
    l.info('setting %s -> %r', localized_ip, names)
    state(hostname)\
        .host.present(
            ip=str(localized_ip),
            names=names)\
        .require(host=localhost)

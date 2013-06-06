#!pydsl

from itertools import chain
from logging import getLogger

try:
    from ipaddress import IPv4Address
except ImportError:
    from salt.utils.socket_util import IPv4Address

TIMEOUT = 10


class ReceiptIPv4(IPv4Address):
    @property
    def is_vpn(self):
        return IPv4Address(u'10.8.0.0') <= self <= IPv4Address(u'10.8.255.255')

l = getLogger('hosts')

datacenters = __salt__['publish.publish']('*', 'grains.item', 'datacenter', 'glob', TIMEOUT)
ip_addrs = __salt__['publish.publish']('*', 'network.ip_addrs', '', 'glob', TIMEOUT)

l.info('hosts responding for grains.items: {0}, network.ip_addrs: {1}'.format(len(datacenters), len(ip_addrs)))

datacenter_keys = datacenters.keys()
ip_addr_keys = ip_addrs.keys()

in_dc_but_not_addr = [ x for x in datacenter_keys if x not in ip_addr_keys ]
in_addr_but_not_dc = [ x for x in ip_addr_keys if x not in datacenter_keys ]

if in_dc_but_not_addr:
    l.error('in grains.item but not network.ip_addrs: %r', in_dc_but_not_addr)
if in_addr_but_not_dc:
    l.error('in network.ip_addrs but not grains.item: %r', in_addr_but_not_dc)

localhost = __grains__['id']
localhost_ip6 = '{0}_ip6'.format(localhost)
local_datacenter = __grains__['datacenter']
link_local_address = ReceiptIPv4(u'169.254.0.1')
localhost_additional_names = __pillar__.get('hosts', {}).get(localhost, {}).get('names', [])

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

for hostname in sorted(ip_addrs.keys()):
    l.info('setting hostname for %s', hostname)
    # Start by assuming we don't have any IPs, provide almost useless Link Local addresses.
    public_ips = [link_local_address,]
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

    # decide which ip is appropriate to use.
    # if the host minion is in the same datacenter as the minion we're considering,
    # then we should prefer a private ip, if there is one available.
    # otherwise, we should prefer a vpn ip, if there is one available.
    # in general a public ip is least desirable because it usually means
    # paying for the traffic used.
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
l.debug('completed')

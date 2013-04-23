#!pydsl

from logging import getLogger

try:
    from ipaddress import IPv4Address
except ImportError:
    from salt.util.socket_util import IPv4Address

TIMEOUT = 5


class ReceiptIPv4(IPv4Address):
  @property
  def is_vpn(self):
    return IPv4Address(u'10.8.0.0') <= self <= IPv4Address(u'10.8.255.255')

l = getLogger('hosts')

datacenters = __salt__['publish.publish']('*', 'grains.item', 'datacenter', 'glob', TIMEOUT)
l.debug('datacenters: %r', datacenters)
ip_addrs = __salt__['publish.publish']('*', 'network.ip_addrs', '', 'glob', TIMEOUT)
l.debug('ip_addrs: %r', ip_addrs)

localhost = __grains__['localhost']
local_datacenter = __grains__['datacenter']

local_names = [localhost, 'localhost', 'localhost.localdomain']
local_names.extend(__pillar__.get('hosts', {}).get(localhost, {}).get('names', []))
state(localhost).host.present(
  ip='127.0.0.1',
  names=local_names
)

for hostname in sorted(ip_addrs.keys()):
    if localhost == hostname:
        next
    l.info('setting hostname for %s', hostname)
    # Start by assuming we don't have any public or private IPs
    # so, instead provide almost useless Link Local addresses.
    public_ips = [IPv4Address(u'169.254.0.1'),]
    private_ips = [IPv4Address(u'169.254.0.1'),]
    # And don't include _any_ VPN ips until we get some
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

    if local_datacenter == datacenters.get(hostname, None):
        localized_ip = private_ips.pop()
    else:
        localized_ip = vpn_ips.pop() if vpn_ips else public_ips.pop()
    l.debug('localized_ip: %s', hostname, localized_ip)

    names = [hostname, ]
    names.extend(__pillar__.get('hosts', {}).get(hostname, {}).get('names', []))
    l.info('setting %s -> %r', localized_ip, names)
    state(hostname).host.present(
        ip=str(localized_ip),
        names=names
    )

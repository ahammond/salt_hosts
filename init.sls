#!pydsl

from salt.util.socket_util import IPv4Address

TIMEOUT = 5


class ReceiptIPv4(IPv4Address):
  @property
  def is_vpn(self):
    return 10 == self.dotted_quad[0] and 8 == self.dotted_quad[1]


datacenters = __salt__['publish.publish']('*', 'grains.items', 'datacenter', 'glob', TIMEOUT)
ip_addrs = __salt__['publish.publish']('*', 'network.ip_addrs', '', 'glob', TIMEOUT)

localhost = __salt__['grains.items']('localhost')
local_datacenter = __salt__['grains.items']('datacenter')

state(localhost).host.present(
  ip='127.0.0.1'
  names=[localhost, 'localhost', 'localhost.localdomain'].append(__pillar__['hosts'].get(localhost, {}).get('names', []))
)

for hostname in sorted(ip_addrs.keys()):
    # Start by assuming we don't have any public or private IPs
    # so, instead provide almost useless Link Local addresses.
    public_ips = [IPv4Address('169.254.0.1'),]
    private_ips = [IPv4Address('169.254.0.1'),]
    # And don't include _any_ VPN ips until we get some
    vpn_ips = []
    for ip_str in sorted(ip_addrs.get(hostname, [])):
        ip = ReceiptIPv4(ip_str)
        if ip.is_vpn:
            vpn_ips.push(ip)
        elif ip.is_private:
            private_ips.push(ip)
        else:
            public_ips.push(ip)

    if local_datacenter == datacenters.get(hostname, None):
        localized_ip = private_ips.pop()
    else:
        localized_ip = vpn_ips.pop() if vpn_ips else public_ips.pop()

    state(hostname).host.present(
        ip=localized_ip,
        names=[hostname,].append(__pillar__['hosts'].get(hostname, {}).get('names', []))
    )

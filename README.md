hosts
=====

This state is intended to manage the /etc/hosts file on servers.

It is datacenter aware and will attempt to route data between servers in
the same datacenter via non-routeable IPs. For servers in different
datacenters, it will perfer a VPN IP (this is currently SmartReceipt
specific, but could probably be generalized), but will default to a
public / routeable IP.

The idea here is to avoid paying for metered traffic in cloud environments
by using the "back-channel" networks for inter-server communication.

There is rudimentary IPv6 support, but it has a way to go.

Environment
-----------

### grains

On each server, you should set a datacenter grain. For example:

```
datacenter: rackspace
```

Servers in the same datacenter should have the same grain.
Servers in different datacenters should have different grains.
If you don't set the datacenter grain, then this state will assume that all
your servers are in the same datacenter.

### pillars

This state assigns the salt id for the server as it's primary name.
It will assign additional names to server based on the hosts.names.
So, to add the names `mail` and `repo` on server `foo`, you would configure
your `hosts.sls` pillar as follows:

```yaml
hosts:
  foo:
    names:
      - mail
      - repo
```


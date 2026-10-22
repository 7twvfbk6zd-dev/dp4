#!/bin/sh
set -eu

# DS4 runs with hostNetwork and listens on 0.0.0.0:18080. Allow only the
# cluster pod network and the node itself; drop every other source so all
# external traffic has to go through the New API gateway on NodePort 30300.

del() {
    while iptables -D INPUT "$@" 2>/dev/null; do :; done
}

del -p tcp --dport 18080 -s 10.244.0.0/16 -j ACCEPT
del -p tcp --dport 18080 -s 127.0.0.1 -j ACCEPT
del -p tcp --dport 18080 -s 192.168.5.170 -j ACCEPT
del -p tcp --dport 18080 -s 172.16.0.168 -j ACCEPT
del -p tcp --dport 18080 -j DROP

# Insert in reverse order so the final INPUT order is: allow, allow, allow,
# allow, drop.
iptables -I INPUT 1 -p tcp --dport 18080 -j DROP
iptables -I INPUT 1 -p tcp --dport 18080 -s 172.16.0.168 -j ACCEPT
iptables -I INPUT 1 -p tcp --dport 18080 -s 192.168.5.170 -j ACCEPT
iptables -I INPUT 1 -p tcp --dport 18080 -s 127.0.0.1 -j ACCEPT
iptables -I INPUT 1 -p tcp --dport 18080 -s 10.244.0.0/16 -j ACCEPT
#!/system/bin/sh

iptables -I FORWARD -i ot0 -j ACCEPT
iptables -I FORWARD -o ot0 -j ACCEPT
iptables -I INPUT -i ot0 -j ACCEPT
iptables -I OUTPUT -o ot0 -j ACCEPT
iptables -t mangle -I PREROUTING -i ot0 -j MARK --set-mark 0x1001
iptables -t nat -I POSTROUTING -m mark --mark 0x1001 -j MASQUERADE


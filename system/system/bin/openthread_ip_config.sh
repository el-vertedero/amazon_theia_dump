#!/system/bin/sh

IF_ID=$(ip link show wlan0 | grep -Eo '^[0-9]+:' | tr -d ':')
WLAN_TABLE_ID=$(expr $IF_ID + 1000)
ip -6 rule add from all iif lo lookup 100 priority 10300
ip -6 rule add from all iif wlan0 lookup 100 priority 10200
ip -6 rule add from all iif ot0 lookup $WLAN_TABLE_ID priority 10400
ip6tables -P FORWARD DROP
ip6tables -A FORWARD -i ot0 -j ACCEPT
ip6tables -A FORWARD -o ot0 -j ACCEPT
ip6tables -A INPUT -i ot0 -j ACCEPT
ip6tables -A OUTPUT -o ot0 -j ACCEPT

# Configure firewall for NAT64
ip -4 rule add from all iif wlan0 lookup 100 priority 10200
ip -4 rule add from all iif ot0 lookup $WLAN_TABLE_ID priority 10400


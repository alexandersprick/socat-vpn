#!/bin/bash

# Connect to a socat server and attach to a TUN interface to create a simple VPN
# see socat-vpn-server.sh for the server side

# The VPN server address
VPN_SERVER=my.socat.vpn.server.com

# The IP addresses used in the VPN, see also socat-vpn-server.sh
SOCAT_SERVER_IP=192.168.255.1

# The client IP address we will use
SOCAT_CLIENT_IP=192.168.255.2

# Optional: set the SNI (Server Name Indication) for TLS handshake
# See sslh.config.example
SNI=socat.traffic


test -n "$SNI" && OPTION_SNI=",openssl-commonname=$SNI"
DEFAULT_GATEWAY=$(ip route show 0.0.0.0/0 | awk '{ print $3; }')
DEFAULT_DEVICE=$(ip route show 0.0.0.0/0 | awk '{ print $5; }')

function stop() {
    grep -q "nameserver $SOCAT_SERVER_IP" /etc/resolv.conf && systemctl restart systemd-resolved
    SOCAT=$(ps -eo pid,cmd --no-headers | grep -e "socat.*$SOCAT_CLIENT_IP/24,up,tun-name=socat1,iff-up$")
    if [ -n "$SOCAT" ]; then
        kill "$(echo "$SOCAT" | awk '{print $1}')"
    else
        echo "socat VPN client is not running."
    fi
    ip link delete socat1 2>/dev/null
    ip route del default via $DEFAULT_GATEWAY
    ip route add default via $DEFAULT_GATEWAY dev $DEFAULT_DEVICE metric 1
    ip route del $(dig +short $VPN_SERVER)
}

function start() {
    # Delete existing TUN device if any
    ip link delete socat1 2>/dev/null

    # Start socat to connect to the VPN server
    socat OPENSSL:$VPN_SERVER:443,forever,interval=10,verify=0,$OPTION_SNI TUN:$SOCAT_CLIENT_IP/24,up,tun-name=socat1,iff-up >/dev/null 2>&1 &

    # Wait for the TUN device to be created, or return if it fails
    for _ in $(seq 1 10); do
        sleep 1
        TUN_DEV=$(ip -o addr show to $SOCAT_CLIENT_IP/24 | grep socat1 | awk '{print $2}')
        test -n "$TUN_DEV" && break
    done
    test -z "$TUN_DEV" && return

    # socat shall still use the old default route to local router
    ip route add $(dig +short $VPN_SERVER) via $DEFAULT_GATEWAY dev $DEFAULT_DEVICE

    # Add a new default route via the VPN with higher priority (lower metric)
    ip route add default via $SOCAT_CLIENT_IP dev socat1 metric 1

    # Delete the old default route and re-add with higher metric
    ip route del default via $DEFAULT_GATEWAY
    ip route add default via $DEFAULT_GATEWAY dev $DEFAULT_DEVICE metric 100

    # Set DNS to use vpn server. 
    systemctl stop systemd-resolved
    echo "nameserver $SOCAT_SERVER_IP" > /etc/resolv.conf
}

# Ensure cleanup on exit
trap stop EXIT

# Main loop to maintain the VPN connection
while true; do
    while ! ping -c1 -W1 $SOCAT_SERVER_IP &>/dev/null; do
        stop
        start
        sleep 10
    done
    grep -q "nameserver $SOCAT_SERVER_IP" /etc/resolv.conf || echo "nameserver $SOCAT_SERVER_IP" > /etc/resolv.conf
    sleep 10
done

#!/bin/bash

# attach socat to a TUN interface to create a simple VPN server
# see socat-vpn-client.sh for the client side
# Assumes TLS termination is done for 127.0.0.1:11443, see nginx.conf.stream
SERVER_IP=192.168.255.1

DEFAULT_GATEWAY=$(ip route show 0.0.0.0/0 | awk '{ print $3; }')
DEFAULT_DEVICE=$(ip route show 0.0.0.0/0 | awk '{ print $5; }')


function start() {

    # Start socat to listen for incoming VPN connections
    socat TCP4-LISTEN:11443,bind=127.0.0.1,reuseaddr,fork TUN:$SERVER_IP/24,up,tun-name=socat1,iff-up >/dev/null 2>&1 &
    PID=$!
    sleep 1
    if ! kill -0 "$PID" 2>/dev/null; then
        echo "Failed to start socat VPN server."
        exit 1
    fi

    # Configure iptables for NAT and forwarding
    iptables -t nat -A POSTROUTING -o $DEFAULT_DEVICE -j MASQUERADE
    iptables -A FORWARD -i socat1 -o $DEFAULT_DEVICE -j ACCEPT
    iptables -A FORWARD -i $DEFAULT_DEVICE -o socat1 -m state --state RELATED,ESTABLISHED -j ACCEPT
    # DNS forwarding
    iptables -t nat -A PREROUTING -i socat1 -p udp --dport 53 -j DNAT --to-destination $DEFAULT_GATEWAY:53
    iptables -A FORWARD -i socat1 -p udp --dport 53 -j ACCEPT
    iptables -A FORWARD -o socat1 -p udp --sport 53 -m state --state RELATED,ESTABLISHED -j ACCEPT
}

function stop() {
    SOCAT=$(ps -eo pid,cmd --no-headers | grep -e "socat.*$SERVER_IP/24,up,tun-name=socat1,iff-up$")
    if [ -n "$SOCAT" ]; then
        kill $(echo "$SOCAT" | awk '{print $1}' | xargs)
    else
        echo "socat VPN server is not running."
    fi
    
    # Delete the TUN device (although socat should do this automatically)
    ip link delete socat1 2>/dev/null
    # Remove iptables rules
    iptables -t nat -D POSTROUTING -o $DEFAULT_DEVICE -j MASQUERADE
    iptables -D FORWARD -i socat1 -o $DEFAULT_DEVICE -j ACCEPT
    iptables -D FORWARD -i $DEFAULT_DEVICE -o socat1 -m state --state RELATED,ESTABLISHED -j ACCEPT
    iptables -t nat -D PREROUTING -i socat1 -p udp --dport 53 -j DNAT --to-destination $DEFAULT_GATEWAY:53
    iptables -D FORWARD -i socat1 -p udp --dport 53 -j ACCEPT
    iptables -D FORWARD -o socat1 -p udp --sport 53 -m state --state RELATED,ESTABLISHED -j ACCEPT
}

$1

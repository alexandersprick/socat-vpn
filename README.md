# socat-vpn
A simple, unsecure VPN using socat with TUN interfaces

Provides a point-to-point connection with socat. By using TLS on port 443, there is a good chance that firewalls do not detect this hole.

(everything below was written by AI Claude)
## Overview

This project creates a simple VPN tunnel using `socat` to establish a point-to-point connection between a client and server. The connection uses TUN interfaces on both ends and can be disguised as regular HTTPS traffic on port 443 to bypass restrictive firewalls.

**Warning**: This is described as "unsecure" - it's designed for bypassing network restrictions, not for security or privacy.

## Architecture

The VPN setup consists of:

- **Client** (`socat-vpn-client.sh`): Connects to the server using TLS and creates a TUN interface
- **Server** (`socat-vpn-server.sh`): Listens for connections and creates a TUN interface
- **TLS Termination**: Uses nginx stream module to handle TLS connections
- **Optional SNI Routing**: Uses sslh to multiplex different services on port 443 based on SNI

### Network Flow

```
Client → TLS:443 → [sslh] → nginx:2444 → socat:11443 → TUN interface
```

## Components

### Server Side

1. **socat-vpn-server.sh**: 
   - Creates a TUN interface (`socat1`) with IP `192.168.255.1/24`
   - Listens on `127.0.0.1:11443` for incoming connections
   - Sets up NAT and forwarding rules with iptables
   - Forwards DNS queries to the default gateway

2. **nginx.conf.stream**: 
   - Terminates TLS connections on port 2444
   - Proxies decrypted traffic to socat on `127.0.0.1:11443`

3. **sslh.config.example** (optional):
   - Multiplexes port 443 traffic based on protocol/SNI
   - Routes traffic with SNI `socat.traffic` to nginx:2444
   - Allows SSH and other services to coexist on port 443

### Client Side

1. **socat-vpn-client.sh**:
   - Creates a TUN interface (`socat1`) with IP `192.168.255.2/24`
   - Connects to the server using TLS with optional SNI
   - Modifies routing table to route all traffic through the VPN
   - Updates DNS to use the VPN server (`192.168.255.1`)
   - Automatically reconnects if the connection drops

## Installation

### Server Setup

1. **Install dependencies**:
   ```bash
   apt-get install socat nginx iptables
   # Optional: apt-get install sslh
   ```

2. **Enable IP forwarding**:
   ```bash
   echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
   sysctl -p
   ```

3. **Configure TLS certificates**:
   - Place your SSL certificate and key in `/etc/ssl/nginx/`
   - Update paths in `nginx.conf.stream` if needed

4. **Configure nginx**:
   ```bash
   # Add or include nginx.conf.stream in your main nginx.conf
   # In /etc/nginx/nginx.conf, add:
   # include /etc/nginx/nginx.conf.stream;
   systemctl restart nginx
   ```

5. **Install the server script**:
   ```bash
   cp socat-vpn-server.sh /usr/local/bin/
   chmod +x /usr/local/bin/socat-vpn-server.sh
   ```

6. **Install and enable the service**:
   ```bash
   cp socat-vpn-server.service /etc/systemd/system/
   systemctl daemon-reload
   systemctl enable socat-vpn-server
   systemctl start socat-vpn-server
   ```

7. **Optional: Configure sslh** (to share port 443 with SSH and other services):
   ```bash
   cp sslh.config.example /etc/sslh/sslh.cfg
   # Edit the config as needed
   systemctl restart sslh
   ```

### Client Setup

1. **Install dependencies**:
   ```bash
   apt-get install socat dnsutils
   ```

2. **Configure the client script**:
   Edit `socat-vpn-client.sh` and set:
   - `VPN_SERVER`: Your VPN server hostname/IP
   - `SNI`: The SNI value if using sslh (e.g., `socat.traffic`)

3. **Install the client script**:
   ```bash
   cp socat-vpn-client.sh /usr/local/bin/
   chmod +x /usr/local/bin/socat-vpn-client.sh
   ```

4. **Install and enable the service**:
   ```bash
   cp socat-vpn-client.service /etc/systemd/system/
   systemctl daemon-reload
   systemctl enable socat-vpn-client
   systemctl start socat-vpn-client
   ```

## Configuration

### Server Configuration

Edit `socat-vpn-server.sh`:
- `SERVER_IP`: The VPN server's TUN interface IP (default: `192.168.255.1`)

### Client Configuration

Edit `socat-vpn-client.sh`:
- `VPN_SERVER`: Your VPN server's hostname or IP address
- `SOCAT_SERVER_IP`: Must match the server's `SERVER_IP` (default: `192.168.255.1`)
- `SOCAT_CLIENT_IP`: The client's TUN interface IP (default: `192.168.255.2`)
- `SNI`: Server Name Indication for TLS handshake (optional, used with sslh)

## Usage

### Manual Start/Stop

**Server**:
```bash
/usr/local/bin/socat-vpn-server.sh start
/usr/local/bin/socat-vpn-server.sh stop
```

**Client**:
```bash
# Start (runs continuously)
/usr/local/bin/socat-vpn-client.sh

# Stop (Ctrl+C or kill the process)
```

### Using systemd

**Server**:
```bash
systemctl start socat-vpn-server
systemctl stop socat-vpn-server
systemctl status socat-vpn-server
```

**Client**:
```bash
systemctl start socat-vpn-client
systemctl stop socat-vpn-client
systemctl status socat-vpn-client
```

## How It Works

### Client Operation

1. Deletes any existing `socat1` TUN interface
2. Establishes a TLS connection to the VPN server on port 443
3. Creates a TUN interface with IP `192.168.255.2/24`
4. Adds a specific route for the VPN server through the original gateway
5. Adds a new default route through the VPN with higher priority (metric 1)
6. Demotes the original default route to lower priority (metric 100)
7. Updates DNS to use the VPN server
8. Continuously monitors the connection and reconnects if it drops

### Server Operation

1. Listens on `127.0.0.1:11443` (behind nginx TLS termination)
2. Creates a TUN interface with IP `192.168.255.1/24` for each connection
3. Configures iptables rules to:
   - Masquerade outgoing traffic (NAT)
   - Allow forwarding between TUN interface and default network
   - Forward DNS queries to the default gateway

### Traffic Flow

All client traffic is routed through the TUN interface to the server, which then forwards it to the internet using NAT. DNS queries are handled by the server's DNS resolver.

## Firewall Evasion

The VPN uses TLS on port 443, making it appear as regular HTTPS traffic. When combined with sslh and proper SNI configuration, it can coexist with legitimate HTTPS services, making it harder for firewalls to block.

## Troubleshooting

### Check if the VPN is running

**Server**:
```bash
ip addr show socat1
ps aux | grep socat
```

**Client**:
```bash
ip addr show socat1
ip route show
ping 192.168.255.1
```

### Check iptables rules (server)

```bash
iptables -t nat -L -n -v
iptables -L FORWARD -n -v
```

### Test connectivity

From client:
```bash
ping 192.168.255.1  # Ping VPN server
ping 8.8.8.8        # Ping through VPN
curl ifconfig.me    # Check external IP
```

### View logs

```bash
journalctl -u socat-vpn-server -f
journalctl -u socat-vpn-client -f
```

## Security Considerations

- **This VPN is "unsecure"**: The connection uses TLS, but with `verify=0`, so it doesn't validate certificates
- **No authentication**: Anyone who can connect to the server port can use the VPN
- **No encryption** after TLS termination: Traffic between nginx and socat is unencrypted
- **Root required**: Both scripts need root privileges to create TUN interfaces and modify routing
- **DNS exposure**: DNS queries are forwarded but not encrypted separately

This VPN is designed for bypassing restrictive networks, not for privacy or security.

## License

Do whatever you want.


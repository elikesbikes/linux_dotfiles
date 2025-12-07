#!/bin/bash
set -e

HOME_IP="$1"

if [[ -z "$HOME_IP" ]]; then
    echo "[ERROR] HOME_IP argument missing."
    exit 1
fi

echo "[INFO] Applying DOCKER-USER rules with HOME_IP=$HOME_IP ..."

# Ensure DOCKER-USER chain exists
if ! sudo iptables -n -L DOCKER-USER >/dev/null 2>&1; then
    echo "[ERROR] DOCKER-USER chain not found. Is Docker running?"
    exit 1
fi

# Flush existing rules
sudo iptables -F DOCKER-USER

# 1. Allow HOME IP to reach ports 22,443,2375
sudo iptables -A DOCKER-USER -s "$HOME_IP" -p tcp -m multiport --dports 22,443,2375 -j ACCEPT

# 2. Allow HOME IP ICMP (ping)
sudo iptables -A DOCKER-USER -s "$HOME_IP" -p icmp -j ACCEPT

# 3. Allow INTERNAL DOCKER BRIDGES (IMPORTANT FIX)
#    This matches 172.17.x.x, 172.18.x.x, 172.20.x.x etc.
sudo iptables -A DOCKER-USER -s 172.16.0.0/12 -j ACCEPT

# 4. Allow Tailscale traffic
sudo iptables -A DOCKER-USER -i tailscale0 -j ACCEPT

# 5. Allow localhost
sudo iptables -A DOCKER-USER -i lo -j ACCEPT

# 6. Allow established/related return traffic
sudo iptables -A DOCKER-USER -m state --state RELATED,ESTABLISHED -j ACCEPT

# 7. Block ICMP from everywhere else
sudo iptables -A DOCKER-USER -p icmp -j DROP

# 8. Drop EVERYTHING ELSE
sudo iptables -A DOCKER-USER -j DROP

echo "[INFO] DOCKER-USER rules updated successfully."
exit 0


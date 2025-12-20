#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "[ERROR] HOME_IP argument missing."
  exit 1
fi

HOME_IP="$1"

echo "[firewall] Applying DOCKER-USER rules with HOME_IP=$HOME_IP ..."

# Ensure DOCKER-USER exists (Docker creates it)
if ! iptables -L DOCKER-USER -n >/dev/null 2>&1; then
  echo "[ERROR] DOCKER-USER chain not found. Is Docker running?"
  exit 1
fi

# Flush only DOCKER-USER (DO NOT touch Docker-managed chains)
iptables -F DOCKER-USER

#
# ORDER MATTERS — FIRST MATCH WINS
#

# 1️⃣ Allow Docker internal networks (CRITICAL — this fixed your timeouts)
iptables -I DOCKER-USER 1 -s 172.16.0.0/12 -j ACCEPT

# 2️⃣ Allow traffic from HOME IP to host services
iptables -A DOCKER-USER -s "$HOME_IP" -p tcp -m multiport --dports 22,443,2375 -j ACCEPT

# 3️⃣ Allow ICMP (ping) from HOME IP
iptables -A DOCKER-USER -s "$HOME_IP" -p icmp -j ACCEPT

# 4️⃣ Allow Tailscale traffic
iptables -A DOCKER-USER -i tailscale0 -j ACCEPT

# 5️⃣ Allow localhost
iptables -A DOCKER-USER -i lo -j ACCEPT

# 6️⃣ Allow established / related traffic
iptables -A DOCKER-USER -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT

# 7️⃣ Drop ICMP from everywhere else
iptables -A DOCKER-USER -p icmp -j DROP

# 8️⃣ Drop EVERYTHING else
iptables -A DOCKER-USER -j DROP

echo "[firewall] DOCKER-USER rules applied successfully."

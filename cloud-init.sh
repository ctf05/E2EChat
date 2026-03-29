#!/bin/bash
# =============================================================================
# Oracle Cloud Ubuntu Cloud-Init Script
# =============================================================================
# Paste this into the "Cloud-Init Script" field when creating an Oracle Cloud
# instance, or run it manually on a fresh Ubuntu server as root.
#
# What it does:
#   1. Opens required firewall ports (iptables) and blocks internal-only ports
#   2. Installs Docker Engine + Docker Compose v2 from official repo
#   3. Adds the ubuntu user to the docker group
#   4. Installs git
# =============================================================================
set -euo pipefail

# --- Firewall Rules ----------------------------------------------------------
# Oracle Cloud Ubuntu has a default REJECT-all rule that blocks everything.
# We must delete it first, add our rules, then append it at the end.

# Find and delete the REJECT-all rule (typically at position 5)
REJECT_LINE=$(iptables -L INPUT -n --line-numbers | grep "REJECT.*icmp-host-prohibited" | awk '{print $1}' | head -1)
if [ -n "$REJECT_LINE" ]; then
    iptables -D INPUT "$REJECT_LINE"
fi

# Open required ports for E2EChat
iptables -A INPUT -m state --state NEW -p tcp --dport 80 -j ACCEPT
iptables -A INPUT -m state --state NEW -p tcp --dport 443 -j ACCEPT
iptables -A INPUT -m state --state NEW -p udp --dport 443 -j ACCEPT
iptables -A INPUT -m state --state NEW -p tcp --dport 8448 -j ACCEPT
iptables -A INPUT -m state --state NEW -p tcp --dport 7881 -j ACCEPT
iptables -A INPUT -m state --state NEW -p udp --dport 3478 -j ACCEPT
iptables -A INPUT -m state --state NEW -p udp --dport 50100:50400 -j ACCEPT

# Block internal-only ports from external access, but allow Docker bridge traffic
# (Caddy on 172.17.0.x needs to reach these ports internally)
iptables -A INPUT -m state --state NEW -p tcp --dport 7880 ! -s 172.16.0.0/12 -j DROP
iptables -A INPUT -m state --state NEW -p tcp --dport 8080 ! -s 172.16.0.0/12 -j DROP

# Re-add the REJECT-all rule at the end (catch-all)
iptables -A INPUT -j REJECT --reject-with icmp-host-prohibited

netfilter-persistent save

# --- System Updates ----------------------------------------------------------
apt-get update
apt-get upgrade -y

# --- Docker Installation -----------------------------------------------------
apt-get install -y ca-certificates curl gnupg
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo $VERSION_CODENAME) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# --- User Setup --------------------------------------------------------------
usermod -aG docker ubuntu
apt-get install -y git

touch /home/ubuntu/.cloud-init-complete

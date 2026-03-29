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
# Open required ports for E2EChat
iptables -I INPUT 6 -m state --state NEW -p tcp --dport 80 -j ACCEPT
iptables -I INPUT 6 -m state --state NEW -p tcp --dport 443 -j ACCEPT
iptables -I INPUT 6 -m state --state NEW -p udp --dport 443 -j ACCEPT
iptables -I INPUT 6 -m state --state NEW -p tcp --dport 8448 -j ACCEPT
iptables -I INPUT 6 -m state --state NEW -p tcp --dport 7881 -j ACCEPT
iptables -I INPUT 6 -m state --state NEW -p udp --dport 3478 -j ACCEPT
iptables -I INPUT 6 -m state --state NEW -p udp --dport 50100:50400 -j ACCEPT

# Block internal-only ports from external access (Caddy proxies to these)
iptables -I INPUT 6 -m state --state NEW -p tcp --dport 7880 -j DROP
iptables -I INPUT 6 -m state --state NEW -p tcp --dport 8080 -j DROP

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

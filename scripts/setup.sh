#!/usr/bin/env bash
# =============================================================================
# E2EChat Setup Script
# =============================================================================
# First-time setup: validates prerequisites, generates secrets, creates
# configuration files from templates.
#
# Usage:
#   ./scripts/setup.sh                    # Interactive mode (prompts for domain)
#   ./scripts/setup.sh example.com        # Non-interactive (base domain as argument)
#
# What it does:
#   1. Checks Docker, Docker Compose, and openssl are installed
#   2. Prompts for your base domain (or accepts it as an argument)
#   3. Generates cryptographic secrets (LiveKit API key/secret, registration token)
#   4. Creates .env from .env.example with generated values
#   5. Generates final config files in data/ from templates
#   6. Prints firewall and DNS setup instructions
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
DATA_DIR="$PROJECT_DIR/data"
ENV_FILE="$PROJECT_DIR/.env"
ENV_EXAMPLE="$PROJECT_DIR/.env.example"

# --- Colors ------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# --- Prerequisite Checks ----------------------------------------------------
check_prerequisites() {
    local missing=0

    if ! command -v docker &>/dev/null; then
        error "Docker is not installed. Install it from https://docs.docker.com/engine/install/"
        missing=1
    else
        local docker_version
        docker_version=$(docker version --format '{{.Server.Version}}' 2>/dev/null || echo "0")
        local docker_major
        docker_major=$(echo "$docker_version" | cut -d. -f1)
        if [ "$docker_major" -lt 20 ] 2>/dev/null; then
            error "Docker version $docker_version is too old. Need 20+."
            missing=1
        else
            success "Docker $docker_version"
        fi
    fi

    if ! docker compose version &>/dev/null; then
        error "Docker Compose v2 is not installed. Install it from https://docs.docker.com/compose/install/"
        missing=1
    else
        local compose_version
        compose_version=$(docker compose version --short 2>/dev/null || echo "unknown")
        success "Docker Compose $compose_version"
    fi

    if ! command -v openssl &>/dev/null; then
        error "openssl is not installed. Install it with: sudo apt install openssl"
        missing=1
    else
        success "openssl available"
    fi

    if [ $missing -ne 0 ]; then
        echo ""
        error "Missing prerequisites. Install them and re-run this script."
        exit 1
    fi
}

# --- Secret Generation ------------------------------------------------------
generate_api_key() {
    openssl rand -base64 15 | tr -dc 'A-Za-z0-9' | head -c 20
}

generate_api_secret() {
    openssl rand -base64 33 | tr -dc 'A-Za-z0-9' | head -c 44
}

generate_token() {
    openssl rand -hex 32
}

# --- Template Substitution ---------------------------------------------------
# Uses envsubst if available, falls back to sed-based substitution.
substitute_template() {
    local input="$1"
    local output="$2"

    # Only substitute our known variables (prevents $HOME, $PATH, etc. leaking)
    local var_list='${MATRIX_DOMAIN} ${LIVEKIT_DOMAIN} ${ELEMENT_DOMAIN} ${LIVEKIT_API_KEY} ${LIVEKIT_API_SECRET} ${REGISTRATION_TOKEN} ${ACME_EMAIL} ${LOG_LEVEL} ${MAX_UPLOAD_SIZE}'

    if command -v envsubst &>/dev/null; then
        envsubst "$var_list" < "$input" > "$output"
    else
        cp "$input" "$output"
        while IFS='=' read -r key value; do
            # Skip comments and empty lines
            [[ "$key" =~ ^[[:space:]]*# ]] && continue
            [[ -z "$key" ]] && continue
            # Remove surrounding quotes from value
            value="${value%\"}"
            value="${value#\"}"
            # Escape special sed characters in value (& / \ | for | delimiter)
            local escaped_value
            escaped_value=$(printf '%s\n' "$value" | sed 's/[&/\|]/\\&/g')
            sed -i "s|\${${key}}|${escaped_value}|g" "$output"
        done < "$ENV_FILE"
    fi
}

# --- Main --------------------------------------------------------------------
main() {
    echo ""
    echo "=========================================="
    echo "  E2EChat Setup"
    echo "=========================================="
    echo ""

    # Check prerequisites
    info "Checking prerequisites..."
    check_prerequisites
    echo ""

    # Check if .env already exists
    if [ -f "$ENV_FILE" ]; then
        warn ".env already exists."
        read -rp "Overwrite with new values? (y/N): " overwrite
        if [[ ! "$overwrite" =~ ^[Yy] ]]; then
            info "Keeping existing .env. Regenerating config files only..."
            # Source existing .env and regenerate configs
            set -a
            source "$ENV_FILE"
            set +a
            # Fall through to config generation
        else
            rm "$ENV_FILE"
        fi
    fi

    # Get domain if .env doesn't exist
    if [ ! -f "$ENV_FILE" ]; then
        local base_domain="${1:-}"

        if [ -z "$base_domain" ]; then
            echo "Enter your base domain (e.g., ctf-compendium.uk):"
            read -rp "> " base_domain
        fi

        if [ -z "$base_domain" ]; then
            error "Domain cannot be empty."
            exit 1
        fi

        # Derive subdomains
        local matrix_domain="chat.${base_domain}"
        local livekit_domain="call.${base_domain}"
        local element_domain="app.${base_domain}"

        echo ""
        info "Subdomains:"
        echo "  Matrix:     $matrix_domain"
        echo "  LiveKit:    $livekit_domain"
        echo "  Element Web: $element_domain"
        echo ""
        read -rp "Use these subdomains? (Y/n): " confirm
        if [[ "$confirm" =~ ^[Nn] ]]; then
            read -rp "Matrix subdomain (e.g., chat.${base_domain}): " matrix_domain
            read -rp "LiveKit subdomain (e.g., call.${base_domain}): " livekit_domain
            read -rp "Element Web subdomain (e.g., app.${base_domain}): " element_domain
        fi

        # Generate secrets
        info "Generating secrets..."
        local api_key api_secret reg_token
        api_key=$(generate_api_key)
        api_secret=$(generate_api_secret)
        reg_token=$(generate_token)
        success "Secrets generated"

        # Optional email
        echo ""
        read -rp "Email for Let's Encrypt notifications (optional, press Enter to skip): " acme_email

        # Write .env
        cat > "$ENV_FILE" <<EOF
# Generated by setup.sh on $(date -u +"%Y-%m-%d %H:%M:%S UTC")
MATRIX_DOMAIN=${matrix_domain}
LIVEKIT_DOMAIN=${livekit_domain}
ELEMENT_DOMAIN=${element_domain}
LIVEKIT_API_KEY=${api_key}
LIVEKIT_API_SECRET=${api_secret}
REGISTRATION_TOKEN=${reg_token}
ACME_EMAIL=${acme_email}
LOG_LEVEL=info
MAX_UPLOAD_SIZE=20971520
EOF
        success ".env created"

        # Source the new .env
        set -a
        source "$ENV_FILE"
        set +a
    fi

    # Create data directory
    mkdir -p "$DATA_DIR"

    # Generate config files from templates
    info "Generating config files..."

    # Handle Caddyfile — strip email line if ACME_EMAIL is empty
    if [ -z "${ACME_EMAIL:-}" ]; then
        sed '/email \${ACME_EMAIL}/d' "$PROJECT_DIR/Caddyfile" > "$DATA_DIR/Caddyfile.tmp"
        substitute_template "$DATA_DIR/Caddyfile.tmp" "$DATA_DIR/Caddyfile"
        rm "$DATA_DIR/Caddyfile.tmp"
    else
        substitute_template "$PROJECT_DIR/Caddyfile" "$DATA_DIR/Caddyfile"
    fi
    success "data/Caddyfile"

    substitute_template "$PROJECT_DIR/continuwuity.toml" "$DATA_DIR/continuwuity.toml"
    success "data/continuwuity.toml"

    substitute_template "$PROJECT_DIR/livekit.yaml" "$DATA_DIR/livekit.yaml"
    success "data/livekit.yaml"

    substitute_template "$PROJECT_DIR/element-web-config.json" "$DATA_DIR/element-web-config.json"
    success "data/element-web-config.json"

    echo ""
    success "All config files generated in data/"

    # --- Firewall Instructions -----------------------------------------------
    echo ""
    echo "=========================================="
    echo "  Firewall Setup"
    echo "=========================================="
    echo ""
    echo "Open the following ports on your server:"
    echo ""
    echo "  TCP:  80, 443, 8448, 7881"
    echo "  UDP:  443, 3478, 50100-50200, 50300-50400"
    echo ""
    echo "Block these ports externally (internal only via Caddy):"
    echo "  TCP:  7880, 8080"
    echo ""

    # Detect Oracle Cloud
    if [ -f /etc/oracle-cloud-agent/agent.yml ] || \
       dmidecode -s system-product-name 2>/dev/null | grep -qi "oracle" || \
       curl -s --connect-timeout 2 http://169.254.169.254/opc/v1/instance/ &>/dev/null; then
        echo "Oracle Cloud detected! You need BOTH VCN Security List rules AND iptables:"
        echo ""
        echo "  # Allow required ports through iptables"
        echo "  sudo iptables -I INPUT 6 -m state --state NEW -p tcp --match multiport --dports 80,443,8448,7881 -j ACCEPT"
        echo "  sudo iptables -I INPUT 6 -m state --state NEW -p udp --dport 443 -j ACCEPT"
        echo "  sudo iptables -I INPUT 6 -m state --state NEW -p udp --dport 3478 -j ACCEPT"
        echo "  sudo iptables -I INPUT 6 -m state --state NEW -p udp --dport 50100:50400 -j ACCEPT"
        echo ""
        echo "  # Block direct access to internal ports"
        echo "  sudo iptables -I INPUT 6 -m state --state NEW -p tcp --match multiport --dports 7880,8080 -j DROP"
        echo ""
        echo "  # Save rules"
        echo "  sudo netfilter-persistent save"
        echo ""
        echo "  Also add these same port rules in the OCI Console:"
        echo "  Networking > Virtual Cloud Networks > [your VCN] > Security Lists"
        echo ""
    else
        echo "If using UFW:"
        echo "  sudo ufw allow 80,443,8448,7881/tcp"
        echo "  sudo ufw allow 443/udp"
        echo "  sudo ufw allow 3478/udp"
        echo "  sudo ufw allow 50100:50400/udp"
        echo "  sudo ufw deny 7880/tcp"
        echo "  sudo ufw deny 8080/tcp"
        echo ""
    fi

    # --- DNS Instructions ----------------------------------------------------
    echo "=========================================="
    echo "  DNS Setup"
    echo "=========================================="
    echo ""
    echo "Create these A records pointing to your server's public IP:"
    echo ""
    echo "  ${MATRIX_DOMAIN}   →  <your-server-ip>"
    echo "  ${LIVEKIT_DOMAIN}  →  <your-server-ip>"
    echo "  ${ELEMENT_DOMAIN}  →  <your-server-ip>"
    echo ""

    # --- Next Steps ----------------------------------------------------------
    echo "=========================================="
    echo "  Next Steps"
    echo "=========================================="
    echo ""
    echo "  1. Set up DNS records (above)"
    echo "  2. Set up firewall rules (above)"
    echo "  3. Start the stack:"
    echo ""
    echo "     docker compose up -d"
    echo ""
    echo "  4. Create your first admin user:"
    echo ""
    echo "     ./scripts/create-user.sh --admin yourusername"
    echo ""
    echo "  5. Log in at https://${ELEMENT_DOMAIN}"
    echo "     or use Element X (mobile) / Element Desktop"
    echo "     with homeserver: ${MATRIX_DOMAIN}"
    echo ""

    # Print registration token for reference
    echo "=========================================="
    echo "  Registration Token (save this!)"
    echo "=========================================="
    echo ""
    echo "  ${REGISTRATION_TOKEN}"
    echo ""
    echo "  Users need this token to create accounts."
    echo "  It's stored in .env (not committed to git)."
    echo ""
}

main "$@"

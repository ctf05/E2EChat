#!/usr/bin/env bash
# =============================================================================
# Create Matrix User Account
# =============================================================================
# Creates a new user on your Continuwuity homeserver.
#
# Usage:
#   ./scripts/create-user.sh <username>              # Regular user
#   ./scripts/create-user.sh --admin <username>       # Admin user
#
# The user will be @username:chat.ctf-compendium.uk (or whatever your domain is).
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$PROJECT_DIR/.env"

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC} $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# --- Parse Arguments --------------------------------------------------------
ADMIN=false
USERNAME=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --admin|-a)
            ADMIN=true
            shift
            ;;
        -*)
            error "Unknown option: $1"
            echo "Usage: $0 [--admin] <username>"
            exit 1
            ;;
        *)
            USERNAME="$1"
            shift
            ;;
    esac
done

if [ -z "$USERNAME" ]; then
    echo "Usage: $0 [--admin] <username>"
    exit 1
fi

# --- Load Config -------------------------------------------------------------
if [ ! -f "$ENV_FILE" ]; then
    error ".env not found. Run ./scripts/setup.sh first."
    exit 1
fi

set -a
source "$ENV_FILE"
set +a

MATRIX_DOMAIN="${MATRIX_DOMAIN:?MATRIX_DOMAIN not set in .env}"
REGISTRATION_TOKEN="${REGISTRATION_TOKEN:?REGISTRATION_TOKEN not set in .env}"

# --- Check Container --------------------------------------------------------
if ! docker ps -q -f name=continuwuity -f status=running | grep -q .; then
    error "Continuwuity container is not running. Start with: docker compose up -d"
    exit 1
fi

# --- Get Password ------------------------------------------------------------
echo "Create user @${USERNAME}:${MATRIX_DOMAIN}"
echo ""

while true; do
    read -rsp "Password: " PASSWORD
    echo ""
    read -rsp "Confirm password: " PASSWORD2
    echo ""

    if [ "$PASSWORD" = "$PASSWORD2" ]; then
        break
    fi
    error "Passwords do not match. Try again."
    echo ""
done

if [ ${#PASSWORD} -lt 8 ]; then
    error "Password must be at least 8 characters."
    exit 1
fi

# --- Register User -----------------------------------------------------------
info "Registering user..."

# Step 1: Get a registration nonce
NONCE_RESPONSE=$(curl -s "https://${MATRIX_DOMAIN}/_matrix/client/v3/register" \
    -X POST \
    -H "Content-Type: application/json" \
    -d '{"auth":{}}' \
    2>/dev/null || true)

SESSION=$(echo "$NONCE_RESPONSE" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if 'session' in data:
        print(data['session'])
    else:
        print('')
except:
    print('')
" 2>/dev/null || echo "")

# Step 2: Register with the token
REGISTER_BODY=$(REG_USERNAME="$USERNAME" REG_PASSWORD="$PASSWORD" REG_TOKEN="$REGISTRATION_TOKEN" REG_SESSION="$SESSION" python3 -c "
import json, os
body = {
    'username': os.environ['REG_USERNAME'],
    'password': os.environ['REG_PASSWORD'],
    'auth': {
        'type': 'm.login.registration_token',
        'token': os.environ['REG_TOKEN'],
        'session': os.environ['REG_SESSION']
    }
}
print(json.dumps(body))
")

RESULT=$(curl -s "https://${MATRIX_DOMAIN}/_matrix/client/v3/register" \
    -X POST \
    -H "Content-Type: application/json" \
    -d "$REGISTER_BODY" \
    2>/dev/null)

# Check if registration succeeded
USER_ID=$(echo "$RESULT" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if 'user_id' in data:
        print(data['user_id'])
    elif 'error' in data:
        print('ERROR: ' + data['error'])
    else:
        print('ERROR: Unknown response')
except:
    print('ERROR: Failed to parse response')
" 2>/dev/null)

if [[ "$USER_ID" == ERROR:* ]]; then
    error "${USER_ID#ERROR: }"
    echo ""
    echo "If registration fails, you can create the user directly:"
    echo "  docker exec -it continuwuity /usr/local/bin/continuwuity-debug --execute 'users create ${USERNAME} ${PASSWORD}'"
    exit 1
fi

success "Created user $USER_ID"

# --- Admin Promotion ---------------------------------------------------------
if [ "$ADMIN" = true ]; then
    info "Promoting to admin..."

    # Use continuwuity's admin command via docker exec
    docker exec continuwuity \
        /usr/local/bin/continuwuity-debug --execute "users set-admin ${USER_ID}" \
        2>/dev/null || \
    docker exec continuwuity \
        /usr/local/bin/conduwuit-debug --execute "users set-admin ${USER_ID}" \
        2>/dev/null || \
    warn "Could not auto-promote to admin. Promote manually via the admin room."

    success "User $USER_ID is now an admin"
fi

echo ""
echo "You can now log in:"
echo "  Web:     https://${ELEMENT_DOMAIN}"
echo "  Desktop: Set homeserver to ${MATRIX_DOMAIN}"
echo "  Mobile:  Set homeserver to ${MATRIX_DOMAIN}"

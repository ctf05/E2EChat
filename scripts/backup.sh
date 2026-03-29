#!/usr/bin/env bash
# =============================================================================
# E2EChat Backup Script
# =============================================================================
# Creates a timestamped backup archive of all persistent data:
#   - Continuwuity database and media (Docker volume)
#   - Caddy TLS certificates (Docker volume)
#   - Configuration files (data/ directory)
#   - Environment file (.env)
#
# Usage:
#   ./scripts/backup.sh                 # Backup to ./backups/
#   ./scripts/backup.sh /path/to/dir    # Backup to custom directory
#
# Restore:
#   See README.md for restore instructions.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BACKUP_DIR="${1:-$PROJECT_DIR/backups}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="e2echat_${TIMESTAMP}"

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }

echo ""
echo "=========================================="
echo "  E2EChat Backup"
echo "=========================================="
echo ""

mkdir -p "$BACKUP_DIR"

# --- Backup Continuwuity Data -----------------------------------------------
info "Backing up Continuwuity database and media..."
docker run --rm \
    -v e2echat_continuwuity_data:/source:ro \
    -v "$BACKUP_DIR":/backup \
    alpine tar czf "/backup/${BACKUP_NAME}_continuwuity.tar.gz" -C /source .
success "Continuwuity data → ${BACKUP_NAME}_continuwuity.tar.gz"

# --- Backup Caddy Certificates ----------------------------------------------
info "Backing up Caddy TLS certificates..."
docker run --rm \
    -v e2echat_caddy_data:/source:ro \
    -v "$BACKUP_DIR":/backup \
    alpine tar czf "/backup/${BACKUP_NAME}_caddy.tar.gz" -C /source .
success "Caddy data → ${BACKUP_NAME}_caddy.tar.gz"

# --- Backup Config Files ----------------------------------------------------
info "Backing up configuration files..."
tar czf "$BACKUP_DIR/${BACKUP_NAME}_config.tar.gz" \
    -C "$PROJECT_DIR" \
    data/ .env 2>/dev/null || \
tar czf "$BACKUP_DIR/${BACKUP_NAME}_config.tar.gz" \
    -C "$PROJECT_DIR" \
    data/ 2>/dev/null
success "Config → ${BACKUP_NAME}_config.tar.gz"

# --- Summary -----------------------------------------------------------------
echo ""
echo "=========================================="
echo "  Backup Complete"
echo "=========================================="
echo ""
echo "Location: $BACKUP_DIR/"
echo ""

# List backup files with sizes
for f in "$BACKUP_DIR/${BACKUP_NAME}"_*.tar.gz; do
    size=$(du -h "$f" | cut -f1)
    echo "  $size  $(basename "$f")"
done

total=$(du -sh "$BACKUP_DIR/${BACKUP_NAME}"_*.tar.gz 2>/dev/null | tail -1 | cut -f1)
echo ""
echo "Total: $total"
echo ""

# --- Retention ---------------------------------------------------------------
KEEP=5
BACKUP_COUNT=$(ls -1 "$BACKUP_DIR"/e2echat_*_continuwuity.tar.gz 2>/dev/null | wc -l)
if [ "$BACKUP_COUNT" -gt "$KEEP" ]; then
    warn "You have $BACKUP_COUNT backups. Consider removing old ones."
    echo "  Oldest backups:"
    ls -1t "$BACKUP_DIR"/e2echat_*_continuwuity.tar.gz | tail -n +$((KEEP + 1)) | while read -r old; do
        timestamp=$(basename "$old" | sed 's/e2echat_\(.*\)_continuwuity.tar.gz/\1/')
        echo "    $timestamp"
    done
fi

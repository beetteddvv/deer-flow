#!/bin/bash
# health_check.sh - Verify service health endpoints after deployment
# Used by both local and Docker smoke test flows

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
BACKEND_HOST="${BACKEND_HOST:-localhost}"
BACKEND_PORT="${BACKEND_PORT:-8000}"
FRONTEND_HOST="${FRONTEND_HOST:-localhost}"
FRONTEND_PORT="${FRONTEND_PORT:-3000}"

MAX_RETRIES="${HEALTH_CHECK_RETRIES:-12}"
RETRY_INTERVAL="${HEALTH_CHECK_INTERVAL:-5}"  # seconds

BACKEND_URL="http://${BACKEND_HOST}:${BACKEND_PORT}"
FRONTEND_URL="http://${FRONTEND_HOST}:${FRONTEND_PORT}"

# Colours
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
log()  { echo -e "[health_check] $*"; }
ok()   { echo -e "${GREEN}[✓]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
fail() { echo -e "${RED}[✗]${NC} $*"; }

# Wait for a URL to return HTTP 200 (or any 2xx)
wait_for_url() {
    local url="$1"
    local label="$2"
    local attempt=1

    log "Waiting for ${label} at ${url} ..."
    while [[ $attempt -le $MAX_RETRIES ]]; do
        local http_code
        http_code=$(curl -s -o /dev/null -w "%{http_code}" \
            --max-time 5 --connect-timeout 3 "${url}" 2>/dev/null || echo "000")

        if [[ "$http_code" =~ ^2 ]]; then
            ok "${label} responded with HTTP ${http_code} (attempt ${attempt})"
            return 0
        fi

        warn "${label} returned HTTP ${http_code} — retrying in ${RETRY_INTERVAL}s (${attempt}/${MAX_RETRIES})"
        sleep "$RETRY_INTERVAL"
        ((attempt++))
    done

    fail "${label} did not become healthy after $((MAX_RETRIES * RETRY_INTERVAL))s"
    return 1
}

# Check a specific JSON field in the health response
check_backend_health_payload() {
    local response
    response=$(curl -s --max-time 5 "${BACKEND_URL}/health" 2>/dev/null || echo "{}")

    local status
    status=$(echo "$response" | python3 -c \
        "import sys, json; d=json.load(sys.stdin); print(d.get('status','unknown'))" 2>/dev/null || echo "unknown")

    if [[ "$status" == "ok" || "$status" == "healthy" ]]; then
        ok "Backend health payload: status=${status}"
        return 0
    else
        warn "Backend health payload reports status='${status}' (expected ok/healthy)"
        return 1
    fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    local exit_code=0

    log "=== DeerFlow Health Check ==="
    log "Backend : ${BACKEND_URL}"
    log "Frontend: ${FRONTEND_URL}"
    echo

    # 1. Backend liveness
    if ! wait_for_url "${BACKEND_URL}/health" "Backend /health"; then
        exit_code=1
    else
        # 2. Backend health payload (best-effort)
        check_backend_health_payload || true
    fi

    # 3. Backend API docs reachable (optional sanity check)
    if curl -s -o /dev/null -w "%{http_code}" \
           --max-time 5 "${BACKEND_URL}/docs" 2>/dev/null | grep -q '^2'; then
        ok "Backend /docs is reachable"
    else
        warn "Backend /docs not reachable — may be disabled in production mode"
    fi

    # 4. Frontend liveness
    if ! wait_for_url "${FRONTEND_URL}" "Frontend /"; then
        exit_code=1
    fi

    echo
    if [[ $exit_code -eq 0 ]]; then
        ok "All health checks passed."
    else
        fail "One or more health checks failed."
    fi

    return $exit_code
}

main "$@"

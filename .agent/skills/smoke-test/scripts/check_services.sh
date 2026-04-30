#!/bin/bash
# check_services.sh - Verify all required services are running and healthy
# Part of the deer-flow smoke test suite

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../../lib/common.sh" 2>/dev/null || true

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Service check results
PASS=0
FAIL=0
WARN=0

log_pass() { echo -e "${GREEN}[PASS]${NC} $1"; ((PASS++)); }
log_fail() { echo -e "${RED}[FAIL]${NC} $1"; ((FAIL++)); }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; ((WARN++)); }
log_info() { echo -e "[INFO] $1"; }

# Default ports
BACKEND_PORT=${BACKEND_PORT:-8000}
FRONTEND_PORT=${FRONTEND_PORT:-3000}
BACKEND_HOST=${BACKEND_HOST:-localhost}
FRONTEND_HOST=${FRONTEND_HOST:-localhost}

check_port_open() {
  local host="$1"
  local port="$2"
  local service="$3"

  if command -v nc &>/dev/null; then
    nc -z -w 3 "$host" "$port" 2>/dev/null
  elif command -v curl &>/dev/null; then
    curl -s --connect-timeout 3 "http://${host}:${port}" &>/dev/null
  else
    # Fallback using /dev/tcp
    (echo > /dev/tcp/"$host"/"$port") 2>/dev/null
  fi
}

check_backend_service() {
  log_info "Checking backend service on ${BACKEND_HOST}:${BACKEND_PORT}..."

  if check_port_open "$BACKEND_HOST" "$BACKEND_PORT" "backend"; then
    log_pass "Backend port ${BACKEND_PORT} is open"
  else
    log_fail "Backend port ${BACKEND_PORT} is not reachable on ${BACKEND_HOST}"
    return 1
  fi

  # Check health endpoint
  local health_url="http://${BACKEND_HOST}:${BACKEND_PORT}/api/health"
  local http_code
  http_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "$health_url" 2>/dev/null || echo "000")

  if [[ "$http_code" == "200" ]]; then
    log_pass "Backend health endpoint returned HTTP 200"
  elif [[ "$http_code" == "000" ]]; then
    log_fail "Backend health endpoint unreachable at ${health_url}"
  else
    log_warn "Backend health endpoint returned HTTP ${http_code} (expected 200)"
  fi
}

check_frontend_service() {
  log_info "Checking frontend service on ${FRONTEND_HOST}:${FRONTEND_PORT}..."

  if check_port_open "$FRONTEND_HOST" "$FRONTEND_PORT" "frontend"; then
    log_pass "Frontend port ${FRONTEND_PORT} is open"
  else
    log_fail "Frontend port ${FRONTEND_PORT} is not reachable on ${FRONTEND_HOST}"
    return 1
  fi

  local frontend_url="http://${FRONTEND_HOST}:${FRONTEND_PORT}"
  local http_code
  http_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "$frontend_url" 2>/dev/null || echo "000")

  if [[ "$http_code" =~ ^(200|301|302)$ ]]; then
    log_pass "Frontend responded with HTTP ${http_code}"
  elif [[ "$http_code" == "000" ]]; then
    log_fail "Frontend unreachable at ${frontend_url}"
  else
    log_warn "Frontend returned unexpected HTTP ${http_code}"
  fi
}

check_docker_services() {
  if ! command -v docker &>/dev/null; then
    log_warn "Docker not available, skipping container service checks"
    return 0
  fi

  log_info "Checking Docker container status..."

  local containers
  containers=$(docker ps --filter "name=deer-flow" --format "{{.Names}}:{{.Status}}" 2>/dev/null || echo "")

  if [[ -z "$containers" ]]; then
    log_warn "No deer-flow Docker containers found running"
    return 0
  fi

  while IFS= read -r container; do
    local name status
    name=$(echo "$container" | cut -d: -f1)
    status=$(echo "$container" | cut -d: -f2-)

    if echo "$status" | grep -qi "up"; then
      log_pass "Container '${name}' is running (${status})"
    else
      log_fail "Container '${name}' is not healthy: ${status}"
    fi
  done <<< "$containers"
}

print_summary() {
  echo ""
  echo "======================================"
  echo "  Service Check Summary"
  echo "======================================"
  echo -e "  ${GREEN}Passed:${NC}  ${PASS}"
  echo -e "  ${YELLOW}Warnings:${NC} ${WARN}"
  echo -e "  ${RED}Failed:${NC}  ${FAIL}"
  echo "======================================"

  if [[ $FAIL -gt 0 ]]; then
    echo -e "${RED}Some services are not running correctly.${NC}"
    exit 1
  elif [[ $WARN -gt 0 ]]; then
    echo -e "${YELLOW}Services running with warnings.${NC}"
    exit 0
  else
    echo -e "${GREEN}All services are healthy.${NC}"
    exit 0
  fi
}

main() {
  echo "======================================"
  echo "  deer-flow Service Health Checks"
  echo "======================================"
  echo ""

  check_backend_service || true
  check_frontend_service || true
  check_docker_services || true

  print_summary
}

main "$@"

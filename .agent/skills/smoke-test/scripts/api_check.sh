#!/bin/bash
# api_check.sh - Validate core API endpoints are responding correctly
# Part of the deer-flow smoke test suite

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_URL="${DEERFLOW_BASE_URL:-http://localhost:8000}"
TIMEOUT="${API_TIMEOUT:-10}"
MAX_RETRIES="${API_MAX_RETRIES:-3}"
RETRY_DELAY="${API_RETRY_DELAY:-2}"

# Colour helpers
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASS=0
FAIL=0
SKIP=0

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
log()  { echo -e "[api_check] $*"; }
pass() { echo -e "${GREEN}  ✔ $*${NC}"; ((PASS++)); }
fail() { echo -e "${RED}  ✘ $*${NC}"; ((FAIL++)); }
skip() { echo -e "${YELLOW}  ⊘ $*${NC}"; ((SKIP++)); }

# Perform a GET request with retry logic.
# Usage: http_get <path> [expected_status]
http_get() {
  local path="$1"
  local expected="${2:-200}"
  local url="${BASE_URL}${path}"
  local attempt=0
  local status

  while (( attempt < MAX_RETRIES )); do
    status=$(curl -s -o /dev/null -w "%{http_code}" \
      --max-time "${TIMEOUT}" \
      --header "Accept: application/json" \
      "${url}" 2>/dev/null) || status="000"

    if [[ "${status}" == "${expected}" ]]; then
      echo "${status}"
      return 0
    fi

    ((attempt++)) || true
    sleep "${RETRY_DELAY}"
  done

  echo "${status}"
  return 1
}

# Perform a POST request and return the HTTP status code.
http_post() {
  local path="$1"
  local body="$2"
  local expected="${3:-200}"
  local url="${BASE_URL}${path}"

  local status
  status=$(curl -s -o /dev/null -w "%{http_code}" \
    --max-time "${TIMEOUT}" \
    --header "Content-Type: application/json" \
    --header "Accept: application/json" \
    --data "${body}" \
    "${url}" 2>/dev/null) || status="000"

  echo "${status}"
  [[ "${status}" == "${expected}" ]]
}

# ---------------------------------------------------------------------------
# Test cases
# ---------------------------------------------------------------------------
check_health_endpoint() {
  log "Checking /health …"
  local status
  status=$(http_get "/health" 200) || true
  if [[ "${status}" == "200" ]]; then
    pass "/health returned 200"
  else
    fail "/health returned ${status} (expected 200)"
  fi
}

check_api_docs() {
  log "Checking API docs endpoint …"
  local status
  status=$(http_get "/docs" 200) || true
  if [[ "${status}" == "200" ]]; then
    pass "/docs returned 200"
  else
    skip "/docs returned ${status} — docs may be disabled in production"
  fi
}

check_chat_endpoint() {
  log "Checking /api/chat/stream …"
  # A minimal payload; we only validate the server accepts the request.
  local payload='{"messages":[{"role":"user","content":"ping"}],"thread_id":"smoke-test"}'
  local status
  status=$(http_post "/api/chat/stream" "${payload}" 200) || status="$?"
  # Accept 200 or 422 (validation error) — both mean the route exists.
  if [[ "${status}" =~ ^(200|422)$ ]]; then
    pass "/api/chat/stream is reachable (status ${status})"
  else
    fail "/api/chat/stream returned ${status}"
  fi
}

check_models_endpoint() {
  log "Checking /api/models …"
  local status
  status=$(http_get "/api/models" 200) || true
  if [[ "${status}" == "200" ]]; then
    pass "/api/models returned 200"
  else
    fail "/api/models returned ${status} (expected 200)"
  fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
  log "Starting API checks against ${BASE_URL}"
  echo "----------------------------------------------"

  check_health_endpoint
  check_api_docs
  check_chat_endpoint
  check_models_endpoint

  echo "----------------------------------------------"
  echo -e "Results — ${GREEN}passed: ${PASS}${NC}  ${RED}failed: ${FAIL}${NC}  ${YELLOW}skipped: ${SKIP}${NC}"

  if (( FAIL > 0 )); then
    log "One or more API checks failed."
    exit 1
  fi

  log "All API checks passed."
  exit 0
}

main "$@"

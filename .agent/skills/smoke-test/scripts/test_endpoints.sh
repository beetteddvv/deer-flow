#!/bin/bash
# test_endpoints.sh - Validates specific API endpoints with expected responses
# Part of the deer-flow smoke test suite

set -euo pipefail

# ── Config ────────────────────────────────────────────────────────────────────
BACKEND_URL="${BACKEND_URL:-http://localhost:8000}"
FRONTEND_URL="${FRONTEND_URL:-http://localhost:3000}"
TIMEOUT="${REQUEST_TIMEOUT:-10}"
PASS=0
FAIL=0
SKIP=0

# Colors
GREEN=$(tput setaf 2 2>/dev/null || echo '')
RED=$(tput setaf 1 2>/dev/null || echo '')
YELLOW=$(tput setaf 3 2>/dev/null || echo '')
RESET=$(tput sgr0 2>/dev/null || echo '')

# ── Helpers ───────────────────────────────────────────────────────────────────
pass() { echo "  ${GREEN}✓${RESET} $1"; ((PASS++)); }
fail() { echo "  ${RED}✗${RESET} $1"; ((FAIL++)); }
skip() { echo "  ${YELLOW}~${RESET} $1 (skipped)"; ((SKIP++)); }

# Perform a GET request and check HTTP status code
check_status() {
  local label="$1"
  local url="$2"
  local expected_status="${3:-200}"

  local actual_status
  actual_status=$(curl -s -o /dev/null -w "%{http_code}" \
    --max-time "$TIMEOUT" "$url" 2>/dev/null) || actual_status="000"

  if [[ "$actual_status" == "$expected_status" ]]; then
    pass "$label → HTTP $actual_status"
  else
    fail "$label → expected HTTP $expected_status, got $actual_status ($url)"
  fi
}

# Perform a GET request and check that the body contains a substring
check_body_contains() {
  local label="$1"
  local url="$2"
  local needle="$3"

  local body
  body=$(curl -s --max-time "$TIMEOUT" "$url" 2>/dev/null) || body=""

  if echo "$body" | grep -q "$needle"; then
    pass "$label → body contains '$needle'"
  else
    fail "$label → body missing '$needle' ($url)"
  fi
}

# POST JSON and check response status
check_post_status() {
  local label="$1"
  local url="$2"
  local payload="$3"
  local expected_status="${4:-200}"

  local actual_status
  actual_status=$(curl -s -o /dev/null -w "%{http_code}" \
    --max-time "$TIMEOUT" \
    -X POST \
    -H 'Content-Type: application/json' \
    -d "$payload" \
    "$url" 2>/dev/null) || actual_status="000"

  if [[ "$actual_status" == "$expected_status" ]]; then
    pass "$label → HTTP $actual_status"
  else
    fail "$label → expected HTTP $expected_status, got $actual_status ($url)"
  fi
}

# ── Backend endpoint tests ────────────────────────────────────────────────────
test_backend() {
  echo ""
  echo "Backend: $BACKEND_URL"
  echo "─────────────────────────────────────"

  check_status   "GET /health"              "$BACKEND_URL/health"
  check_status   "GET /api/v1/models"       "$BACKEND_URL/api/v1/models"
  check_body_contains "GET /health returns ok" "$BACKEND_URL/health" '"status"'

  # Chat completions endpoint should reject empty payload with 422
  check_post_status "POST /api/v1/chat/completions (empty body → 422)" \
    "$BACKEND_URL/api/v1/chat/completions" '{}' "422"

  # Docs / OpenAPI schema
  check_status   "GET /docs"                "$BACKEND_URL/docs"
  check_status   "GET /openapi.json"        "$BACKEND_URL/openapi.json"
}

# ── Frontend endpoint tests ───────────────────────────────────────────────────
test_frontend() {
  echo ""
  echo "Frontend: $FRONTEND_URL"
  echo "─────────────────────────────────────"

  check_status        "GET /"                "$FRONTEND_URL/"
  check_body_contains "/ contains <html>"    "$FRONTEND_URL/" '<html'
  check_status        "GET /favicon.ico"     "$FRONTEND_URL/favicon.ico"
}

# ── Main ──────────────────────────────────────────────────────────────────────
main() {
  echo "====================================="
  echo " Endpoint Tests"
  echo "====================================="

  test_backend
  test_frontend

  echo ""
  echo "─────────────────────────────────────"
  echo "Results: ${GREEN}${PASS} passed${RESET}  ${RED}${FAIL} failed${RESET}  ${YELLOW}${SKIP} skipped${RESET}"
  echo ""

  if [[ $FAIL -gt 0 ]]; then
    exit 1
  fi
}

main "$@"

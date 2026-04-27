#!/bin/bash
# report_results.sh - Aggregate and report smoke test results
# Collects outputs from all check scripts and generates a summary report

set -euo pipefail

# ── Config ────────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPORT_DIR="${REPORT_DIR:-/tmp/deer-flow-smoke-test}"
REPORT_FILE="${REPORT_DIR}/summary_$(date +%Y%m%d_%H%M%S).txt"
JSON_REPORT="${REPORT_DIR}/summary_$(date +%Y%m%d_%H%M%S).json"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Colour codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Colour

# ── Helpers ───────────────────────────────────────────────────────────────────
log()  { echo -e "${BLUE}[REPORT]${NC} $*"; }
pass() { echo -e "${GREEN}[PASS]${NC}   $*"; }
fail() { echo -e "${RED}[FAIL]${NC}   $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC}   $*"; }

mkdir -p "${REPORT_DIR}"

# ── Result tracking ───────────────────────────────────────────────────────────
declare -A RESULTS       # check_name -> PASS | FAIL | SKIP
declare -A DURATIONS     # check_name -> seconds
declare -A MESSAGES      # check_name -> detail message
TOTAL_PASS=0
TOTAL_FAIL=0
TOTAL_SKIP=0

record_result() {
  local name="$1"
  local status="$2"   # PASS | FAIL | SKIP
  local duration="$3"
  local message="${4:-}"

  RESULTS["$name"]="$status"
  DURATIONS["$name"]="$duration"
  MESSAGES["$name"]="$message"

  case "$status" in
    PASS) (( TOTAL_PASS++ )); pass "${name} (${duration}s)" ;;
    FAIL) (( TOTAL_FAIL++ )); fail "${name} (${duration}s) — ${message}" ;;
    SKIP) (( TOTAL_SKIP++ )); warn "${name} — skipped: ${message}" ;;
  esac
}

# ── Run a single check script and capture result ───────────────────────────────
run_check() {
  local name="$1"
  local script="$2"
  shift 2
  local args=("$@")

  if [[ ! -x "$script" ]]; then
    record_result "$name" "SKIP" 0 "script not found or not executable: $script"
    return
  fi

  local start end duration output exit_code
  start=$(date +%s)
  output=$("$script" "${args[@]}" 2>&1) && exit_code=0 || exit_code=$?
  end=$(date +%s)
  duration=$(( end - start ))

  if [[ $exit_code -eq 0 ]]; then
    record_result "$name" "PASS" "$duration"
  else
    # Grab last non-empty line as short message
    local short_msg
    short_msg=$(echo "$output" | grep -v '^$' | tail -1 | cut -c1-120)
    record_result "$name" "FAIL" "$duration" "$short_msg"
    # Persist full output for debugging
    echo "=== $name ==" >> "${REPORT_DIR}/details.log"
    echo "$output"      >> "${REPORT_DIR}/details.log"
  fi
}

# ── Execute all checks ─────────────────────────────────────────────────────────
log "Starting deer-flow smoke-test suite — ${TIMESTAMP}"
log "Reports will be written to: ${REPORT_DIR}"
echo

run_check "local_env"   "${SCRIPT_DIR}/check_local_env.sh"
run_check "docker_env"  "${SCRIPT_DIR}/check_docker.sh"
run_check "deploy_local" "${SCRIPT_DIR}/deploy_local.sh"
run_check "deploy_docker" "${SCRIPT_DIR}/deploy_docker.sh"
run_check "frontend"    "${SCRIPT_DIR}/frontend_check.sh"
run_check "all_checks"  "${SCRIPT_DIR}/run_all_checks.sh"

# ── Write plain-text summary ───────────────────────────────────────────────────
{
  echo "deer-flow Smoke Test Report"
  echo "Generated : ${TIMESTAMP}"
  echo "Host      : $(hostname)"
  echo "-------------------------------------------"
  printf "%-20s  %-6s  %s\n" "Check" "Status" "Duration"
  echo "-------------------------------------------"
  for name in "${!RESULTS[@]}"; do
    printf "%-20s  %-6s  %ss\n" "$name" "${RESULTS[$name]}" "${DURATIONS[$name]}"
  done
  echo "-------------------------------------------"
  echo "PASS: ${TOTAL_PASS}  FAIL: ${TOTAL_FAIL}  SKIP: ${TOTAL_SKIP}"
} | tee "${REPORT_FILE}"

# ── Write JSON summary ─────────────────────────────────────────────────────────
{
  echo "{"
  echo "  \"timestamp\": \"${TIMESTAMP}\","
  echo "  \"host\": \"$(hostname)\","
  echo "  \"totals\": { \"pass\": ${TOTAL_PASS}, \"fail\": ${TOTAL_FAIL}, \"skip\": ${TOTAL_SKIP} },"
  echo "  \"checks\": ["
  local first=true
  for name in "${!RESULTS[@]}"; do
    $first || echo ","
    first=false
    printf '    { "name": "%s", "status": "%s", "duration_s": %s, "message": "%s" }' \
      "$name" "${RESULTS[$name]}" "${DURATIONS[$name]}" "${MESSAGES[$name]//"/\\"}"
  done
  echo
  echo "  ]"
  echo "}"
} > "${JSON_REPORT}"

log "Plain-text report : ${REPORT_FILE}"
log "JSON report       : ${JSON_REPORT}"
echo

# ── Exit code reflects overall result ─────────────────────────────────────────
if [[ $TOTAL_FAIL -gt 0 ]]; then
  fail "Smoke test FAILED — ${TOTAL_FAIL} check(s) did not pass."
  exit 1
else
  pass "All checks passed (${TOTAL_PASS} pass, ${TOTAL_SKIP} skipped)."
  exit 0
fi

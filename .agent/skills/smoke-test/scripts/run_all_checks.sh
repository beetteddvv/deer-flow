#!/bin/bash
# run_all_checks.sh - Master smoke test runner
# Orchestrates all smoke test checks and produces a summary report

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
LOG_DIR="${SCRIPT_DIR}/../logs"
LOG_FILE="${LOG_DIR}/smoke_test_${TIMESTAMP}.log"
SUMMARY_FILE="${LOG_DIR}/smoke_test_${TIMESTAMP}_summary.txt"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Track results
PASS=0
FAIL=0
SKIP=0

mkdir -p "$LOG_DIR"

log() {
    echo -e "$1" | tee -a "$LOG_FILE"
}

run_check() {
    local name="$1"
    local script="$2"
    local required="${3:-true}"

    log "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    log "${BLUE}▶ Running: ${name}${NC}"
    log "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    if [ ! -f "$script" ]; then
        log "${YELLOW}⚠ SKIP: Script not found: ${script}${NC}"
        ((SKIP++)) || true
        echo "SKIP  | ${name}" >> "$SUMMARY_FILE"
        return 0
    fi

    if bash "$script" >> "$LOG_FILE" 2>&1; then
        log "${GREEN}✔ PASS: ${name}${NC}"
        ((PASS++)) || true
        echo "PASS  | ${name}" >> "$SUMMARY_FILE"
    else
        local exit_code=$?
        log "${RED}✘ FAIL: ${name} (exit code: ${exit_code})${NC}"
        ((FAIL++)) || true
        echo "FAIL  | ${name}" >> "$SUMMARY_FILE"
        if [ "$required" = "true" ]; then
            log "${RED}Required check failed. See log: ${LOG_FILE}${NC}"
        fi
    fi
}

print_summary() {
    local total=$((PASS + FAIL + SKIP))
    log "\n${BLUE}╔══════════════════════════════════════╗${NC}"
    log "${BLUE}║         SMOKE TEST SUMMARY           ║${NC}"
    log "${BLUE}╚══════════════════════════════════════╝${NC}"
    log "  Total checks : ${total}"
    log "  ${GREEN}Passed        : ${PASS}${NC}"
    log "  ${RED}Failed        : ${FAIL}${NC}"
    log "  ${YELLOW}Skipped       : ${SKIP}${NC}"
    log "\n  Log file      : ${LOG_FILE}"
    log "  Summary file  : ${SUMMARY_FILE}"

    if [ "$FAIL" -gt 0 ]; then
        log "\n${RED}✘ Smoke test FAILED — ${FAIL} check(s) did not pass.${NC}"
        log "  Refer to .agent/skills/smoke-test/references/troubleshooting.md for help."
        return 1
    else
        log "\n${GREEN}✔ Smoke test PASSED — all required checks OK.${NC}"
        return 0
    fi
}

# ── Parse flags ───────────────────────────────────────────────────────────────
MODE="local"  # default: local | docker
while [[ $# -gt 0 ]]; do
    case "$1" in
        --docker) MODE="docker" ;;
        --local)  MODE="local" ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
    shift
done

# ── Header ────────────────────────────────────────────────────────────────────
log "${BLUE}DeerFlow Smoke Test Suite${NC}"
log "Mode      : ${MODE}"
log "Started   : $(date)"
log "Log       : ${LOG_FILE}"

# Initialise summary file
echo "DeerFlow Smoke Test — ${TIMESTAMP}" > "$SUMMARY_FILE"
echo "Mode: ${MODE}" >> "$SUMMARY_FILE"
echo "--------------------------------------" >> "$SUMMARY_FILE"

# ── Run checks ────────────────────────────────────────────────────────────────
if [ "$MODE" = "docker" ]; then
    run_check "Docker environment"   "${SCRIPT_DIR}/check_docker.sh"    true
    run_check "Deploy (Docker)"      "${SCRIPT_DIR}/deploy_docker.sh"   true
else
    run_check "Local environment"    "${SCRIPT_DIR}/check_local_env.sh" true
    run_check "Deploy (local)"       "${SCRIPT_DIR}/deploy_local.sh"    true
fi

run_check "Frontend health" "${SCRIPT_DIR}/frontend_check.sh" true

# ── Summary ───────────────────────────────────────────────────────────────────
print_summary

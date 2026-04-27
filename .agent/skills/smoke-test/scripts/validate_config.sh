#!/bin/bash
# validate_config.sh - Validates environment configuration before smoke tests
# Checks for required env vars, config files, and service dependencies

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"

# Source common utilities if available
if [[ -f "$SCRIPT_DIR/common.sh" ]]; then
  source "$SCRIPT_DIR/common.sh"
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASS=0
FAIL=0
WARN=0

log_pass() { echo -e "${GREEN}[PASS]${NC} $1"; ((PASS++)); }
log_fail() { echo -e "${RED}[FAIL]${NC} $1"; ((FAIL++)); }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; ((WARN++)); }
log_info() { echo -e "[INFO] $1"; }

echo "======================================"
echo " DeerFlow Config Validation"
echo "======================================"
echo ""

# Check for .env file
log_info "Checking environment files..."
if [[ -f "$PROJECT_ROOT/.env" ]]; then
  log_pass ".env file exists"
  ENV_FILE="$PROJECT_ROOT/.env"
elif [[ -f "$PROJECT_ROOT/.env.example" ]]; then
  log_warn ".env not found, using .env.example (some checks may fail)"
  ENV_FILE="$PROJECT_ROOT/.env.example"
else
  log_fail "No .env or .env.example found in project root"
  ENV_FILE=""
fi

# Required environment variables
REQUIRED_VARS=(
  "OPENAI_API_KEY"
  "TAVILY_API_KEY"
)

OPTIONAL_VARS=(
  "OPENAI_BASE_URL"
  "OPENAI_MODEL"
  "MAX_SEARCH_RESULTS"
  "LOG_LEVEL"
)

log_info "Checking required environment variables..."
for var in "${REQUIRED_VARS[@]}"; do
  if [[ -n "${!var:-}" ]]; then
    log_pass "$var is set"
  elif [[ -n "$ENV_FILE" ]] && grep -q "^${var}=" "$ENV_FILE" 2>/dev/null; then
    val=$(grep "^${var}=" "$ENV_FILE" | cut -d'=' -f2- | tr -d '"\'')
    if [[ -n "$val" && "$val" != "your_*" && "$val" != "<*>" ]]; then
      log_pass "$var found in env file"
    else
      log_fail "$var is empty or placeholder in env file"
    fi
  else
    log_fail "$var is not set (required)"
  fi
done

log_info "Checking optional environment variables..."
for var in "${OPTIONAL_VARS[@]}"; do
  if [[ -n "${!var:-}" ]]; then
    log_pass "$var is set"
  else
    log_warn "$var not set (optional, defaults will be used)"
  fi
done

# Check required config files
log_info "Checking required project files..."
REQUIRED_FILES=(
  "pyproject.toml"
  "src/server.py"
  "web/package.json"
)

for file in "${REQUIRED_FILES[@]}"; do
  if [[ -f "$PROJECT_ROOT/$file" ]]; then
    log_pass "$file exists"
  else
    log_fail "$file not found"
  fi
done

# Check Python version
log_info "Checking Python version..."
if command -v python3 &>/dev/null; then
  PY_VERSION=$(python3 --version 2>&1 | awk '{print $2}')
  PY_MAJOR=$(echo "$PY_VERSION" | cut -d'.' -f1)
  PY_MINOR=$(echo "$PY_VERSION" | cut -d'.' -f2)
  if [[ "$PY_MAJOR" -ge 3 && "$PY_MINOR" -ge 11 ]]; then
    log_pass "Python $PY_VERSION (>=3.11 required)"
  else
    log_fail "Python $PY_VERSION is too old (need >=3.11)"
  fi
else
  log_fail "python3 not found"
fi

# Check Node version
log_info "Checking Node.js version..."
if command -v node &>/dev/null; then
  NODE_VERSION=$(node --version | sed 's/v//')
  NODE_MAJOR=$(echo "$NODE_VERSION" | cut -d'.' -f1)
  if [[ "$NODE_MAJOR" -ge 18 ]]; then
    log_pass "Node.js v$NODE_VERSION (>=18 required)"
  else
    log_fail "Node.js v$NODE_VERSION is too old (need >=18)"
  fi
else
  log_fail "node not found"
fi

# Summary
echo ""
echo "======================================"
echo " Validation Summary"
echo "======================================"
echo -e " ${GREEN}Passed:${NC}  $PASS"
echo -e " ${YELLOW}Warnings:${NC} $WARN"
echo -e " ${RED}Failed:${NC}  $FAIL"
echo ""

if [[ $FAIL -gt 0 ]]; then
  echo -e "${RED}Config validation FAILED — fix issues before running smoke tests${NC}"
  exit 1
else
  echo -e "${GREEN}Config validation PASSED${NC}"
  exit 0
fi

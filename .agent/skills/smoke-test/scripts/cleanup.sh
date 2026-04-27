#!/usr/bin/env bash
# cleanup.sh - Clean up smoke test artifacts, temp files, and optionally tear down deployments
# Usage: ./cleanup.sh [--docker] [--logs] [--all]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"
LOGS_DIR="${PROJECT_ROOT}/.agent/logs/smoke-test"
TMP_DIR="${PROJECT_ROOT}/.agent/tmp/smoke-test"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

CLEAN_DOCKER=false
CLEAN_LOGS=false
CLEAN_ALL=false

usage() {
  echo "Usage: $0 [OPTIONS]"
  echo ""
  echo "Options:"
  echo "  --docker    Stop and remove smoke-test Docker containers/networks"
  echo "  --logs      Remove smoke-test log files"
  echo "  --all       Perform all cleanup actions"
  echo "  -h, --help  Show this help message"
  exit 0
}

parse_args() {
  for arg in "$@"; do
    case $arg in
      --docker) CLEAN_DOCKER=true ;;
      --logs)   CLEAN_LOGS=true ;;
      --all)    CLEAN_ALL=true ;;
      -h|--help) usage ;;
      *) echo -e "${YELLOW}Unknown option: $arg${NC}" && usage ;;
    esac
  done

  if [[ "$CLEAN_ALL" == true ]]; then
    CLEAN_DOCKER=true
    CLEAN_LOGS=true
  fi
}

clean_tmp() {
  if [[ -d "$TMP_DIR" ]]; then
    echo -e "${YELLOW}Removing temp directory: $TMP_DIR${NC}"
    rm -rf "$TMP_DIR"
    echo -e "${GREEN}Temp files removed.${NC}"
  else
    echo "No temp directory found, skipping."
  fi
}

clean_logs() {
  if [[ -d "$LOGS_DIR" ]]; then
    echo -e "${YELLOW}Removing log directory: $LOGS_DIR${NC}"
    rm -rf "$LOGS_DIR"
    echo -e "${GREEN}Logs removed.${NC}"
  else
    echo "No logs directory found, skipping."
  fi
}

clean_docker() {
  echo -e "${YELLOW}Stopping smoke-test Docker containers...${NC}"

  # Stop containers with the smoke-test label if they exist
  local containers
  containers=$(docker ps -aq --filter "label=smoke-test=true" 2>/dev/null || true)

  if [[ -n "$containers" ]]; then
    docker stop $containers && docker rm $containers
    echo -e "${GREEN}Containers stopped and removed.${NC}"
  else
    echo "No smoke-test containers running."
  fi

  # Remove dedicated smoke-test network if present
  if docker network ls --format '{{.Name}}' | grep -q '^smoke-test-net$'; then
    docker network rm smoke-test-net
    echo -e "${GREEN}Docker network 'smoke-test-net' removed.${NC}"
  fi
}

main() {
  parse_args "$@"

  echo "======================================"
  echo "  DeerFlow Smoke Test Cleanup"
  echo "======================================"

  # Always clean temp files
  clean_tmp

  if [[ "$CLEAN_DOCKER" == true ]]; then
    clean_docker
  fi

  if [[ "$CLEAN_LOGS" == true ]]; then
    clean_logs
  fi

  if [[ "$CLEAN_DOCKER" == false && "$CLEAN_LOGS" == false ]]; then
    echo -e "${YELLOW}No specific cleanup flags provided. Only temp files were removed.${NC}"
    echo "Run with --help to see available options."
  fi

  echo ""
  echo -e "${GREEN}Cleanup complete.${NC}"
}

main "$@"

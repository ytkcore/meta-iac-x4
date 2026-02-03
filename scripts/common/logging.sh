#!/bin/bash
# =============================================================================
# Common Logging Utility
# =============================================================================

# Colors
export COLOR_GREEN='\033[32m'
export COLOR_YELLOW='\033[33m'
export COLOR_CYAN='\033[36m'
export COLOR_RED='\033[31m'
export COLOR_DIM='\033[2m'
export COLOR_NC='\033[0m'
export COLOR_BOLD='\033[1m'

# Log File Setup (Defaults)
# If LOG_FILE is already set, use it. Otherwise, use a default global log.
if [[ -z "${LOG_FILE:-}" ]]; then
  GLOBAL_LOG_DIR="$(pwd)/logs/global"
  mkdir -p "$GLOBAL_LOG_DIR"
  export LOG_FILE="${GLOBAL_LOG_DIR}/operation-$(date +%Y%m%d).log"
fi

_log_to_file() {
    local level="$1"
    shift
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    local msg="$*"

    # Ensure log directory exists
    mkdir -p "$(dirname "$LOG_FILE")"

    # Strip ANSI escape codes for clean text logs
    local clean_msg
    clean_msg=$(echo "$msg" | sed 's/\x1B\[[0-9;]*[mK]//g' | sed 's/\\033\[[0-9;]*[mK]//g')

    printf "[%s] [%-5s] %s\n" "$timestamp" "$level" "$clean_msg" >> "$LOG_FILE"
}

# Human-readable console + log file functions
ok()     { echo -e "  ${COLOR_GREEN}✓${COLOR_NC} $*"; _log_to_file "OK" "$*"; }
warn()   { echo -e "  ${COLOR_YELLOW}!${COLOR_NC} $*"; _log_to_file "WARN" "$*"; }
err()    { echo -e "  ${COLOR_RED}✗${COLOR_NC} $*" >&2; _log_to_file "ERROR" "$*"; }
info()   { echo -e "  ${COLOR_DIM}$*${COLOR_NC}"; _log_to_file "INFO" "$*"; }
header() { echo -e "\n${COLOR_BOLD}${COLOR_CYAN}>>> $*${COLOR_NC}"; _log_to_file "HEAD" "$*"; }

# Operational Checkpoint (Special log for key architectural changes)
checkpoint() {
    echo -e "\n${COLOR_BOLD}${COLOR_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_NC}"
    echo -e "${COLOR_BOLD}${COLOR_CYAN}[CHECKPOINT]${COLOR_NC} $*"
    echo -e "${COLOR_BOLD}${COLOR_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_NC}"
    _log_to_file "CHECK" "!!! $* !!!"
}

# Export these for subshells if needed
export -f ok warn err info header checkpoint _log_to_file

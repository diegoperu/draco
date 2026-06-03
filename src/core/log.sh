#!/usr/bin/env bash
# DRACO - log.sh: Logging utilities
# GNU GPL v3 - See LICENSE

# ─── Color definitions ────────────────────────────────────────────────────────
_draco_colors_init() {
    if [[ "${DRACO_NO_COLOR:-0}" -eq 1 ]] || [[ ! -t 1 && "${DRACO_FORCE_COLOR:-0}" -eq 0 ]]; then
        C_RESET=""
        C_RED=""
        C_GREEN=""
        C_YELLOW=""
        C_BLUE=""
        C_CYAN=""
        C_MAGENTA=""
        C_BOLD=""
        C_DIM=""
    else
        C_RESET="\033[0m"
        C_RED="\033[0;31m"
        C_GREEN="\033[0;32m"
        C_YELLOW="\033[0;33m"
        C_BLUE="\033[0;34m"
        C_CYAN="\033[0;36m"
        C_MAGENTA="\033[0;35m"
        C_BOLD="\033[1m"
        C_DIM="\033[2m"
    fi
}

_draco_colors_init

# ─── Log levels ───────────────────────────────────────────────────────────────
# 0=DEBUG 1=INFO 2=WARN 3=ERROR
DRACO_LOG_LEVEL="${DRACO_LOG_LEVEL:-1}"

draco_log_init() {
    mkdir -p "$DRACO_LOG_DIR"
    DRACO_SESSION_LOG="${DRACO_LOG_DIR}/draco-$(date +%Y%m%d-%H%M%S).log"
    export DRACO_SESSION_LOG

    [[ "${DRACO_VERBOSE:-0}" -eq 1 ]] && DRACO_LOG_LEVEL=0 || true
    [[ "${DRACO_QUIET:-0}" -eq 1 ]]   && DRACO_LOG_LEVEL=3 || true
}

_draco_log() {
    local level="$1"
    local level_num="$2"
    local color="$3"
    shift 3
    local msg="$*"
    local ts
    ts="$(date '+%Y-%m-%d %H:%M:%S')"

    # Write to log file always
    if [[ -n "${DRACO_SESSION_LOG:-}" ]]; then
        echo "[$ts] [$level] $msg" >> "$DRACO_SESSION_LOG" 2>/dev/null || true
    fi

    # Write to stderr/stdout based on level
    if [[ "$level_num" -ge "${DRACO_LOG_LEVEL:-1}" ]]; then
        if [[ "$level_num" -ge 3 ]]; then
            echo -e "${color}[${level}]${C_RESET} $msg" >&2
        else
            echo -e "${color}[${level}]${C_RESET} $msg"
        fi
    fi
}

draco_debug() { _draco_log "DEBUG" 0 "${C_DIM}"     "$@"; }
draco_info()  { _draco_log "INFO"  1 "${C_GREEN}"   "$@"; }
draco_warn()  { _draco_log "WARN"  2 "${C_YELLOW}"  "$@"; }
draco_error() { _draco_log "ERROR" 3 "${C_RED}"     "$@"; }

draco_fatal() {
    draco_error "$@"
    exit 1
}

draco_step() {
    local msg="$*"
    echo -e "${C_BOLD}${C_CYAN}  ▶ ${msg}${C_RESET}"
    if [[ -n "${DRACO_SESSION_LOG:-}" ]]; then
        echo "[STEP] $msg" >> "$DRACO_SESSION_LOG" 2>/dev/null || true
    fi
}

draco_ok() {
    local msg="$*"
    echo -e "${C_GREEN}  ✓ ${msg}${C_RESET}"
}

draco_skip() {
    local msg="$*"
    echo -e "${C_DIM}  - ${msg} (skipped)${C_RESET}"
}

# ─── Backup log file (separate from session log) ──────────────────────────────
draco_backup_log_write() {
    local backup_id="$1"
    local log_file="${DRACO_BACKUP_DIR}/.meta/${backup_id}.log"
    shift
    mkdir -p "${DRACO_BACKUP_DIR}/.meta"
    echo "$@" >> "$log_file"
}

draco_backup_log_show() {
    local backup_id="${1:-}"
    if [[ -z "$backup_id" ]]; then
        draco_error "No backup ID specified."
        return 1
    fi
    local log_file="${DRACO_BACKUP_DIR}/.meta/${backup_id}.log"
    if [[ ! -f "$log_file" ]]; then
        draco_error "No log found for backup: $backup_id"
        return 1
    fi
    cat "$log_file"
}

draco_backup_show_log() {
    local backup_id="${1:-}"
    if [[ -z "$backup_id" ]]; then
        # Show last backup log
        backup_id="$(draco_get_last_backup_id)"
    fi
    draco_backup_log_show "$backup_id"
}

#!/usr/bin/env bash
# DRACO - tui/tui.sh: Terminal UI using whiptail/dialog with themes
# GNU GPL v3 - See LICENSE

# ─── TUI backend detection ────────────────────────────────────────────────────
_DRACO_TUI_BIN=""
draco_tui_detect() {
    if command -v whiptail &>/dev/null; then
        _DRACO_TUI_BIN="whiptail"
    elif command -v dialog &>/dev/null; then
        _DRACO_TUI_BIN="dialog"
    else
        draco_fatal "TUI requires 'whiptail' (package: newt / libnewt) or 'dialog'. Neither found."
    fi
}

# ─── Theme definitions ────────────────────────────────────────────────────────
# whiptail uses NEWT_COLORS env var
# dialog uses --colors and terminal escape codes (limited)

draco_tui_apply_theme() {
    local theme="${DRACO_TUI_THEME:-default}"

    case "$theme" in
        default)
            # Plain white/black - no color env
            unset NEWT_COLORS
            ;;

        blue)
            # Blue and white - classic sysadmin
            export NEWT_COLORS='
root=white,blue
border=white,blue
window=white,blue
shadow=black,blue
title=white,blue
button=black,white
actbutton=white,blue
checkbox=white,blue
actcheckbox=black,white
entry=white,blue
label=white,blue
listbox=white,blue
actlistbox=black,white
sellistbox=white,black
actsellistbox=white,black
textbox=white,blue
acttextbox=black,white
helpline=black,white
roottext=white,blue
'
            ;;

        anthropic)
            # Anthropic brand: coral/cream on dark
            # Closest approximation with terminal colors
            export NEWT_COLORS='
root=white,black
border=red,black
window=white,black
shadow=black,black
title=red,black
button=black,red
actbutton=white,red
checkbox=white,black
actcheckbox=black,red
entry=white,black
label=red,black
listbox=white,black
actlistbox=black,red
sellistbox=white,red
actsellistbox=white,red
textbox=white,black
acttextbox=black,red
helpline=white,black
roottext=red,black
'
            ;;

        eva01)
            # Evangelion Unit 01 - purple and green on black
            export NEWT_COLORS='
root=green,black
border=magenta,black
window=green,black
shadow=black,black
title=magenta,black
button=black,magenta
actbutton=green,magenta
checkbox=green,black
actcheckbox=black,magenta
entry=green,black
label=magenta,black
listbox=green,black
actlistbox=black,magenta
sellistbox=green,magenta
actsellistbox=green,magenta
textbox=green,black
acttextbox=black,magenta
helpline=green,black
roottext=magenta,black
'
            ;;

        matrix)
            # The Matrix - green on black
            export NEWT_COLORS='
root=green,black
border=green,black
window=green,black
shadow=black,black
title=green,black
button=black,green
actbutton=black,green
checkbox=green,black
actcheckbox=black,green
entry=green,black
label=green,black
listbox=green,black
actlistbox=black,green
sellistbox=green,black
actsellistbox=black,green
textbox=green,black
acttextbox=black,green
helpline=black,green
roottext=green,black
'
            ;;
    esac
}

# ─── Wrapper functions ────────────────────────────────────────────────────────
draco_tui_msgbox() {
    local title="$1"
    local msg="$2"
    local h="${3:-10}"
    local w="${4:-70}"
    "$_DRACO_TUI_BIN" --title "$title" --msgbox "$msg" "$h" "$w" 3>&1 1>&2 2>&3
}

draco_tui_yesno() {
    local title="$1"
    local msg="$2"
    local h="${3:-8}"
    local w="${4:-60}"
    "$_DRACO_TUI_BIN" --title "$title" --yesno "$msg" "$h" "$w" 3>&1 1>&2 2>&3
}

draco_tui_menu() {
    local title="$1"
    local prompt="$2"
    local h="${3:-20}"
    local w="${4:-70}"
    local list_h="${5:-10}"
    shift 5
    # Remaining: item pairs
    "$_DRACO_TUI_BIN" --title "$title" --menu "$prompt" "$h" "$w" "$list_h" \
        "$@" 3>&1 1>&2 2>&3
}

draco_tui_inputbox() {
    local title="$1"
    local prompt="$2"
    local default="${3:-}"
    local h="${4:-8}"
    local w="${5:-60}"
    "$_DRACO_TUI_BIN" --title "$title" --inputbox "$prompt" "$h" "$w" "$default" \
        3>&1 1>&2 2>&3
}

draco_tui_passwordbox() {
    local title="$1"
    local prompt="$2"
    local h="${3:-8}"
    local w="${4:-60}"
    "$_DRACO_TUI_BIN" --title "$title" --passwordbox "$prompt" "$h" "$w" \
        3>&1 1>&2 2>&3
}

draco_tui_textbox() {
    local title="$1"
    local file="$2"
    local h="${3:-20}"
    local w="${4:-78}"
    "$_DRACO_TUI_BIN" --title "$title" --scrolltext --textbox "$file" "$h" "$w" \
        3>&1 1>&2 2>&3 || true
}

draco_tui_checklist() {
    local title="$1"
    local prompt="$2"
    local h="${3:-20}"
    local w="${4:-70}"
    local list_h="${5:-10}"
    shift 5
    "$_DRACO_TUI_BIN" --title "$title" --checklist "$prompt" "$h" "$w" "$list_h" \
        "$@" 3>&1 1>&2 2>&3
}

# ─── Main TUI ─────────────────────────────────────────────────────────────────
draco_tui_main() {
    draco_tui_detect
    draco_tui_apply_theme
    clear

    while true; do
        local choice
        choice="$(draco_tui_menu \
            "DRACO v${DRACO_VERSION}" \
            "Dotfile & Runtime Archive and Configuration Orchestrator\n\nBackup dir: ${DRACO_BACKUP_DIR:-'(not configured)'}\nLast backup: $(draco_get_last_backup_id 2>/dev/null || echo 'none')\nStorage: $(draco_backup_total_size 2>/dev/null || echo '0')" \
            22 72 8 \
            "BACKUP"   "Run backup now" \
            "RESTORE"  "Restore a backup" \
            "LIST"     "List backups and storage usage" \
            "LOG"      "View backup logs and diffs" \
            "DELETE"   "Delete backup(s)" \
            "SCHEDULE" "Manage automatic schedule" \
            "CONFIG"   "Configure DRACO settings" \
            "ABOUT"    "About DRACO" \
        )" || { clear; exit 0; }

        case "$choice" in
            BACKUP)   draco_tui_backup ;;
            RESTORE)  draco_tui_restore ;;
            LIST)     draco_tui_list ;;
            LOG)      draco_tui_log ;;
            DELETE)   draco_tui_delete ;;
            SCHEDULE) draco_tui_schedule ;;
            CONFIG)   draco_tui_config ;;
            ABOUT)    draco_tui_about ;;
        esac
    done
}

# ─── Backup screen ────────────────────────────────────────────────────────────
draco_tui_backup() {
    if draco_tui_yesno "DRACO - Backup" "Start backup now?\n\nDestination: ${DRACO_BACKUP_DIR:-'(not configured)'}"; then
        clear
        draco_backup_run
        read -r -p "Press Enter to continue..."
    fi
}

# ─── Restore screen ───────────────────────────────────────────────────────────
draco_tui_restore() {
    local backup_id
    backup_id="$(draco_restore_select_interactive)"
    if [[ -n "$backup_id" ]]; then
        clear
        draco_restore_run_with_id "$backup_id"
        read -r -p "Press Enter to continue..."
    fi
}

# ─── List screen ─────────────────────────────────────────────────────────────
draco_tui_list() {
    local tmp
    tmp="$(mktemp)"
    {
        draco_backup_list
    } > "$tmp" 2>&1
    draco_tui_textbox "DRACO - Backup List" "$tmp" 22 78
    rm -f "$tmp"
}

# ─── Log screen ───────────────────────────────────────────────────────────────
draco_tui_log() {
    # Select backup
    local backups=()
    while IFS= read -r f; do
        local bid
        bid="$(basename "$f" | sed 's/draco-\(.*\)\..*/\1/')"
        local dt
        dt="$(stat -c '%y' "$f" 2>/dev/null | cut -d'.' -f1 || echo '')"
        backups+=("$bid" "$dt")
    done < <(find "$DRACO_BACKUP_DIR" -maxdepth 1 -name "draco-*.enc" | sort -r)

    if [[ ${#backups[@]} -eq 0 ]]; then
        draco_tui_msgbox "DRACO - Logs" "No backups found."
        return
    fi

    local selected
    selected="$(draco_tui_menu "DRACO - View Log" "Select backup:" 20 70 8 "${backups[@]}")" || return

    local tmp
    tmp="$(mktemp)"
    draco_backup_log_show "$selected" > "$tmp" 2>&1
    draco_tui_textbox "DRACO - Log: $selected" "$tmp" 22 78
    rm -f "$tmp"
}

# ─── Delete screen ────────────────────────────────────────────────────────────
draco_tui_delete() {
    local items=()
    while IFS= read -r f; do
        local bid
        bid="$(basename "$f" | sed 's/draco-\(.*\)\..*/\1/')"
        local sz
        sz="$(draco_human_size "$f")"
        items+=("$bid" "$sz" "OFF")
    done < <(find "$DRACO_BACKUP_DIR" -maxdepth 1 -name "draco-*.enc" | sort -r)

    if [[ ${#items[@]} -eq 0 ]]; then
        draco_tui_msgbox "DRACO - Delete" "No backups found."
        return
    fi

    local selected
    selected="$(draco_tui_checklist "DRACO - Delete Backups" \
        "Select backups to delete (Space to toggle):" 20 70 8 \
        "${items[@]}")" || return

    if [[ -z "$selected" ]]; then
        draco_tui_msgbox "DRACO - Delete" "Nothing selected."
        return
    fi

    # Confirm
    local count
    count="$(echo "$selected" | wc -w)"
    if draco_tui_yesno "DRACO - Confirm Delete" "Delete $count backup(s)?\n\nThis cannot be undone."; then
        clear
        for bid in $selected; do
            bid="${bid//\"/}"
            draco_backup_delete_silent "$bid"
            draco_ok "Deleted: $bid"
        done
        read -r -p "Press Enter to continue..."
    fi
}

# ─── Schedule screen ──────────────────────────────────────────────────────────
draco_tui_schedule() {
    local choice
    choice="$(draco_tui_menu "DRACO - Schedule" \
        "Current: ${DRACO_SCHEDULE_TYPE:-none} / ${DRACO_SCHEDULE_FREQ:-daily}" \
        14 60 4 \
        "INSTALL" "Install/change automatic schedule" \
        "REMOVE"  "Remove automatic schedule" \
        "STATUS"  "View schedule status" \
    )" || return

    case "$choice" in
        INSTALL)
            clear
            draco_schedule_interactive_install
            read -r -p "Press Enter to continue..."
            ;;
        REMOVE)
            if draco_tui_yesno "DRACO - Remove Schedule" "Remove automatic backup schedule?"; then
                clear
                draco_schedule_remove
                read -r -p "Press Enter to continue..."
            fi
            ;;
        STATUS)
            local tmp
            tmp="$(mktemp)"
            draco_schedule_status > "$tmp" 2>&1
            draco_tui_textbox "DRACO - Schedule Status" "$tmp" 14 60
            rm -f "$tmp"
            ;;
    esac
}

# ─── Config screen ────────────────────────────────────────────────────────────
draco_tui_config() {
    while true; do
        local choice
        choice="$(draco_tui_menu "DRACO - Configuration" \
            "Current config: ${DRACO_CONFIG_FILE}" \
            20 70 8 \
            "BACKUPDIR"  "Backup directory: ${DRACO_BACKUP_DIR:-'(not set)'}" \
            "RETENTION"  "Retention policy: ${DRACO_RETENTION_POLICY}" \
            "DAILY"      "Keep daily: ${DRACO_RETENTION_KEEP_DAILY}" \
            "WEEKLY"     "Keep weekly: ${DRACO_RETENTION_KEEP_WEEKLY}" \
            "MONTHLY"    "Keep monthly: ${DRACO_RETENTION_KEEP_MONTHLY}" \
            "THEME"      "TUI theme: ${DRACO_TUI_THEME}" \
            "SAVE"       "Save and return" \
        )" || break

        case "$choice" in
            BACKUPDIR)
                local new_dir
                new_dir="$(draco_tui_inputbox "Backup Directory" \
                    "Enter backup destination path:" \
                    "${DRACO_BACKUP_DIR:-$HOME/draco-backups}")"
                if [[ -n "$new_dir" ]]; then
                    new_dir="${new_dir/#\~/$HOME}"
                    mkdir -p "$new_dir" 2>/dev/null || true
                    DRACO_BACKUP_DIR="$(realpath "$new_dir")"
                fi
                ;;
            RETENTION)
                local rp
                rp="$(draco_tui_menu "Retention Policy" "Choose policy:" 12 50 5 \
                    "all"     "Keep all backups" \
                    "daily"   "Keep N daily" \
                    "weekly"  "Keep N weekly" \
                    "monthly" "Keep N monthly" \
                    "smart"   "Smart: daily+weekly+monthly+yearly" \
                )" || continue
                DRACO_RETENTION_POLICY="$rp"
                ;;
            DAILY)
                local n
                n="$(draco_tui_inputbox "Daily Retention" "Keep last N daily backups:" "$DRACO_RETENTION_KEEP_DAILY")"
                [[ "$n" =~ ^[0-9]+$ ]] && DRACO_RETENTION_KEEP_DAILY="$n"
                ;;
            WEEKLY)
                local n
                n="$(draco_tui_inputbox "Weekly Retention" "Keep last N weekly backups:" "$DRACO_RETENTION_KEEP_WEEKLY")"
                [[ "$n" =~ ^[0-9]+$ ]] && DRACO_RETENTION_KEEP_WEEKLY="$n"
                ;;
            MONTHLY)
                local n
                n="$(draco_tui_inputbox "Monthly Retention" "Keep last N monthly backups:" "$DRACO_RETENTION_KEEP_MONTHLY")"
                [[ "$n" =~ ^[0-9]+$ ]] && DRACO_RETENTION_KEEP_MONTHLY="$n"
                ;;
            THEME)
                local theme
                theme="$(draco_tui_menu "TUI Theme" "Select theme:" 12 50 5 \
                    "default"    "Plain black and white" \
                    "blue"       "Blue and white (classic)" \
                    "anthropic"  "Anthropic coral/dark" \
                    "eva01"      "Evangelion Unit-01 (purple/green)" \
                    "matrix"     "The Matrix (green/black)" \
                )" || continue
                DRACO_TUI_THEME="$theme"
                draco_tui_apply_theme
                ;;
            SAVE)
                draco_save_config
                break
                ;;
        esac
    done
}

# ─── About screen ─────────────────────────────────────────────────────────────
draco_tui_about() {
    draco_tui_msgbox "About DRACO" \
"DRACO v${DRACO_VERSION}
Dotfile & Runtime Archive and Configuration Orchestrator

A portable Linux backup system for:
  - Dotfiles and shell configs
  - SSH keys and GPG keys
  - KDE / GNOME personalizations
  - Konsole + Spaceship prompt themes
  - Installed software manifests
  - Auto-reinstall scripts

Supported distros:
  Fedora 42+, Debian 12+, Ubuntu 24.04+, Arch

Encryption: AES-256-CBC (OpenSSL PBKDF2)
Compression: zstd / gzip

License: GNU GPL v3
https://github.com/your-repo/draco" \
    20 65
}

#!/usr/bin/env bash
# DRACO - scheduler/scheduler.sh: Automatic scheduling (systemd user / cron)
# GNU GPL v3 - See LICENSE

# ─── Check if scheduler installed ────────────────────────────────────────────
draco_scheduler_is_installed() {
    # Check systemd user timer
    if systemctl --user list-timers 2>/dev/null | grep -q "draco"; then
        return 0
    fi
    # Check cron
    if (crontab -l 2>/dev/null | grep -q "draco"); then
        return 0
    fi
    return 1
}

# ─── CLI dispatch ─────────────────────────────────────────────────────────────
draco_schedule_cmd() {
    local subcmd="${1:-}"
    case "$subcmd" in
        install)   draco_schedule_interactive_install ;;
        remove)    draco_schedule_remove ;;
        status)    draco_schedule_status ;;
        "")        draco_schedule_status ;;
        *)
            draco_error "Unknown schedule subcommand: $subcmd"
            echo "Usage: draco schedule [install|remove|status]"
            ;;
    esac
}

# ─── Password file for unattended backups ────────────────────────────────────
# One mechanism for systemd and cron: a 0600 file read via DRACO_PASSWORD_FILE /
# --password-file. The password never appears in argv, unit files or crontab.
draco_schedule_setup_password_file() {
    local pwfile="${1:-}"
    local pass="" pass2="" tmp=""

    # The path is embedded in the unit file / crontab line: whitelist it
    if [[ ! "$pwfile" =~ ^/[A-Za-z0-9_./-]+$ ]]; then
        draco_error "Unsupported password file path (allowed: A-Z a-z 0-9 _ . / -): $pwfile"
        return 1
    fi

    if [[ -e "$pwfile" || -L "$pwfile" ]]; then
        if draco_read_password_file "$pwfile" >/dev/null; then
            if draco_confirm "Password file $pwfile exists. Keep it?" "y"; then
                return 0
            fi
        else
            draco_warn "The existing password file is not usable (see above)."
        fi
        draco_confirm "Replace $pwfile?" "n" || return 1
    fi

    draco_info "Unattended backups need the backup password stored in $pwfile (mode 600)."
    draco_info "Use the SAME password as your existing backups."
    while true; do
        read -r -s -p "Backup password: " pass || return 1
        echo
        read -r -s -p "Confirm password: " pass2 || return 1
        echo
        if [[ "$pass" != "$pass2" ]]; then
            draco_warn "Passwords do not match. Try again."
        elif [[ ${#pass} -lt 8 || ${#pass} -gt 1024 || "$pass" == *$'\r'* ]]; then
            draco_warn "Password must be 8-1024 characters, without CR."
        else
            break
        fi
    done

    # Non-blocking sanity check against the latest backup: a different password
    # would silently produce backups that cannot be restored with the old one
    local latest="" cand ok=0
    if [[ -d "${DRACO_BACKUP_DIR:-}" ]]; then
        latest="$(find "$DRACO_BACKUP_DIR" -maxdepth 1 -name 'draco-*.enc' 2>/dev/null | sort | tail -1)"
    fi
    if [[ -n "$latest" ]]; then
        for cand in "$pass" $'\n'"$pass" $'\n\n'"$pass"; do
            if draco_decrypt "$cand" < "$latest" >/dev/null 2>&1; then
                ok=1
                break
            fi
        done
        if [[ "$ok" -eq 0 ]]; then
            draco_warn "This password does NOT decrypt your latest backup: $(basename "$latest")"
            draco_warn "Scheduled backups would use a different password than the existing ones."
            draco_confirm "Save it anyway?" "n" || return 1
        fi
    fi

    mkdir -p -m 700 -- "$(dirname "$pwfile")"
    tmp="$(mktemp "${pwfile}.XXXXXX")"
    if ! { printf '%s\n' "$pass" > "$tmp" && chmod 600 "$tmp" && mv -f -- "$tmp" "$pwfile"; }; then
        rm -f -- "$tmp"
        draco_error "Could not write password file: $pwfile"
        return 1
    fi
    draco_ok "Password file written: $pwfile (mode 600)"
    draco_warn "Anyone who can read this file can decrypt your backups. It is NOT included in backups."
}

# ─── Interactive install ───────────────────────────────────────────────────────
draco_schedule_interactive_install() {
    draco_info "DRACO Schedule Installation"
    echo

    # Detect available methods
    local methods=()
    if systemctl --user status &>/dev/null 2>&1; then
        methods+=("systemd" "Systemd user timer (recommended)")
    fi
    if command -v crontab &>/dev/null; then
        methods+=("cron" "Cron job")
    fi

    if [[ ${#methods[@]} -eq 0 ]]; then
        draco_error "Neither systemd user nor cron available."
        return 1
    fi

    local chosen_method=""
    if [[ "${DRACO_TUI_AVAILABLE:-0}" -eq 1 ]] && [[ ${#methods[@]} -gt 2 ]]; then
        chosen_method="$(whiptail --title "DRACO - Schedule Method" \
            --menu "Choose scheduling method:" 15 60 5 \
            "${methods[@]}" \
            3>&1 1>&2 2>&3 || true)"
    else
        echo "Available scheduling methods:"
        local i=1
        local method_ids=()
        for ((j=0; j<${#methods[@]}; j+=2)); do
            echo "  $i) ${methods[$j]} — ${methods[$j+1]}"
            method_ids+=("${methods[$j]}")
            i=$((i+1))
        done
        read -r -p "Choose [1-${#method_ids[@]}]: " sel
        if [[ "$sel" =~ ^[0-9]+$ && "$sel" -ge 1 && "$sel" -le "${#method_ids[@]}" ]]; then
            chosen_method="${method_ids[$((sel-1))]}"
        fi
    fi

    [[ -z "$chosen_method" ]] && { draco_info "Cancelled."; return 0; }

    # Choose frequency
    local freq=""
    local time_val="02:00"
    echo
    echo "Backup frequency:"
    echo "  1) Hourly"
    echo "  2) Daily (recommended)"
    echo "  3) Weekly"
    echo "  4) Monthly"
    read -r -p "Choose [1-4, default 2]: " fsel
    case "${fsel:-2}" in
        1) freq="hourly" ;;
        2) freq="daily" ;;
        3) freq="weekly" ;;
        4) freq="monthly" ;;
        *) freq="daily" ;;
    esac

    if [[ "$freq" != "hourly" ]]; then
        read -r -p "Time to run backup (HH:MM, default 02:00): " time_input
        time_val="${time_input:-02:00}"
    fi

    local pwfile="${DRACO_CONFIG_DIR}/password"
    if ! draco_schedule_setup_password_file "$pwfile"; then
        draco_error "Schedule not installed: password file not set up."
        return 1
    fi

    DRACO_SCHEDULE_TYPE="$chosen_method"
    DRACO_SCHEDULE_FREQ="$freq"
    DRACO_SCHEDULE_TIME="$time_val"
    draco_save_config

    case "$chosen_method" in
        systemd) draco_schedule_install_systemd "$freq" "$time_val" "$pwfile" ;;
        cron)    draco_schedule_install_cron    "$freq" "$time_val" "$pwfile" ;;
    esac
}

# ─── Systemd user timer install ───────────────────────────────────────────────
draco_schedule_install_systemd() {
    local freq="$1"
    local time_val="${2:-02:00}"
    local pwfile="${3:-${DRACO_CONFIG_DIR}/password}"
    local systemd_dir="${HOME}/.config/systemd/user"
    local draco_bin
    draco_bin="$(realpath "$DRACO_SELF")"

    mkdir -p "$systemd_dir"

    # Service unit
    cat > "${systemd_dir}/draco-backup.service" <<EOF
[Unit]
Description=DRACO Backup Service
After=network.target

[Service]
Type=oneshot
ExecStart=${draco_bin} backup --quiet
StandardOutput=journal
StandardError=journal
Environment=DRACO_PASSWORD_FILE=${pwfile}
NoNewPrivileges=yes
EOF

    # Timer unit
    local on_calendar
    case "$freq" in
        hourly)  on_calendar="hourly" ;;
        daily)   on_calendar="daily" ;;
        weekly)  on_calendar="weekly" ;;
        monthly) on_calendar="monthly" ;;
        *)       on_calendar="daily" ;;
    esac

    # If daily/weekly/monthly with specific time
    if [[ "$freq" != "hourly" && -n "$time_val" ]]; then
        local hour="${time_val%%:*}"
        local min="${time_val##*:}"
        case "$freq" in
            daily)   on_calendar="*-*-* ${hour}:${min}:00" ;;
            weekly)  on_calendar="Mon *-*-* ${hour}:${min}:00" ;;
            monthly) on_calendar="*-*-1 ${hour}:${min}:00" ;;
        esac
    fi

    cat > "${systemd_dir}/draco-backup.timer" <<EOF
[Unit]
Description=DRACO Backup Timer
Requires=draco-backup.service

[Timer]
OnCalendar=${on_calendar}
Persistent=true
RandomizedDelaySec=5min

[Install]
WantedBy=timers.target
EOF

    systemctl --user daemon-reload
    systemctl --user enable --now draco-backup.timer

    draco_ok "Systemd user timer installed"
    draco_info "  Service : ${systemd_dir}/draco-backup.service"
    draco_info "  Timer   : ${systemd_dir}/draco-backup.timer"
    draco_info "  Schedule: $on_calendar"
    draco_info ""
    draco_info "  Password: ${pwfile} (mode 600, read via DRACO_PASSWORD_FILE)"
}

# ─── Cron install ─────────────────────────────────────────────────────────────
draco_schedule_install_cron() {
    local freq="$1"
    local time_val="${2:-02:00}"
    local pwfile="${3:-${DRACO_CONFIG_DIR}/password}"
    local hour="${time_val%%:*}"
    local min="${time_val##*:}"
    local draco_bin
    draco_bin="$(realpath "$DRACO_SELF")"

    local cron_expr
    case "$freq" in
        hourly)  cron_expr="0 * * * *" ;;
        daily)   cron_expr="${min} ${hour} * * *" ;;
        weekly)  cron_expr="${min} ${hour} * * 1" ;;
        monthly) cron_expr="${min} ${hour} 1 * *" ;;
        *)       cron_expr="${min} ${hour} * * *" ;;
    esac

    local cron_line="${cron_expr} ${draco_bin} backup --quiet --password-file ${pwfile} >> \${HOME}/.local/share/draco/logs/cron.log 2>&1"
    local tmp_cron
    tmp_cron="$(mktemp)"

    # Preserve existing crontab, remove old draco entry if any
    crontab -l 2>/dev/null | grep -v "draco backup" > "$tmp_cron" || true
    echo "# DRACO backup - added $(date +%Y-%m-%d)" >> "$tmp_cron"
    echo "$cron_line" >> "$tmp_cron"
    crontab "$tmp_cron"
    rm -f "$tmp_cron"

    draco_ok "Cron job installed"
    draco_info "  Schedule: $cron_expr"
    draco_info "  Command : $draco_bin backup --quiet --password-file $pwfile"
    draco_info "  Password: ${pwfile} (mode 600)"
}

# ─── Remove schedule ──────────────────────────────────────────────────────────
draco_schedule_remove() {
    local removed=0

    # Systemd
    local systemd_dir="${HOME}/.config/systemd/user"
    if [[ -f "${systemd_dir}/draco-backup.timer" ]]; then
        systemctl --user disable --now draco-backup.timer 2>/dev/null || true
        rm -f "${systemd_dir}/draco-backup.timer" "${systemd_dir}/draco-backup.service"
        systemctl --user daemon-reload 2>/dev/null || true
        draco_ok "Systemd timer removed"
        removed=$((removed + 1))
    fi

    # Cron
    if crontab -l 2>/dev/null | grep -q "draco backup"; then
        local tmp_cron
        tmp_cron="$(mktemp)"
        crontab -l 2>/dev/null | grep -v "draco backup" | grep -v "# DRACO backup" > "$tmp_cron"
        crontab "$tmp_cron"
        rm -f "$tmp_cron"
        draco_ok "Cron job removed"
        removed=$((removed + 1))
    fi

    if [[ "$removed" -eq 0 ]]; then
        draco_info "No scheduled backup found."
    fi

    DRACO_SCHEDULE_TYPE="none"
    draco_save_config
}

# ─── Schedule status ──────────────────────────────────────────────────────────
draco_schedule_status() {
    echo "DRACO Schedule Status"
    echo "─────────────────────────────"

    # Systemd
    local systemd_dir="${HOME}/.config/systemd/user"
    if [[ -f "${systemd_dir}/draco-backup.timer" ]]; then
        echo "Type: systemd user timer"
        systemctl --user status draco-backup.timer 2>/dev/null \
        | grep -E 'Active|Next|Last' | sed 's/^/  /'
    else
        echo "Systemd: not installed"
    fi

    # Cron
    if crontab -l 2>/dev/null | grep -q "draco backup"; then
        echo "Cron: installed"
        crontab -l 2>/dev/null | grep "draco backup" | sed 's/^/  /'
    else
        echo "Cron: not installed"
    fi
}

#!/usr/bin/env bash
# DRACO - restore/engine.sh: Restore engine
# GNU GPL v3 - See LICENSE

# ─── Main restore entry point ─────────────────────────────────────────────────
draco_restore_run() {
    local backup_id="${1:-}"

    draco_check_deps
    draco_detect_distro
    draco_detect_de

    if [[ -z "${DRACO_BACKUP_DIR:-}" || ! -d "$DRACO_BACKUP_DIR" ]]; then
        draco_fatal "Backup directory not configured or missing: ${DRACO_BACKUP_DIR:-'(not set)'}"
    fi

    # If no ID given, show interactive selection
    if [[ -z "$backup_id" ]]; then
        backup_id="$(draco_restore_select_interactive)"
        [[ -z "$backup_id" ]] && { draco_info "Restore cancelled."; return 0; }
    fi

    draco_restore_run_with_id "$backup_id"
}

draco_restore_run_with_id() {
    local backup_id="$1"

    # Find archive file
    local archive
    archive="$(draco_find_backup_file "$backup_id" 2>/dev/null || true)"
    if [[ -z "$archive" || ! -e "$archive" ]]; then
        draco_fatal "Backup not found: $backup_id"
    fi

    # Resolve symlink (deduped backup)
    if [[ -L "$archive" ]]; then
        local real_archive
        real_archive="$(readlink -f "$archive")"
        draco_info "Backup $backup_id is deduplicated, restoring from: $(basename "$real_archive")"
        archive="$real_archive"
    fi

    # Load meta to check DE
    local meta_file="${DRACO_BACKUP_DIR}/.meta/${backup_id}.meta"
    local backed_up_de=""
    if [[ -f "$meta_file" ]]; then
        backed_up_de="$(grep '^DE=' "$meta_file" | cut -d= -f2)"
    fi

    # DE mismatch warning
    local de_mismatch=0
    if [[ -n "$backed_up_de" ]]; then
        draco_check_de_mismatch "$backed_up_de" || de_mismatch=1
    fi

    # Confirm
    echo
    draco_warn "═══════════════════════════════════════════════════"
    draco_warn "  RESTORE: $backup_id"
    draco_warn "  Archive : $(basename "$archive")"
    draco_warn "  Size    : $(draco_human_size "$archive")"
    [[ -n "$backed_up_de" ]] && draco_warn "  DE (backup) : $backed_up_de"
    draco_warn "  DE (current): $DRACO_DE"
    draco_warn ""
    draco_warn "  This will OVERWRITE existing configs!"
    draco_warn "═══════════════════════════════════════════════════"
    echo

    if ! draco_confirm "Proceed with restore?"; then
        draco_info "Restore aborted."
        return 0
    fi

    # Password
    local pass
    pass="$(draco_prompt_password_only)"
    DRACO_PASSWORD="$pass"

    # Extract to temp dir first (validate before overwriting)
    draco_step "Extracting archive..."
    local staging
    staging="$(mktemp -d)"

    if ! draco_decrypt "$pass" < "$archive" | tar -C "$staging" -xf - 2>/dev/null; then
        rm -rf "$staging"
        draco_fatal "Failed to decrypt/extract archive. Wrong password?"
    fi

    draco_ok "Archive extracted successfully"

    # ─── Restore dotfiles ──────────────────────────────────────────────────────
    draco_step "Restoring dotfiles..."
    if [[ -d "${staging}/dotfiles" ]]; then
        draco_restore_dotfiles "${staging}/dotfiles" "$de_mismatch" "$backed_up_de"
    fi

    # ─── Restore DE config ────────────────────────────────────────────────────
    if [[ "$de_mismatch" -eq 0 ]]; then
        draco_step "Restoring DE configuration..."
        if [[ -d "${staging}/de" ]] && [[ -n "$(ls -A "${staging}/de" 2>/dev/null)" ]]; then
            draco_restore_de "${staging}/de" "$backed_up_de"
        fi
    else
        draco_skip "DE configuration (mismatch: backup=$backed_up_de, current=$DRACO_DE)"
    fi

    # ─── Restore package info ─────────────────────────────────────────────────
    draco_step "Saving package manifests..."
    if [[ -d "${staging}/pkgs" ]]; then
        mkdir -p "${DRACO_DATA_DIR}/restore-${backup_id}"
        cp -r "${staging}/pkgs/." "${DRACO_DATA_DIR}/restore-${backup_id}/"
        draco_ok "Package manifests saved to: ${DRACO_DATA_DIR}/restore-${backup_id}/"
        draco_info "Run reinstall script: ${DRACO_DATA_DIR}/restore-${backup_id}/reinstall.sh"
    fi

    rm -rf "$staging"

    echo
    draco_info "══════════════════════════════════════════"
    draco_info "  Restore complete!"
    if [[ "$de_mismatch" -eq 1 ]]; then
        draco_warn "  DE personalizations were NOT restored"
        draco_warn "  (backup: $backed_up_de, current: $DRACO_DE)"
    fi
    draco_info "  You may need to restart your session"
    draco_info "══════════════════════════════════════════"
}

# ─── Restore dotfiles ─────────────────────────────────────────────────────────
draco_restore_dotfiles() {
    local src_dir="$1"
    local de_mismatch="$2"
    local backed_up_de="${3:-}"

    # KDE/GNOME paths to skip if DE mismatch
    local skip_patterns=()
    if [[ "$de_mismatch" -eq 1 ]]; then
        case "$backed_up_de" in
            kde)
                for p in "${DRACO_KDE_PATHS[@]}"; do
                    skip_patterns+=("$p")
                done
                ;;
            gnome)
                for p in "${DRACO_GNOME_PATHS[@]}"; do
                    skip_patterns+=("$p")
                done
                ;;
        esac
    fi

    # Backup existing before overwrite
    local bak_dir
    bak_dir="${HOME}/.draco-pre-restore-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$bak_dir"
    draco_info "Pre-restore backup: $bak_dir"

    # Walk source and restore
    local count=0
    while IFS= read -r rel_path; do
        local dest="${HOME}/${rel_path}"
        local src="${src_dir}/${rel_path}"

        # Check skip
        local skip=0
        for pattern in "${skip_patterns[@]}"; do
            if [[ "$rel_path" == "$pattern" || "$rel_path" == "${pattern}/"* ]]; then
                skip=1
                break
            fi
        done

        if [[ "$skip" -eq 1 ]]; then
            draco_debug "  skip: $rel_path (DE mismatch)"
            continue
        fi

        # Backup existing
        if [[ -e "$dest" || -L "$dest" ]]; then
            local dest_parent
            dest_parent="$(dirname "${bak_dir}/${rel_path}")"
            mkdir -p "$dest_parent"
            mv "$dest" "${bak_dir}/${rel_path}" 2>/dev/null || true
        fi

        # Restore
        local dest_parent
        dest_parent="$(dirname "$dest")"
        mkdir -p "$dest_parent"
        cp -r "$src" "$dest" 2>/dev/null || true
        draco_debug "  + $rel_path"
        count=$((count + 1))

    done < <(cd "$src_dir" && find . -mindepth 1 -maxdepth 2 | sed 's|^\./||' | sort)

    draco_ok "Restored $count dotfile entries"
    draco_info "Old configs backed up to: $bak_dir"
}

# ─── Restore DE config ────────────────────────────────────────────────────────
draco_restore_de() {
    local src_dir="$1"
    local de="$2"

    case "$de" in
        kde)  draco_restore_kde "$src_dir" ;;
        gnome) draco_restore_gnome "$src_dir" ;;
        *)    draco_skip "Unknown DE: $de" ;;
    esac
}

draco_restore_kde() {
    local src_dir="$1"
    local count=0

    # Konsole profiles
    if [[ -d "${src_dir}/konsole" ]]; then
        mkdir -p "${HOME}/.local/share/konsole"
        cp -r "${src_dir}/konsole/." "${HOME}/.local/share/konsole/" 2>/dev/null || true
        draco_ok "Konsole profiles restored"
        count=$((count + 1))
    fi

    # Spaceship theme
    if [[ -d "${src_dir}/spaceship-prompt" ]]; then
        local dest="${HOME}/.oh-my-zsh/custom/themes/spaceship-prompt"
        mkdir -p "$(dirname "$dest")"
        cp -r "${src_dir}/spaceship-prompt" "$dest" 2>/dev/null || true
        draco_ok "Spaceship prompt restored"
        count=$((count + 1))
    fi
    if [[ -d "${src_dir}/spaceship-config" ]]; then
        mkdir -p "${HOME}/.config/spaceship"
        cp -r "${src_dir}/spaceship-config/." "${HOME}/.config/spaceship/" 2>/dev/null || true
        count=$((count + 1))
    fi

    # Color schemes
    if [[ -d "${src_dir}/color-schemes" ]]; then
        mkdir -p "${HOME}/.local/share/color-schemes"
        cp -r "${src_dir}/color-schemes/." "${HOME}/.local/share/color-schemes/" 2>/dev/null || true
        draco_ok "KDE color schemes restored"
        count=$((count + 1))
    fi

    # Plasma themes
    if [[ -d "${src_dir}/plasma" ]]; then
        mkdir -p "${HOME}/.local/share/plasma"
        cp -r "${src_dir}/plasma/." "${HOME}/.local/share/plasma/" 2>/dev/null || true
        draco_ok "Plasma themes restored"
        count=$((count + 1))
    fi

    # Aurorae
    if [[ -d "${src_dir}/aurorae" ]]; then
        mkdir -p "${HOME}/.local/share/aurorae"
        cp -r "${src_dir}/aurorae/." "${HOME}/.local/share/aurorae/" 2>/dev/null || true
        draco_ok "Aurorae decorations restored"
        count=$((count + 1))
    fi

    # Global shortcuts
    if [[ -f "${src_dir}/kglobalshortcutsrc" ]]; then
        cp "${src_dir}/kglobalshortcutsrc" "${HOME}/.config/kglobalshortcutsrc" 2>/dev/null || true
        draco_ok "KDE global shortcuts restored"
        count=$((count + 1))
    fi

    draco_info "KDE: $count components restored"
    draco_warn "Restart KDE session to apply changes"
}

draco_restore_gnome() {
    local src_dir="$1"
    local count=0

    # dconf restore (excluding monitor settings)
    if [[ -f "${src_dir}/dconf-dump.ini" ]] && command -v dconf &>/dev/null; then
        # Filter out display/monitor settings before loading
        local filtered
        filtered="$(mktemp)"
        draco_gnome_filter_dconf "${src_dir}/dconf-dump.ini" "$filtered"
        dconf load / < "$filtered" 2>/dev/null || true
        rm -f "$filtered"
        draco_ok "GNOME dconf settings restored (monitor settings excluded)"
        count=$((count + 1))
    fi

    # GNOME extensions
    if [[ -d "${src_dir}/gnome-extensions" ]]; then
        mkdir -p "${HOME}/.local/share/gnome-shell/extensions"
        cp -r "${src_dir}/gnome-extensions/." "${HOME}/.local/share/gnome-shell/extensions/" 2>/dev/null || true
        draco_ok "GNOME extensions restored"
        count=$((count + 1))
    fi

    draco_info "GNOME: $count components restored"
    draco_warn "Restart GNOME session (Alt+F2, then 'r') to apply changes"
}

# Filter monitor-specific dconf keys before restore
draco_gnome_filter_dconf() {
    local src="$1"
    local dst="$2"
    # Remove sections related to display/monitor config
    grep -v -E '^\[org/gnome/desktop/background\]' \
        "$src" \
    | awk '
        /^\[org\/gnome\/mutter\]/ { skip=1 }
        /^\[org\/gnome\/settings-daemon\/plugins\/color\]/ { skip=1 }
        /^\[org\/gnome\/desktop\/interface\]/ { skip=0 }
        /^\[/ { if (/displays|monitors|xrandr/) skip=1; else skip=0 }
        !skip { print }
    ' > "$dst"
}

# ─── Interactive backup selection ─────────────────────────────────────────────
draco_restore_select_interactive() {
    # Returns selected backup ID or empty string
    local backups=()
    while IFS= read -r f; do
        local bid
        bid="$(basename "$f" | sed 's/draco-\(.*\)\..*/\1/')"
        local sz
        sz="$(draco_human_size "$f")"
        local dt
        dt="$(stat -c '%y' "$f" 2>/dev/null | cut -d'.' -f1 || echo '')"
        backups+=("$bid" "${sz} - ${dt}")
    done < <(find "$DRACO_BACKUP_DIR" -maxdepth 1 -name "draco-*.enc" | sort -r)

    if [[ ${#backups[@]} -eq 0 ]]; then
        draco_warn "No backups found in $DRACO_BACKUP_DIR"
        return 0
    fi

    if [[ "${DRACO_TUI_AVAILABLE:-0}" -eq 1 ]]; then
        local selected
        selected="$(whiptail --title "DRACO - Select Backup to Restore" \
            --menu "Choose backup:" 20 70 10 \
            "${backups[@]}" \
            3>&1 1>&2 2>&3 || true)"
        echo "$selected"
    else
        echo "Available backups:"
        local i=1
        local ids=()
        for ((j=0; j<${#backups[@]}; j+=2)); do
            echo "  $i) ${backups[$j]} — ${backups[$j+1]}"
            ids+=("${backups[$j]}")
            i=$((i+1))
        done
        read -r -p "Select [1-${#ids[@]}] or Enter to cancel: " sel
        if [[ "$sel" =~ ^[0-9]+$ && "$sel" -ge 1 && "$sel" -le "${#ids[@]}" ]]; then
            echo "${ids[$((sel-1))]}"
        fi
    fi
}

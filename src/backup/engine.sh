#!/usr/bin/env bash
# DRACO - backup/engine.sh: Core backup engine
# GNU GPL v3 - See LICENSE

# ─── Main backup entry point ──────────────────────────────────────────────────
draco_backup_run() {
    draco_check_deps
    draco_detect_distro
    draco_validate_distro_version || true
    draco_detect_de

    if [[ -z "${DRACO_BACKUP_DIR:-}" ]]; then
        draco_fatal "Backup directory not configured. Run 'draco config' first."
    fi

    mkdir -p "$DRACO_BACKUP_DIR"
    mkdir -p "${DRACO_BACKUP_DIR}/.meta"

    local backup_id
    backup_id="$(draco_new_backup_id)"

    draco_info "Starting backup: $backup_id"
    draco_info "Distro  : ${DRACO_DISTRO} (${DRACO_DISTRO_FAMILY})"
    draco_info "DE      : ${DRACO_DE}"
    draco_info "Dest    : ${DRACO_BACKUP_DIR}"
    echo

    local start_ts
    start_ts="$(date +%s)"

    # Build the list of paths to backup
    local all_paths=()
    draco_backup_collect_paths all_paths

    # Password (prompt once, reuse for all archives)
    local pass
    pass="$(draco_get_password)"
    DRACO_PASSWORD="$pass"

    # ─── 1. Dotfiles + SSH + configs archive ──────────────────────────────────
    draco_step "Backing up dotfiles and configs..."
    local dotfiles_archive="${DRACO_BACKUP_DIR}/.tmp-${backup_id}-dotfiles.tar"
    draco_backup_dotfiles "$backup_id" "$dotfiles_archive" "${all_paths[@]}"

    # ─── 2. KDE/GNOME specific export ─────────────────────────────────────────
    local de_archive=""
    if [[ "$DRACO_DE" == "kde" ]]; then
        draco_step "Backing up KDE/Konsole configuration..."
        de_archive="${DRACO_BACKUP_DIR}/.tmp-${backup_id}-de.tar"
        draco_backup_kde "$backup_id" "$de_archive"
    elif [[ "$DRACO_DE" == "gnome" ]]; then
        draco_step "Backing up GNOME configuration..."
        de_archive="${DRACO_BACKUP_DIR}/.tmp-${backup_id}-de.tar"
        draco_backup_gnome "$backup_id" "$de_archive"
    fi

    # ─── 3. Package list + reinstall script ───────────────────────────────────
    draco_step "Generating software manifest and reinstall script..."
    local pkg_dir
    pkg_dir="$(mktemp -d)"
    draco_generate_reinstall_script "${pkg_dir}/reinstall.sh" "$backup_id"
    draco_list_packages        > "${pkg_dir}/packages.list"
    draco_list_flatpaks        > "${pkg_dir}/flatpaks.list"  2>/dev/null || true
    draco_list_snaps           > "${pkg_dir}/snaps.list"     2>/dev/null || true
    draco_list_pip_packages    > "${pkg_dir}/pip.list"       2>/dev/null || true
    draco_list_npm_packages    > "${pkg_dir}/npm.list"       2>/dev/null || true
    # Store distro/DE info for restore-time mismatch check
    cat > "${pkg_dir}/draco.meta" <<META
DRACO_VERSION=${DRACO_VERSION}
DRACO_BACKUP_ID=${backup_id}
DRACO_BACKUP_DATE=$(date -Iseconds)
DRACO_DISTRO=${DRACO_DISTRO}
DRACO_DISTRO_FAMILY=${DRACO_DISTRO_FAMILY}
DRACO_DISTRO_VERSION=${DRACO_DISTRO_VERSION}
DRACO_PKG_MANAGER=${DRACO_PKG_MANAGER}
DRACO_DE=${DRACO_DE}
DRACO_DE_TYPE=${DRACO_DE_TYPE}
DRACO_HOSTNAME=$(hostname)
DRACO_USER=${USER}
META

    # ─── 4. Combine everything into single encrypted archive ──────────────────
    draco_step "Creating encrypted archive..."
    local compress_flag
    compress_flag="$(draco_tar_compress_flag)"
    local ext
    ext="$(draco_compress_ext)"
    local final_archive="${DRACO_BACKUP_DIR}/draco-${backup_id}.${ext}.enc"

    # Create a temp staging dir
    local staging
    staging="$(mktemp -d)"
    mkdir -p "${staging}/dotfiles" "${staging}/de" "${staging}/pkgs"

    # Extract sub-archives into staging
    if [[ -f "$dotfiles_archive" ]]; then
        tar -C "${staging}/dotfiles" -xf "$dotfiles_archive" 2>/dev/null || true
        rm -f "$dotfiles_archive"
    fi
    if [[ -n "$de_archive" && -f "$de_archive" ]]; then
        tar -C "${staging}/de" -xf "$de_archive" 2>/dev/null || true
        rm -f "$de_archive"
    fi
    cp -r "${pkg_dir}/." "${staging}/pkgs/"
    rm -rf "$pkg_dir"

    # Pack staging dir into final encrypted archive
    tar -C "$staging" "${compress_flag}" -cf - . \
    | draco_encrypt "$pass" > "$final_archive"

    local tar_status="${PIPESTATUS[0]}"
    rm -rf "$staging"

    if [[ "$tar_status" -ne 0 ]]; then
        rm -f "$final_archive"
        draco_fatal "Archive creation failed (tar exit: $tar_status)"
    fi

    # ─── 5. Dedup check ───────────────────────────────────────────────────────
    draco_step "Checking for duplicate backup..."
    local new_hash
    new_hash="$(draco_file_hash "$final_archive")"

    local prev_id prev_hash=""
    prev_id="$(draco_get_last_backup_id_before "$backup_id")"
    if [[ -n "$prev_id" ]]; then
        local prev_archive
        prev_archive="$(draco_find_backup_file "$prev_id")"
        if [[ -f "$prev_archive" ]]; then
            prev_hash="$(draco_file_hash "$prev_archive")"
        fi
    fi

    if [[ -n "$prev_hash" && "$new_hash" == "$prev_hash" ]]; then
        draco_info "No changes detected. Deduplicating..."
        rm -f "$final_archive"
        # Create symlink to previous backup
        local prev_file
        prev_file="$(basename "$(draco_find_backup_file "$prev_id")")"
        ln -sf "$prev_file" "$final_archive"
        draco_ok "Linked to: $prev_id (no changes)"
        draco_backup_write_meta "$backup_id" "$new_hash" "deduplicated:$prev_id" "$(draco_human_size "$(draco_find_backup_file "$prev_id")")"
    else
        local size
        size="$(draco_human_size "$final_archive")"
        draco_ok "Archive: $final_archive ($size)"
        draco_backup_write_meta "$backup_id" "$new_hash" "new" "$size"
    fi

    # ─── 6. Generate diff log ─────────────────────────────────────────────────
    draco_step "Generating diff log..."
    draco_backup_generate_diff_log "$backup_id" "${prev_id:-}"

    # ─── 7. Retention ─────────────────────────────────────────────────────────
    draco_step "Applying retention policy..."
    draco_apply_retention

    local end_ts
    end_ts="$(date +%s)"
    local elapsed=$(( end_ts - start_ts ))

    echo
    draco_info "══════════════════════════════════════════"
    draco_info "  Backup complete: $backup_id"
    draco_info "  Duration: ${elapsed}s"
    draco_info "  Total storage: $(draco_backup_total_size)"
    draco_info "══════════════════════════════════════════"
}

# ─── Collect all paths to include in backup ───────────────────────────────────
draco_backup_collect_paths() {
    local -n _paths_ref="$1"

    # Start with default dotfiles
    for p in "${DRACO_DOTFILES_DEFAULT[@]}"; do
        _paths_ref+=("$p")
    done

    # Add DE-specific paths
    case "$DRACO_DE" in
        kde)
            for p in "${DRACO_KDE_PATHS[@]}"; do
                _paths_ref+=("$p")
            done
            ;;
        gnome)
            for p in "${DRACO_GNOME_PATHS[@]}"; do
                _paths_ref+=("$p")
            done
            ;;
    esac

    # Deduplicate
    local -A seen
    local deduped=()
    for p in "${_paths_ref[@]}"; do
        if [[ -z "${seen[$p]+_}" ]]; then
            seen["$p"]=1
            deduped+=("$p")
        fi
    done
    _paths_ref=("${deduped[@]}")
}

# ─── Backup dotfiles ──────────────────────────────────────────────────────────
draco_backup_dotfiles() {
    local backup_id="$1"
    local outfile="$2"
    shift 2
    local paths=("$@")

    # Build exclude list
    local exclude_args=()
    for excl in "${DRACO_EXCLUDE_DEFAULT[@]}"; do
        exclude_args+=(--exclude="${excl}")
    done

    # Filter existing
    local existing=()
    for p in "${paths[@]}"; do
        local full="${HOME}/${p}"
        if [[ -e "$full" || -L "$full" ]]; then
            existing+=("$p")
            draco_debug "  + $p"
        else
            draco_debug "  - $p (not found)"
        fi
    done

    if [[ ${#existing[@]} -eq 0 ]]; then
        draco_warn "No dotfiles found to backup"
        touch "$outfile"
        return
    fi

    tar -C "$HOME" \
        "${exclude_args[@]}" \
        --ignore-failed-read \
        -cf "$outfile" \
        "${existing[@]}" 2>/dev/null || true

    draco_backup_log_write "$backup_id" "=== DOTFILES ==="
    for p in "${existing[@]}"; do
        draco_backup_log_write "$backup_id" "  + $p"
    done
}

# ─── KDE backup ───────────────────────────────────────────────────────────────
draco_backup_kde() {
    local backup_id="$1"
    local outfile="$2"
    local staging
    staging="$(mktemp -d)"

    draco_backup_log_write "$backup_id" "=== KDE CONFIGURATION ==="

    # Konsole profiles
    if [[ -d "${HOME}/.local/share/konsole" ]]; then
        cp -r "${HOME}/.local/share/konsole" "${staging}/konsole" 2>/dev/null || true
        draco_backup_log_write "$backup_id" "  + Konsole profiles"
    fi

    # Spaceship theme
    local spaceship_zsh="${HOME}/.oh-my-zsh/custom/themes/spaceship-prompt"
    local spaceship_config="${HOME}/.config/spaceship"
    if [[ -d "$spaceship_zsh" ]]; then
        cp -r "$spaceship_zsh" "${staging}/spaceship-prompt" 2>/dev/null || true
        draco_backup_log_write "$backup_id" "  + Spaceship prompt theme"
    fi
    if [[ -d "$spaceship_config" ]]; then
        mkdir -p "${staging}/spaceship-config"
        cp -r "$spaceship_config/." "${staging}/spaceship-config/" 2>/dev/null || true
    fi

    # KDE color schemes
    if [[ -d "${HOME}/.local/share/color-schemes" ]]; then
        cp -r "${HOME}/.local/share/color-schemes" "${staging}/color-schemes" 2>/dev/null || true
        draco_backup_log_write "$backup_id" "  + KDE color schemes"
    fi

    # Plasma themes
    if [[ -d "${HOME}/.local/share/plasma" ]]; then
        cp -r "${HOME}/.local/share/plasma" "${staging}/plasma" 2>/dev/null || true
        draco_backup_log_write "$backup_id" "  + Plasma themes"
    fi

    # Aurorae window decorations
    if [[ -d "${HOME}/.local/share/aurorae" ]]; then
        cp -r "${HOME}/.local/share/aurorae" "${staging}/aurorae" 2>/dev/null || true
        draco_backup_log_write "$backup_id" "  + Aurorae decorations"
    fi

    # KWIN rules (monitor-independent only - skip resolution/monitor count rules)
    if [[ -f "${HOME}/.config/kwinrulesrc" ]]; then
        cp "${HOME}/.config/kwinrulesrc" "${staging}/kwinrulesrc" 2>/dev/null || true
        draco_backup_log_write "$backup_id" "  + KWin rules (note: monitor rules may not apply)"
    fi

    # Global shortcuts
    if [[ -f "${HOME}/.config/kglobalshortcutsrc" ]]; then
        cp "${HOME}/.config/kglobalshortcutsrc" "${staging}/kglobalshortcutsrc" 2>/dev/null || true
        draco_backup_log_write "$backup_id" "  + KDE global shortcuts"
    fi

    draco_backup_log_write "$backup_id" "  [NOTE] Monitor-specific settings (resolution, arrangement) excluded"
    draco_backup_log_write "$backup_id" "  [NOTE] KDE Activities not backed up"

    tar -C "$staging" -cf "$outfile" . 2>/dev/null || true
    rm -rf "$staging"
}

# ─── GNOME backup ─────────────────────────────────────────────────────────────
draco_backup_gnome() {
    local backup_id="$1"
    local outfile="$2"
    local staging
    staging="$(mktemp -d)"

    draco_backup_log_write "$backup_id" "=== GNOME CONFIGURATION ==="

    # dconf dump (all GNOME settings)
    if command -v dconf &>/dev/null; then
        dconf dump / > "${staging}/dconf-dump.ini" 2>/dev/null || true
        draco_backup_log_write "$backup_id" "  + dconf settings dump"
        draco_backup_log_write "$backup_id" "  [NOTE] Monitor/display settings in dconf will be excluded on restore"
    fi

    # GNOME extensions
    if [[ -d "${HOME}/.local/share/gnome-shell/extensions" ]]; then
        cp -r "${HOME}/.local/share/gnome-shell/extensions" "${staging}/gnome-extensions" 2>/dev/null || true
        draco_backup_log_write "$backup_id" "  + GNOME extensions"
    fi

    # GTK themes/icons
    for d in ".themes" ".icons"; do
        if [[ -d "${HOME}/${d}" ]]; then
            cp -r "${HOME}/${d}" "${staging}/${d}" 2>/dev/null || true
            draco_backup_log_write "$backup_id" "  + ${d}"
        fi
    done

    tar -C "$staging" -cf "$outfile" . 2>/dev/null || true
    rm -rf "$staging"
}

# ─── Meta file write ──────────────────────────────────────────────────────────
draco_backup_write_meta() {
    local backup_id="$1"
    local hash="$2"
    local status="$3"
    local size="$4"
    local meta_file="${DRACO_BACKUP_DIR}/.meta/${backup_id}.meta"

    mkdir -p "${DRACO_BACKUP_DIR}/.meta"
    cat > "$meta_file" <<META
BACKUP_ID=${backup_id}
BACKUP_DATE=$(date -Iseconds)
BACKUP_HASH=${hash}
BACKUP_STATUS=${status}
BACKUP_SIZE=${size}
DISTRO=${DRACO_DISTRO}
DISTRO_FAMILY=${DRACO_DISTRO_FAMILY}
DE=${DRACO_DE}
HOSTNAME=$(hostname)
USER=${USER}
META
    chmod 600 "$meta_file"
}

# ─── Diff log generation ──────────────────────────────────────────────────────
draco_backup_generate_diff_log() {
    local new_id="$1"
    local prev_id="${2:-}"
    local log_file="${DRACO_BACKUP_DIR}/.meta/${new_id}.log"

    {
        echo "DRACO Backup Log"
        echo "════════════════════════════════════════"
        echo "Backup ID : $new_id"
        echo "Date      : $(date -Iseconds)"
        echo "Distro    : ${DRACO_DISTRO} (${DRACO_DISTRO_FAMILY})"
        echo "DE        : ${DRACO_DE}"
        echo "Host      : $(hostname)"
        echo "User      : ${USER}"
        echo ""
    } >> "$log_file"

    if [[ -n "$prev_id" ]]; then
        local prev_meta="${DRACO_BACKUP_DIR}/.meta/${prev_id}.meta"
        if [[ -f "$prev_meta" ]]; then
            {
                echo "Previous backup : $prev_id"
                local prev_date
                prev_date="$(grep '^BACKUP_DATE=' "$prev_meta" | cut -d= -f2)"
                echo "Previous date   : $prev_date"
                echo ""
            } >> "$log_file"
        fi

        # Diff package lists if available
        local new_pkg_tmp prev_pkg_tmp
        new_pkg_tmp="$(mktemp)"
        prev_pkg_tmp="$(mktemp)"

        draco_list_packages > "$new_pkg_tmp" 2>/dev/null || true

        # Try to extract prev packages list (best effort - would need full extract)
        # For now: log current state only, diff on next run
        {
            echo "=== PACKAGE DIFF (vs $prev_id) ==="
            echo "(Full diff requires extracting previous archive)"
            echo "Current package count: $(wc -l < "$new_pkg_tmp")"
            echo ""
        } >> "$log_file"

        rm -f "$new_pkg_tmp" "$prev_pkg_tmp"
    fi

    echo "Log: $log_file"
}

# ─── Helper: find backup file by ID ───────────────────────────────────────────
draco_find_backup_file() {
    local bid="$1"
    local f
    for f in "${DRACO_BACKUP_DIR}/draco-${bid}."*; do
        if [[ -e "$f" ]]; then
            echo "$f"
            return 0
        fi
    done
    return 1
}

# ─── Helper: get last backup ID before given ID ───────────────────────────────
draco_get_last_backup_id_before() {
    local current_id="$1"
    find "$DRACO_BACKUP_DIR" -maxdepth 1 -name "draco-*.enc" \
    | sort \
    | grep -v "draco-${current_id}" \
    | tail -1 \
    | xargs -r basename \
    | sed 's/draco-\(.*\)\..*/\1/' \
    2>/dev/null || echo ""
}

# ─── Retention ────────────────────────────────────────────────────────────────
draco_apply_retention() {
    case "$DRACO_RETENTION_POLICY" in
        all)
            draco_debug "Retention policy: keep all. No cleanup."
            ;;
        daily)
            draco_retention_keep_n_per_period "day" "${DRACO_RETENTION_KEEP_DAILY}"
            ;;
        weekly)
            draco_retention_keep_n_per_period "week" "${DRACO_RETENTION_KEEP_WEEKLY}"
            ;;
        monthly)
            draco_retention_keep_n_per_period "month" "${DRACO_RETENTION_KEEP_MONTHLY}"
            ;;
        smart)
            # Keep: last N daily, last N weekly, last N monthly, last N yearly
            draco_retention_smart
            ;;
    esac
}

draco_retention_keep_n_per_period() {
    local period="$1"
    local keep="$2"

    # Get all backup IDs sorted by date
    local all_ids=()
    while IFS= read -r f; do
        local bid
        bid="$(basename "$f" | sed 's/draco-\(.*\)\..*/\1/')"
        all_ids+=("$bid")
    done < <(find "$DRACO_BACKUP_DIR" -maxdepth 1 -name "draco-*.enc" ! -type l | sort -r)

    # Keep last N, delete older
    local count=0
    for bid in "${all_ids[@]}"; do
        count=$((count + 1))
        if [[ "$count" -gt "$keep" ]]; then
            draco_debug "Retention: removing old backup $bid"
            draco_backup_delete_silent "$bid"
        fi
    done
}

draco_retention_smart() {
    # Keep: daily for last KEEP_DAILY days, weekly for last KEEP_WEEKLY weeks, etc.
    local all_ids=()
    while IFS= read -r f; do
        local bid
        bid="$(basename "$f" | sed 's/draco-\(.*\)\..*/\1/')"
        all_ids+=("$bid")
    done < <(find "$DRACO_BACKUP_DIR" -maxdepth 1 -name "draco-*.enc" ! -type l | sort -r)

    local now
    now="$(date +%s)"
    local keep_ids=()

    local daily_cutoff=$(( now - DRACO_RETENTION_KEEP_DAILY * 86400 ))
    local weekly_cutoff=$(( now - DRACO_RETENTION_KEEP_WEEKLY * 7 * 86400 ))
    local monthly_cutoff=$(( now - DRACO_RETENTION_KEEP_MONTHLY * 30 * 86400 ))
    local yearly_cutoff=$(( now - DRACO_RETENTION_KEEP_YEARLY * 365 * 86400 ))

    local seen_weeks=() seen_months=() seen_years=()

    for bid in "${all_ids[@]}"; do
        # Parse date from ID: YYYYMMDD-HHMMSS
        local d="${bid:0:8}"
        local dt
        dt="$(date -d "${d:0:4}-${d:4:2}-${d:6:2}" +%s 2>/dev/null || echo 0)"

        if [[ "$dt" -ge "$daily_cutoff" ]]; then
            keep_ids+=("$bid")
        elif [[ "$dt" -ge "$weekly_cutoff" ]]; then
            local wk
            wk="$(date -d "${d:0:4}-${d:4:2}-${d:6:2}" +%Y-%W 2>/dev/null)"
            if [[ ! " ${seen_weeks[*]} " =~ " ${wk} " ]]; then
                keep_ids+=("$bid")
                seen_weeks+=("$wk")
            fi
        elif [[ "$dt" -ge "$monthly_cutoff" ]]; then
            local mo="${d:0:6}"
            if [[ ! " ${seen_months[*]} " =~ " ${mo} " ]]; then
                keep_ids+=("$bid")
                seen_months+=("$mo")
            fi
        elif [[ "$dt" -ge "$yearly_cutoff" ]]; then
            local yr="${d:0:4}"
            if [[ ! " ${seen_years[*]} " =~ " ${yr} " ]]; then
                keep_ids+=("$bid")
                seen_years+=("$yr")
            fi
        fi
    done

    for bid in "${all_ids[@]}"; do
        if [[ ! " ${keep_ids[*]} " =~ " ${bid} " ]]; then
            draco_debug "Retention smart: removing $bid"
            draco_backup_delete_silent "$bid"
        fi
    done
}

draco_backup_delete_silent() {
    local bid="$1"
    local pattern="${DRACO_BACKUP_DIR}/draco-${bid}.*"
    for f in $pattern; do
        [[ -e "$f" || -L "$f" ]] && rm -f "$f"
    done
    rm -f "${DRACO_BACKUP_DIR}/.meta/${bid}.log"
    rm -f "${DRACO_BACKUP_DIR}/.meta/${bid}.meta"
}

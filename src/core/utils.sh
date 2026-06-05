#!/usr/bin/env bash
# DRACO - utils.sh: Utility functions
# GNU GPL v3 - See LICENSE

# ─── Dependency checks ────────────────────────────────────────────────────────
draco_check_deps() {
    local required=(tar openssl sha256sum date find grep sed awk)
    local optional_warn=(zstd whiptail dialog)
    local missing=()

    for cmd in "${required[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        draco_fatal "Missing required tools: ${missing[*]}"
    fi

    # zstd: fallback to gzip if missing
    if ! command -v zstd &>/dev/null; then
        draco_warn "zstd not found, falling back to gzip compression"
        DRACO_COMPRESSION="gzip"
    fi

    # TUI check
    if ! command -v whiptail &>/dev/null && ! command -v dialog &>/dev/null; then
        draco_warn "Neither whiptail nor dialog found. TUI unavailable. Use CLI mode."
        DRACO_TUI_AVAILABLE=0
    else
        DRACO_TUI_AVAILABLE=1
    fi
}

# ─── Password handling ────────────────────────────────────────────────────────
draco_get_password() {
    # Priority: CLI arg > env var > prompt
    if [[ -n "${DRACO_PASSWORD:-}" ]]; then
        echo "$DRACO_PASSWORD"
        return
    fi

    local pass pass2
    while true; do
        read -r -s -p "Encryption password: " pass
        echo
        read -r -s -p "Confirm password: " pass2
        echo
        if [[ "$pass" == "$pass2" ]]; then
            if [[ ${#pass} -lt 8 ]]; then
                draco_warn "Password too short (min 8 chars)"
                continue
            fi
            DRACO_PASSWORD="$pass"
            echo "$DRACO_PASSWORD"
            return
        fi
        draco_warn "Passwords do not match. Try again."
    done
}

draco_prompt_password_only() {
    if [[ -n "${DRACO_PASSWORD:-}" ]]; then
        echo "$DRACO_PASSWORD"
        return
    fi
    local pass
    read -r -s -p "Backup password: " pass
    echo
    DRACO_PASSWORD="$pass"
    echo "$DRACO_PASSWORD"
}

# ─── Encryption ───────────────────────────────────────────────────────────────
draco_encrypt() {
    # Usage: draco_encrypt <password> < plaintext > ciphertext
    local pass="$1"
    openssl enc -"${DRACO_ENCRYPTION_ALGO}" \
        -pbkdf2 -iter 600000 \
        -pass pass:"$pass" \
        -salt
}

draco_decrypt() {
    # Usage: draco_decrypt <password> < ciphertext > plaintext
    local pass="$1"
    openssl enc -d -"${DRACO_ENCRYPTION_ALGO}" \
        -pbkdf2 -iter 600000 \
        -pass pass:"$pass" \
        -salt
}

# ─── Compression ──────────────────────────────────────────────────────────────
draco_compress_ext() {
    case "${DRACO_COMPRESSION}" in
        zstd)  echo "tar.zst" ;;
        gzip)  echo "tar.gz" ;;
        bzip2) echo "tar.bz2" ;;
        xz)    echo "tar.xz" ;;
        *)     echo "tar.gz" ;;
    esac
}

draco_tar_compress_flag() {
    case "${DRACO_COMPRESSION}" in
        zstd)  echo "--zstd" ;;
        gzip)  echo "-z" ;;
        bzip2) echo "-j" ;;
        xz)    echo "-J" ;;
        *)     echo "-z" ;;
    esac
}

# Create archive: draco_create_archive <output_file.tar.EXT.enc> <base_dir> <paths...>
draco_create_archive() {
    local outfile="$1"
    local basedir="$2"
    shift 2
    local paths=("$@")

    local pass
    pass="$(draco_prompt_password_only)"

    local compress_flag
    compress_flag="$(draco_tar_compress_flag)"

    # Build exclude flags
    local exclude_args=()
    for excl in "${DRACO_EXCLUDE_DEFAULT[@]}"; do
        exclude_args+=(--exclude="$excl")
    done

    # Filter: only include paths that exist
    local existing_paths=()
    for p in "${paths[@]}"; do
        local full="${HOME}/${p}"
        if [[ -e "$full" || -L "$full" ]]; then
            # Use relative path for portability
            existing_paths+=("$p")
        fi
    done

    if [[ ${#existing_paths[@]} -eq 0 ]]; then
        draco_warn "No paths to archive."
        return 1
    fi

    # Create encrypted archive via pipe
    tar -C "$basedir" \
        "${exclude_args[@]}" \
        "${compress_flag}" \
        -cf - \
        "${existing_paths[@]}" 2>/dev/null \
    | draco_encrypt "$pass" > "$outfile"

    return "${PIPESTATUS[0]}"
}

# Extract archive: draco_extract_archive <archive_file.enc> <dest_dir>
draco_extract_archive() {
    local archive="$1"
    local destdir="$2"
    local pass
    pass="$(draco_prompt_password_only)"

    mkdir -p "$destdir"

    draco_decrypt "$pass" < "$archive" \
    | tar -C "$destdir" -xf -

    return "${PIPESTATUS[0]}"
}

# ─── Hash / dedup ─────────────────────────────────────────────────────────────
draco_file_hash() {
    local file="$1"
    sha256sum "$file" | awk '{print $1}'
}

draco_get_last_backup_id() {
    if [[ -z "${DRACO_BACKUP_DIR:-}" || ! -d "$DRACO_BACKUP_DIR" ]]; then
        echo ""
        return 1
    fi
    find "$DRACO_BACKUP_DIR" -maxdepth 1 -name "draco-*.enc" \
        | sort | tail -1 \
        | xargs -r basename \
        | sed 's/draco-\(.*\)\.tar\..*/\1/'
}

draco_backup_total_size() {
    if [[ -z "${DRACO_BACKUP_DIR:-}" || ! -d "$DRACO_BACKUP_DIR" ]]; then
        echo "0"
        return
    fi
    du -sh "${DRACO_BACKUP_DIR}" 2>/dev/null | awk '{print $1}'
}

# ─── Backup ID ────────────────────────────────────────────────────────────────
draco_new_backup_id() {
    date +%Y%m%d-%H%M%S
}

# ─── Human-readable size ──────────────────────────────────────────────────────
draco_human_size() {
    local file="$1"
    if [[ -f "$file" ]]; then
        du -sh "$file" 2>/dev/null | awk '{print $1}'
    else
        echo "0"
    fi
}

# ─── Prompt yes/no ────────────────────────────────────────────────────────────
draco_confirm() {
    local prompt="${1:-Are you sure?}"
    local default="${2:-n}"
    local yn
    if [[ "$default" == "y" ]]; then
        read -r -p "$prompt [Y/n]: " yn
        yn="${yn:-y}"
    else
        read -r -p "$prompt [y/N]: " yn
        yn="${yn:-n}"
    fi
    [[ "$yn" =~ ^[Yy]$ ]]
}

# ─── List backups ─────────────────────────────────────────────────────────────
draco_backup_list() {
    if [[ -z "${DRACO_BACKUP_DIR:-}" || ! -d "$DRACO_BACKUP_DIR" ]]; then
        draco_warn "Backup directory not configured or does not exist."
        return 1
    fi

    local count=0
    echo -e "${C_BOLD}ID                    SIZE    DATE${C_RESET}"
    echo "─────────────────────────────────────────"

    while IFS= read -r f; do
        local base
        base="$(basename "$f")"
        local bid
        bid="$(echo "$base" | sed 's/draco-\(.*\)\..*/\1/')"
        local sz
        sz="$(draco_human_size "$f")"
        local dt
        dt="$(stat -c '%y' "$f" 2>/dev/null | cut -d'.' -f1 || date)"
        printf "%-22s %-8s %s\n" "$bid" "$sz" "$dt"
        count=$((count+1))
    done < <(find "$DRACO_BACKUP_DIR" -maxdepth 1 -name "draco-*.enc" | sort)

    echo "─────────────────────────────────────────"
    echo "Total: $count backup(s) — $(draco_backup_total_size)"
}

# ─── Delete backup ────────────────────────────────────────────────────────────
draco_backup_delete() {
    local bid="${1:-}"

    if [[ -z "$bid" ]]; then
        draco_warn "No backup ID specified. Use 'draco list' to see available backups."
        return 1
    fi

    local pattern="${DRACO_BACKUP_DIR}/draco-${bid}.*"
    local found=0

    for f in $pattern; do
        [[ -e "$f" ]] || continue
        found=1
        draco_warn "About to delete: $(basename "$f")"
    done

    if [[ "$found" -eq 0 ]]; then
        draco_error "Backup not found: $bid"
        return 1
    fi

    if draco_confirm "Delete backup $bid?"; then
        for f in $pattern; do
            [[ -e "$f" || -L "$f" ]] || continue
            rm -f "$f"
            draco_ok "Deleted: $(basename "$f")"
        done
        # Remove meta
        rm -f "${DRACO_BACKUP_DIR}/.meta/${bid}.log"
        rm -f "${DRACO_BACKUP_DIR}/.meta/${bid}.meta"
    else
        draco_info "Aborted."
    fi
}

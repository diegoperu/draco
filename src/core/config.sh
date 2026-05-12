#!/usr/bin/env bash
# DRACO - config.sh: Configuration management
# GNU GPL v3 - See LICENSE

# ─── Default config values ────────────────────────────────────────────────────
DRACO_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/draco"
DRACO_CONFIG_FILE="${DRACO_CONFIG_DIR}/draco.conf"
DRACO_DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/draco"
DRACO_LOG_DIR="${DRACO_DATA_DIR}/logs"

# Backup defaults
DRACO_BACKUP_DIR=""           # Set by user - required
DRACO_ENCRYPTION_ALGO="aes-256-cbc"
DRACO_COMPRESSION="zstd"
DRACO_COMPRESSION_LEVEL=6
DRACO_PASSWORD=""             # Set at runtime

# Retention defaults
DRACO_RETENTION_KEEP_DAILY=7
DRACO_RETENTION_KEEP_WEEKLY=4
DRACO_RETENTION_KEEP_MONTHLY=12
DRACO_RETENTION_KEEP_YEARLY=3
DRACO_RETENTION_POLICY="all"  # all | daily | weekly | monthly

# Schedule defaults
DRACO_SCHEDULE_TYPE=""        # systemd | cron | none
DRACO_SCHEDULE_FREQ="daily"   # hourly | daily | weekly | monthly
DRACO_SCHEDULE_TIME="02:00"

# TUI defaults
DRACO_TUI_THEME="default"     # default | blue | anthropic | eva01 | matrix

# Desktop environment (auto-detected)
DRACO_DE=""

# ─── Dotfiles and config paths to backup ─────────────────────────────────────
# These are relative to $HOME unless starting with /
DRACO_DOTFILES_DEFAULT=(
    ".bashrc"
    ".bash_profile"
    ".bash_aliases"
    ".bash_logout"
    ".zshrc"
    ".zprofile"
    ".zshenv"
    ".zsh_history"
    ".profile"
    ".inputrc"
    ".vimrc"
    ".vim"
    ".nvim"
    ".config/nvim"
    ".tmux.conf"
    ".tmux"
    ".gitconfig"
    ".gitignore_global"
    ".git-credentials"
    ".gnupg"
    ".ssh"
    ".config/fish"
    ".config/starship.toml"
    ".oh-my-zsh"
    ".zsh"
    # Spaceship prompt
    ".config/spaceship"
    # Editors
    ".config/Code/User/settings.json"
    ".config/Code/User/keybindings.json"
    ".config/Code/User/snippets"
    # Terminal emulators
    ".config/alacritty"
    ".config/kitty"
    ".config/wezterm"
    # KDE/Konsole
    ".config/konsolerc"
    ".local/share/konsole"
    ".config/kdeglobals"
    ".config/kglobalshortcutsrc"
    ".config/kwinrc"
    ".config/kscreenlockerrc"
    ".config/plasma-org.kde.plasma.desktop-appletsrc"
    ".config/plasmashellrc"
    ".config/krunnerrc"
    ".config/kcminputrc"
    ".config/kxkbrc"
    ".config/khotkeysrc"
    ".config/ksmserverrc"
    ".config/ktimezonedrc"
    ".local/share/plasma"
    ".local/share/color-schemes"
    ".local/share/aurorae"
    ".local/share/plasma/plasmoids"
    # GNOME
    # GNOME settings exported via dconf - handled separately
    # Fonts (user installed)
    ".local/share/fonts"
    # Icons/themes
    ".local/share/icons"
    ".themes"
    ".icons"
    # Misc
    ".config/mimeapps.list"
    ".config/user-dirs.dirs"
    ".config/environment.d"
    ".local/bin"
)

# KDE-specific paths (only backed up when DE=kde)
DRACO_KDE_PATHS=(
    ".config/konsolerc"
    ".local/share/konsole"
    ".config/kdeglobals"
    ".config/kglobalshortcutsrc"
    ".config/kwinrc"
    ".config/kscreenlockerrc"
    ".config/plasma-org.kde.plasma.desktop-appletsrc"
    ".config/plasmashellrc"
    ".config/krunnerrc"
    ".config/kcminputrc"
    ".config/kxkbrc"
    ".config/khotkeysrc"
    ".config/ksmserverrc"
    ".config/ktimezonedrc"
    ".local/share/plasma"
    ".local/share/color-schemes"
    ".local/share/aurorae"
    ".local/share/plasma/plasmoids"
    ".config/gtk-3.0"
    ".config/gtk-4.0"
)

# GNOME-specific paths (only backed up when DE=gnome)
DRACO_GNOME_PATHS=(
    ".config/gtk-3.0"
    ".config/gtk-4.0"
    ".config/dconf"
    ".local/share/gnome-shell"
    ".config/gnome-terminal"
)

# Paths to EXCLUDE from backup (globs supported)
DRACO_EXCLUDE_DEFAULT=(
    ".ssh/known_hosts"
    ".cache"
    ".local/share/Trash"
    ".local/share/recently-used.xbel"
    ".thumbnails"
    ".local/share/thumbnails"
    "*.pyc"
    "*/__pycache__"
    "*.swp"
    "*.swo"
    ".vim/undo"
    ".vim/backup"
    ".vim/swap"
    ".vscode-server"
    ".local/share/Steam"
    "node_modules"
    ".cargo/registry"
    ".rustup/toolchains"
    ".gradle"
    ".m2/repository"
    ".npm"
    ".cache"
)

# ─── Load config ──────────────────────────────────────────────────────────────
draco_load_config() {
    local alt_config="${1:-}"
    local cfg_file="${alt_config:-$DRACO_CONFIG_FILE}"

    # Apply env overrides first
    [[ -n "${DRACO_BACKUP_DIR:-}" ]] || true
    [[ -n "${DRACO_CONFIG:-}" ]] && cfg_file="$DRACO_CONFIG"

    if [[ -f "$cfg_file" ]]; then
        # Safely source config - only allow KEY=VALUE lines
        while IFS='=' read -r key value; do
            # Skip comments and empty lines
            [[ "$key" =~ ^[[:space:]]*# ]] && continue
            [[ -z "${key// }" ]] && continue
            # Strip surrounding whitespace
            key="${key// /}"
            # Only allow known DRACO_ variables
            if [[ "$key" =~ ^DRACO_[A-Z_]+$ ]]; then
                # Strip quotes from value
                value="${value%\"}"
                value="${value#\"}"
                value="${value%\'}"
                value="${value#\'}"
                export "$key"="$value"
            fi
        done < "$cfg_file"
    fi

    # Env overrides (highest priority)
    [[ -n "${DRACO_PASSWORD:-}" ]] || true
}

# ─── Save config ──────────────────────────────────────────────────────────────
draco_save_config() {
    mkdir -p "$DRACO_CONFIG_DIR"

    cat > "$DRACO_CONFIG_FILE" <<EOF
# DRACO Configuration
# Generated: $(date -Iseconds)
# WARNING: Do not store password here. Use DRACO_PASSWORD env var or enter at prompt.

DRACO_BACKUP_DIR="${DRACO_BACKUP_DIR}"
DRACO_ENCRYPTION_ALGO="${DRACO_ENCRYPTION_ALGO}"
DRACO_COMPRESSION="${DRACO_COMPRESSION}"
DRACO_COMPRESSION_LEVEL="${DRACO_COMPRESSION_LEVEL}"

# Retention policy: all | daily | weekly | monthly
DRACO_RETENTION_POLICY="${DRACO_RETENTION_POLICY}"
DRACO_RETENTION_KEEP_DAILY="${DRACO_RETENTION_KEEP_DAILY}"
DRACO_RETENTION_KEEP_WEEKLY="${DRACO_RETENTION_KEEP_WEEKLY}"
DRACO_RETENTION_KEEP_MONTHLY="${DRACO_RETENTION_KEEP_MONTHLY}"
DRACO_RETENTION_KEEP_YEARLY="${DRACO_RETENTION_KEEP_YEARLY}"

# Schedule: systemd | cron | none
DRACO_SCHEDULE_TYPE="${DRACO_SCHEDULE_TYPE}"
DRACO_SCHEDULE_FREQ="${DRACO_SCHEDULE_FREQ}"
DRACO_SCHEDULE_TIME="${DRACO_SCHEDULE_TIME}"

# TUI theme: default | blue | anthropic | eva01 | matrix
DRACO_TUI_THEME="${DRACO_TUI_THEME}"
EOF
    chmod 600 "$DRACO_CONFIG_FILE"
    draco_debug "Config saved to $DRACO_CONFIG_FILE"
}

# ─── First run interactive setup ──────────────────────────────────────────────
draco_first_run_setup() {
    draco_info "═══════════════════════════════════════════"
    draco_info "  DRACO v${DRACO_VERSION} - First Run Setup"
    draco_info "═══════════════════════════════════════════"
    echo

    # Backup directory
    while true; do
        read -r -p "Backup destination path: " input_dir
        input_dir="${input_dir/#\~/$HOME}"
        if [[ -z "$input_dir" ]]; then
            draco_warn "Path required."
            continue
        fi
        if mkdir -p "$input_dir" 2>/dev/null; then
            DRACO_BACKUP_DIR="$(realpath "$input_dir")"
            break
        else
            draco_error "Cannot create directory: $input_dir"
        fi
    done

    draco_save_config

    # Schedule check
    echo
    if draco_scheduler_is_installed; then
        draco_info "Automatic schedule already installed."
    else
        read -r -p "Install automatic backup schedule? [y/N]: " yn
        if [[ "$yn" =~ ^[Yy]$ ]]; then
            draco_schedule_interactive_install
        else
            draco_info "Skipped. Run 'draco schedule install' later."
        fi
    fi
}

# ─── Config wizard (CLI) ──────────────────────────────────────────────────────
draco_config_wizard() {
    draco_info "DRACO Configuration Wizard"
    echo

    # Backup dir
    echo "Current backup dir: ${DRACO_BACKUP_DIR:-'(not set)'}"
    read -r -p "New backup dir [Enter to keep]: " input
    if [[ -n "$input" ]]; then
        input="${input/#\~/$HOME}"
        mkdir -p "$input"
        DRACO_BACKUP_DIR="$(realpath "$input")"
    fi

    # Compression level
    echo "Compression level 1-19 (current: ${DRACO_COMPRESSION_LEVEL})"
    read -r -p "New level [Enter to keep]: " input
    if [[ -n "$input" && "$input" =~ ^[0-9]+$ ]]; then
        DRACO_COMPRESSION_LEVEL="$input"
    fi

    # Retention policy
    echo "Retention policy: all | daily | weekly | monthly (current: ${DRACO_RETENTION_POLICY})"
    read -r -p "New policy [Enter to keep]: " input
    if [[ -n "$input" ]]; then
        DRACO_RETENTION_POLICY="$input"
    fi

    # TUI theme
    echo "TUI theme: default | blue | anthropic | eva01 | matrix (current: ${DRACO_TUI_THEME})"
    read -r -p "New theme [Enter to keep]: " input
    if [[ -n "$input" ]]; then
        DRACO_TUI_THEME="$input"
    fi

    draco_save_config
    draco_info "Configuration saved."
}

# ─── Status ───────────────────────────────────────────────────────────────────
draco_status() {
    draco_detect_distro 2>/dev/null || true
    draco_detect_de     2>/dev/null || true

    local last_backup
    last_backup="$(draco_get_last_backup_id 2>/dev/null || echo 'none')"
    local total_size
    total_size="$(draco_backup_total_size 2>/dev/null || echo 'unknown')"
    local sched_installed="no"
    draco_scheduler_is_installed 2>/dev/null && sched_installed="yes"

    cat <<EOF
DRACO v${DRACO_VERSION} Status
═══════════════════════════════
Config file    : ${DRACO_CONFIG_FILE}
Backup dir     : ${DRACO_BACKUP_DIR:-(not set)}
Last backup    : ${last_backup}
Total size     : ${total_size}
DE detected    : ${DRACO_DE:-(unknown)}
Distro         : ${DRACO_DISTRO:-(unknown)}
Schedule       : ${DRACO_SCHEDULE_TYPE:-none} (installed: ${sched_installed})
Retention      : ${DRACO_RETENTION_POLICY}
Theme          : ${DRACO_TUI_THEME}
EOF
}

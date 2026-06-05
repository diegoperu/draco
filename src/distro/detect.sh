#!/usr/bin/env bash
# DRACO - detect.sh: Distro and DE detection + package manager abstraction
# GNU GPL v3 - See LICENSE

# ─── Distro detection ─────────────────────────────────────────────────────────
draco_detect_distro() {
    DRACO_DISTRO=""
    DRACO_DISTRO_FAMILY=""
    DRACO_DISTRO_VERSION=""
    DRACO_PKG_MANAGER=""

    if [[ -f /etc/os-release ]]; then
        # shellcheck source=/dev/null
        source /etc/os-release
        DRACO_DISTRO="${ID:-unknown}"
        DRACO_DISTRO_VERSION="${VERSION_ID:-}"
        DRACO_DISTRO_FAMILY="${ID_LIKE:-$ID}"
    elif [[ -f /etc/arch-release ]]; then
        DRACO_DISTRO="arch"
        DRACO_DISTRO_FAMILY="arch"
    elif [[ -f /etc/debian_version ]]; then
        DRACO_DISTRO="debian"
        DRACO_DISTRO_FAMILY="debian"
    fi

    case "$DRACO_DISTRO" in
        fedora|rhel|centos|rocky|almalinux)
            DRACO_DISTRO_FAMILY="redhat"
            DRACO_PKG_MANAGER="dnf"
            ;;
        debian|ubuntu|linuxmint|pop|elementary|zorin|kubuntu|xubuntu)
            DRACO_DISTRO_FAMILY="debian"
            DRACO_PKG_MANAGER="apt"
            ;;
        arch|manjaro|endeavouros|garuda)
            DRACO_DISTRO_FAMILY="arch"
            DRACO_PKG_MANAGER="pacman"
            ;;
        opensuse*|suse*)
            DRACO_DISTRO_FAMILY="suse"
            DRACO_PKG_MANAGER="zypper"
            ;;
        *)
            draco_warn "Unknown distro: $DRACO_DISTRO. Package backup may be incomplete."
            # Try to auto-detect
            if command -v dnf &>/dev/null; then
                DRACO_PKG_MANAGER="dnf"
            elif command -v apt &>/dev/null; then
                DRACO_PKG_MANAGER="apt"
            elif command -v pacman &>/dev/null; then
                DRACO_PKG_MANAGER="pacman"
            elif command -v zypper &>/dev/null; then
                DRACO_PKG_MANAGER="zypper"
            fi
            ;;
    esac

    draco_debug "Distro: $DRACO_DISTRO (${DRACO_DISTRO_FAMILY}), PKG: $DRACO_PKG_MANAGER"
    export DRACO_DISTRO DRACO_DISTRO_FAMILY DRACO_DISTRO_VERSION DRACO_PKG_MANAGER
}

# ─── Version validation ────────────────────────────────────────────────────────
draco_validate_distro_version() {
    local ok=1
    case "$DRACO_DISTRO" in
        fedora)
            local ver="${DRACO_DISTRO_VERSION%%.*}"
            if [[ -n "$ver" && "$ver" -lt 42 ]]; then
                draco_warn "Fedora $ver detected. DRACO supports Fedora 42+. Proceeding anyway."
                ok=0
            fi
            ;;
        debian)
            local ver="${DRACO_DISTRO_VERSION%%.*}"
            if [[ -n "$ver" && "$ver" -lt 12 ]]; then
                draco_warn "Debian $ver detected. DRACO supports Debian 12+. Proceeding anyway."
                ok=0
            fi
            ;;
        ubuntu)
            if [[ -n "$DRACO_DISTRO_VERSION" ]]; then
                local maj="${DRACO_DISTRO_VERSION%%.*}"
                if [[ "$maj" -lt 24 ]]; then
                    draco_warn "Ubuntu $DRACO_DISTRO_VERSION detected. DRACO supports 24.04+. Proceeding anyway."
                    ok=0
                fi
            fi
            ;;
    esac
    return $((1 - ok))
}

# ─── DE detection ─────────────────────────────────────────────────────────────
draco_detect_de() {
    DRACO_DE="unknown"
    DRACO_DE_SESSION="${XDG_SESSION_DESKTOP:-${DESKTOP_SESSION:-}}"
    DRACO_DE_TYPE="${XDG_SESSION_TYPE:-}"   # wayland | x11

    local session_lower
    session_lower="${DRACO_DE_SESSION,,}"

    case "$session_lower" in
        *kde*|*plasma*)
            DRACO_DE="kde"
            ;;
        *gnome*)
            DRACO_DE="gnome"
            ;;
        *xfce*)
            DRACO_DE="xfce"
            ;;
        *lxqt*)
            DRACO_DE="lxqt"
            ;;
        *mate*)
            DRACO_DE="mate"
            ;;
        *cinnamon*)
            DRACO_DE="cinnamon"
            ;;
        *)
            # Fallback: check running processes
            if pgrep -x "plasmashell" &>/dev/null || pgrep -x "kwin_wayland" &>/dev/null; then
                DRACO_DE="kde"
            elif pgrep -x "gnome-shell" &>/dev/null; then
                DRACO_DE="gnome"
            elif pgrep -x "xfce4-session" &>/dev/null; then
                DRACO_DE="xfce"
            fi
            ;;
    esac

    draco_debug "DE: $DRACO_DE (session: ${DRACO_DE_SESSION:-n/a}, type: ${DRACO_DE_TYPE:-n/a})"
    export DRACO_DE DRACO_DE_SESSION DRACO_DE_TYPE
}

# ─── DE mismatch warning ──────────────────────────────────────────────────────
# Used at restore time: check if backed-up DE matches current DE
draco_check_de_mismatch() {
    local backed_up_de="$1"
    local current_de="${DRACO_DE}"

    if [[ "$backed_up_de" == "$current_de" ]]; then
        return 0
    fi

    if [[ "$backed_up_de" =~ ^(kde|gnome)$ && "$current_de" =~ ^(kde|gnome)$ ]]; then
        draco_warn "══════════════════════════════════════════════════════"
        draco_warn "  DE MISMATCH DETECTED"
        draco_warn "  Backup was created with: ${backed_up_de^^}"
        draco_warn "  Current system runs:     ${current_de^^}"
        draco_warn ""
        draco_warn "  All configs will be restored EXCEPT:"
        draco_warn "  - Desktop environment personalizations"
        draco_warn "  - ${backed_up_de^^}-specific settings"
        draco_warn "══════════════════════════════════════════════════════"
        return 1
    fi
    return 0
}

# ─── Package listing ──────────────────────────────────────────────────────────
draco_list_packages() {
    case "$DRACO_PKG_MANAGER" in
        dnf)
            # Explicitly installed (not deps)
            dnf repoquery --userinstalled --qf '%{name}' 2>/dev/null \
            | sort -u
            ;;
        apt)
            # Explicitly installed (not auto)
            comm -23 \
                <(dpkg-query -W -f='${Package}\n' | sort) \
                <(apt-mark showauto 2>/dev/null | sort) \
            2>/dev/null | sort -u
            ;;
        pacman)
            # Explicitly installed, excluding base group
            pacman -Qqe 2>/dev/null | sort -u
            ;;
        zypper)
            zypper se --installed-only -t package 2>/dev/null \
            | awk '/^i/{print $3}' | sort -u
            ;;
        *)
            draco_warn "Cannot list packages: unknown package manager"
            echo ""
            ;;
    esac
}

# List Flatpak apps
draco_list_flatpaks() {
    if command -v flatpak &>/dev/null; then
        flatpak list --app --columns=application 2>/dev/null | tail -n +1 | sort -u
    fi
}

# List Snap packages
draco_list_snaps() {
    if command -v snap &>/dev/null; then
        snap list 2>/dev/null | awk 'NR>1 {print $1}' | sort -u
    fi
}

# List pip global packages (user)
draco_list_pip_packages() {
    if command -v pip3 &>/dev/null; then
        pip3 list --user 2>/dev/null | awk 'NR>2 {print $1}' | sort -u
    elif command -v pip &>/dev/null; then
        pip list --user 2>/dev/null | awk 'NR>2 {print $1}' | sort -u
    fi
}

# List npm global packages
draco_list_npm_packages() {
    if command -v npm &>/dev/null; then
        npm list -g --depth=0 2>/dev/null \
        | awk 'NR>1 {gsub(/@.*/, "", $2); print $2}' \
        | grep -v '^$' | sort -u
    fi
}

# ─── Generate reinstall script ─────────────────────────────────────────────────
draco_generate_reinstall_script() {
    local outfile="$1"
    local backup_id="$2"

    draco_detect_distro
    draco_detect_de

    cat > "$outfile" <<REINSTALL_SCRIPT
#!/usr/bin/env bash
# DRACO Reinstall Script
# Generated: $(date -Iseconds)
# Backup ID: ${backup_id}
# Distro: ${DRACO_DISTRO} (${DRACO_DISTRO_FAMILY})
# DE: ${DRACO_DE}
# Package manager: ${DRACO_PKG_MANAGER}
# GNU GPL v3

set -euo pipefail

echo "════════════════════════════════════════"
echo "  DRACO - Software Reinstall Script"
echo "  Backup: ${backup_id}"
echo "════════════════════════════════════════"
echo

# Detect current distro
if [[ -f /etc/os-release ]]; then
    source /etc/os-release
    CURRENT_DISTRO="\${ID:-unknown}"
else
    CURRENT_DISTRO="unknown"
fi

BACKED_UP_DISTRO="${DRACO_DISTRO}"

if [[ "\$CURRENT_DISTRO" != "\$BACKED_UP_DISTRO" ]]; then
    echo "[WARN] Distro mismatch: backup from '\$BACKED_UP_DISTRO', current '\$CURRENT_DISTRO'"
    echo "[WARN] Package names may differ. Proceeding anyway..."
    echo
fi

REINSTALL_SCRIPT

    # System packages
    local pkg_list
    pkg_list="$(draco_list_packages)"

    case "$DRACO_PKG_MANAGER" in
        dnf)
            cat >> "$outfile" <<EOF

# ─── DNF packages ─────────────────────────────────────────────────────────────
echo "[INFO] Installing system packages via dnf..."
sudo dnf install -y \\
EOF
            echo "$pkg_list" | sed 's/^/    /' | sed 's/$/ \\/' >> "$outfile"
            echo '    2>/dev/null || true' >> "$outfile"
            ;;
        apt)
            cat >> "$outfile" <<EOF

# ─── APT packages ─────────────────────────────────────────────────────────────
echo "[INFO] Installing system packages via apt..."
sudo apt-get update
sudo apt-get install -y \\
EOF
            echo "$pkg_list" | sed 's/^/    /' | sed 's/$/ \\/' >> "$outfile"
            echo '    2>/dev/null || true' >> "$outfile"
            ;;
        pacman)
            cat >> "$outfile" <<EOF

# ─── Pacman packages ──────────────────────────────────────────────────────────
echo "[INFO] Installing system packages via pacman..."
sudo pacman -S --needed --noconfirm \\
EOF
            echo "$pkg_list" | sed 's/^/    /' | sed 's/$/ \\/' >> "$outfile"
            echo '    2>/dev/null || true' >> "$outfile"
            ;;
        zypper)
            cat >> "$outfile" <<EOF

# ─── Zypper packages ──────────────────────────────────────────────────────────
echo "[INFO] Installing system packages via zypper..."
sudo zypper install -n \\
EOF
            echo "$pkg_list" | sed 's/^/    /' | sed 's/$/ \\/' >> "$outfile"
            echo '    2>/dev/null || true' >> "$outfile"
            ;;
    esac

    # Flatpak
    local flatpak_list
    flatpak_list="$(draco_list_flatpaks 2>/dev/null || true)"
    if [[ -n "$flatpak_list" ]]; then
        cat >> "$outfile" <<EOF

# ─── Flatpak applications ─────────────────────────────────────────────────────
echo "[INFO] Installing Flatpak applications..."
command -v flatpak &>/dev/null || { echo "[WARN] flatpak not installed, skipping"; }
if command -v flatpak &>/dev/null; then
    flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo || true
EOF
        while IFS= read -r app; do
            [[ -n "$app" ]] && echo "    flatpak install -y flathub $app || true" >> "$outfile"
        done <<< "$flatpak_list"
        echo "fi" >> "$outfile"
    fi

    # Snap
    local snap_list
    snap_list="$(draco_list_snaps 2>/dev/null || true)"
    if [[ -n "$snap_list" ]]; then
        cat >> "$outfile" <<EOF

# ─── Snap packages ────────────────────────────────────────────────────────────
echo "[INFO] Installing Snap packages..."
if command -v snap &>/dev/null; then
EOF
        while IFS= read -r pkg; do
            [[ -n "$pkg" ]] && echo "    sudo snap install $pkg || true" >> "$outfile"
        done <<< "$snap_list"
        echo "fi" >> "$outfile"
    fi

    # pip
    local pip_list
    pip_list="$(draco_list_pip_packages 2>/dev/null || true)"
    if [[ -n "$pip_list" ]]; then
        cat >> "$outfile" <<EOF

# ─── Python (pip) packages ────────────────────────────────────────────────────
echo "[INFO] Installing pip packages..."
if command -v pip3 &>/dev/null; then
EOF
        while IFS= read -r pkg; do
            [[ -n "$pkg" ]] && echo "    pip3 install --user $pkg || true" >> "$outfile"
        done <<< "$pip_list"
        echo "fi" >> "$outfile"
    fi

    # npm
    local npm_list
    npm_list="$(draco_list_npm_packages 2>/dev/null || true)"
    if [[ -n "$npm_list" ]]; then
        cat >> "$outfile" <<EOF

# ─── Node.js (npm) global packages ───────────────────────────────────────────
echo "[INFO] Installing npm global packages..."
if command -v npm &>/dev/null; then
EOF
        while IFS= read -r pkg; do
            [[ -n "$pkg" ]] && echo "    npm install -g $pkg || true" >> "$outfile"
        done <<< "$npm_list"
        echo "fi" >> "$outfile"
    fi

    cat >> "$outfile" <<'EOF'

echo
echo "════════════════════════════════════════"
echo "  Reinstall complete!"
echo "  Restore your dotfiles with:"
echo "    draco restore"
echo "════════════════════════════════════════"
EOF

    chmod +x "$outfile"
    draco_ok "Reinstall script: $outfile"
}

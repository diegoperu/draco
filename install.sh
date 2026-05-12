#!/usr/bin/env bash
# DRACO - install.sh: Install DRACO to system or user path
# GNU GPL v3

set -euo pipefail

DRACO_INSTALL_DIR="${HOME}/.local/bin"
DRACO_DIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"

echo "DRACO Installer"
echo "═══════════════"
echo

# Detect install target
echo "Install options:"
echo "  1) User only: ${HOME}/.local/bin/draco  (no sudo)"
echo "  2) System:    /usr/local/bin/draco       (requires sudo)"
read -r -p "Choose [1-2, default 1]: " choice

case "${choice:-1}" in
    2)
        DRACO_INSTALL_DIR="/usr/local/bin"
        SUDO="sudo"
        ;;
    *)
        DRACO_INSTALL_DIR="${HOME}/.local/bin"
        SUDO=""
        ;;
esac

mkdir -p "$DRACO_INSTALL_DIR"

# Copy entire draco tree
DRACO_TARGET_DIR="${DRACO_INSTALL_DIR}/../share/draco"
DRACO_TARGET_DIR="$(realpath "${DRACO_INSTALL_DIR}/../share/draco" 2>/dev/null || echo "${HOME}/.local/share/draco-app")"

if [[ "$DRACO_INSTALL_DIR" == "/usr/local/bin" ]]; then
    DRACO_TARGET_DIR="/usr/local/share/draco"
fi

$SUDO mkdir -p "$DRACO_TARGET_DIR"
$SUDO cp -r "${DRACO_DIR}/." "$DRACO_TARGET_DIR/"
$SUDO chmod +x "$DRACO_TARGET_DIR/draco"
$SUDO find "$DRACO_TARGET_DIR/src" -name "*.sh" -exec chmod +x {} \;

# Create wrapper symlink/script
DRACO_BIN="${DRACO_INSTALL_DIR}/draco"
$SUDO tee "$DRACO_BIN" > /dev/null <<EOF
#!/usr/bin/env bash
exec "${DRACO_TARGET_DIR}/draco" "\$@"
EOF
$SUDO chmod +x "$DRACO_BIN"

echo
echo "DRACO installed to: $DRACO_BIN"

# PATH check
if ! echo "$PATH" | grep -q "$DRACO_INSTALL_DIR"; then
    echo
    echo "[WARN] ${DRACO_INSTALL_DIR} is not in your PATH."
    echo "  Add to ~/.bashrc or ~/.zshrc:"
    echo "    export PATH=\"\$PATH:${DRACO_INSTALL_DIR}\""
fi

echo
echo "Run: draco"

# DRACO — Claude Code Project Memory

## WHY
DRACO è un sistema di backup cifrato e portabile per workstation Linux.
Salva dotfile, SSH/GPG, KDE/GNOME config, e genera reinstall script automatici.
NON è un backup dati utente — solo configurazioni e software manifest.

## WHAT
- Shell: Bash 4+ puro, zero compilazione, zero dipendenze esterne oltre a tar/openssl/zstd
- Struttura: `draco` (entry point) + `src/{core,backup,restore,distro,scheduler,tui}/`
- Cifratura: AES-256-CBC via OpenSSL, PBKDF2 600k iterazioni
- Compressione: zstd (fallback gzip)
- TUI: dialog (preferito) o whiptail, 5 temi — NEWT_COLORS ignorato su KDE Konsole con palette custom; usare dialog con DIALOGRC

## HOW — Regole di sviluppo

### Bash
- `set -euo pipefail` in tutti gli script — MAI usare `[[ ! -t 1 && ... ]]` a top level (causa exit silenzioso)
- Ogni `||` o `&&` in condizioni booleane complesse: wrappa in `{ ... } || true`
- Tutti i file `.sh` in `src/` sono SOURCED da `draco`, non eseguiti direttamente
- Variabili con `:-` default ovunque: `${VAR:-default}` mai `$VAR` nudo
- Dopo ogni modifica: `bash -n src/**/*.sh && bash -n draco`

### Struttura moduli
- `src/core/config.sh`         — config, first-run, wizard, draco_status
- `src/core/log.sh`            — logging, colori ANSI (_draco_colors_init)
- `src/core/utils.sh`          — crypto, compress, dedup, list, delete
- `src/distro/detect.sh`       — distro/DE detection, pkg manager, reinstall script
- `src/backup/engine.sh`       — backup engine, KDE/GNOME, retention, diff
- `src/restore/engine.sh`      — restore, DE mismatch, pre-restore backup
- `src/scheduler/scheduler.sh` — systemd user timer + cron
- `src/tui/tui.sh`             — TUI dialog/whiptail, 5 temi, DIALOGRC per dialog

### Commit convention (Conventional Commits)
- `feat:` nuova funzionalità
- `fix:` bugfix
- `fix(modulo):` bugfix in modulo specifico (es. `fix(log): ...`)
- `docs:` solo documentazione
- `refactor:` refactoring senza cambio funzionale
- `chore:` manutenzione, config

### Bug noti risolti — NON reintrodurre
- `_draco_colors_init`: usare `{ [[ -t 1 ]] && has_tty=1; } || true` — mai `[[ ! -t 1 && ... ]]`
- `install.sh`: dopo `cp -r`, sempre `chmod +x draco` e `find src -name '*.sh' -exec chmod +x {}`
- `draco_log_init`: fallback `${DRACO_LOG_DIR:-$HOME/.local/share/draco/logs}`
- `draco_status`: chiamare `draco_detect_distro` e `draco_detect_de` prima di stampare

## Distro target
Fedora 42+, Debian 12+, Ubuntu 24.04+, Arch Linux

## DE support
- KDE: completo (Konsole, Spaceship, Plasma, Aurorae, shortcuts)
- GNOME: dconf export/import, extensions, GTK themes
- Mismatch KDE↔GNOME: warning + skip DE config al restore

## Cosa NON backuppare (by design)
Downloads, Documents, ~/.cache, Steam, monitor config, KDE Activities

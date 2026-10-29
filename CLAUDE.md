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
- TUI: bash nativa con ANSI 256-color — disegna su /dev/tty con `\033[38;5;Nm` (fg) e `\033[48;5;Nm` (bg)
  - Range 0-15 rimappati da KDE Konsole → MAI usarli nei temi
  - Range 16-231 (cubo RGB) e 232-255 (grayscale) sono fissi → sempre usare questi
  - Temi: ghost(255/232) blood(196/232) acid(226/232) matrix(46/232) void(51/232)
  - whiptail/dialog usati SOLO per inputbox/passwordbox (colori irrilevanti lì)

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
- `src/tui/tui.sh`             — TUI bash nativa, 5 temi 256-color, output su /dev/tty

### Commit convention (Conventional Commits)
- `feat:` nuova funzionalità
- `fix:` bugfix
- `fix(modulo):` bugfix in modulo specifico (es. `fix(log): ...`)
- `docs:` solo documentazione
- `refactor:` refactoring senza cambio funzionale
- `chore:` manutenzione, config

### Versione
- Attuale: 1.0.2 (2026-10-29). Bump = `DRACO_VERSION` in `draco` + `README.md`, `docs/draco.1`, `docs/draco.1.txt`, `docs/draco-quickguide.txt`

### Bug noti risolti — NON reintrodurre
- `_draco_colors_init`: usare `{ [[ -t 1 ]] && has_tty=1; } || true` — mai `[[ ! -t 1 && ... ]]`
- `install.sh`: dopo `cp -r`, sempre `chmod +x draco` e `find src -name '*.sh' -exec chmod +x {}`
- `draco_log_init`: aggiungere `|| true` alla fine — l'ultima riga `[[ ... ]] && VAR=x` ritorna 1 con set -e se la condizione è falsa, causando exit silenzioso prima della TUI
- `draco_status`: chiamare `draco_detect_distro` e `draco_detect_de` prima di stampare
- TUI temi: MAI usare colori ANSI 0-15 (rimappati da Konsole) — usare solo range 16-255
- **BID extraction (CRITICO)**: usare SEMPRE `sed 's/^draco-//;s/\..*//'` per estrarre backup ID da filename — MAI `sed 's/draco-\(.*\)\..*/\1/'` (greedy: estrae `20260512-093002.tar.zst` invece di `20260512-093002`, lookup `.meta/` fallisce → exit silenzioso)
- **Log ordinamento**: header del log scritto in `draco_backup_run` con `>` (crea file) PRIMA di chiamare `draco_backup_dotfiles`/`draco_backup_kde`/`draco_backup_gnome` che appendono con `>>`. `draco_backup_generate_diff_log` appende solo il diff, NON l'header.
- **Funzioni chiamate in `$(...)`** (es. `draco_restore_select_interactive`): su stdout SOLO il valore di ritorno. Elenchi, prompt e messaggi UI vanno su stderr (`>&2`) — altrimenti finiscono nella variabile catturata (bug RESTORE: "Backup not found" + elenco, 2026-10-29)
- **Password prompt (CRITICO)**: `draco_get_password`/`draco_prompt_password_only` sono chiamate in `$(...)`: l'`echo` dopo `read -s` va SEMPRE su stderr (`echo >&2`). Prima finiva su stdout → backup cifrati con `\n\n+pass`, restore con `\n+pass` → `bad decrypt` (2026-10-29). Backup legacy ancora apribili: `draco_restore_extract` prova pass pulita, poi `\n+pass`, `\n\n+pass` (rimuovere quando non esistono più backup vecchi)
- **Password in argv (CWE-214)**: MAI `openssl -pass pass:"$pass"` (visibile in `ps`). `draco_encrypt`/`draco_decrypt` usano `-pass env:DRACO_OSSL_PASS` con la variabile impostata solo per il processo openssl. NON usare `fd:`/`file:` (leggono solo la prima riga → rompono il fallback legacy con `\n`). Compatibile coi file cifrati col vecchio metodo (2026-10-29)
- **TUI → motore**: `draco_tui_*` che chiamano `draco_restore_run_with_id`/simili devono prima fare `draco_check_deps; draco_detect_distro; draco_detect_de` (la TUI non li esegue; `DRACO_TUI_AVAILABLE` e `DRACO_DE` altrimenti non sono impostati). La selezione backup in TUI usa `draco_tui_menu` nativo, mai whiptail
- **Log location**: `${DRACO_BACKUP_DIR}/.meta/${backup_id}.log` — esterno all'archivio cifrato, leggibile dalla TUI. Se mancante: `draco_backup_log_show` ritorna 1 → wrappare con `if ! ...; then msgbox; return; fi`

## Distro target
Fedora 42+, Debian 12+, Ubuntu 24.04+, Arch Linux

## DE support
- KDE: completo (Konsole, Spaceship, Plasma, Aurorae, shortcuts)
- GNOME: dconf export/import, extensions, GTK themes
- Mismatch KDE↔GNOME: warning + skip DE config al restore

## Cosa NON backuppare (by design)
Downloads, Documents, ~/.cache, Steam, monitor config, KDE Activities

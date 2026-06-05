# DRACO — Setup Claude Code per la gestione del progetto

## 1. Installa Claude Code

```bash
# Installer nativo (non serve Node.js globale)
curl -fsSL https://claude.ai/install.sh | sh

# Verifica
claude --version
```

> Se hai già Node.js installato:
> ```bash
> npm install -g @anthropic-ai/claude-code
> ```

---

## 2. Posizionati nella cartella del progetto

```bash
cd ~/draco   # o dove hai il repo
```

---

## 3. Inizializza la memoria di progetto con /init

```bash
claude
```

Una volta dentro Claude Code, esegui:

```
/init
```

Claude Code scansionerà il progetto e genererà un file `CLAUDE.md` nella root. Questo file viene letto **automaticamente ad ogni sessione** — è la memoria persistente del progetto.

---

## 4. Sostituisci il CLAUDE.md generato con questo

Dopo che `/init` ha creato il file, sostituiscilo con il contenuto qui sotto
(ottimizzato per DRACO):

```bash
cat > CLAUDE.md << 'EOF'
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

### Struttura moduli
- `src/core/config.sh`    — config, first-run, wizard, draco_status
- `src/core/log.sh`       — logging, colori ANSI (_draco_colors_init)
- `src/core/utils.sh`     — crypto, compress, dedup, list, delete
- `src/distro/detect.sh`  — distro/DE detection, pkg manager, reinstall script
- `src/backup/engine.sh`  — backup engine, KDE/GNOME, retention, diff
- `src/restore/engine.sh` — restore, DE mismatch, pre-restore backup
- `src/scheduler/scheduler.sh` — systemd user timer + cron
- `src/tui/tui.sh`        — TUI bash nativa, 5 temi 256-color, output su /dev/tty

### Comandi utili per sviluppo
- Syntax check tutti i file: `bash -n src/**/*.sh && bash -n draco`
- Test manuale: `bash -x draco status 2>&1 | head -40`
- Installazione locale: `bash install.sh` (sceglie user: ~/.local/bin)

### Commit convention (Conventional Commits)
- `feat:` nuova funzionalità
- `fix:` bugfix
- `fix(modulo):` bugfix in modulo specifico (es. `fix(log): ...`)
- `docs:` solo documentazione
- `refactor:` refactoring senza cambio funzionale
- `chore:` manutenzione, dipendenze, config

### Bug noti risolti (non reintrodurre)
- `_draco_colors_init`: usare `{ [[ -t 1 ]] && has_tty=1; } || true` — mai `[[ ! -t 1 && ... ]]`
- `install.sh`: dopo `cp -r`, sempre `chmod +x draco` e `find src -name '*.sh' -exec chmod +x {}`
- `draco_log_init`: aggiungere `|| true` alla fine — l'ultima riga `[[ ... ]] && VAR=x` ritorna 1 con set -e se la condizione è falsa, causando exit silenzioso prima della TUI
- `draco_status`: chiamare `draco_detect_distro` e `draco_detect_de` prima di stampare
- TUI temi: MAI usare colori ANSI 0-15 (rimappati da Konsole) — usare solo range 16-255

## Distro target
Fedora 42+, Debian 12+, Ubuntu 24.04+, Arch Linux

## Desktop Environment support
- KDE: completo (Konsole, Spaceship, Plasma, Aurorae, shortcuts)
- GNOME: dconf export/import, extensions, GTK themes
- Mismatch KDE↔GNOME: warning automatico + skip DE config al restore

## Cosa NON backuppare (by design)
Downloads, Documents, ~/.cache, Steam, monitor config, KDE Activities
EOF
```

---

## 5. Workflow quotidiano con Claude Code

### Avvio sessione

```bash
cd ~/draco
claude
```

Claude Code legge `CLAUDE.md` automaticamente. Non devi rispiegare il progetto.

### Comandi utili dentro Claude Code

| Comando | Cosa fa |
|---------|---------|
| `/init` | Rigenera/aggiorna CLAUDE.md dalla struttura del progetto |
| `/memory` | Mostra cosa Claude ha imparato autonomamente nelle sessioni precedenti |
| `Shift+Tab` | **Plan mode** — Claude pianifica le modifiche PRIMA di scriverle |

### Esempio: chiedere un fix

```
fix: draco_backup_run non gestisce il caso in cui DRACO_BACKUP_DIR
contenga spazi nel path. Fai il fix in src/backup/engine.sh,
poi fai syntax check con bash -n, poi mostrami il diff.
```

### Esempio: chiedere una feature

```
feat: aggiungi il supporto al backup di ~/.config/nvim/lazy-lock.json
e dei plugin installati da lazy.nvim. Aggiorna anche la lista
DRACO_DOTFILES_DEFAULT in src/core/config.sh e documenta in README.md.
```

### Esempio: commit automatico

```
i test passano, fai commit con conventional commits di tutte
le modifiche fatte in questa sessione
```

Claude Code scriverà il messaggio di commit, farà `git add` dei file
modificati e committa. Tu revisi e confermi.

---

## 6. Workflow raccomandato per ogni modifica

```
1. Apri Claude Code: claude
2. Shift+Tab → Plan mode
3. Descrivi la modifica in linguaggio naturale
4. Revisiona il piano proposto
5. Conferma → Claude implementa
6. Claude fa syntax check automatico (grazie a CLAUDE.md)
7. Chiedi commit: "committa con conventional commits"
8. git push
```

---

## 7. Aggiungi CLAUDE.md al .gitignore o committalo?

**Commita `CLAUDE.md`** — è la memoria condivisa del progetto, utile se
in futuro collabori o riprendi il progetto su un'altra macchina.

```bash
git add CLAUDE.md
git commit -m "chore: add CLAUDE.md for Claude Code project memory"
git push
```

---

## 8. File CLAUDE.local.md (opzionale — gitignored)

Per preferenze personali che non vuoi nel repo (es. percorso backup locale,
password di test):

```bash
cat > CLAUDE.local.md << 'EOF'
## Preferenze personali
- Il mio backup dir di test: /tmp/draco-test-backup
- Uso zsh con Spaceship, quindi testa sempre il backup di .zshrc e .config/spaceship
EOF

echo "CLAUDE.local.md" >> .gitignore
```

---

## Riepilogo struttura file Claude Code

```
~/draco/
├── CLAUDE.md           ← memoria progetto (committata)
├── CLAUDE.local.md     ← preferenze personali (gitignored)
├── draco               ← entry point
├── install.sh
├── src/
│   └── ...
└── docs/
    └── ...
```

```
~/.claude/
└── CLAUDE.md           ← memoria globale (tutti i tuoi progetti)
```

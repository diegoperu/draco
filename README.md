<div align="center">

```
██████╗ ██████╗  █████╗  ██████╗ ██████╗
██╔══██╗██╔══██╗██╔══██╗██╔════╝██╔═══██╗
██║  ██║██████╔╝███████║██║     ██║   ██║
██║  ██║██╔══██╗██╔══██║██║     ██║   ██║
██████╔╝██║  ██║██║  ██║╚██████╗╚██████╔╝
╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝ ╚═════╝
```

**Dotfile & Runtime Archive and Configuration Orchestrator**

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)
[![Bash](https://img.shields.io/badge/Shell-Bash%204%2B-green.svg)](https://www.gnu.org/software/bash/)
[![Encryption](https://img.shields.io/badge/Encryption-AES--256--CBC-red.svg)](#security)
[![Compression](https://img.shields.io/badge/Compression-zstd-orange.svg)](#)

*Porta la tua workstation ovunque. In un file. Cifrato.*

</div>

---

DRACO è un sistema di backup **portabile**, **cifrato** e **automatizzabile** per workstation Linux. Salva dotfile, chiavi SSH/GPG, personalizzazioni KDE e GNOME (Konsole, Spaceship prompt, temi Plasma...), e genera automaticamente uno script per reinstallare tutto il software con un solo comando.

Non è un backup dei tuoi dati. È il backup della tua **identità da sysadmin**.

## Indice

- [Funzionalità](#funzionalità)
- [Distribuzione supportate](#distribuzioni-supportate)
- [Requisiti](#requisiti)
- [Installazione](#installazione)
- [Utilizzo rapido](#utilizzo-rapido)
- [TUI](#tui--interfaccia-testuale)
- [Backup automatico](#backup-automatico)
- [Ripristino](#ripristino)
- [Retention](#retention)
- [Sicurezza](#sicurezza)
- [Struttura progetto](#struttura-progetto)
- [Limitazioni note](#limitazioni-note)
- [Licenza](#licenza)

---

## Funzionalità

- **Backup cifrato** — AES-256-CBC via OpenSSL, PBKDF2 con 600.000 iterazioni
- **Compressione zstd** — rapida e efficiente; fallback automatico su gzip
- **Deduplicazione SHA-256** — se non ci sono modifiche, nessun file duplicato (symlink)
- **Versioning con log e diff** — ogni backup ha un log leggibile con le variazioni rispetto al precedente
- **KDE completo** — Konsole profiles, Spaceship prompt, color schemes, Plasma themes, Aurorae, shortcut globali
- **GNOME completo** — export/import dconf, estensioni, temi GTK
- **Reinstall script** — generato automaticamente per dnf / apt / pacman / zypper + flatpak + snap + pip + npm
- **Retention configurabile** — `all` / `daily` / `weekly` / `monthly` / `smart`
- **TUI colorata** — 5 temi selezionabili (default, blue, anthropic, eva01, matrix)
- **Automazione** — systemd user timer o cron, installazione interattiva
- **DE mismatch detection** — ripristino da KDE su GNOME (e viceversa) con warning automatico e skip delle config DE-specifiche
- **Portabile** — una cartella, zero compilazione, funziona su qualsiasi Linux con bash 4+

---

## Distribuzioni supportate

| Distro | Versione minima | Package manager |
|--------|----------------|-----------------|
| Fedora | 42+ | dnf |
| Debian | 12 (Bookworm)+ | apt |
| Ubuntu | 24.04 LTS+ | apt |
| Arch Linux | rolling | pacman |
| Manjaro / EndeavourOS / Garuda | — | pacman |
| Kubuntu / Xubuntu / Pop!_OS | 24.04+ | apt |

---

## Requisiti

**Obbligatori** (presenti in quasi tutte le distro):

```
bash >= 4.0   tar   openssl   sha256sum   find   grep   sed   awk
```

**Raccomandati:**

```
zstd      # compressione (fallback: gzip)
dialog    # TUI (raccomandato: colori corretti su tutti i terminali)
whiptail  # TUI alternativa (pacchetto: newt / libnewt)
```

> **Nota:** `dialog` è preferito a `whiptail` perché su KDE Konsole (e in generale
> con terminali con palette personalizzata) `whiptail`/newt ignora i colori
> configurati e usa quelli del tema terminale. `dialog` con DIALOGRC funziona
> correttamente su qualsiasi terminale.

Installazione dipendenze:

```bash
# Fedora
sudo dnf install tar openssl zstd dialog

# Debian / Ubuntu / Kubuntu
sudo apt install tar openssl zstd dialog

# Arch
sudo pacman -S tar openssl zstd dialog
```

---

## Installazione

```bash
# Clona il repo
git clone https://github.com/diegoperu/draco.git
cd draco

# Oppure scarica ed estrai l'archivio
tar xzf draco-*.tar.gz && cd draco

# Installa (user o system)
bash install.sh
```

Lo script installa DRACO in `~/.local/bin/draco` (utente, senza sudo) o `/usr/local/bin/draco` (sistema, con sudo).

> Se `~/.local/bin` non è nel tuo `$PATH`, aggiungi a `~/.bashrc` o `~/.zshrc`:
> ```bash
> export PATH="$PATH:$HOME/.local/bin"
> ```

---

## Utilizzo rapido

```bash
draco                         # Avvia la TUI
draco backup                  # Backup immediato
draco restore                 # Ripristino (selezione interattiva)
draco restore 20260508-143022 # Ripristino backup specifico
draco list                    # Lista backup con dimensioni
draco log                     # Log ultimo backup
draco log 20260508-143022     # Log backup specifico (con diff)
draco delete 20260101-120000  # Elimina un backup
draco schedule install        # Installa schedule automatico
draco config                  # Configurazione
draco status                  # Riepilogo stato
```

**Prima esecuzione:**

```bash
draco
# Chiede: directory di destinazione backup
# Chiede: installare schedule automatico?
# Salva config in: ~/.config/draco/draco.conf
```

---

## TUI — Interfaccia Testuale

```
┌──────────────────────────────────────────────────────────┐
│  DRACO v1.0.0                                            │
│  Dotfile & Runtime Archive and Configuration Orchestrator│
│                                                          │
│  Backup dir: /mnt/backup/draco                           │
│  Last backup: 20260508-020001                            │
│  Storage: 142M                                           │
│                                                          │
│  ┌────────────────────────────────────────┐              │
│  │  BACKUP    Run backup now              │              │
│  │  RESTORE   Restore a backup            │              │
│  │  LIST      List backups and storage    │              │
│  │  LOG       View backup logs and diffs  │              │
│  │  DELETE    Delete backup(s)            │              │
│  │  SCHEDULE  Manage automatic schedule   │              │
│  │  CONFIG    Configure DRACO settings    │              │
│  │  ABOUT     About DRACO                 │              │
│  └────────────────────────────────────────┘              │
└──────────────────────────────────────────────────────────┘
```

### Temi disponibili

| Tema | Palette | Ispirazione |
|------|---------|-------------|
| `default` | Bianco/nero | Massima compatibilità |
| `blue` | Blu/bianco | Sysadmin classico |
| `anthropic` | Corallo su scuro | Brand Anthropic |
| `eva01` | Viola/verde su nero | Evangelion Unit-01 |
| `matrix` | Verde su nero | The Matrix |

```bash
# Cambia tema
draco config   # → TUI theme
# oppure
DRACO_TUI_THEME=matrix draco
```

---

## Backup automatico

### Systemd user timer (raccomandato)

```bash
draco schedule install
# Sceglie: systemd, giornaliero, 02:00
```

Configurare la password per l'esecuzione non presidiata:

```bash
mkdir -p ~/.config/environment.d
echo 'DRACO_PASSWORD=tuapassword' > ~/.config/environment.d/draco.conf
chmod 600 ~/.config/environment.d/draco.conf
```

### Cron

```bash
draco schedule install   # sceglie cron
# oppure manualmente in crontab:
DRACO_PASSWORD=tuapassword
0 2 * * * /home/utente/.local/bin/draco backup -q
```

### Verifica schedule

```bash
draco schedule status
systemctl --user list-timers | grep draco
```

---

## Ripristino

### Scenario 1: stessa macchina / stessa distro

```bash
draco restore              # seleziona il backup dalla lista
# inserisci password
# i file esistenti vengono spostati in ~/.draco-pre-restore-TIMESTAMP/
```

### Scenario 2: nuova macchina / fresh install

```bash
# 1. Installa DRACO (vedi sopra)
# 2. Monta/copia la directory dei backup
# 3. Configura la destinazione
draco config               # o: export DRACO_BACKUP_DIR=/path/backup

# 4. Ripristina dotfile e config
draco restore

# 5. Reinstalla il software
bash ~/.local/share/draco/restore-<ID>/reinstall.sh
```

### Scenario 3: KDE → GNOME (o viceversa)

DRACO rileva il mismatch automaticamente:

```
══════════════════════════════════════════════════════
  DE MISMATCH DETECTED
  Backup creato con: KDE
  Sistema attuale:   GNOME

  Tutto verrà ripristinato TRANNE:
  - Personalizzazioni desktop environment
  - Impostazioni KDE-specifiche
══════════════════════════════════════════════════════
```

Le config DE-specifiche vengono saltate automaticamente. Dotfile, SSH, GPG e tutto il resto vengono ripristinati normalmente.

---

## Retention

| Policy | Comportamento |
|--------|--------------|
| `all` | Mantiene tutto. Il disco cresce indefinitamente. (default) |
| `daily` | Ultimi N backup giornalieri |
| `weekly` | Ultimi N backup settimanali |
| `monthly` | Ultimi N backup mensili |
| `smart` | N giornalieri + 1/settimana per N settimane + 1/mese per N mesi + 1/anno per N anni |

Configurazione in `~/.config/draco/draco.conf`:

```bash
DRACO_RETENTION_POLICY=smart
DRACO_RETENTION_KEEP_DAILY=7
DRACO_RETENTION_KEEP_WEEKLY=4
DRACO_RETENTION_KEEP_MONTHLY=12
DRACO_RETENTION_KEEP_YEARLY=3
```

---

## Sicurezza

- **AES-256-CBC** con PBKDF2 (600.000 iterazioni) — protezione contro brute force
- **La password non viene mai salvata su disco**
- I backup includono chiavi SSH private e keyring GPG: usa una password forte (12+ caratteri)
- Imposta i permessi corretti sulla directory backup:

```bash
chmod 700 $DRACO_BACKUP_DIR
```

- Per l'automazione, usa `~/.config/environment.d/draco.conf` con `chmod 600`
- **Non usare mai `-p password`** dalla CLI in ambienti condivisi (la password appare in `ps aux`)

---

## Struttura progetto

```
draco/
├── draco                        # Entry point principale
├── install.sh                   # Installer (user o system)
├── LICENSE                      # GNU GPL v3
├── docs/
│   ├── draco.1                  # Man page (groff/troff)
│   ├── draco.1.txt              # Man page plain text
│   ├── draco-quickguide.pdf     # Quick guide PDF
│   └── draco-quickguide.txt     # Quick guide plain text
└── src/
    ├── core/
    │   ├── config.sh            # Configurazione, first-run, wizard
    │   ├── log.sh               # Logging, livelli, colori ANSI
    │   └── utils.sh             # Crypto, compressione, dedup, listing
    ├── distro/
    │   └── detect.sh            # Rilevamento distro/DE, package manager,
    │                            # generazione reinstall script
    ├── backup/
    │   └── engine.sh            # Engine backup: dotfile, KDE, GNOME,
    │                            # retention, dedup, log/diff
    ├── restore/
    │   └── engine.sh            # Engine restore, DE mismatch detection,
    │                            # pre-restore backup
    ├── scheduler/
    │   └── scheduler.sh         # Systemd user timer + cron
    └── tui/
        └── tui.sh               # TUI dialog/whiptail, 5 temi
```

---

## Cosa viene backuppato

<details>
<summary>Espandi lista completa</summary>

**Shell e terminale:**
`.bashrc`, `.bash_profile`, `.zshrc`, `.zshenv`, `.profile`, `.inputrc`, `.oh-my-zsh`, `.config/fish`, `.config/spaceship`

**Editor:**
`.vimrc`, `.vim/`, `.config/nvim/`, `.config/Code/User/` (VS Code settings, keybindings, snippets)

**Git e VCS:**
`.gitconfig`, `.gitignore_global`

**SSH e GPG:**
`.ssh/` (escluso `known_hosts`), `.gnupg/`

**Terminali:**
`.config/alacritty/`, `.config/kitty/`, `.config/wezterm/`

**KDE / Plasma:**
`konsolerc`, `~/.local/share/konsole/` (profili), `kdeglobals`, `kglobalshortcutsrc`, `kwinrc`, `plasma-org.kde.plasma.desktop-appletsrc`, `plasmashellrc`, `~/.local/share/plasma/`, `~/.local/share/color-schemes/`, `~/.local/share/aurorae/`, `.config/spaceship/` (Spaceship prompt)

**GNOME:**
dconf dump, `~/.local/share/gnome-shell/extensions/`, `.config/gtk-3.0/`, `.config/gtk-4.0/`

**Font e temi:**
`~/.local/share/fonts/`, `~/.local/share/icons/`, `~/.themes/`, `~/.icons/`

**Misc:**
`.config/mimeapps.list`, `.config/user-dirs.dirs`, `.local/bin/` (script utente)

**Software (manifests):**
Lista pacchetti di sistema, Flatpak, Snap, pip (user), npm globals + reinstall script eseguibile

</details>

---

## Limitazioni note

- **Nessun backup dati utente** (Downloads, Documenti, media) — by design
- **Configurazione monitor esclusa** dal ripristino (risoluzione, disposizione schermi)
- **KDE Activities** non supportate
- **Flatpak**: solo overrides, non i dati per-applicazione
- **Reinstall script**: pacchetti rinominati o rimossi dai repo dal momento del backup falliranno silenziosamente (`|| true`)
- **npm/pip/snap**: liste best-effort, non garantite complete
- **Wayland**: input remapping fuori DE potrebbe non essere catturato

---

## Variabili d'ambiente

| Variabile | Descrizione |
|-----------|-------------|
| `DRACO_PASSWORD` | Password cifratura (nessun prompt se impostata) |
| `DRACO_CONFIG` | Override percorso config file |
| `DRACO_BACKUP_DIR` | Override directory backup (priorità massima) |
| `DRACO_LOG_LEVEL` | `0`=DEBUG `1`=INFO `2`=WARN `3`=ERROR |
| `DRACO_TUI_THEME` | Tema TUI: `default` `blue` `anthropic` `eva01` `matrix` |
| `DRACO_NO_COLOR` | `1` per disabilitare colori ANSI |

---

## Documentazione

| File | Contenuto |
|------|-----------|
| `docs/draco.1` | Man page (installa con `cp draco.1 ~/.local/share/man/man1/`) |
| `docs/draco.1.txt` | Man page plain text |
| `docs/draco-quickguide.pdf` | Quick guide con tabelle e workflow visuale |
| `docs/draco-quickguide.txt` | Quick guide plain text per terminale |

```bash
# Installa man page
mkdir -p ~/.local/share/man/man1
cp docs/draco.1 ~/.local/share/man/man1/
man draco
```

---

## Licenza

DRACO è distribuito sotto licenza **GNU General Public License v3**.  
Vedi [LICENSE](LICENSE) oppure [gnu.org/licenses/gpl-3.0](https://www.gnu.org/licenses/gpl-3.0.html).

---

<div align="center">

*"La workstation perfetta non si costruisce due volte. Si ripristina."*

</div>

#!/usr/bin/env bash
# DRACO - tui/tui.sh: Native bash TUI with ANSI 256-color themes
# GNU GPL v3 - See LICENSE

# ─── Backend detection (whiptail/dialog only for inputbox/passwordbox) ────────
_DRACO_TUI_BIN=""
draco_tui_detect() {
    if command -v whiptail &>/dev/null; then
        _DRACO_TUI_BIN="whiptail"
    elif command -v dialog &>/dev/null; then
        _DRACO_TUI_BIN="dialog"
    else
        _DRACO_TUI_BIN="bash"
    fi
}

# ─── Themes: 5 high-contrast 256-color palettes ──────────────────────────────
# 256-color indices bypass terminal palette remapping — works on all terminals.
# \033[38;5;Nm = fg, \033[48;5;Nm = bg

DRACO_TUI_BG=232  DRACO_TUI_FG=255  DRACO_TUI_ACCENT=250
DRACO_TUI_SEL_BG=255  DRACO_TUI_SEL_FG=232  DRACO_TUI_NAME="ghost"

draco_tui_apply_theme() {
    local theme="${DRACO_TUI_THEME:-ghost}"
    case "$theme" in
        ghost|default)
            DRACO_TUI_BG=232; DRACO_TUI_FG=255; DRACO_TUI_ACCENT=250
            DRACO_TUI_SEL_BG=255; DRACO_TUI_SEL_FG=232; DRACO_TUI_NAME="ghost"  ;;
        blood|anthropic)
            DRACO_TUI_BG=232; DRACO_TUI_FG=196; DRACO_TUI_ACCENT=160
            DRACO_TUI_SEL_BG=196; DRACO_TUI_SEL_FG=232; DRACO_TUI_NAME="blood"  ;;
        acid)
            DRACO_TUI_BG=232; DRACO_TUI_FG=226; DRACO_TUI_ACCENT=220
            DRACO_TUI_SEL_BG=226; DRACO_TUI_SEL_FG=232; DRACO_TUI_NAME="acid"   ;;
        matrix|eva01)
            DRACO_TUI_BG=232; DRACO_TUI_FG=46;  DRACO_TUI_ACCENT=34
            DRACO_TUI_SEL_BG=46;  DRACO_TUI_SEL_FG=232; DRACO_TUI_NAME="matrix" ;;
        void|blue)
            DRACO_TUI_BG=232; DRACO_TUI_FG=51;  DRACO_TUI_ACCENT=38
            DRACO_TUI_SEL_BG=51;  DRACO_TUI_SEL_FG=232; DRACO_TUI_NAME="void"   ;;
        *)
            DRACO_TUI_BG=232; DRACO_TUI_FG=255; DRACO_TUI_ACCENT=250
            DRACO_TUI_SEL_BG=255; DRACO_TUI_SEL_FG=232; DRACO_TUI_NAME="ghost"  ;;
    esac
}

# ─── Low-level drawing primitives ─────────────────────────────────────────────
# All output goes to /dev/tty so functions work inside $() substitutions.

_tui_fg()    { printf '\033[38;5;%dm' "$1" >/dev/tty; }
_tui_bg()    { printf '\033[48;5;%dm' "$1" >/dev/tty; }
_tui_reset() { printf '\033[0m'            >/dev/tty; }
_tui_bold()  { printf '\033[1m'            >/dev/tty; }
_tui_goto()  { printf '\033[%d;%dH' "$1" "$2" >/dev/tty; }
_tui_cls()   { printf '\033[H\033[2J'      >/dev/tty; }
_tui_cur_hide() { printf '\033[?25l'       >/dev/tty; }
_tui_cur_show() { printf '\033[?25h'       >/dev/tty; }
_tui_alt_on()   { printf '\033[?1049h'     >/dev/tty; }
_tui_alt_off()  { printf '\033[?1049l'     >/dev/tty; }
_tui_write() { printf '%s' "$*"            >/dev/tty; }

_tui_cleanup() { _tui_alt_off; _tui_cur_show; _tui_reset; }

_tui_term_size() {
    _TUI_ROWS=$(tput lines  2>/dev/null || echo 24)
    _TUI_COLS=$(tput cols   2>/dev/null || echo 80)
}

_tui_hline() {
    local n=$1 c="${2:-─}" s=""
    for ((i=0; i<n; i++)); do s+="$c"; done
    _tui_write "$s"
}

_tui_pad() {
    local s="$1" w="$2"
    if [[ ${#s} -ge $w ]]; then
        printf '%s' "${s:0:$w}"
    else
        printf '%-*s' "$w" "$s"
    fi
}

# Read one key / escape sequence into global _DRACO_KEY
_DRACO_KEY=""
_tui_read_key() {
    _DRACO_KEY=""
    local c
    IFS= read -rsn1 -t 300 c </dev/tty || { _DRACO_KEY=$'\004'; return 0; }
    _DRACO_KEY="$c"
    if [[ "$c" == $'\033' ]]; then
        local seq=""
        while true; do
            IFS= read -rsn1 -t 0.05 c </dev/tty || break
            seq+="$c"
            [[ "$c" =~ [A-Za-z~] ]] && break
        done
        _DRACO_KEY="${_DRACO_KEY}${seq}"
    fi
    return 0
}

# ─── Box / layout helpers ─────────────────────────────────────────────────────

_tui_fill_rect() {
    local r=$1 c=$2 h=$3 w=$4
    local line
    printf -v line '%*s' "$w" ""
    for ((i=0; i<h; i++)); do
        _tui_goto "$(( r + i ))" "$c"
        _tui_write "$line"
    done
}

_tui_draw_box() {
    local r=$1 c=$2 h=$3 w=$4 title="${5:-}"
    local inner=$(( w - 2 ))

    _tui_goto "$r" "$c"
    if [[ -n "$title" ]]; then
        local tl=${#title}
        local lpad=$(( (inner - tl - 2) / 2 ))
        local rpad=$(( inner - tl - 2 - lpad ))
        local top="┌"
        for ((i=0; i<lpad; i++)); do top+="─"; done
        top+=" ${title} "
        for ((i=0; i<rpad; i++)); do top+="─"; done
        top+="┐"
        _tui_write "$top"
    else
        _tui_write "┌"; _tui_hline "$inner"; _tui_write "┐"
    fi

    local er=$(( r + h - 1 ))
    for ((i=r+1; i<er; i++)); do
        _tui_goto "$i" "$c";         _tui_write "│"
        _tui_goto "$i" "$(( c + w - 1 ))"; _tui_write "│"
    done

    _tui_goto "$er" "$c"
    _tui_write "└"; _tui_hline "$inner"; _tui_write "┘"
}

_tui_draw_sep() {
    local r=$1 c=$2 w=$3
    _tui_goto "$r" "$c"
    _tui_write "├"; _tui_hline "$(( w - 2 ))"; _tui_write "┤"
}

# Parse literal \n strings into array
_tui_split_lines() {
    local -n _out=$1
    local text="$2"
    _out=()
    local rest="$text"
    while [[ "$rest" == *'\\n'* ]]; do
        _out+=("${rest%%\\n*}")
        rest="${rest#*\\n}"
    done
    _out+=("$rest")
}

# ─── draco_tui_menu ───────────────────────────────────────────────────────────
# Usage: draco_tui_menu title prompt [h w list_h] key1 desc1 key2 desc2 ...
# Returns selected key via stdout. Exit 1 on cancel.

draco_tui_menu() {
    local title="$1" prompt="$2"
    shift 2
    # skip numeric dimension args (whiptail compat: h w list_h)
    while [[ $# -gt 0 && "$1" =~ ^[0-9]+$ ]]; do shift; done

    local -a mkeys=() mdescs=()
    while [[ $# -ge 2 ]]; do
        mkeys+=("$1"); mdescs+=("$2"); shift 2
    done

    local count=${#mkeys[@]}
    [[ $count -eq 0 ]] && return 1

    local -a prompt_lines=()
    _tui_split_lines prompt_lines "$prompt"

    _tui_term_size
    local rows=$_TUI_ROWS cols=$_TUI_COLS

    local max_kw=0 max_dw=0 max_pw=0
    for k in "${mkeys[@]}";  do [[ ${#k} -gt $max_kw ]] && max_kw=${#k}; done
    for d in "${mdescs[@]}"; do [[ ${#d} -gt $max_dw ]] && max_dw=${#d}; done
    for p in "${prompt_lines[@]}"; do [[ ${#p} -gt $max_pw ]] && max_pw=${#p}; done

    local n_prompt=${#prompt_lines[@]}
    local item_w=$(( max_kw + max_dw + 6 ))
    local inner=$(( item_w > max_pw ? item_w : max_pw ))
    [[ $(( ${#title} + 2 )) -gt $inner ]] && inner=$(( ${#title} + 2 ))
    [[ $inner -lt 36 ]] && inner=36
    local box_w=$(( inner + 2 ))
    [[ $box_w -gt $cols ]] && box_w=$cols
    inner=$(( box_w - 2 ))

    # rows: top+bottom=2, prompt, sep, items, sep, helpline=1 → total
    local box_h=$(( 2 + n_prompt + 1 + count + 1 + 1 ))
    local max_h=$(( rows - 2 ))
    [[ $box_h -gt $max_h ]] && box_h=$max_h

    local br=$(( (rows - box_h) / 2 + 1 ))
    local bc=$(( (cols - box_w) / 2 + 1 ))
    local desc_w=$(( inner - max_kw - 6 ))
    [[ $desc_w -lt 1 ]] && desc_w=1

    local selected=0

    _tui_alt_on; _tui_cur_hide
    trap '_tui_cleanup' EXIT

    while true; do
        _tui_fg "$DRACO_TUI_BG"; _tui_bg "$DRACO_TUI_BG"; _tui_cls

        # Box border (accent color)
        _tui_fg "$DRACO_TUI_ACCENT"; _tui_bg "$DRACO_TUI_BG"
        _tui_draw_box "$br" "$bc" "$box_h" "$box_w" "$title"

        # Fill interior
        _tui_fg "$DRACO_TUI_FG"; _tui_bg "$DRACO_TUI_BG"
        _tui_fill_rect "$(( br + 1 ))" "$(( bc + 1 ))" "$(( box_h - 2 ))" "$inner"

        # Prompt lines
        for ((i=0; i<n_prompt; i++)); do
            _tui_goto "$(( br + 1 + i ))" "$(( bc + 2 ))"
            _tui_fg "$DRACO_TUI_FG"; _tui_bg "$DRACO_TUI_BG"
            _tui_write "$(_tui_pad "${prompt_lines[$i]}" "$inner")"
        done

        # Separator after prompt
        _tui_fg "$DRACO_TUI_ACCENT"; _tui_bg "$DRACO_TUI_BG"
        _tui_draw_sep "$(( br + 1 + n_prompt ))" "$bc" "$box_w"

        # Menu items
        local item_row=$(( br + 2 + n_prompt ))
        for ((i=0; i<count; i++)); do
            _tui_goto "$(( item_row + i ))" "$(( bc + 1 ))"
            if [[ $i -eq $selected ]]; then
                _tui_fg "$DRACO_TUI_SEL_FG"; _tui_bg "$DRACO_TUI_SEL_BG"; _tui_bold
                printf ' > %-*s  %-*s ' "$max_kw" "${mkeys[$i]}" "$desc_w" "${mdescs[$i]}" >/dev/tty
            else
                _tui_fg "$DRACO_TUI_FG"; _tui_bg "$DRACO_TUI_BG"
                printf '   %-*s  %-*s ' "$max_kw" "${mkeys[$i]}" "$desc_w" "${mdescs[$i]}" >/dev/tty
            fi
        done

        # Help line
        local help_row=$(( br + box_h - 2 ))
        _tui_fg "$DRACO_TUI_ACCENT"; _tui_bg "$DRACO_TUI_BG"
        _tui_draw_sep "$(( help_row - 1 ))" "$bc" "$box_w"
        _tui_goto "$help_row" "$(( bc + 2 ))"
        _tui_write "[up/dn] move  [Enter] select  [q] quit"

        _tui_read_key
        case "$_DRACO_KEY" in
            $'\033[A'|$'\033OA')
                [[ $selected -gt 0 ]] && selected=$(( selected - 1 )) || true ;;
            $'\033[B'|$'\033OB')
                [[ $selected -lt $(( count - 1 )) ]] && selected=$(( selected + 1 )) || true ;;
            ''|$'\r'|$'\n')
                _tui_cleanup
                printf '%s' "${mkeys[$selected]}"
                return 0 ;;
            'q'|'Q'|$'\033'|$'\004')
                _tui_cleanup
                return 1 ;;
        esac
    done
}

# ─── draco_tui_msgbox ─────────────────────────────────────────────────────────

draco_tui_msgbox() {
    local title="$1" msg="$2"

    local -a lines=()
    _tui_split_lines lines "$msg"

    _tui_term_size
    local rows=$_TUI_ROWS cols=$_TUI_COLS

    local max_lw=0
    for l in "${lines[@]}"; do [[ ${#l} -gt $max_lw ]] && max_lw=${#l}; done

    local box_w=$(( max_lw + 6 ))
    [[ $(( ${#title} + 4 )) -gt $box_w ]] && box_w=$(( ${#title} + 4 ))
    [[ $box_w -gt $cols ]] && box_w=$cols
    [[ $box_w -lt 30 ]] && box_w=30
    local inner=$(( box_w - 2 ))

    local n_lines=${#lines[@]}
    local box_h=$(( n_lines + 5 ))
    [[ $box_h -gt $(( rows - 2 )) ]] && box_h=$(( rows - 2 ))

    local br=$(( (rows - box_h) / 2 + 1 ))
    local bc=$(( (cols - box_w) / 2 + 1 ))

    _tui_alt_on; _tui_cur_hide

    _tui_fg "$DRACO_TUI_BG"; _tui_bg "$DRACO_TUI_BG"; _tui_cls
    _tui_fg "$DRACO_TUI_ACCENT"; _tui_bg "$DRACO_TUI_BG"
    _tui_draw_box "$br" "$bc" "$box_h" "$box_w" "$title"
    _tui_fg "$DRACO_TUI_FG"; _tui_bg "$DRACO_TUI_BG"
    _tui_fill_rect "$(( br + 1 ))" "$(( bc + 1 ))" "$(( box_h - 2 ))" "$inner"

    for ((i=0; i<n_lines; i++)); do
        _tui_goto "$(( br + 1 + i ))" "$(( bc + 2 ))"
        _tui_write "${lines[$i]}"
    done

    _tui_fg "$DRACO_TUI_ACCENT"; _tui_bg "$DRACO_TUI_BG"
    _tui_draw_sep "$(( br + box_h - 3 ))" "$bc" "$box_w"
    _tui_goto "$(( br + box_h - 2 ))" "$(( bc + 2 ))"
    _tui_write "[Enter] OK"

    while true; do
        _tui_read_key
        case "$_DRACO_KEY" in ''|$'\r'|$'\n'|'q'|'Q'|$'\004') break ;; esac
    done

    _tui_cleanup
}

# ─── draco_tui_yesno ─────────────────────────────────────────────────────────
# Returns 0=yes 1=no

draco_tui_yesno() {
    local title="$1" msg="$2"

    local -a lines=()
    _tui_split_lines lines "$msg"

    _tui_term_size
    local rows=$_TUI_ROWS cols=$_TUI_COLS

    local max_lw=0
    for l in "${lines[@]}"; do [[ ${#l} -gt $max_lw ]] && max_lw=${#l}; done

    local box_w=$(( max_lw + 6 ))
    [[ $box_w -lt 42 ]] && box_w=42
    [[ $box_w -gt $cols ]] && box_w=$cols
    local inner=$(( box_w - 2 ))

    local n_lines=${#lines[@]}
    local box_h=$(( n_lines + 5 ))

    local br=$(( (rows - box_h) / 2 + 1 ))
    local bc=$(( (cols - box_w) / 2 + 1 ))

    local cur=0  # 0=Yes 1=No

    _tui_alt_on; _tui_cur_hide

    while true; do
        _tui_fg "$DRACO_TUI_BG"; _tui_bg "$DRACO_TUI_BG"; _tui_cls
        _tui_fg "$DRACO_TUI_ACCENT"; _tui_bg "$DRACO_TUI_BG"
        _tui_draw_box "$br" "$bc" "$box_h" "$box_w" "$title"
        _tui_fg "$DRACO_TUI_FG"; _tui_bg "$DRACO_TUI_BG"
        _tui_fill_rect "$(( br + 1 ))" "$(( bc + 1 ))" "$(( box_h - 2 ))" "$inner"

        for ((i=0; i<n_lines; i++)); do
            _tui_goto "$(( br + 1 + i ))" "$(( bc + 2 ))"
            _tui_write "${lines[$i]}"
        done

        local btn_row=$(( br + box_h - 2 ))
        local mid=$(( bc + inner / 2 ))

        _tui_goto "$btn_row" "$(( mid - 10 ))"
        if [[ $cur -eq 0 ]]; then
            _tui_fg "$DRACO_TUI_SEL_FG"; _tui_bg "$DRACO_TUI_SEL_BG"; _tui_bold
        else
            _tui_fg "$DRACO_TUI_FG"; _tui_bg "$DRACO_TUI_BG"
        fi
        _tui_write "  < Yes >  "

        _tui_goto "$btn_row" "$(( mid + 1 ))"
        if [[ $cur -eq 1 ]]; then
            _tui_fg "$DRACO_TUI_SEL_FG"; _tui_bg "$DRACO_TUI_SEL_BG"; _tui_bold
        else
            _tui_fg "$DRACO_TUI_FG"; _tui_bg "$DRACO_TUI_BG"
        fi
        _tui_write "  < No  >  "

        _tui_read_key
        case "$_DRACO_KEY" in
            $'\033[C'|$'\033[D'|$'\011')  # right/left/tab
                cur=$(( 1 - cur )) ;;
            $'\033[A'|$'\033[B')
                cur=$(( 1 - cur )) ;;
            ''|$'\r'|$'\n')
                _tui_cleanup; return $cur ;;
            'y'|'Y')
                _tui_cleanup; return 0 ;;
            'n'|'N'|'q'|'Q'|$'\004')
                _tui_cleanup; return 1 ;;
        esac
    done
}

# ─── draco_tui_inputbox ───────────────────────────────────────────────────────
# Uses whiptail/dialog (colors don't matter for text input).

draco_tui_inputbox() {
    local title="$1" prompt="$2" default="${3:-}" h="${4:-8}" w="${5:-60}"
    if [[ "$_DRACO_TUI_BIN" == "whiptail" || "$_DRACO_TUI_BIN" == "dialog" ]]; then
        "$_DRACO_TUI_BIN" --title "$title" --inputbox "$prompt" "$h" "$w" "$default" \
            3>&1 1>&2 2>&3
    else
        _tui_reset
        local result
        printf '%s [%s]: ' "$prompt" "$default" >/dev/tty
        IFS= read -r result </dev/tty
        printf '%s' "${result:-$default}"
    fi
}

# ─── draco_tui_passwordbox ────────────────────────────────────────────────────

draco_tui_passwordbox() {
    local title="$1" prompt="$2" h="${3:-8}" w="${4:-60}"
    if [[ "$_DRACO_TUI_BIN" == "whiptail" || "$_DRACO_TUI_BIN" == "dialog" ]]; then
        "$_DRACO_TUI_BIN" --title "$title" --passwordbox "$prompt" "$h" "$w" \
            3>&1 1>&2 2>&3
    else
        _tui_reset
        local result
        IFS= read -rs -p "$prompt: " result </dev/tty
        printf '\n' >/dev/tty
        printf '%s' "$result"
    fi
}

# ─── draco_tui_textbox ────────────────────────────────────────────────────────

draco_tui_textbox() {
    local title="$1" file="$2"

    [[ ! -f "$file" ]] && return 0

    _tui_term_size
    local rows=$_TUI_ROWS cols=$_TUI_COLS

    local -a flines=()
    while IFS= read -r line; do
        flines+=("$line")
    done < "$file"
    local total=${#flines[@]}

    local view_h=$(( rows - 6 ))
    [[ $view_h -lt 3 ]] && view_h=3
    local box_h=$(( view_h + 4 ))
    local box_w=$(( cols - 4 ))
    local inner=$(( box_w - 2 ))
    local br=$(( (rows - box_h) / 2 + 1 ))
    local bc=$(( (cols - box_w) / 2 + 1 ))
    local offset=0

    _tui_alt_on; _tui_cur_hide

    while true; do
        _tui_fg "$DRACO_TUI_BG"; _tui_bg "$DRACO_TUI_BG"; _tui_cls
        _tui_fg "$DRACO_TUI_ACCENT"; _tui_bg "$DRACO_TUI_BG"
        _tui_draw_box "$br" "$bc" "$box_h" "$box_w" "$title"
        _tui_fg "$DRACO_TUI_FG"; _tui_bg "$DRACO_TUI_BG"
        _tui_fill_rect "$(( br + 1 ))" "$(( bc + 1 ))" "$(( box_h - 2 ))" "$inner"

        for ((i=0; i<view_h; i++)); do
            local li=$(( offset + i ))
            _tui_goto "$(( br + 1 + i ))" "$(( bc + 2 ))"
            if [[ $li -lt $total ]]; then
                local fline="${flines[$li]}"
                [[ ${#fline} -gt $inner ]] && fline="${fline:0:$inner}"
                _tui_write "$fline"
            fi
        done

        _tui_fg "$DRACO_TUI_ACCENT"; _tui_bg "$DRACO_TUI_BG"
        _tui_draw_sep "$(( br + box_h - 3 ))" "$bc" "$box_w"
        _tui_goto "$(( br + box_h - 2 ))" "$(( bc + 2 ))"
        _tui_write "[up/dn/PgUp/PgDn] scroll  [q] close  $(( offset + 1 ))/$total"

        _tui_read_key
        case "$_DRACO_KEY" in
            $'\033[A')
                [[ $offset -gt 0 ]] && offset=$(( offset - 1 )) || true ;;
            $'\033[B')
                local max_off=$(( total - view_h ))
                [[ $max_off -lt 0 ]] && max_off=0
                [[ $offset -lt $max_off ]] && offset=$(( offset + 1 )) || true ;;
            $'\033[5~')
                offset=$(( offset - view_h ))
                [[ $offset -lt 0 ]] && offset=0 ;;
            $'\033[6~')
                local max_off=$(( total - view_h ))
                [[ $max_off -lt 0 ]] && max_off=0
                offset=$(( offset + view_h ))
                [[ $offset -gt $max_off ]] && offset=$max_off ;;
            'q'|'Q'|''|$'\r'|$'\n'|$'\004') break ;;
        esac
    done

    _tui_cleanup
}

# ─── draco_tui_checklist ─────────────────────────────────────────────────────
# Usage: title prompt h w list_h tag1 desc1 state1 ...
# state: ON|OFF. Returns space-separated selected tags via stdout.

draco_tui_checklist() {
    local title="$1" prompt="$2"
    shift 2
    while [[ $# -gt 0 && "$1" =~ ^[0-9]+$ ]]; do shift; done

    local -a ck_keys=() ck_descs=() ck_on=()
    while [[ $# -ge 3 ]]; do
        ck_keys+=("$1"); ck_descs+=("$2")
        [[ "$3" == "ON" ]] && ck_on+=(1) || ck_on+=(0)
        shift 3
    done

    local count=${#ck_keys[@]}
    [[ $count -eq 0 ]] && return 1

    _tui_term_size
    local rows=$_TUI_ROWS cols=$_TUI_COLS

    local max_kw=0 max_dw=0
    for k in "${ck_keys[@]}";  do [[ ${#k} -gt $max_kw ]] && max_kw=${#k}; done
    for d in "${ck_descs[@]}"; do [[ ${#d} -gt $max_dw ]] && max_dw=${#d}; done

    local item_w=$(( max_kw + max_dw + 9 ))  # "[x] KEY  DESC "
    local box_w=$(( item_w + 4 ))
    [[ $box_w -gt $cols ]] && box_w=$cols
    [[ $box_w -lt 40 ]] && box_w=40
    local inner=$(( box_w - 2 ))
    local desc_w=$(( inner - max_kw - 9 ))
    [[ $desc_w -lt 1 ]] && desc_w=1

    local box_h=$(( count + 6 ))
    [[ $box_h -gt $(( rows - 2 )) ]] && box_h=$(( rows - 2 ))
    local br=$(( (rows - box_h) / 2 + 1 ))
    local bc=$(( (cols - box_w) / 2 + 1 ))

    local selected=0

    _tui_alt_on; _tui_cur_hide
    trap '_tui_cleanup' EXIT

    while true; do
        _tui_fg "$DRACO_TUI_BG"; _tui_bg "$DRACO_TUI_BG"; _tui_cls
        _tui_fg "$DRACO_TUI_ACCENT"; _tui_bg "$DRACO_TUI_BG"
        _tui_draw_box "$br" "$bc" "$box_h" "$box_w" "$title"
        _tui_fg "$DRACO_TUI_FG"; _tui_bg "$DRACO_TUI_BG"
        _tui_fill_rect "$(( br + 1 ))" "$(( bc + 1 ))" "$(( box_h - 2 ))" "$inner"

        _tui_goto "$(( br + 1 ))" "$(( bc + 2 ))"
        _tui_write "$(_tui_pad "$prompt" "$inner")"
        _tui_fg "$DRACO_TUI_ACCENT"; _tui_bg "$DRACO_TUI_BG"
        _tui_draw_sep "$(( br + 2 ))" "$bc" "$box_w"

        for ((i=0; i<count; i++)); do
            local ir=$(( br + 3 + i ))
            local mark="[ ]"
            [[ ${ck_on[$i]} -eq 1 ]] && mark="[x]"
            _tui_goto "$ir" "$(( bc + 1 ))"
            if [[ $i -eq $selected ]]; then
                _tui_fg "$DRACO_TUI_SEL_FG"; _tui_bg "$DRACO_TUI_SEL_BG"; _tui_bold
            else
                _tui_fg "$DRACO_TUI_FG"; _tui_bg "$DRACO_TUI_BG"
            fi
            printf ' %s %-*s  %-*s ' "$mark" "$max_kw" "${ck_keys[$i]}" \
                "$desc_w" "${ck_descs[$i]}" >/dev/tty
        done

        _tui_fg "$DRACO_TUI_ACCENT"; _tui_bg "$DRACO_TUI_BG"
        _tui_draw_sep "$(( br + box_h - 3 ))" "$bc" "$box_w"
        _tui_goto "$(( br + box_h - 2 ))" "$(( bc + 2 ))"
        _tui_write "[up/dn] move  [Space] toggle  [Enter] confirm  [q] cancel"

        _tui_read_key
        case "$_DRACO_KEY" in
            $'\033[A')
                [[ $selected -gt 0 ]] && selected=$(( selected - 1 )) || true ;;
            $'\033[B')
                [[ $selected -lt $(( count - 1 )) ]] && selected=$(( selected + 1 )) || true ;;
            ' ')
                if [[ ${ck_on[$selected]} -eq 1 ]]; then
                    ck_on[$selected]=0
                else
                    ck_on[$selected]=1
                fi ;;
            ''|$'\r'|$'\n')
                _tui_cleanup
                local result=""
                for ((i=0; i<count; i++)); do
                    [[ ${ck_on[$i]} -eq 1 ]] && result+="${ck_keys[$i]} " || true
                done
                printf '%s' "${result% }"
                return 0 ;;
            'q'|'Q'|$'\004')
                _tui_cleanup; return 1 ;;
        esac
    done
}

# ─── Main TUI ─────────────────────────────────────────────────────────────────
draco_tui_main() {
    draco_tui_detect
    draco_tui_apply_theme

    while true; do
        local choice
        choice="$(draco_tui_menu \
            "DRACO v${DRACO_VERSION}" \
            "Dotfile & Runtime Archive and Configuration Orchestrator\n\nBackup dir: ${DRACO_BACKUP_DIR:-'(not configured)'}\nLast backup: $(draco_get_last_backup_id 2>/dev/null || echo 'none')\nStorage: $(draco_backup_total_size 2>/dev/null || echo '0')" \
            22 72 8 \
            "BACKUP"   "Run backup now" \
            "RESTORE"  "Restore a backup" \
            "LIST"     "List backups and storage usage" \
            "LOG"      "View backup logs and diffs" \
            "DELETE"   "Delete backup(s)" \
            "SCHEDULE" "Manage automatic schedule" \
            "CONFIG"   "Configure DRACO settings" \
            "ABOUT"    "About DRACO" \
        )" || exit 0

        case "$choice" in
            BACKUP)   draco_tui_backup ;;
            RESTORE)  draco_tui_restore ;;
            LIST)     draco_tui_list ;;
            LOG)      draco_tui_log ;;
            DELETE)   draco_tui_delete ;;
            SCHEDULE) draco_tui_schedule ;;
            CONFIG)   draco_tui_config ;;
            ABOUT)    draco_tui_about ;;
        esac
    done
}

# ─── Backup screen ────────────────────────────────────────────────────────────
draco_tui_backup() {
    if draco_tui_yesno "DRACO - Backup" "Start backup now?\n\nDestination: ${DRACO_BACKUP_DIR:-'(not configured)'}"; then
        clear
        draco_backup_run
        read -r -p "Press Enter to continue..."
    fi
}

# ─── Restore screen ───────────────────────────────────────────────────────────
draco_tui_restore() {
    local backup_id
    backup_id="$(draco_restore_select_interactive)"
    if [[ -n "$backup_id" ]]; then
        clear
        draco_restore_run_with_id "$backup_id"
        read -r -p "Press Enter to continue..."
    fi
}

# ─── List screen ─────────────────────────────────────────────────────────────
draco_tui_list() {
    local tmp
    tmp="$(mktemp)"
    draco_backup_list > "$tmp" 2>&1
    draco_tui_textbox "DRACO - Backup List" "$tmp" 22 78
    rm -f "$tmp"
}

# ─── Log screen ───────────────────────────────────────────────────────────────
draco_tui_log() {
    local -a backups=()
    while IFS= read -r f; do
        local bid dt
        bid="$(basename "$f" | sed 's/draco-\(.*\)\..*/\1/')"
        dt="$(stat -c '%y' "$f" 2>/dev/null | cut -d'.' -f1 || echo '')"
        backups+=("$bid" "$dt")
    done < <(find "$DRACO_BACKUP_DIR" -maxdepth 1 -name "draco-*.enc" 2>/dev/null | sort -r)

    if [[ ${#backups[@]} -eq 0 ]]; then
        draco_tui_msgbox "DRACO - Logs" "No backups found."
        return
    fi

    local selected
    selected="$(draco_tui_menu "DRACO - View Log" "Select backup:" 20 70 8 "${backups[@]}")" || return

    local tmp
    tmp="$(mktemp)"
    draco_backup_log_show "$selected" > "$tmp" 2>&1
    draco_tui_textbox "DRACO - Log: $selected" "$tmp" 22 78
    rm -f "$tmp"
}

# ─── Delete screen ────────────────────────────────────────────────────────────
draco_tui_delete() {
    local -a items=()
    while IFS= read -r f; do
        local bid sz
        bid="$(basename "$f" | sed 's/draco-\(.*\)\..*/\1/')"
        sz="$(draco_human_size "$f")"
        items+=("$bid" "$sz" "OFF")
    done < <(find "$DRACO_BACKUP_DIR" -maxdepth 1 -name "draco-*.enc" 2>/dev/null | sort -r)

    if [[ ${#items[@]} -eq 0 ]]; then
        draco_tui_msgbox "DRACO - Delete" "No backups found."
        return
    fi

    local selected
    selected="$(draco_tui_checklist "DRACO - Delete Backups" \
        "Select backups to delete (Space to toggle):" 20 70 8 \
        "${items[@]}")" || return

    if [[ -z "$selected" ]]; then
        draco_tui_msgbox "DRACO - Delete" "Nothing selected."
        return
    fi

    local count
    count="$(echo "$selected" | wc -w)"
    if draco_tui_yesno "DRACO - Confirm Delete" "Delete $count backup(s)?\n\nThis cannot be undone."; then
        clear
        for bid in $selected; do
            draco_backup_delete_silent "$bid"
            draco_ok "Deleted: $bid"
        done
        read -r -p "Press Enter to continue..."
    fi
}

# ─── Schedule screen ──────────────────────────────────────────────────────────
draco_tui_schedule() {
    local choice
    choice="$(draco_tui_menu "DRACO - Schedule" \
        "Current: ${DRACO_SCHEDULE_TYPE:-none} / ${DRACO_SCHEDULE_FREQ:-daily}" \
        14 60 4 \
        "INSTALL" "Install/change automatic schedule" \
        "REMOVE"  "Remove automatic schedule" \
        "STATUS"  "View schedule status" \
    )" || return

    case "$choice" in
        INSTALL)
            clear
            draco_schedule_interactive_install
            read -r -p "Press Enter to continue..."
            ;;
        REMOVE)
            if draco_tui_yesno "DRACO - Remove Schedule" "Remove automatic backup schedule?"; then
                clear
                draco_schedule_remove
                read -r -p "Press Enter to continue..."
            fi
            ;;
        STATUS)
            local tmp
            tmp="$(mktemp)"
            draco_schedule_status > "$tmp" 2>&1
            draco_tui_textbox "DRACO - Schedule Status" "$tmp" 14 60
            rm -f "$tmp"
            ;;
    esac
}

# ─── Config screen ────────────────────────────────────────────────────────────
draco_tui_config() {
    while true; do
        local choice
        choice="$(draco_tui_menu "DRACO - Configuration" \
            "Config: ${DRACO_CONFIG_FILE}" \
            20 70 8 \
            "BACKUPDIR"  "Backup dir: ${DRACO_BACKUP_DIR:-'(not set)'}" \
            "RETENTION"  "Retention: ${DRACO_RETENTION_POLICY}" \
            "DAILY"      "Keep daily: ${DRACO_RETENTION_KEEP_DAILY}" \
            "WEEKLY"     "Keep weekly: ${DRACO_RETENTION_KEEP_WEEKLY}" \
            "MONTHLY"    "Keep monthly: ${DRACO_RETENTION_KEEP_MONTHLY}" \
            "THEME"      "Theme: ${DRACO_TUI_THEME} (${DRACO_TUI_NAME})" \
            "SAVE"       "Save and return" \
        )" || break

        case "$choice" in
            BACKUPDIR)
                local new_dir
                new_dir="$(draco_tui_inputbox "Backup Directory" \
                    "Enter backup destination path:" \
                    "${DRACO_BACKUP_DIR:-$HOME/draco-backups}")"
                if [[ -n "$new_dir" ]]; then
                    new_dir="${new_dir/#\~/$HOME}"
                    mkdir -p "$new_dir" 2>/dev/null || true
                    DRACO_BACKUP_DIR="$(realpath "$new_dir")"
                fi
                ;;
            RETENTION)
                local rp
                rp="$(draco_tui_menu "Retention Policy" "Choose policy:" 12 50 5 \
                    "all"     "Keep all backups" \
                    "daily"   "Keep N daily" \
                    "weekly"  "Keep N weekly" \
                    "monthly" "Keep N monthly" \
                    "smart"   "Smart: daily+weekly+monthly+yearly" \
                )" || continue
                DRACO_RETENTION_POLICY="$rp"
                ;;
            DAILY)
                local n
                n="$(draco_tui_inputbox "Daily Retention" \
                    "Keep last N daily backups:" "$DRACO_RETENTION_KEEP_DAILY")"
                [[ "$n" =~ ^[0-9]+$ ]] && DRACO_RETENTION_KEEP_DAILY="$n" || true
                ;;
            WEEKLY)
                local n
                n="$(draco_tui_inputbox "Weekly Retention" \
                    "Keep last N weekly backups:" "$DRACO_RETENTION_KEEP_WEEKLY")"
                [[ "$n" =~ ^[0-9]+$ ]] && DRACO_RETENTION_KEEP_WEEKLY="$n" || true
                ;;
            MONTHLY)
                local n
                n="$(draco_tui_inputbox "Monthly Retention" \
                    "Keep last N monthly backups:" "$DRACO_RETENTION_KEEP_MONTHLY")"
                [[ "$n" =~ ^[0-9]+$ ]] && DRACO_RETENTION_KEEP_MONTHLY="$n" || true
                ;;
            THEME)
                local theme
                theme="$(draco_tui_menu "TUI Theme" "Select theme:" 12 50 5 \
                    "ghost"   "White on black (default)" \
                    "blood"   "Red on black" \
                    "acid"    "Yellow on black" \
                    "matrix"  "Green on black" \
                    "void"    "Cyan on black" \
                )" || continue
                DRACO_TUI_THEME="$theme"
                draco_tui_apply_theme
                ;;
            SAVE)
                draco_save_config
                break
                ;;
        esac
    done
}

# ─── About screen ─────────────────────────────────────────────────────────────
draco_tui_about() {
    draco_tui_msgbox "About DRACO" \
"DRACO v${DRACO_VERSION}
Dotfile & Runtime Archive and Configuration Orchestrator

A portable Linux backup system for:
  - Dotfiles and shell configs
  - SSH keys and GPG keys
  - KDE / GNOME personalizations
  - Konsole + Spaceship prompt themes
  - Installed software manifests
  - Auto-reinstall scripts

Supported distros:
  Fedora 42+, Debian 12+, Ubuntu 24.04+, Arch

Encryption: AES-256-CBC (OpenSSL PBKDF2)
Compression: zstd / gzip

License: GNU GPL v3" \
    20 65
}

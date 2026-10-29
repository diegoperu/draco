#!/usr/bin/env bash
# DRACO - tests/test_password.sh: password file, CLI option removal, schedule password setup
# Usage: bash tests/test_password.sh   (no root needed, uses a throwaway HOME)
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
chmod 700 "$T"

PASS=0
FAIL=0
ok()   { PASS=$((PASS+1)); echo "  ok   $1"; }
fail() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
check() { # check <description> <command...>: expects success
    local d="$1"; shift
    if "$@" >/dev/null 2>&1; then ok "$d"; else fail "$d"; fi
}
check_not() { # check_not <description> <command...>: expects failure
    local d="$1"; shift
    if "$@" >/dev/null 2>&1; then fail "$d"; else ok "$d"; fi
}

# shellcheck disable=SC1091
source "${ROOT}/src/core/log.sh"
# shellcheck disable=SC1091
source "${ROOT}/src/core/utils.sh"
# shellcheck disable=SC1091
source "${ROOT}/src/scheduler/scheduler.sh"
DRACO_ENCRYPTION_ALGO="aes-256-cbc"
DRACO_CONFIG_DIR="${T}/cfg"

echo "== draco_read_password_file"
f="${T}/pw"
printf 'Sup3r-secret\n' > "$f"; chmod 600 "$f"
[[ "$(draco_read_password_file "$f" 2>/dev/null)" == "Sup3r-secret" ]] && ok "reads 0600 file" || fail "reads 0600 file"
chmod 400 "$f"
check "accepts 0400" draco_read_password_file "$f"
for m in 640 644 660 666 700 604; do
    chmod "$m" "$f"
    check_not "rejects mode $m" draco_read_password_file "$f"
done
chmod 600 "$f"
printf 'nonewline' > "$f"
[[ "$(draco_read_password_file "$f" 2>/dev/null)" == "nonewline" ]] && ok "file without trailing newline" || fail "file without trailing newline"
printf 'first\nsecond\n' > "$f"
[[ "$(draco_read_password_file "$f" 2>/dev/null)" == "first" ]] && ok "only first line used" || fail "only first line used"
: > "$f"
check_not "rejects empty file" draco_read_password_file "$f"
printf 'abc\r\n' > "$f"
check_not "rejects CRLF" draco_read_password_file "$f"
head -c 1100 /dev/zero | tr '\0' 'a' > "$f"; echo >> "$f"
check_not "rejects >1024 chars" draco_read_password_file "$f"
printf 'x\n' > "$f"
ln -s "$f" "${T}/link"
check_not "rejects symlink" draco_read_password_file "${T}/link"
mkdir -p "${T}/dir"; chmod 600 "${T}/dir"
check_not "rejects directory" draco_read_password_file "${T}/dir"
check_not "rejects missing file" draco_read_password_file "${T}/nope"
check_not "rejects empty path" draco_read_password_file ""

echo "== CLI (-p removed, --password-file)"
export HOME="${T}/home" XDG_CONFIG_HOME="${T}/home/.config" XDG_DATA_HOME="${T}/home/.local/share"
mkdir -p "$HOME"
out="$(bash "${ROOT}/draco" -p SEKRETVALUE list 2>&1)"; rc=$?
[[ $rc -ne 0 ]] && ok "-p exits non-zero" || fail "-p exits non-zero"
[[ "$out" != *SEKRETVALUE* ]] && ok "-p value never echoed" || fail "-p value never echoed"
[[ "$out" == *"--password-file"* ]] && ok "-p error points to --password-file" || fail "-p error points to --password-file"
out="$(bash "${ROOT}/draco" --password SEKRETVALUE list 2>&1)"; rc=$?
[[ $rc -ne 0 && "$out" != *SEKRETVALUE* ]] && ok "--password rejected, value not echoed" || fail "--password rejected, value not echoed"
bash "${ROOT}/draco" --password-file "${T}/nope" backup >/dev/null 2>&1 && fail "backup with missing --password-file fails" || ok "backup with missing --password-file fails"
printf 'x\n' > "${T}/loose"; chmod 644 "${T}/loose"
bash "${ROOT}/draco" --password-file "${T}/loose" backup >/dev/null 2>&1 && fail "backup with 0644 --password-file fails" || ok "backup with 0644 --password-file fails"
DRACO_PASSWORD_FILE="${T}/nope" bash "${ROOT}/draco" --version >/dev/null 2>&1 && ok "--version unaffected by bad DRACO_PASSWORD_FILE" || fail "--version unaffected by bad DRACO_PASSWORD_FILE"

echo "== draco_schedule_setup_password_file"
for bad in "relative/path" "/tmp/with space" '/tmp/$(id)' "/tmp/a;b" '/tmp/a`b`'; do
    check_not "rejects path: $bad" draco_schedule_setup_password_file "$bad"
done

pw="${DRACO_CONFIG_DIR}/password"
DRACO_BACKUP_DIR="${T}/backups"; mkdir -p "$DRACO_BACKUP_DIR"
printf 'GoodPass123\nGoodPass123\n' | draco_schedule_setup_password_file "$pw" >/dev/null 2>&1
[[ -f "$pw" && "$(stat -c %a "$pw")" == "600" ]] && ok "creates password file with mode 600" || fail "creates password file with mode 600"
[[ "$(stat -c %a "$DRACO_CONFIG_DIR")" == "700" ]] && ok "creates config dir with mode 700" || fail "creates config dir with mode 700"
[[ "$(draco_read_password_file "$pw" 2>/dev/null)" == "GoodPass123" ]] && ok "stored password readable back" || fail "stored password readable back"
ls "${DRACO_CONFIG_DIR}" | grep -q 'password\.' && fail "no temp files left behind" || ok "no temp files left behind"

rm -f "$pw"
printf 'GoodPass123\nOtherPass999\nGoodPass123\nGoodPass123\n' | draco_schedule_setup_password_file "$pw" >/dev/null 2>&1
[[ "$(draco_read_password_file "$pw" 2>/dev/null)" == "GoodPass123" ]] && ok "mismatch is retried" || fail "mismatch is retried"
rm -f "$pw"
printf 'short\nshort\nGoodPass123\nGoodPass123\n' | draco_schedule_setup_password_file "$pw" >/dev/null 2>&1
[[ "$(draco_read_password_file "$pw" 2>/dev/null)" == "GoodPass123" ]] && ok "password <8 chars is retried" || fail "password <8 chars is retried"

# existing valid file: keep (default y) leaves it untouched
printf 'y\n' | draco_schedule_setup_password_file "$pw" >/dev/null 2>&1
[[ "$(draco_read_password_file "$pw" 2>/dev/null)" == "GoodPass123" ]] && ok "keeping existing file leaves it untouched" || fail "keeping existing file leaves it untouched"
# existing file, user declines keep and replace -> aborted, file untouched
printf 'n\nn\n' | draco_schedule_setup_password_file "$pw" >/dev/null 2>&1 && fail "declining replace aborts" || ok "declining replace aborts"
[[ "$(draco_read_password_file "$pw" 2>/dev/null)" == "GoodPass123" ]] && ok "file untouched after abort" || fail "file untouched after abort"

# sanity check against the latest backup (legacy "\n\n"+pass encoding and clean encoding)
rm -f "$pw"
echo data | draco_encrypt $'\n\n'"GoodPass123" > "${DRACO_BACKUP_DIR}/draco-20260101-000000.tar.zst.enc"
out="$(printf 'GoodPass123\nGoodPass123\n' | draco_schedule_setup_password_file "$pw" 2>&1)"
[[ -f "$pw" && "$out" != *"does NOT decrypt"* ]] && ok "matching password (legacy backup): no warning" || fail "matching password (legacy backup): no warning"
rm -f "$pw"
out="$(printf 'WrongPass123\nWrongPass123\nn\n' | draco_schedule_setup_password_file "$pw" 2>&1)"; rc=$?
[[ $rc -ne 0 && ! -e "$pw" && "$out" == *"does NOT decrypt"* ]] && ok "wrong password: warns, declined -> nothing written" || fail "wrong password: warns, declined -> nothing written"
printf 'WrongPass123\nWrongPass123\ny\n' | draco_schedule_setup_password_file "$pw" >/dev/null 2>&1
[[ "$(draco_read_password_file "$pw" 2>/dev/null)" == "WrongPass123" ]] && ok "wrong password: accepted when user confirms" || fail "wrong password: accepted when user confirms"

echo
echo "passed: $PASS  failed: $FAIL"
[[ "$FAIL" -eq 0 ]]

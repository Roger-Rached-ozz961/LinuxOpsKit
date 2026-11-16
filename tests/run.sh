#!/usr/bin/env bash
set -Eeuo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
TMP=$(mktemp -d)
cleanup() { rm -rf -- "$TMP"; }
trap cleanup EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

mkdir -p "$TMP/source/nested" "$TMP/cleanup"
printf 'original\n' > "$TMP/source/one.txt"
printf 'nested\n' > "$TMP/source/nested/two.txt"
printf 'remove me\n' > "$TMP/cleanup/old.tmp"
touch -d '3 days ago' "$TMP/cleanup/old.tmp"
cat > "$TMP/linuxopskit.conf" <<EOFCONF
DESTINATION="$TMP/backups"
BACKUP_SET="integration"
HOST_ID="testhost"
STATE_DIR="$TMP/state"
LOG_DIR="$TMP/logs"
BACKUP_PATHS=("$TMP/source")
CLEANUP_PATHS=("$TMP/cleanup")
CLEANUP_GLOB="*.tmp"
CLEANUP_MIN_AGE_DAYS=0
RETENTION_FULL_CHAINS=3
MIN_FREE_SPACE_PERCENT=0
POSTGRES_ENABLED=false
RCLONE_REMOTE=""
EOFCONF
export LINUXOPSKIT_CONFIG="$TMP/linuxopskit.conf"
CLI="$ROOT/bin/linuxopskit"

"$CLI" backup full >/dev/null
[[ $(find "$TMP/backups" -name '*.tar.gz' | wc -l) -eq 1 ]] || fail 'full backup archive not created'
pass 'full backup creates an archive'
CHAIN=$(cat "$TMP/state/testhost/integration/current_chain")
printf 'changed\n' > "$TMP/source/nested/two.txt"
rm "$TMP/source/one.txt"
printf 'new file\n' > "$TMP/source/three.txt"
"$CLI" backup incremental >/dev/null
[[ $(find "$TMP/backups" -name '*.tar.gz' | wc -l) -eq 2 ]] || fail 'incremental archive not created'
pass 'incremental backup extends the active chain'
"$CLI" verify >/dev/null
pass 'archive checksums and member paths verify'
"$CLI" restore "$CHAIN" "$TMP/restored" >/dev/null
RESTORED_SOURCE="$TMP/restored${TMP}/source"
[[ -f "$RESTORED_SOURCE/nested/two.txt" ]] || fail 'restored changed file missing'
[[ -f "$RESTORED_SOURCE/three.txt" ]] || fail 'restored newly added file missing'
[[ ! -e "$RESTORED_SOURCE/one.txt" ]] || fail 'incremental restore did not reflect deletion'
pass 'full plus incremental restore reproduces file changes and deletions'
"$CLI" cleanup >/dev/null
[[ -f "$TMP/cleanup/old.tmp" ]] || fail 'cleanup dry-run deleted a file'
pass 'cleanup defaults to dry-run'
"$CLI" cleanup --apply >/dev/null
[[ ! -e "$TMP/cleanup/old.tmp" ]] || fail 'cleanup --apply did not remove eligible file'
pass 'cleanup --apply removes only matching aged regular files'
mkdir "$TMP/nonempty"
printf x > "$TMP/nonempty/keep.txt"
if "$CLI" restore "$CHAIN" "$TMP/nonempty" >/dev/null 2>&1; then fail 'restore accepted a non-empty target'; fi
[[ -f "$TMP/nonempty/keep.txt" ]] || fail 'restore altered pre-existing data'
pass 'restore refuses non-empty targets without altering their contents'

echo 'All LinuxOpsKit integration tests passed.'

#!/usr/bin/env bash
set -o pipefail

loks_die() { printf 'ERROR: %s\n' "$*" >&2; loks_log error "$*" 2>/dev/null || true; exit 1; }
loks_info() { printf 'INFO: %s\n' "$*"; loks_log info "$*" 2>/dev/null || true; }
loks_warn() { printf 'WARN: %s\n' "$*" >&2; loks_log warning "$*" 2>/dev/null || true; }

loks_log() {
  local level=${1:-info}; shift || true
  local message=${*:-}
  [[ -n ${LOG_DIR:-} ]] || return 0
  mkdir -p -- "$LOG_DIR" 2>/dev/null || return 0
  chmod 0700 "$LOG_DIR" 2>/dev/null || true
  local logfile=${LOG_FILE:-$LOG_DIR/events.jsonl} ts host
  ts=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
  host=$(hostname -f 2>/dev/null || hostname)
  if command -v jq >/dev/null 2>&1; then
    jq -cn --arg ts "$ts" --arg host "$host" --arg level "$level" --arg message "$message" '{timestamp:$ts,host:$host,level:$level,message:$message}' >> "$logfile"
  else
    local escaped
    escaped=$(printf '%s' "$message" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e ':a;N;$!ba;s/\n/\\n/g')
    printf '{"timestamp":"%s","host":"%s","level":"%s","message":"%s"}\n' "$ts" "$host" "$level" "$escaped" >> "$logfile"
  fi
  chmod 0600 "$logfile" 2>/dev/null || true
}

loks_require() {
  local cmd
  for cmd in "$@"; do command -v "$cmd" >/dev/null 2>&1 || loks_die "Required command not found: $cmd"; done
}

loks_load_config() {
  local config=${LINUXOPSKIT_CONFIG:-${LINUXOPSKIT_ROOT}/config/linuxopskit.conf}
  [[ -f $config && ! -L $config ]] || loks_die "Trusted configuration missing or symlinked: $config"
  local config_mode
  config_mode=$(stat -c '%a' "$config" 2>/dev/null || echo 600)
  if (( (8#$config_mode & 0022) != 0 )); then
    loks_warn "Configuration is group/world writable; use chmod 0600"
  fi
  # shellcheck source=/dev/null
  source "$config"
  : "${DESTINATION:=/var/backups/linuxopskit}"
  : "${BACKUP_SET:=default}"
  : "${STATE_DIR:=$DESTINATION/.linuxopskit-state}"
  : "${LOG_DIR:=/var/log/linuxopskit}"
  : "${RETENTION_FULL_CHAINS:=4}"
  : "${MIN_FREE_SPACE_PERCENT:=5}"
  : "${POSTGRES_ENABLED:=false}"
  : "${POSTGRES_DUMP_FILE:=/var/lib/linuxopskit/postgres.sql}"
  : "${RCLONE_REMOTE:=}"
  : "${WEBHOOK_URL:=}"
  : "${NOTIFY_EMAIL:=}"
  : "${CLEANUP_MIN_AGE_DAYS:=30}"
  : "${CLEANUP_GLOB:=*.tmp}"
  : "${REQUIRE_MOUNTPOINT:=}"
  HOST_ID=${HOST_ID:-$(hostname -s | tr -cs 'A-Za-z0-9._-' '_')}
  [[ $BACKUP_SET =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$ ]] || loks_die "Invalid BACKUP_SET"
  [[ $HOST_ID =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$ ]] || loks_die "Invalid HOST_ID"
  [[ $RETENTION_FULL_CHAINS =~ ^[1-9][0-9]*$ ]] || loks_die "RETENTION_FULL_CHAINS must be >= 1"
  [[ $CLEANUP_MIN_AGE_DAYS =~ ^[0-9]+$ ]] || loks_die "CLEANUP_MIN_AGE_DAYS must be >= 0"
  [[ $MIN_FREE_SPACE_PERCENT =~ ^[0-9]+$ ]] && (( MIN_FREE_SPACE_PERCENT <= 99 )) || loks_die "MIN_FREE_SPACE_PERCENT must be 0..99"
  [[ ${BACKUP_PATHS+x} ]] || BACKUP_PATHS=()
  [[ ${CLEANUP_PATHS+x} ]] || CLEANUP_PATHS=()
}

loks_canonical() { realpath -m -- "$1"; }
loks_is_within() {
  local child parent
  child=$(loks_canonical "$1") || return 1
  parent=$(loks_canonical "$2") || return 1
  [[ $child == "$parent" || $child == "$parent/"* ]]
}

loks_validate_backup_paths() {
  (( ${#BACKUP_PATHS[@]} > 0 )) || loks_die "BACKUP_PATHS is empty"
  local p canon internal i j
  for p in "${BACKUP_PATHS[@]}"; do
    [[ $p == /* && -d $p && ! -L $p ]] || loks_die "Backup source must be an existing absolute non-symlink directory: $p"
    canon=$(loks_canonical "$p") || loks_die "Cannot resolve source: $p"
    [[ $canon != / ]] || loks_die "Backing up filesystem root is not supported"
    for internal in "$DESTINATION" "$STATE_DIR" "$LOG_DIR"; do
      if loks_is_within "$internal" "$canon" || loks_is_within "$canon" "$internal"; then
        loks_die "Operational path ($internal) overlaps backup source ($canon)"
      fi
    done
    if [[ $POSTGRES_ENABLED == true ]]; then
      [[ $POSTGRES_DUMP_FILE == /* ]] || loks_die "POSTGRES_DUMP_FILE must be absolute"
      loks_is_within "$POSTGRES_DUMP_FILE" "$canon" && loks_die "PostgreSQL dump path overlaps backup source ($canon)"
    fi
  done
  for ((i=0; i<${#BACKUP_PATHS[@]}; i++)); do
    for ((j=i+1; j<${#BACKUP_PATHS[@]}; j++)); do
      if loks_is_within "${BACKUP_PATHS[i]}" "${BACKUP_PATHS[j]}" || loks_is_within "${BACKUP_PATHS[j]}" "${BACKUP_PATHS[i]}"; then
        loks_die "Backup source paths overlap: ${BACKUP_PATHS[i]} and ${BACKUP_PATHS[j]}"
      fi
    done
  done
}

loks_prepare_storage() {
  [[ $DESTINATION == /* && $STATE_DIR == /* && $LOG_DIR == /* ]] || loks_die "Storage paths must be absolute"
  mkdir -p -- "$DESTINATION" "$STATE_DIR" "$LOG_DIR" || loks_die "Cannot create storage directories"
  chmod 0700 "$DESTINATION" "$STATE_DIR" "$LOG_DIR" 2>/dev/null || true
  if [[ -n $REQUIRE_MOUNTPOINT ]]; then
    command -v mountpoint >/dev/null 2>&1 || loks_die "mountpoint is required"
    mountpoint -q -- "$REQUIRE_MOUNTPOINT" || loks_die "Required mount is not mounted: $REQUIRE_MOUNTPOINT"
    loks_is_within "$DESTINATION" "$REQUIRE_MOUNTPOINT" || loks_die "DESTINATION must be inside REQUIRE_MOUNTPOINT"
  fi
  local free
  free=$(df -P "$DESTINATION" | awk 'NR==2 {gsub(/%/,"",$5); print 100-$5}')
  [[ $free =~ ^[0-9]+$ ]] || loks_die "Cannot determine free space"
  (( free >= MIN_FREE_SPACE_PERCENT )) || loks_die "Only $free% free space remains (minimum $MIN_FREE_SPACE_PERCENT%)"
}

loks_run_hooks() {
  local hook_dir=$1 hook
  [[ -d $hook_dir ]] || return 0
  while IFS= read -r -d '' hook; do
    [[ -x $hook ]] || continue
    loks_info "Running hook: $hook"
    "$hook" || return $?
  done < <(find "$hook_dir" -maxdepth 1 -type f -print0 | sort -z)
}

loks_send_notification() {
  local subject=$1 body=$2
  if [[ -n $NOTIFY_EMAIL ]]; then
    if command -v mail >/dev/null 2>&1; then printf '%s\n' "$body" | mail -s "$subject" -- "$NOTIFY_EMAIL" || loks_warn "Email notification failed"
    else loks_warn "mail is not installed"; fi
  fi
  if [[ -n $WEBHOOK_URL ]]; then
    if command -v curl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
      local payload
      payload=$(jq -cn --arg text "$subject: $body" '{text:$text}')
      curl --silent --show-error --fail --max-time 10 -H 'Content-Type: application/json' -d "$payload" "$WEBHOOK_URL" >/dev/null || loks_warn "Webhook notification failed"
    else loks_warn "Webhook requires curl and jq"; fi
  fi
}

loks_state_dir() { printf '%s/%s/%s' "${STATE_DIR%/}" "$HOST_ID" "$BACKUP_SET"; }
loks_archive_dir() { printf '%s/%s/%s/archives' "${DESTINATION%/}" "$HOST_ID" "$BACKUP_SET"; }

loks_lock() {
  loks_require flock
  mkdir -p -- "$(loks_state_dir)"
  exec 9>"$(loks_state_dir)/linuxopskit.lock"
  flock -n 9 || loks_die "Another LinuxOpsKit operation is running for $BACKUP_SET"
}

loks_verify_archive_paths() {
  local archive=$1 entry
  tar -tzf "$archive" >/dev/null || loks_die "Cannot read archive member list: $archive"
  while IFS= read -r entry; do
    [[ -n $entry ]] || continue
    [[ $entry != /* ]] || loks_die "Unsafe absolute path in archive: $entry"
    case "/$entry/" in */../*) loks_die "Unsafe parent traversal path: $entry" ;; esac
    [[ $entry != -* ]] || loks_die "Unsafe option-like path: $entry"
  done < <(tar -tzf "$archive")
}

#!/usr/bin/env bash

loks_backup() {
  local mode=${1:-incremental}
  [[ $mode == full || $mode == incremental ]] || loks_die "Usage: linuxopskit backup [full|incremental]"
  loks_require tar sha256sum date find df awk realpath hostname
  loks_validate_backup_paths
  loks_prepare_storage
  loks_lock

  local state_dir archive_dir stamp archive snapshot current_chain chain_id kind workdir postgres_created=false
  state_dir=$(loks_state_dir); archive_dir=$(loks_archive_dir)
  mkdir -p -- "$state_dir" "$archive_dir"
  snapshot="$state_dir/backup.snar"
  current_chain="$state_dir/current_chain"
  if [[ $mode == full ]]; then
    stamp=$(date -u +'%Y%m%dT%H%M%SZ')-$$
    chain_id=$stamp
    kind=full
    rm -f -- "$snapshot"
  else
    [[ -s $current_chain ]] || loks_die "No full backup chain exists; run 'backup full' first"
    IFS= read -r chain_id < "$current_chain"
    [[ $chain_id =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,80}$ ]] || loks_die "Invalid chain state; run a new full backup"
    if ! find "$archive_dir" -maxdepth 1 -type f -name '*.meta' -exec grep -l -F -x "chain_id=$chain_id" {} + | grep -q .; then
      loks_die "Current full backup chain is missing; run 'backup full' first"
    fi
    stamp=$(date -u +'%Y%m%dT%H%M%SZ')-$$
    kind=incremental
  fi
  archive="$archive_dir/${stamp}_${kind}.tar.gz"
  [[ ! -e $archive ]] || loks_die "Archive already exists: $archive"
  workdir=$(mktemp -d "${state_dir}/work.XXXXXX") || loks_die "Cannot create work directory"
  local -a paths=("${BACKUP_PATHS[@]}")
  if [[ $POSTGRES_ENABLED == true ]]; then
    # shellcheck source=../plugins/postgres.sh
    source "${LINUXOPSKIT_ROOT}/plugins/postgres.sh"
    loks_postgres_dump "$workdir"
    postgres_created=true
    paths+=("$POSTGRES_DUMP_FILE")
  fi

  export LINUXOPSKIT_MODE=$mode LINUXOPSKIT_CHAIN_ID=$chain_id LINUXOPSKIT_ARCHIVE=$archive
  loks_run_hooks "${LINUXOPSKIT_ROOT}/hooks/pre-backup.d" || { [[ $postgres_created == true ]] && rm -f -- "$POSTGRES_DUMP_FILE"; rm -rf -- "$workdir"; loks_die "A pre-backup hook failed; backup cancelled"; }
  loks_info "Creating $mode backup in chain $chain_id"
  if ! tar --create --gzip --file="$archive" --listed-incremental="$snapshot" --warning=no-file-changed -- "${paths[@]}"; then
    rm -f -- "$archive"; [[ $postgres_created == true ]] && rm -f -- "$POSTGRES_DUMP_FILE"; rm -rf -- "$workdir"; loks_die "tar backup failed"
  fi
  if [[ $postgres_created == true ]]; then rm -f -- "$POSTGRES_DUMP_FILE"; fi
  rm -rf -- "$workdir"
  chmod 0600 "$archive"
  (cd "$archive_dir" && sha256sum -- "$(basename "$archive")" > "$(basename "$archive").sha256")
  chmod 0600 "$archive.sha256"
  {
    printf 'chain_id=%s\n' "$chain_id"
    printf 'kind=%s\n' "$kind"
    printf 'created_utc=%s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
    printf 'host_id=%s\n' "$HOST_ID"
    printf 'backup_set=%s\n' "$BACKUP_SET"
  } > "$archive.meta"
  chmod 0600 "$archive.meta"
  if [[ $mode == full ]]; then printf '%s\n' "$chain_id" > "$current_chain"; chmod 0600 "$current_chain"; fi
  if [[ -n $RCLONE_REMOTE ]]; then
    command -v rclone >/dev/null 2>&1 || loks_die "RCLONE_REMOTE is set but rclone is not installed"
    rclone copy "$archive_dir" "${RCLONE_REMOTE%/}/$HOST_ID/$BACKUP_SET/archives" --checksum || loks_die "rclone upload failed"
  fi
  loks_log info "backup_complete mode=$mode chain_id=$chain_id archive=$(basename "$archive")"
  if ! loks_run_hooks "${LINUXOPSKIT_ROOT}/hooks/post-backup.d"; then loks_warn "A post-backup hook failed; the archive is already complete"; fi
  loks_send_notification "LinuxOpsKit backup completed" "$mode backup completed: $archive"
  loks_info "Backup completed: $archive"
  loks_apply_retention
}

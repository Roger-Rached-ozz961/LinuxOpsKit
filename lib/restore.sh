#!/usr/bin/env bash

loks_restore() {
  local chain_id=${1:-} target=${2:-}
  [[ $chain_id =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,80}$ ]] || loks_die "Usage: linuxopskit restore CHAIN_ID ABSOLUTE_TARGET"
  [[ $target == /* ]] || loks_die "Restore target must be an absolute path"
  local archive_dir state_dir target_canonical parent staging meta archive found_full=false protected
  archive_dir=$(loks_archive_dir); state_dir=$(loks_state_dir)
  [[ -d $archive_dir ]] || loks_die "Archive directory does not exist"
  target_canonical=$(loks_canonical "$target")
  [[ $target_canonical != / ]] || loks_die "Refusing to restore over filesystem root"
  for protected in "$DESTINATION" "$STATE_DIR" "$LOG_DIR" "${BACKUP_PATHS[@]}"; do
    if loks_is_within "$target_canonical" "$protected" || loks_is_within "$protected" "$target_canonical"; then
      loks_die "Restore target overlaps a protected source or operational path: $protected"
    fi
  done
  [[ ! -L $target ]] || loks_die "Restore target must not be a symlink"
  if [[ -e $target ]]; then
    [[ -d $target ]] || loks_die "Restore target exists and is not a directory"
    [[ -z $(find "$target" -mindepth 1 -maxdepth 1 -print -quit) ]] || loks_die "Restore target must be empty; refusing to overwrite existing data"
  fi
  parent=$(dirname -- "$target_canonical")
  mkdir -p -- "$parent"
  staging=$(mktemp -d "${parent}/.linuxopskit-restore.XXXXXX") || loks_die "Cannot create restore staging directory"
  local restore_snapshot="$staging/.linuxopskit-restore.snar"
  local -a chain_archives=()
  while IFS= read -r -d '' meta; do
    grep -q -F -x "chain_id=$chain_id" "$meta" || continue
    archive=${meta%.meta}
    [[ -f $archive && -f $archive.sha256 ]] || { rm -rf -- "$staging"; loks_die "Backup chain contains a missing archive or checksum"; }
    chain_archives+=("$archive")
  done < <(find "$archive_dir" -maxdepth 1 -type f -name '*.meta' -print0 | sort -z)
  ((${#chain_archives[@]} > 0)) || { rm -rf -- "$staging"; loks_die "Backup chain not found: $chain_id"; }
  local a
  for a in "${chain_archives[@]}"; do
    (cd "$archive_dir" && sha256sum --check --status "$(basename "$a").sha256") || { rm -rf -- "$staging"; loks_die "Checksum validation failed: $(basename "$a")"; }
    loks_verify_archive_paths "$a" || { rm -rf -- "$staging"; loks_die "Archive path validation failed"; }
    if [[ $(sed -n 's/^kind=//p' "$a.meta") == full ]]; then found_full=true; fi
    tar --extract --gzip --file="$a" --directory="$staging" --listed-incremental="$restore_snapshot" --no-same-owner --no-same-permissions --no-overwrite-dir --delay-directory-restore || {
      rm -rf -- "$staging"; loks_die "Restore extraction failed at $(basename "$a")"
    }
  done
  [[ $found_full == true ]] || { rm -rf -- "$staging"; loks_die "Refusing to restore a chain without a full archive"; }
  rm -f -- "$restore_snapshot"
  if [[ -d $target ]]; then rmdir -- "$target" || { rm -rf -- "$staging"; loks_die "Could not replace empty restore target"; }; fi
  mv -- "$staging" "$target_canonical" || loks_die "Could not move restored data into place"
  loks_log info "restore_complete chain_id=$chain_id target=$target_canonical"
  loks_info "Restore completed at $target_canonical"
}

loks_verify() {
  local archive_dir meta archive count=0
  archive_dir=$(loks_archive_dir)
  [[ -d $archive_dir ]] || loks_die "Archive directory does not exist"
  while IFS= read -r -d '' meta; do
    archive=${meta%.meta}
    [[ -f $archive && -f $archive.sha256 ]] || loks_die "Incomplete backup set: $(basename "$archive")"
    (cd "$archive_dir" && sha256sum --check "$(basename "$archive").sha256") || loks_die "Checksum validation failed: $(basename "$archive")"
    loks_verify_archive_paths "$archive"
    ((count+=1))
  done < <(find "$archive_dir" -maxdepth 1 -type f -name '*.meta' -print0 | sort -z)
  (( count > 0 )) || loks_die "No completed backup archives found"
  loks_info "Verified $count archive(s) and their internal path lists"
}

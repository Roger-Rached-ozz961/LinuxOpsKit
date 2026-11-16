#!/usr/bin/env bash

loks_list() {
  local archive_dir meta archive
  archive_dir=$(loks_archive_dir)
  [[ -d $archive_dir ]] || { loks_info "No backups found"; return 0; }
  printf '%-42s %-14s %-30s %s\n' 'ARCHIVE' 'TYPE' 'CHAIN' 'SIZE'
  while IFS= read -r -d '' meta; do
    archive=${meta%.meta}
    printf '%-42s %-14s %-30s %s\n' "$(basename "$archive")" "$(sed -n 's/^kind=//p' "$meta")" \
      "$(sed -n 's/^chain_id=//p' "$meta")" "$(du -h -- "$archive" 2>/dev/null | awk '{print $1}')"
  done < <(find "$archive_dir" -maxdepth 1 -type f -name '*.meta' -print0 | sort -z)
}

loks_cleanup() {
  local apply=false path canonical file
  [[ ${1:-} == --apply ]] && apply=true
  [[ -z ${1:-} || ${1:-} == --apply ]] || loks_die "Usage: linuxopskit cleanup [--apply]"
  ((${#CLEANUP_PATHS[@]} > 0)) || { loks_info "No CLEANUP_PATHS configured; nothing to clean"; return 0; }
  for path in "${CLEANUP_PATHS[@]}"; do
    [[ $path == /* ]] || loks_die "Cleanup path must be absolute: $path"
    [[ -d $path && ! -L $path ]] || loks_die "Cleanup target must be an existing, non-symlink directory: $path"
    canonical=$(loks_canonical "$path")
    [[ $canonical != / && $canonical != "$HOME" ]] || loks_die "Refusing dangerous cleanup target: $canonical"
    local protected
    for protected in "$DESTINATION" "$STATE_DIR" "$LOG_DIR" "${BACKUP_PATHS[@]}"; do
      if loks_is_within "$canonical" "$protected" || loks_is_within "$protected" "$canonical"; then
        loks_die "Cleanup path overlaps a protected source or operational path: $protected"
      fi
    done
    while IFS= read -r -d '' file; do
      if [[ $apply == true ]]; then
        rm -f -- "$file" && loks_info "Removed: $file"
      else
        printf 'DRY-RUN would remove: %s\n' "$file"
      fi
    done < <(find "$canonical" -xdev -type f -name "$CLEANUP_GLOB" -mtime "+$CLEANUP_MIN_AGE_DAYS" -print0)
  done
  [[ $apply == true ]] && loks_log info "cleanup_applied" || loks_log info "cleanup_dry_run"
}

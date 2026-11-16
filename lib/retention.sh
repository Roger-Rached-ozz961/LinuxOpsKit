#!/usr/bin/env bash

loks_apply_retention() {
  local archive_dir meta chain count=0
  archive_dir=$(loks_archive_dir)
  [[ -d $archive_dir ]] || return 0
  local -a full_metas=()
  while IFS= read -r -d '' meta; do
    grep -q '^kind=full$' "$meta" && full_metas+=("$meta")
  done < <(find "$archive_dir" -maxdepth 1 -type f -name '*.meta' -print0 | sort -z)
  # Retention is chain-aware: keep the newest N full snapshots and their incrementals.
  local -A keep=()
  for ((count=${#full_metas[@]}-1; count>=0 && count>=${#full_metas[@]}-RETENTION_FULL_CHAINS; count--)); do
    chain=$(sed -n 's/^chain_id=//p' "${full_metas[count]}")
    [[ -n $chain ]] && keep[$chain]=1
  done
  while IFS= read -r -d '' meta; do
    chain=$(sed -n 's/^chain_id=//p' "$meta")
    [[ -n ${keep[$chain]+x} ]] && continue
    local archive=${meta%.meta}
    loks_warn "Retention removing backup chain $chain ($(basename "$archive"))"
    rm -f -- "$archive" "$archive.sha256" "$meta"
  done < <(find "$archive_dir" -maxdepth 1 -type f -name '*.meta' -print0)
}

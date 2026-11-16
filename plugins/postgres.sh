#!/usr/bin/env bash

loks_postgres_dump() {
  local workdir=$1
  command -v pg_dumpall >/dev/null 2>&1 || loks_die "POSTGRES_ENABLED=true but pg_dumpall is not installed"
  [[ $POSTGRES_DUMP_FILE == /* ]] || loks_die "POSTGRES_DUMP_FILE must be an absolute path"
  [[ ! -L $POSTGRES_DUMP_FILE ]] || loks_die "Refusing symlinked PostgreSQL dump path"
  mkdir -p -- "$(dirname -- "$POSTGRES_DUMP_FILE")"
  [[ ! -e $POSTGRES_DUMP_FILE ]] || loks_die "PostgreSQL dump file already exists; move or remove it first: $POSTGRES_DUMP_FILE"
  umask 077
  pg_dumpall --file="$POSTGRES_DUMP_FILE" || { rm -f -- "$POSTGRES_DUMP_FILE"; loks_die "pg_dumpall failed"; }
  chmod 0600 "$POSTGRES_DUMP_FILE"
  loks_info "PostgreSQL logical dump created (credentials are not logged)"
}

# Post-backup hooks

Place executable scripts in this directory. They run in filename order after the archive and checksum are written. A failure is logged as a warning and does not invalidate the completed archive. The hook receives `LINUXOPSKIT_MODE`, `LINUXOPSKIT_CHAIN_ID`, and `LINUXOPSKIT_ARCHIVE` in its environment.

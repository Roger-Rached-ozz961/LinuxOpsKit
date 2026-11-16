# Pre-backup hooks

Place executable scripts in this directory. They run in filename order before an archive is created. A non-zero exit status cancels the backup. The hook receives `LINUXOPSKIT_MODE`, `LINUXOPSKIT_CHAIN_ID`, and `LINUXOPSKIT_ARCHIVE` in its environment. Hooks run with the same privileges as the LinuxOpsKit process; review them carefully.

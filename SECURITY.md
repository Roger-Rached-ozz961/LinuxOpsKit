# Security policy and operational safeguards

LinuxOpsKit handles filesystem data and can delete files during explicit cleanup or incremental restore operations. Treat it as privileged infrastructure software.

- **Configuration trust:** the configuration is Bash and is sourced. Only administrators should be able to write it; use owner `root`, group `linuxopskit`, and mode `0640` when using the supplied service unit (the group can read but cannot write). For manual-only usage, mode `0600` is suitable. Never load configuration from an untrusted checkout or writable directory.
- **Least privilege:** configure only required source paths. Use a dedicated service account with read access to sources and write access only to destination, state, and logs. The supplied systemd units run as the dedicated account and grant `CAP_DAC_READ_SEARCH` so the process can read configured protected paths without being root. This capability is sensitive; review the service account's configured source paths and remove it when not needed.
- **Backup storage:** encrypt storage at rest or use a separately managed encrypted volume. Optional rclone credentials must live outside the repository and be readable only by the service account. Keep an offline/immutable copy and test recovery.
- **Restore:** restore is non-destructive to an existing populated target; it requires an empty target directory and validates archive checksums and member paths. GNU tar incremental extraction can remove files from the restore staging tree to reflect deletions. Restore only archives from trusted sources. Review symlink-heavy or untrusted archives before extraction.
- **Cleanup:** cleanup is dry-run by default and only searches explicitly configured directories. `cleanup --apply` deletes matching regular files older than the configured age. Review the dry-run output before applying. Cleanup does not follow symlinks and stays on one filesystem.
- **Hooks and plugins:** executable hooks run with the same privileges as the main process. PostgreSQL dumps may contain all database data; protect and promptly remove the transient dump file. Keep webhook URLs and database credentials out of logs and source control.
- **Integrity:** SHA-256 detects accidental modification but is not an authenticity guarantee. Protect checksums and archives together; use signed manifests or authenticated immutable storage for stronger assurance.
- **Production validation:** validate mount behavior, permissions, application consistency, database restore, retention, capacity alerts, rclone provider behavior, and full disaster recovery on each target distribution before production use.

Report security issues privately to the repository owner rather than publishing exploit details in an issue.

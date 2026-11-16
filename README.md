# LinuxOpsKit

**A modular Bash toolkit for Linux backups, log hygiene, and recurring maintenance.**

LinuxOpsKit provides timestamped full and incremental filesystem backups, chain-aware retention, SHA-256 verification, controlled restore, optional PostgreSQL logical dumps, optional rclone replication, hooks, notifications, cleanup previews, and systemd/cron scheduling examples.

> **Status:** development baseline. Local integration tests cover the core backup/restore and cleanup flows. This project is not declared production-ready; validate it against your distribution, permissions, applications, storage providers, and recovery objectives before operational deployment.

## Features

- **Full and incremental backups:** GNU tar snapshot-based backup chains. Start each chain with a full backup; subsequent incremental runs capture changes and deletions.
- **Integrity verification:** per-archive SHA-256 checksums and archive-member path checks before restore.
- **Controlled restore:** restores an entire chain into a new staging directory and requires the requested target to be absent or empty.
- **Chain-aware retention:** retains a configured number of complete full-backup chains, including their incrementals.
- **Destination validation:** local directories, mounted NFS shares, and mounted external drives are supported as filesystem destinations. A mountpoint guard can prevent writing to an unmounted path.
- **Optional cloud replication:** rclone can copy completed archive sets to configured remotes; configure provider credentials separately.
- **Optional PostgreSQL plugin:** creates a `pg_dumpall` logical dump which is included in the backup archive. Database import is a separate recovery step.
- **Maintenance cleanup:** explicit allowlisted paths, age and glob filters, no symlink following, one-filesystem traversal, and dry-run by default.
- **Operations integration:** JSON Lines event logs, optional email/webhook notifications, pre/post hooks, logrotate, cron, and a hardened systemd service/timer example.
- **Automated checks:** Bash syntax checks and integration tests run through GitHub Actions on pushes and pull requests to `main`.

## Requirements

- Bash 4.4 or later
- GNU tar with incremental snapshot support
- GNU coreutils (`sha256sum`, `realpath`, `date`, `install`)
- `find`, `flock`, `df`, `awk`, and `hostname`
- `jq` is recommended for JSONL logging and required for webhook notifications
- Optional: `rclone`, `curl`, `mail`, `pg_dumpall`, `logrotate`, and systemd

The automation is designed for common Debian/Ubuntu and RHEL-family environments, but it has not been validated on every distribution or release. Some utilities and system paths differ on SUSE and other platforms.

## Installation

Clone the repository and install the files:

```bash
git clone https://github.com/Roger-Rached-ozz961/LinuxOpsKit.git
cd LinuxOpsKit
sudo ./install.sh
```

Edit `/etc/linuxopskit/linuxopskit.conf`. The installer copies the example only when no configuration already exists. Keep the configuration root-owned and writable only by root. The installer sets group read access for the dedicated service account (mode `0640`) because it must source the configuration:

```bash
sudo chown root:linuxopskit /etc/linuxopskit/linuxopskit.conf
sudo chmod 0640 /etc/linuxopskit/linuxopskit.conf
sudoedit /etc/linuxopskit/linuxopskit.conf
```

Set `BACKUP_PATHS` to the directories you need, choose a destination, and review service-account read/write permissions. The destination must not be inside a directory being backed up.

For a non-installed checkout or a custom config path:

```bash
export LINUXOPSKIT_CONFIG="$PWD/config/linuxopskit.conf"
```

Copy the example first and adjust it; do not run with the sample paths blindly.

## Usage

Run the initial full backup through the supplied one-shot systemd unit so it uses the same dedicated account, permissions, and read-only DAC capability as scheduled jobs:

```bash
sudo systemctl start linuxopskit-backup-full.service
sudo systemctl status linuxopskit-backup-full.service
```

The daily timer then runs incremental backups. To start an incremental backup manually, use:

```bash
sudo systemctl start linuxopskit-backup.service
```

Inspect and verify the stored archives:

```bash
sudo -u linuxopskit /opt/linuxopskit/bin/linuxopskit list
sudo -u linuxopskit /opt/linuxopskit/bin/linuxopskit verify
```

Restore a complete chain to a new, empty directory. Use the `CHAIN` value shown by `list`:

```bash
sudo install -d -o linuxopskit -g linuxopskit -m 0700 /srv/restore-test
sudo -u linuxopskit /opt/linuxopskit/bin/linuxopskit restore 20261117T021500Z-1234 /srv/restore-test
```

Cleanup is a preview unless explicitly applied:

```bash
sudo -u linuxopskit /opt/linuxopskit/bin/linuxopskit cleanup
sudo -u linuxopskit /opt/linuxopskit/bin/linuxopskit cleanup --apply
```

The cleanup command only considers configured `CLEANUP_PATHS`, matching regular files older than `CLEANUP_MIN_AGE_DAYS` and matching `CLEANUP_GLOB`. Review the preview before applying deletion.

### Scheduling

After editing and testing the configuration, enable the supplied systemd timer:

```bash
sudo systemctl enable --now linuxopskit-backup.timer
systemctl list-timers linuxopskit-backup.timer
```

The timer performs incremental backups. Create and verify the initial full backup manually. A cron example is provided in `cron/linuxopskit.cron`.

### Optional PostgreSQL plugin

Set `POSTGRES_ENABLED=true`, configure `POSTGRES_DUMP_FILE`, and arrange secure libpq authentication for the service account (for example, a tightly permissioned `.pgpass` or service file). `pg_dumpall` output includes roles and database contents and must be protected as sensitive data. A successful filesystem restore does not automatically import the SQL dump; review it and use an appropriate PostgreSQL recovery procedure.

### Optional rclone replication

Install and configure rclone for the service account, then set `RCLONE_REMOTE`, for example `s3:my-bucket/linuxopskit`. LinuxOpsKit runs `rclone copy` after local archive creation. Remote provider consistency, encryption, credentials, object-lock, and recovery must be validated independently.

## Configuration reference

| Setting | Purpose |
|---|---|
| `DESTINATION` | Local filesystem path for host/set archives |
| `BACKUP_SET`, `HOST_ID` | Safe identifiers that separate backup streams |
| `STATE_DIR` | Incremental snapshot and lock state |
| `BACKUP_PATHS` | Explicit source directories |
| `RETENTION_FULL_CHAINS` | Number of full chains to retain |
| `MIN_FREE_SPACE_PERCENT` | Minimum free-space threshold before backup |
| `REQUIRE_MOUNTPOINT` | Optional mount that must be mounted and contain the destination |
| `POSTGRES_ENABLED`, `POSTGRES_DUMP_FILE` | Optional PostgreSQL dump plugin |
| `RCLONE_REMOTE` | Optional rclone destination |
| `NOTIFY_EMAIL`, `WEBHOOK_URL` | Optional notifications |
| `CLEANUP_PATHS`, `CLEANUP_GLOB`, `CLEANUP_MIN_AGE_DAYS` | Explicit cleanup scope and age filter |

## Security considerations

- The config is **executable Bash**, not a passive key/value file. Only source trusted files and restrict write permissions.
- Backups may contain credentials, private keys, user data, and database contents. Use encrypted volumes or a separately managed encryption layer, restrictive permissions, and off-host copies.
- SHA-256 checksums detect corruption but do not authenticate an archive against an attacker who can replace both archive and checksum.
- Hooks run as the service account. Audit every executable hook and plugin before enabling it.
- Restore requires an empty target and checks checksums and member paths, but only restore trusted archives. Review untrusted archives and unusual symlink structures in an isolated environment.
- **Cleanup:** dry-run by default. `cleanup --apply` is destructive within the explicitly configured allowlist.
- Test recovery regularly. Backup success is not proof that an application can be restored consistently.

See [SECURITY.md](SECURITY.md) for operational safeguards and limitations.

## Project structure

```text
LinuxOpsKit/
├── .github/workflows/ci.yml       # GitHub Actions validation
├── bin/linuxopskit                 # CLI entry point
├── config/linuxopskit.conf.example # Example configuration
├── cron/linuxopskit.cron           # Cron schedule example
├── hooks/{pre,post}-backup.d/      # Administrator-managed lifecycle hooks
├── lib/                            # Core, backup, restore, retention, maintenance
├── logrotate/linuxopskit           # JSONL log rotation policy
├── plugins/postgres.sh             # Optional PostgreSQL dump plugin
├── systemd/                        # Hardened full/incremental services and timer
├── tests/run.sh                    # Integration test suite
├── install.sh
├── Makefile
├── SECURITY.md
└── README.md
```

## Development and tests

```bash
make syntax
make test
make check
```

The integration suite creates isolated temporary directories and tests full backup, incremental backup, checksum/path verification, full-chain restore (including a deletion), cleanup dry-run, cleanup application, and rejection of a non-empty restore target.

GitHub Actions runs the same checks for pushes and pull requests targeting `main`.

## Limitations and validation still required

- NFS/external-drive operation depends on correct mount configuration and filesystem semantics; test disconnects, remounts, permissions, and capacity behavior.
- rclone provider uploads, cloud authentication, remote retention, encryption, and remote restore have not been exercised by the local suite.
- PostgreSQL dump execution and database restore have not been tested against a live database.
- Email and webhook delivery have not been tested against real services.
- Incremental backup uses GNU tar snapshot semantics. Validate application quiescing, open-file consistency, ownership/ACL/xattr needs, and restore behavior on your target hosts.
- The supplied systemd unit assumes the `linuxopskit` service account and default paths created by the installer. Review hardening and write paths before enabling it; highly restrictive settings may need adjustment for your local policies.
- Cross-distribution support is a design goal, not a claim of exhaustive platform testing.

## License

MIT. See [LICENSE](LICENSE).

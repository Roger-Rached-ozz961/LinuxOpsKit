#!/usr/bin/env bash
set -Eeuo pipefail

PREFIX=${PREFIX:-/opt/linuxopskit}
CONFIG_DIR=${CONFIG_DIR:-/etc/linuxopskit}
SERVICE_USER=${SERVICE_USER:-linuxopskit}
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)

if (( EUID != 0 )); then echo 'Run install.sh as root (for example: sudo ./install.sh).' >&2; exit 1; fi
command -v install >/dev/null 2>&1 || { echo 'install command is required' >&2; exit 1; }
install -d -m 0755 "$PREFIX" "$CONFIG_DIR" /var/lib/linuxopskit/state /var/log/linuxopskit /var/backups/linuxopskit /var/tmp/linuxopskit-cleanup
cp -a "$ROOT/bin" "$ROOT/lib" "$ROOT/plugins" "$ROOT/hooks" "$PREFIX/"
chmod 0755 "$PREFIX/bin/linuxopskit"
if [[ ! -e "$CONFIG_DIR/linuxopskit.conf" ]]; then install -m 0600 "$ROOT/config/linuxopskit.conf.example" "$CONFIG_DIR/linuxopskit.conf"; fi
if ! id "$SERVICE_USER" >/dev/null 2>&1; then
  if command -v useradd >/dev/null 2>&1; then useradd --system --home-dir /var/lib/linuxopskit --shell /usr/sbin/nologin "$SERVICE_USER";
  else echo "Create a dedicated service account named $SERVICE_USER manually." >&2; exit 1; fi
fi
chown -R "$SERVICE_USER":"$SERVICE_USER" /var/lib/linuxopskit /var/log/linuxopskit /var/backups/linuxopskit /var/tmp/linuxopskit-cleanup
# The service account needs read-only access to configuration while only root may edit it.
chown root:"$SERVICE_USER" "$CONFIG_DIR/linuxopskit.conf"
chmod 0640 "$CONFIG_DIR/linuxopskit.conf"
install -m 0644 "$ROOT/systemd/linuxopskit-backup.service" /etc/systemd/system/linuxopskit-backup.service
install -m 0644 "$ROOT/systemd/linuxopskit-backup-full.service" /etc/systemd/system/linuxopskit-backup-full.service
install -m 0644 "$ROOT/systemd/linuxopskit-backup.timer" /etc/systemd/system/linuxopskit-backup.timer
install -m 0644 "$ROOT/logrotate/linuxopskit" /etc/logrotate.d/linuxopskit
systemctl daemon-reload
printf 'Installed LinuxOpsKit to %s. Edit %s/linuxopskit.conf, then enable the timer with: systemctl enable --now linuxopskit-backup.timer\n' "$PREFIX" "$CONFIG_DIR"

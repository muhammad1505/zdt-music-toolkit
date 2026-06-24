#!/usr/bin/env bash
# Install ZDT systemd scheduler
# Run: sudo bash install-systemd.sh

set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "Installing ZDT Scheduler systemd service..."

# Copy service files
sudo cp "$SCRIPT_DIR/zdt-scheduler.service" /etc/systemd/system/
sudo cp "$SCRIPT_DIR/zdt-scheduler.timer" /etc/systemd/system/

# Update the ExecStart path to use the real python
sudo sed -i "s|/usr/bin/python3|$(which python3)|g" /etc/systemd/system/zdt-scheduler.service
sudo sed -i "s|/home/zaki/zdt-project/zdt-scheduler.py|$(dirname "$SCRIPT_DIR")/zdt-scheduler.py|g" /etc/systemd/system/zdt-scheduler.service

# Reload and enable
sudo systemctl daemon-reload
sudo systemctl enable zdt-scheduler.timer
sudo systemctl start zdt-scheduler.timer

echo "✅ ZDT Scheduler timer installed and started!"
echo "   Check status: systemctl status zdt-scheduler.timer"
echo "   View logs: journalctl -u zdt-scheduler.service -f"

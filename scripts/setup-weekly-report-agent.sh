#!/bin/bash
# setup-weekly-report-agent.sh
#
# Idempotent installer for the DO Card weekly analytics report local mirror.
# Pairs with the cloud routine "DO Card Weekly Analytics Report"
# (claude.ai/code/routines/trig_018iBTTiQ4VkpF34GBVmZkKK) which pushes weekly
# markdown reports to `reports/` on origin/main.
#
# After this script runs, every Monday 09:30 Asia/Taipei the launchd agent
# `online.do.weekly-report-pull` fetches new reports into a sparse-checkout
# mirror at ~/Library/Application Support/do-card/reports-mirror/ and rsyncs
# them into ~/Weekly report/, visible from the Desktop via a symlink.
#
# Designed to be re-run any time (Mac reinstall, script update, etc.) —
# idempotent. Requires `git` already authenticated for the private repo
# (e.g., signed in via gh CLI or the macOS keychain helper).

set -eu

REPO_URL="https://github.com/YC-0210/DO-IOS-Claude-"
APP_SUPPORT="$HOME/Library/Application Support/do-card"
MIRROR="$APP_SUPPORT/reports-mirror"
SCRIPT_DEST="$APP_SUPPORT/weekly-report-pull.sh"
DEST="$HOME/Weekly report"
DESKTOP_LINK="$HOME/Desktop/Weekly report"
PLIST="$HOME/Library/LaunchAgents/online.do.weekly-report-pull.plist"
LABEL="online.do.weekly-report-pull"

THIS_DIR="$(cd "$(dirname "$0")" && pwd)"
PULL_SRC="$THIS_DIR/weekly-report-pull.sh"

if [ ! -f "$PULL_SRC" ]; then
  echo "ERROR: missing $PULL_SRC (run from the repo's scripts/ folder)"
  exit 1
fi

echo "==> installing pull script -> $SCRIPT_DEST"
mkdir -p "$APP_SUPPORT"
cp "$PULL_SRC" "$SCRIPT_DEST"
chmod +x "$SCRIPT_DEST"

echo "==> setting up sparse-checkout mirror at $MIRROR"
if [ ! -d "$MIRROR/.git" ]; then
  git -c http.version=HTTP/1.1 clone --filter=blob:none --sparse "$REPO_URL" "$MIRROR"
  git -C "$MIRROR" sparse-checkout set reports
else
  echo "    mirror already present; fetching"
  git -C "$MIRROR" -c http.version=HTTP/1.1 fetch origin main
  git -C "$MIRROR" merge --ff-only FETCH_HEAD || true
fi

echo "==> creating destination + Desktop symlink"
mkdir -p "$DEST"
if [ ! -e "$DESKTOP_LINK" ]; then
  ln -s "$DEST" "$DESKTOP_LINK"
elif [ -L "$DESKTOP_LINK" ]; then
  echo "    symlink already present"
else
  echo "    WARNING: $DESKTOP_LINK exists and is not a symlink — leaving alone"
fi

echo "==> writing launchd plist -> $PLIST"
mkdir -p "$(dirname "$PLIST")"
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>$LABEL</string>
	<key>ProgramArguments</key>
	<array>
		<string>/bin/bash</string>
		<string>$SCRIPT_DEST</string>
	</array>
	<key>StartCalendarInterval</key>
	<dict>
		<key>Weekday</key>
		<integer>1</integer>
		<key>Hour</key>
		<integer>9</integer>
		<key>Minute</key>
		<integer>30</integer>
	</dict>
	<key>StandardOutPath</key>
	<string>$HOME/Library/Logs/do-card-weekly-pull.log</string>
	<key>StandardErrorPath</key>
	<string>$HOME/Library/Logs/do-card-weekly-pull.log</string>
	<key>RunAtLoad</key>
	<false/>
</dict>
</plist>
EOF
plutil -lint "$PLIST" >/dev/null

echo "==> (re-)bootstrapping launchd agent"
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
launchctl list | grep "$LABEL" >/dev/null || { echo "ERROR: agent not registered"; exit 1; }

echo
echo "DONE. Next scheduled run: Mon 09:30 Asia/Taipei."
echo "Trigger immediately: launchctl kickstart -k gui/$(id -u)/$LABEL"
echo "Logs: ~/Library/Logs/do-card-weekly-pull.log"
echo "View reports: ~/Desktop/Weekly\\ report/ (symlink) or ~/Weekly\\ report/"

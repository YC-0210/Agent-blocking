#!/bin/bash
# weekly-report-pull.sh
#
# Fetches the latest weekly analytics report from origin/main into a sparse
# mirror, then rsyncs *.md into the visible destination. Triggered weekly by
# the launchd agent `online.do.weekly-report-pull` (Mon 09:30 Asia/Taipei),
# ~30 min after the cloud routine pushes a fresh report.
#
# Both source mirror and destination live OUTSIDE macOS TCC-protected folders,
# so launchd needs no Full Disk Access grant. `~/Desktop/Weekly report` is a
# symlink to $DEST.
#
# HTTP/1.1: GitHub's HTTP/2 transport returns persistent 500 ISE on this repo;
# HTTP/1.1 is the workaround.

set -u

REPO="$HOME/Library/Application Support/do-card/reports-mirror"
DEST="$HOME/Weekly report"
LOG="$HOME/Library/Logs/do-card-weekly-pull.log"

mkdir -p "$DEST"

{
  echo
  echo "==== $(date "+%Y-%m-%d %H:%M:%S %z") ===="
  cd "$REPO" || { echo "repo missing at $REPO"; exit 1; }
  # Retry fetch a few times — GitHub HTTPS occasionally drops the connection.
  for attempt in 1 2 3; do
    if git -c http.version=HTTP/1.1 fetch origin main; then
      break
    fi
    echo "fetch attempt $attempt failed, retrying in 5s..."
    sleep 5
  done
  if ! git merge --ff-only FETCH_HEAD; then
    echo "non-fast-forward in mirror; resolve manually. aborting pull."
    exit 1
  fi
  # --delete keeps each destination as a faithful mirror of its source folder.
  # Reports are immutable once committed, so removing files locally that vanish
  # upstream is safe. --exclude='*' protects sibling sub-directories in $DEST
  # (e.g. "DO App/") from being touched by the weekly/ mirror — they're handled
  # by separate rsync passes below.
  rsync -av --delete --include='*.md' --exclude='*' "$REPO/weekly/" "$DEST/"
  # Website report (GA4 + Clarity) → DO App/ subfolder.
  mkdir -p "$DEST/DO App"
  rsync -av --delete --include='*.md' --exclude='*' "$REPO/reports/" "$DEST/DO App/"
  echo "done."
} >> "$LOG" 2>&1

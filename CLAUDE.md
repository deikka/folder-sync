# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Folder Sync - macOS incremental backup system with native menu bar app. Mirrors a source folder to an external drive using rsync, scheduled via launchd, with a Swift/AppKit UI for monitoring and configuration.

## Build & Run

```bash
# Compile and create .app bundle
./build.sh

# Or with make
make build

# Launch
open FolderSync.app

# Full install (script + launchd + app)
./install.sh
```

Requires Xcode Command Line Tools (`swiftc`). No external dependencies.

## Manual Backup

```bash
~/.local/bin/backup-dev-apps.sh          # incremental
~/.local/bin/backup-dev-apps.sh --full   # skip dry-run, copy everything
```

## Architecture

Three-layer system communicating via JSON files:

**Swift App (app/main.swift)** → UI layer. Menu bar icon, settings window, progress display. Polls `progress.json` every 1.5s during backup. Generates launchd plist from `config.json` on save.

**Bash Script (scripts/backup-dev-apps.sh)** → Execution layer. Reads paths from `config.json`, runs rsync with `--delete --itemize-changes`, writes `progress.json` per-item and `status.json` on completion. Auto-detects empty destination to skip dry-run.

**LaunchAgent (scripts/com.klab.folder-sync.plist)** → Scheduling layer. Generated dynamically by the Swift app via `regeneratePlist()` which does unload → write → load cycle.

### Data flow during backup
```
App starts Process(/bin/bash, [script])
  → Script writes progress.json (phase/percent/current/total)
  → App polls progress.json, updates menu bar with "%"
  → Script writes status.json on completion
  → Script sends macOS notification via osascript
  → App stops polling, refreshes menu
```

### Runtime files (in ~/.local/share/backup-dev-apps/)

| File | Written by | Read by | Purpose |
|---|---|---|---|
| config.json | App | App + Script | Source/dest paths, schedule |
| progress.json | Script | App (poll 1.5s) | Live sync progress |
| status.json | Script | App | Last backup result |

## Key Implementation Details

- **Permission detection**: `checkNeedsPermissions()` spawns `/bin/ls` as subprocess (not FileManager API) because GUI apps have implicit volume access that terminal processes don't. This triggers macOS granular volume permission dialog.
- **Volume path extraction**: Uses `split(separator: "/").prefix(2)` to get `/Volumes/DiskName` from any destination path.
- **Plist regeneration**: `regeneratePlist()` - empty `days` array generates a single `StartCalendarInterval` dict; specific days generate an array of dicts with `Weekday` keys.
- **Full copy mode**: Triggered by `--full` flag or auto-detected when destination is empty. Uses `find` to count source files (local, fast) instead of rsync dry-run.
- **Progress tracking**: Script regex `^[\>\*\<cd][a-zA-Z\+\.]` matches rsync `--itemize-changes` output lines. Logs every ~10% via `COUNT % (TOTAL_ITEMS / 10 + 1)`.
- **Config JSON parsing in bash**: Uses `python3 -c "import json; ..."` with fallback defaults.

## Homebrew Distribution

Published via tap: `brew tap deikka/tap && brew install folder-sync`

Formula at `github.com/deikka/homebrew-tap`. Release flow: tag in this repo → update SHA in formula → push tap.

#!/bin/bash
# Copia BackupMenu.app a ~/Applications para que Spotlight/Raycast lo indexen
# (los symlinks no son indexados)
set -euo pipefail

SOURCE="${1:-/opt/homebrew/opt/folder-sync/BackupMenu.app}"

if [ ! -d "$SOURCE" ]; then
  echo "Error: no se encontro $SOURCE"
  echo "Instala primero: brew install deikka/tap/folder-sync"
  exit 1
fi

mkdir -p ~/Applications
rm -rf ~/Applications/BackupMenu.app
cp -R "$SOURCE" ~/Applications/BackupMenu.app

echo "BackupMenu.app copiado a ~/Applications/"
echo "Ya deberia aparecer en Spotlight y Raycast."

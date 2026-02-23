#!/bin/bash
# Copia FolderSync.app a ~/Applications para que Spotlight/Raycast lo indexen
# (los symlinks no son indexados)
set -euo pipefail

SOURCE="${1:-/opt/homebrew/opt/folder-sync/FolderSync.app}"

if [ ! -d "$SOURCE" ]; then
  echo "Error: no se encontro $SOURCE"
  echo "Instala primero: brew install deikka/tap/folder-sync"
  exit 1
fi

mkdir -p ~/Applications
rm -rf ~/Applications/FolderSync.app
cp -R "$SOURCE" ~/Applications/FolderSync.app

echo "FolderSync.app copiado a ~/Applications/"
echo "Ya deberia aparecer en Spotlight y Raycast."

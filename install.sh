#!/bin/bash
set -euo pipefail

echo "Instalando backup-dev-apps..."

# Crear directorios
mkdir -p ~/.local/bin
mkdir -p ~/.local/logs
mkdir -p ~/.local/share/backup-dev-apps

# Copiar script de backup
cp scripts/backup-dev-apps.sh ~/.local/bin/backup-dev-apps.sh
chmod +x ~/.local/bin/backup-dev-apps.sh

# Crear config por defecto si no existe
if [ ! -f ~/.local/share/backup-dev-apps/config.json ]; then
  cat > ~/.local/share/backup-dev-apps/config.json <<EOF
{
  "hour": 10,
  "minute": 0,
  "days": [],
  "source": "$HOME/Desktop/dev_apps/",
  "destination": "/Volumes/Toshiba/dev_apps/"
}
EOF
  echo "Config creada en ~/.local/share/backup-dev-apps/config.json (editar rutas)"
fi

# Compilar app
echo "Compilando FolderSync..."
./build.sh

# Migrar LaunchAgent antiguo si existe
OLD_PLIST="$HOME/Library/LaunchAgents/com.alex.backup-dev-apps.plist"
if [ -f "$OLD_PLIST" ]; then
  echo "Migrando LaunchAgent antiguo..."
  launchctl unload "$OLD_PLIST" 2>/dev/null || true
  rm -f "$OLD_PLIST"
fi

# Instalar LaunchAgent
cp scripts/com.klab.folder-sync.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.klab.folder-sync.plist 2>/dev/null || true

# Copiar a ~/Applications (Spotlight/Raycast/Launchpad no indexan symlinks)
mkdir -p ~/Applications
rm -rf ~/Applications/FolderSync.app
cp -R ~/.local/share/backup-dev-apps/FolderSync.app ~/Applications/FolderSync.app

echo ""
echo "Instalacion completada."
echo "  - Ejecutar app: open -a FolderSync"
echo "  - Tambien disponible en Spotlight y Launchpad"
echo "  - Editar config: ~/.local/share/backup-dev-apps/config.json"

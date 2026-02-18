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
  cat > ~/.local/share/backup-dev-apps/config.json <<'EOF'
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
echo "Compilando BackupMenu..."
./build.sh

# Instalar LaunchAgent
cp scripts/com.alex.backup-dev-apps.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.alex.backup-dev-apps.plist 2>/dev/null || true

# Crear symlink en ~/Applications (Spotlight, Launchpad, open -a)
mkdir -p ~/Applications
ln -sf ~/.local/share/backup-dev-apps/BackupMenu.app ~/Applications/BackupMenu.app

echo ""
echo "Instalacion completada."
echo "  - Ejecutar app: open -a BackupMenu"
echo "  - Tambien disponible en Spotlight y Launchpad"
echo "  - Editar config: ~/.local/share/backup-dev-apps/config.json"

#!/bin/bash
# Backup incremental de dev_apps a disco externo Toshiba
# Ejecutado diariamente via launchd

set -euo pipefail

# Configuración
SOURCE="/Users/alex/Desktop/dev_apps/"
DEST="/Volumes/Toshiba/dev_apps/"
VOLUME="/Volumes/Toshiba"
LOG="$HOME/.local/logs/backup-dev-apps.log"
STATUS_FILE="$HOME/.local/share/backup-dev-apps/status.json"
PROGRESS_FILE="$HOME/.local/share/backup-dev-apps/progress.json"
TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")

EXCLUDE_ARGS=(
  --exclude='node_modules'
  --exclude='.git'
  --exclude='tmp'
  --exclude='.cache'
  --exclude='cache'
  --exclude='.DS_Store'
)

log() {
  echo "[$TIMESTAMP] $1" >> "$LOG"
}

notify() {
  osascript -e "display notification \"$1\" with title \"Backup dev_apps\" sound name \"$2\""
}

write_status() {
  local status="$1"
  local files="${2:-0}"
  local size="${3:-0 bytes}"
  local disk="${4:-false}"
  cat > "$STATUS_FILE" <<EOFSTATUS
{
  "lastRun": "$TIMESTAMP",
  "status": "$status",
  "filesTransferred": $files,
  "totalSize": "$size",
  "diskConnected": $disk
}
EOFSTATUS
}

write_progress() {
  cat > "$PROGRESS_FILE" <<EOFPROG
{
  "phase": "$1",
  "percent": $2,
  "current": $3,
  "total": $4
}
EOFPROG
}

cleanup_progress() {
  sleep 3
  rm -f "$PROGRESS_FILE"
}

# Verificar si el disco está montado
if [ ! -d "$VOLUME" ]; then
  log "SKIP - Disco Toshiba no montado"
  write_status "skip" 0 "0 bytes" "false"
  notify "Disco Toshiba no conectado. Backup omitido." "Basso"
  exit 0
fi

# Fase 1: Conteo de items (dry run)
write_progress "counting" 0 0 0
log "INICIO - Contando archivos a sincronizar..."

TOTAL_ITEMS=$(rsync -ah --delete --dry-run --itemize-changes \
  "${EXCLUDE_ARGS[@]}" "$SOURCE" "$DEST" 2>&1 | \
  grep -c '^[>*<cd]' || echo "0")
TOTAL_ITEMS=${TOTAL_ITEMS:-0}

log "INICIO - $TOTAL_ITEMS items a procesar. Sincronizando $SOURCE -> $DEST"

if [ "$TOTAL_ITEMS" -eq 0 ]; then
  write_progress "done" 100 0 0
  log "OK - Sin cambios"
  write_status "ok" "0" "0 bytes" "true"
  notify "Backup: sin cambios." "Glass"
  cleanup_progress &
  exit 0
fi

write_progress "sync" 0 0 "$TOTAL_ITEMS"

# Fase 2: Sincronización con seguimiento de progreso
COUNT=0
RSYNC_FULL_OUTPUT=""

while IFS= read -r line; do
  RSYNC_FULL_OUTPUT+="$line"$'\n'
  if [[ "$line" =~ ^[\>\*\<cd][a-zA-Z\+\.] ]]; then
    ((COUNT++)) || true
    PCT=$((COUNT * 100 / TOTAL_ITEMS))
    write_progress "sync" "$PCT" "$COUNT" "$TOTAL_ITEMS"
  fi
done < <(rsync -ah --delete --itemize-changes --stats \
  "${EXCLUDE_ARGS[@]}" "$SOURCE" "$DEST" 2>&1)

RSYNC_EXIT=$?

write_progress "done" 100 "$COUNT" "$TOTAL_ITEMS"

# Extraer resumen de stats
FILES_TRANSFERRED=$(echo "$RSYNC_FULL_OUTPUT" | grep "Number of regular files transferred" | awk '{print $NF}')
TOTAL_SIZE=$(echo "$RSYNC_FULL_OUTPUT" | grep "Total transferred file size" | awk -F: '{print $2}' | xargs)

if [ "$RSYNC_EXIT" -ne 0 ]; then
  log "ERROR - rsync exit code: $RSYNC_EXIT"
  write_status "error" 0 "0 bytes" "true"
  notify "Error en backup. Revisa el log." "Basso"
  cleanup_progress &
  exit 1
fi

log "OK - Archivos transferidos: ${FILES_TRANSFERRED:-0}, Tamaño: ${TOTAL_SIZE:-0}"
write_status "ok" "${FILES_TRANSFERRED:-0}" "${TOTAL_SIZE:-0 bytes}" "true"
notify "Backup completado. ${FILES_TRANSFERRED:-0} archivos transferidos." "Glass"

cleanup_progress &

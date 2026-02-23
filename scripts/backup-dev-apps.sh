#!/bin/bash
# Backup incremental de dev_apps a disco externo
# Ejecutado diariamente via launchd

set -euo pipefail

# Modo de ejecucion: --full para copia completa sin analisis previo
FULL_MODE=false
if [ "${1:-}" = "--full" ]; then
  FULL_MODE=true
fi

# Configuración
CONFIG_FILE="$HOME/.local/share/backup-dev-apps/config.json"
LOG="$HOME/.local/logs/backup-dev-apps.log"
STATUS_FILE="$HOME/.local/share/backup-dev-apps/status.json"
PROGRESS_FILE="$HOME/.local/share/backup-dev-apps/progress.json"
START_TIME=$(date +%s)

# Leer rutas de config.json (con fallback a valores por defecto)
if [ -f "$CONFIG_FILE" ]; then
  SOURCE=$(python3 -c "import json; print(json.load(open('$CONFIG_FILE'))['source'])" 2>/dev/null)
  DEST=$(python3 -c "import json; print(json.load(open('$CONFIG_FILE'))['destination'])" 2>/dev/null)
fi
SOURCE="${SOURCE:-/Users/alex/dev/}"
DEST="${DEST:-/Volumes/Toshiba/dev/}"

# Extraer volumen del destino (ej: /Volumes/Toshiba de /Volumes/Toshiba/dev_apps/)
VOLUME=$(echo "$DEST" | cut -d'/' -f1-3)
VOLUME_NAME=$(basename "$VOLUME")

EXCLUDE_ARGS=(
  --exclude='node_modules'
  --exclude='.git'
  --exclude='tmp'
  --exclude='.cache'
  --exclude='cache'
  --exclude='.DS_Store'
)

# Timestamp dinámico (se actualiza en cada llamada a log)
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG"
}

elapsed() {
  local now=$(date +%s)
  local diff=$((now - START_TIME))
  local min=$((diff / 60))
  local sec=$((diff % 60))
  printf "%dm%02ds" "$min" "$sec"
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
  "lastRun": "$(date '+%Y-%m-%d %H:%M:%S')",
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

# ============================================================
# PASO 1: Verificaciones previas
# ============================================================

MODO_STR="incremental"
if [ "$FULL_MODE" = true ]; then
  MODO_STR="copia completa (--full)"
fi

log "========================================"
log "BACKUP INICIADO"
log "  Origen:   $SOURCE"
log "  Destino:  $DEST"
log "  Volumen:  $VOLUME_NAME"
log "  Modo:     $MODO_STR"
log "  Excluye:  node_modules, .git, tmp, .cache, cache, .DS_Store"
log "----------------------------------------"

# Verificar si el disco está montado
if [ ! -d "$VOLUME" ]; then
  log "PASO 1: Disco $VOLUME_NAME no detectado en /Volumes/"
  log "RESULTADO: OMITIDO (disco no conectado)"
  log "========================================"
  write_status "skip" 0 "0 bytes" "false"
  notify "Disco $VOLUME_NAME no conectado. Backup omitido." "Basso"
  exit 0
fi
log "PASO 1: Disco $VOLUME_NAME montado OK"

# Verificar origen existe
if [ ! -d "$SOURCE" ]; then
  log "PASO 1: ERROR - Carpeta origen no existe: $SOURCE"
  log "RESULTADO: ERROR"
  log "========================================"
  write_status "error" 0 "0 bytes" "true"
  notify "Error: carpeta origen no existe." "Basso"
  exit 1
fi

# Crear carpeta destino si no existe
if [ ! -d "$DEST" ]; then
  log "PASO 1: Creando carpeta destino $DEST"
  mkdir -p "$DEST" 2>/dev/null || {
    log "PASO 1: ERROR - No se puede crear $DEST (permisos insuficientes)"
    log "RESULTADO: ERROR (permisos)"
    log "========================================"
    write_status "error" 0 "0 bytes" "true"
    notify "Error: sin permisos para escribir en destino." "Basso"
    exit 1
  }
  log "PASO 1: Carpeta destino creada"
else
  log "PASO 1: Carpeta destino existe OK"
fi

# ============================================================
# PASO 2: Determinar modo y contar items
# ============================================================

# Detectar si el destino esta vacio (primera copia)
DEST_EMPTY=false
DEST_COUNT=$(find "$DEST" -maxdepth 1 -not -name '.' 2>/dev/null | wc -l | tr -d ' ')
if [ "$DEST_COUNT" -eq 0 ]; then
  DEST_EMPTY=true
fi

SKIP_DRY_RUN=false

if [ "$FULL_MODE" = true ]; then
  log "PASO 2: Modo COPIA COMPLETA (--full), sin analisis previo"
  SKIP_DRY_RUN=true
elif [ "$DEST_EMPTY" = true ]; then
  log "PASO 2: Destino vacio detectado, copia inicial directa"
  SKIP_DRY_RUN=true
fi

if [ "$SKIP_DRY_RUN" = true ]; then
  # Contar archivos en origen con find (rapido, es local)
  write_progress "counting" 0 0 0
  log "PASO 2: Contando archivos en origen..."
  COUNT_START=$(date +%s)

  TOTAL_ITEMS=$(find "$SOURCE" -type f \
    -not -path '*/node_modules/*' \
    -not -path '*/.git/*' \
    -not -path '*/tmp/*' \
    -not -path '*/.cache/*' \
    -not -path '*/cache/*' \
    -not -name '.DS_Store' 2>/dev/null | wc -l | tr -d ' ')
  TOTAL_ITEMS=${TOTAL_ITEMS:-0}

  COUNT_ELAPSED=$(( $(date +%s) - COUNT_START ))
  log "PASO 2: $TOTAL_ITEMS archivos en origen (conteo en ${COUNT_ELAPSED}s)"

else
  # Modo incremental: dry run para analizar cambios
  log "PASO 2: Analizando cambios (dry run)..."
  write_progress "counting" 0 0 0

  DRY_START=$(date +%s)

  DRY_OUTPUT=$(rsync -ah --delete --dry-run --itemize-changes \
    "${EXCLUDE_ARGS[@]}" "$SOURCE" "$DEST" 2>&1)

  DRY_ELAPSED=$(( $(date +%s) - DRY_START ))

  TOTAL_ITEMS=$(echo "$DRY_OUTPUT" | grep -c '^[>*<cd]' || true)
  TOTAL_ITEMS=${TOTAL_ITEMS:-0}

  # Desglose de operaciones
  ITEMS_SEND=$(echo "$DRY_OUTPUT" | grep -c '^>f' || true)
  ITEMS_DELETE=$(echo "$DRY_OUTPUT" | grep -c '^\*deleting' || true)
  ITEMS_DIRS=$(echo "$DRY_OUTPUT" | grep -c '^cd' || true)

  log "PASO 2: Analisis completado en ${DRY_ELAPSED}s"
  log "  Total items a procesar: $TOTAL_ITEMS"
  log "  - Archivos a enviar:    ${ITEMS_SEND:-0}"
  log "  - Archivos a eliminar:  ${ITEMS_DELETE:-0}"
  log "  - Directorios nuevos:   ${ITEMS_DIRS:-0}"

  if [ "$TOTAL_ITEMS" -eq 0 ]; then
    write_progress "done" 100 0 0
    log "PASO 2: Sin cambios detectados"
    log "RESULTADO: OK (sin cambios) | Tiempo total: $(elapsed)"
    log "========================================"
    write_status "ok" "0" "0 bytes" "true"
    notify "Backup: sin cambios." "Glass"
    cleanup_progress &
    exit 0
  fi
fi

# ============================================================
# PASO 3: Sincronizacion
# ============================================================

if [ "$SKIP_DRY_RUN" = true ]; then
  log "PASO 3: Copiando $TOTAL_ITEMS archivos (copia directa)..."
else
  log "PASO 3: Sincronizando $TOTAL_ITEMS items (incremental)..."
fi
write_progress "sync" 0 0 "$TOTAL_ITEMS"

SYNC_START=$(date +%s)
COUNT=0
LOG_INTERVAL=$(( TOTAL_ITEMS / 10 + 1 ))
RSYNC_LOG=$(mktemp /tmp/backup-rsync.XXXXXX)

rsync -ah --delete --itemize-changes --stats \
  "${EXCLUDE_ARGS[@]}" "$SOURCE" "$DEST" > "$RSYNC_LOG" 2>&1 &
RSYNC_PID=$!

# Monitor progress by tailing rsync output
while kill -0 "$RSYNC_PID" 2>/dev/null; do
  NEW_COUNT=$(grep -c '^[>*<cd][a-zA-Z+.]' "$RSYNC_LOG" 2>/dev/null || true)
  if [ "$NEW_COUNT" -gt "$COUNT" ]; then
    COUNT=$NEW_COUNT
    if [ "$TOTAL_ITEMS" -gt 0 ]; then
      PCT=$((COUNT * 100 / TOTAL_ITEMS))
      PCT=$(( PCT > 100 ? 100 : PCT ))
    else
      PCT=0
    fi
    write_progress "sync" "$PCT" "$COUNT" "$TOTAL_ITEMS"

    if (( COUNT % LOG_INTERVAL == 0 )); then
      log "PASO 3: Progreso ${PCT}% ($COUNT/$TOTAL_ITEMS) | $(elapsed)"
    fi
  fi
  sleep 2
done

wait "$RSYNC_PID"
RSYNC_EXIT=$?
SYNC_ELAPSED=$(( $(date +%s) - SYNC_START ))

# Final count
COUNT=$(grep -c '^[>*<cd][a-zA-Z+.]' "$RSYNC_LOG" 2>/dev/null || true)
write_progress "done" 100 "$COUNT" "$TOTAL_ITEMS"

# ============================================================
# PASO 4: Resultado
# ============================================================

# Extraer resumen de stats de rsync
FILES_TRANSFERRED=$(grep "Number of regular files transferred" "$RSYNC_LOG" | awk '{print $NF}')
TOTAL_SIZE=$(grep "Total transferred file size" "$RSYNC_LOG" | awk -F: '{print $2}' | xargs)
TOTAL_FILES=$(grep "Number of files:" "$RSYNC_LOG" | head -1 | awk -F: '{print $2}' | xargs)
SPEEDUP=$(grep "speedup is" "$RSYNC_LOG" | awk '{print $NF}')

if [ "$RSYNC_EXIT" -ne 0 ]; then
  log "PASO 4: rsync fallo con codigo $RSYNC_EXIT"

  # Intentar capturar lineas de error
  ERRORS=$(grep -i "error\|failed\|denied\|permission" "$RSYNC_LOG" | head -5)
  if [ -n "$ERRORS" ]; then
    log "  Errores detectados:"
    while IFS= read -r err; do
      log "    $err"
    done <<< "$ERRORS"
  fi

  log "RESULTADO: ERROR | Tiempo total: $(elapsed)"
  log "========================================"
  write_status "error" 0 "0 bytes" "true"
  notify "Error en backup. Revisa el log." "Basso"
  rm -f "$RSYNC_LOG"
  cleanup_progress &
  exit 1
fi

log "PASO 4: Sincronizacion completada"
log "  Archivos transferidos: ${FILES_TRANSFERRED:-0}"
log "  Tamano transferido:    ${TOTAL_SIZE:-0}"
log "  Total archivos en set: ${TOTAL_FILES:-?}"
log "  Speedup rsync:         ${SPEEDUP:-?}x"
log "  Tiempo sync:           ${SYNC_ELAPSED}s"
log "RESULTADO: OK | Tiempo total: $(elapsed)"
log "========================================"

write_status "ok" "${FILES_TRANSFERRED:-0}" "${TOTAL_SIZE:-0 bytes}" "true"
notify "Backup completado. ${FILES_TRANSFERRED:-0} archivos en $(elapsed)." "Glass"

rm -f "$RSYNC_LOG"
cleanup_progress &

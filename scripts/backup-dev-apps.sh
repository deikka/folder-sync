#!/bin/bash
# Backup incremental de dev_apps a disco externo
# Ejecutado diariamente via launchd

set -u

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

# Archivos temporales (se limpian en trap)
RSYNC_LOG=""
DRY_LOG=""

# Flag para distinguir salida normal de interrupcion
SCRIPT_FINISHED=false

# Leer rutas de config.json (con fallback a valores por defecto)
if [ -f "$CONFIG_FILE" ]; then
  SOURCE=$(python3 -c "import json; print(json.load(open('$CONFIG_FILE'))['source'])" 2>/dev/null) || true
  DEST=$(python3 -c "import json; print(json.load(open('$CONFIG_FILE'))['destination'])" 2>/dev/null) || true
fi
SOURCE="${SOURCE:-$HOME/dev/}"
DEST="${DEST:-/Volumes/Toshiba/dev/}"

# Nombre del directorio fuente para notificaciones
SOURCE_NAME=$(basename "${SOURCE%/}")

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
  osascript -e "display notification \"$1\" with title \"Backup $SOURCE_NAME\" sound name \"$2\""
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
# TRAP EXIT: limpieza garantizada
# ============================================================
cleanup_on_exit() {
  # Limpiar archivos temporales siempre
  rm -f "$RSYNC_LOG" "$DRY_LOG" 2>/dev/null

  # Si el script no termino normalmente, registrar error
  if [ "$SCRIPT_FINISHED" != "true" ]; then
    log "RESULTADO: ERROR (interrupcion inesperada) | Tiempo total: $(elapsed)"
    log "========================================"
    write_status "error" 0 "0 bytes" "true"
    rm -f "$PROGRESS_FILE" 2>/dev/null
  fi
}
trap cleanup_on_exit EXIT

# ============================================================
# Rotacion de log (max ~5MB, guarda 1 historico)
# ============================================================
mkdir -p "$(dirname "$LOG")"
if [ -f "$LOG" ]; then
  LOG_SIZE=$(stat -f%z "$LOG" 2>/dev/null || echo "0")
  if [ "$LOG_SIZE" -gt 5242880 ]; then
    mv "$LOG" "${LOG}.1"
  fi
fi

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
  SCRIPT_FINISHED=true
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
  SCRIPT_FINISHED=true
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
    SCRIPT_FINISHED=true
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
  # Modo incremental: dry run a archivo temporal
  log "PASO 2: Analizando cambios (dry run)..."
  write_progress "counting" 0 0 0

  DRY_START=$(date +%s)
  DRY_LOG=$(mktemp /tmp/backup-dry.XXXXXX)

  rsync -ah --delete --dry-run --itemize-changes \
    "${EXCLUDE_ARGS[@]}" "$SOURCE" "$DEST" > "$DRY_LOG" 2>&1 || true

  DRY_ELAPSED=$(( $(date +%s) - DRY_START ))

  TOTAL_ITEMS=$(grep -c '^[>*<cd]' "$DRY_LOG" || true)
  TOTAL_ITEMS=${TOTAL_ITEMS:-0}

  # Desglose de operaciones
  ITEMS_SEND=$(grep -c '^>f' "$DRY_LOG" || true)
  ITEMS_DELETE=$(grep -c '^\*deleting' "$DRY_LOG" || true)
  ITEMS_DIRS=$(grep -c '^cd' "$DRY_LOG" || true)

  rm -f "$DRY_LOG"
  DRY_LOG=""

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
    SCRIPT_FINISHED=true
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

# Monitoreo de progreso con offset de bytes (evita re-escanear O(n^2))
BYTE_OFFSET=1
while kill -0 "$RSYNC_PID" 2>/dev/null; do
  FILE_SIZE=$(stat -f%z "$RSYNC_LOG" 2>/dev/null || echo "0")
  if [ "$FILE_SIZE" -gt "$BYTE_OFFSET" ]; then
    NEW_MATCHES=$(tail -c +"$BYTE_OFFSET" "$RSYNC_LOG" 2>/dev/null | grep -c '^[>*<cd][a-zA-Z+.]' || true)
    if [ "$NEW_MATCHES" -gt 0 ]; then
      COUNT=$((COUNT + NEW_MATCHES))
      BYTE_OFFSET=$((FILE_SIZE + 1))

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
  fi
  sleep 2
done

wait "$RSYNC_PID"
RSYNC_EXIT=$?
SYNC_ELAPSED=$(( $(date +%s) - SYNC_START ))

# Conteo final (leer lo que quede sin procesar)
REMAINING=$(tail -c +"$BYTE_OFFSET" "$RSYNC_LOG" 2>/dev/null | grep -c '^[>*<cd][a-zA-Z+.]' || true)
COUNT=$((COUNT + REMAINING))
write_progress "done" 100 "$COUNT" "$TOTAL_ITEMS"

# ============================================================
# PASO 4: Resultado
# ============================================================

# Extraer resumen de stats de rsync
FILES_TRANSFERRED=$(grep "Number of regular files transferred" "$RSYNC_LOG" | awk '{print $NF}') || true
TOTAL_SIZE=$(grep "Total transferred file size" "$RSYNC_LOG" | awk -F: '{print $2}' | xargs) || true
TOTAL_FILES=$(grep "Number of files:" "$RSYNC_LOG" | head -1 | awk -F: '{print $2}' | xargs) || true
SPEEDUP=$(grep "speedup is" "$RSYNC_LOG" | awk '{print $NF}') || true

if [ "$RSYNC_EXIT" -ne 0 ]; then
  log "PASO 4: rsync fallo con codigo $RSYNC_EXIT"

  # Intentar capturar lineas de error
  ERRORS=$(grep -i "error\|failed\|denied\|permission" "$RSYNC_LOG" | head -5) || true
  if [ -n "${ERRORS:-}" ]; then
    log "  Errores detectados:"
    while IFS= read -r err; do
      log "    $err"
    done <<< "$ERRORS"
  fi

  log "RESULTADO: ERROR | Tiempo total: $(elapsed)"
  log "========================================"
  write_status "error" 0 "0 bytes" "true"
  notify "Error en backup. Revisa el log." "Basso"
  cleanup_progress &
  SCRIPT_FINISHED=true
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

cleanup_progress &
SCRIPT_FINISHED=true

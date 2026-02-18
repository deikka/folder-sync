# Folder Sync

Backup incremental de carpetas a disco externo en macOS con app nativa de menu de barra.

Usa `rsync` con `--delete` para mantener un espejo exacto del origen, `launchd` para programar la ejecucion automatica, y una app Swift/AppKit ligera para monitorizar y configurar desde la barra de menu.

## Funcionalidades

- **Sincronizacion incremental** - Solo transfiere archivos modificados
- **Copia completa** - Modo directo sin analisis previo, ideal para primera copia o reseteos
- **Deteccion inteligente** - Si el destino esta vacio, salta el analisis y copia directo
- **Espejo exacto** - `--delete` elimina en destino lo que se borra en origen
- **Progreso en tiempo real** - Porcentaje en la barra de menu y barra de progreso en el dropdown
- **Programacion flexible** - Configura hora, dias y rutas desde la app
- **Deteccion de disco** - Si el disco no esta conectado, registra el evento y notifica
- **Deteccion de permisos** - Aviso y asistente si faltan permisos de acceso al volumen
- **Notificaciones nativas** - Sonido y notificacion de macOS al completar o fallar
- **Log detallado** - Pasos, tiempos, desglose de operaciones y progreso cada 10%

## Instalacion

### Homebrew (recomendado)

```sh
brew tap deikka/tap
brew install folder-sync
open /opt/homebrew/opt/folder-sync/BackupMenu.app
```

### Desde fuente

```sh
git clone git@github.com:deikka/folder-sync.git
cd folder-sync
./install.sh
open ~/.local/share/backup-dev-apps/BackupMenu.app
```

### Arranque automatico con el sistema

```sh
# Ajustar la ruta segun el metodo de instalacion
osascript -e 'tell application "System Events" to make login item at end with properties {path:"/opt/homebrew/opt/folder-sync/BackupMenu.app", hidden:true}'
```

Al primer uso, macOS pedira permisos de acceso al volumen externo. Aceptar el dialogo.

## Uso

### App de menu de barra

Haz clic en el icono de disco en la barra de menu para ver:

- Estado de la ultima copia (fecha, archivos, tamano)
- Estado del disco externo (en tiempo real)
- Horario y dias programados
- Progreso durante la ejecucion

Acciones disponibles:

| Accion | Atajo |
|---|---|
| Ejecutar backup ahora | `B` |
| Copia completa (sin analisis) | `F` |
| Ajustes | `,` |
| Ver log | `L` |
| Abrir carpeta backup | `O` |
| Configurar permisos | `P` |

### Modos de backup

| Modo | Cuando se usa | Que hace |
|---|---|---|
| Incremental | Backup normal (destino con datos) | Dry-run para detectar cambios, luego sincroniza solo lo necesario |
| Copia directa | Destino vacio o "Copia completa" | Cuenta archivos en origen (rapido) y copia todo sin dry-run |

El modo se selecciona automaticamente segun el estado del destino, o manualmente con "Copia completa" en el menu.

### Linea de comandos

```sh
# Backup incremental
~/.local/bin/backup-dev-apps.sh

# Copia completa (sin analisis previo)
~/.local/bin/backup-dev-apps.sh --full

# Ver log
cat ~/.local/logs/backup-dev-apps.log

# Desactivar programacion
launchctl unload ~/Library/LaunchAgents/com.alex.backup-dev-apps.plist

# Reactivar programacion
launchctl load ~/Library/LaunchAgents/com.alex.backup-dev-apps.plist
```

## Configuracion

La app guarda la configuracion en `~/.local/share/backup-dev-apps/config.json`:

```json
{
  "hour": 10,
  "minute": 0,
  "days": [1, 2, 3, 4, 5],
  "source": "/Users/alex/Desktop/dev_apps/",
  "destination": "/Volumes/Toshiba/dev_apps/"
}
```

- `days` vacio `[]` = cada dia
- `days` con valores = dias especificos (0=Dom, 1=Lun ... 6=Sab)
- `source` y `destination` configurables desde Ajustes con selector de carpeta

Al guardar desde la app, se regenera automaticamente el `LaunchAgent` y se recarga `launchd`.

## Log

Cada ejecucion registra 4 pasos detallados:

```
[2026-02-18 10:45:00] ========================================
[2026-02-18 10:45:00] BACKUP INICIADO
[2026-02-18 10:45:00]   Origen:   /Users/alex/Desktop/dev_apps/
[2026-02-18 10:45:00]   Destino:  /Volumes/Toshiba/dev_apps/
[2026-02-18 10:45:00]   Volumen:  Toshiba
[2026-02-18 10:45:00]   Modo:     incremental
[2026-02-18 10:45:00] ----------------------------------------
[2026-02-18 10:45:00] PASO 1: Disco Toshiba montado OK
[2026-02-18 10:45:00] PASO 1: Carpeta destino existe OK
[2026-02-18 10:45:02] PASO 2: Analisis completado en 2s
[2026-02-18 10:45:02]   Total items a procesar: 42
[2026-02-18 10:45:02]   - Archivos a enviar:    38
[2026-02-18 10:45:02]   - Archivos a eliminar:  2
[2026-02-18 10:45:02]   - Directorios nuevos:   2
[2026-02-18 10:45:05] PASO 3: Progreso 50% (21/42) | 0m05s
[2026-02-18 10:45:08] PASO 4: Sincronizacion completada
[2026-02-18 10:45:08]   Archivos transferidos: 38
[2026-02-18 10:45:08]   Tamano transferido:    12.5M
[2026-02-18 10:45:08]   Speedup rsync:         8.2x
[2026-02-18 10:45:08] RESULTADO: OK | Tiempo total: 0m08s
[2026-02-18 10:45:08] ========================================
```

## Exclusiones

El script excluye por defecto:

- `node_modules`
- `.git`
- `tmp`
- `.cache` / `cache`
- `.DS_Store`

Modificar la variable `EXCLUDE_ARGS` en `scripts/backup-dev-apps.sh` para ajustar.

## Estructura

```
├── app/
│   └── main.swift              # App de menu (Swift/AppKit)
├── scripts/
│   ├── backup-dev-apps.sh      # Script rsync con progreso
│   └── com.alex.backup-dev-apps.plist  # LaunchAgent template
├── build.sh                    # Compila el bundle .app
└── install.sh                  # Instalacion completa
```

## Requisitos

- macOS 11+
- Xcode Command Line Tools (`xcode-select --install`)

# Folder Sync

Backup incremental de carpetas a disco externo en macOS con app nativa de menu de barra.

Usa `rsync` con `--delete` para mantener un espejo exacto del origen, `launchd` para programar la ejecucion automatica, y una app Swift/AppKit ligera para monitorizar y configurar desde la barra de menu.

## Funcionalidades

- **Sincronizacion incremental** - Solo transfiere archivos modificados
- **Espejo exacto** - `--delete` elimina en destino lo que se borra en origen
- **Progreso en tiempo real** - Porcentaje visible en la barra de menu y barra de progreso en el dropdown
- **Programacion flexible** - Configura hora y dias de la semana desde la app
- **Deteccion de disco** - Si el disco no esta conectado, registra el evento y notifica
- **Notificaciones nativas** - Sonido y notificacion de macOS al completar o fallar
- **Log persistente** - Registro de todas las ejecuciones en `~/.local/logs/`

## Instalacion

```sh
git clone git@github.com:deikka/folder-sync.git
cd folder-sync
```

Editar las rutas en `scripts/backup-dev-apps.sh` y `install.sh` segun tu configuracion, y luego:

```sh
./install.sh
open ~/.local/share/backup-dev-apps/BackupMenu.app
```

## Uso

### App de menu de barra

Haz clic en el icono de disco en la barra de menu para ver:

- Estado de la ultima copia (fecha, archivos, tamano)
- Estado del disco externo
- Horario programado

Acciones disponibles:

| Accion | Atajo |
|---|---|
| Ejecutar backup ahora | `B` |
| Configurar horario | `,` |
| Ver log | `L` |
| Abrir carpeta backup | `O` |

### Linea de comandos

```sh
# Ejecutar backup manualmente
~/.local/bin/backup-dev-apps.sh

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

Al guardar desde la app, se regenera automaticamente el `LaunchAgent` y se recarga `launchd`.

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

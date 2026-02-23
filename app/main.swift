import Cocoa

// MARK: - Paths

let home = NSHomeDirectory()
let dataDir = "\(home)/.local/share/backup-dev-apps"
let configPath = "\(dataDir)/config.json"
let statusPath = "\(dataDir)/status.json"
let progressPath = "\(dataDir)/progress.json"
let logPath = "\(home)/.local/logs/backup-dev-apps.log"
let scriptPath = "\(home)/.local/bin/backup-dev-apps.sh"
let plistPath = "\(home)/Library/LaunchAgents/com.klab.folder-sync.plist"

// MARK: - Data Models

struct BackupConfig: Codable {
    var hour: Int
    var minute: Int
    var days: [Int]
    var source: String
    var destination: String
}

struct BackupStatus: Codable {
    var lastRun: String
    var status: String
    var filesTransferred: Int
    var totalSize: String
    var diskConnected: Bool
}

struct BackupProgress: Codable {
    var phase: String      // "counting", "sync", "done"
    var percent: Int
    var current: Int
    var total: Int
}

func loadJSON<T: Decodable>(_ path: String, as type: T.Type) -> T? {
    guard let data = FileManager.default.contents(atPath: path) else { return nil }
    return try? JSONDecoder().decode(type, from: data)
}

func saveJSON<T: Encodable>(_ value: T, to path: String) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    guard let data = try? encoder.encode(value) else { return }
    FileManager.default.createFile(atPath: path, contents: data)
}

// MARK: - Plist Generator

func regeneratePlist(config: BackupConfig) {
    let unload = Process()
    unload.executableURL = URL(fileURLWithPath: "/bin/launchctl")
    unload.arguments = ["unload", plistPath]
    try? unload.run()
    unload.waitUntilExit()

    var calendarEntries = ""

    if config.days.isEmpty {
        calendarEntries = """
                <dict>
                    <key>Hour</key>
                    <integer>\(config.hour)</integer>
                    <key>Minute</key>
                    <integer>\(config.minute)</integer>
                </dict>
        """
    } else {
        calendarEntries = "        <array>\n"
        for day in config.days.sorted() {
            calendarEntries += """
                    <dict>
                        <key>Weekday</key>
                        <integer>\(day)</integer>
                        <key>Hour</key>
                        <integer>\(config.hour)</integer>
                        <key>Minute</key>
                        <integer>\(config.minute)</integer>
                    </dict>\n
            """
        }
        calendarEntries += "        </array>"
    }

    let plist = """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" \
    "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
        <key>Label</key>
        <string>com.klab.folder-sync</string>
        <key>ProgramArguments</key>
        <array>
            <string>\(scriptPath)</string>
        </array>
        <key>StartCalendarInterval</key>
    \(calendarEntries)
        <key>StandardErrorPath</key>
        <string>\(home)/.local/logs/backup-dev-apps-stderr.log</string>
    </dict>
    </plist>
    """

    try? plist.write(toFile: plistPath, atomically: true, encoding: .utf8)

    let load = Process()
    load.executableURL = URL(fileURLWithPath: "/bin/launchctl")
    load.arguments = ["load", plistPath]
    try? load.run()
    load.waitUntilExit()
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var refreshTimer: Timer?
    var progressTimer: Timer?
    var configWindow: NSWindow?
    var isBackupRunning = false
    var backupProcess: Process?

    // Config window controls
    var hourField: NSTextField!
    var minuteField: NSTextField!
    var sourceField: NSTextField!
    var destField: NSTextField!
    var dayCheckboxes: [NSButton] = []

    let dayNames = ["Dom", "Lun", "Mar", "Mie", "Jue", "Vie", "Sab"]

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            if #available(macOS 11.0, *),
               let img = NSImage(systemSymbolName: "externaldrive.badge.timemachine",
                                 accessibilityDescription: "Backup") {
                img.isTemplate = true
                button.image = img
            } else {
                button.title = "BK"
            }
        }
        refreshMenu()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.refreshMenu()
        }
    }

    // MARK: - Progress Tracking

    func startProgressPolling() {
        progressTimer?.invalidate()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.updateProgressDisplay()
        }
    }

    func stopProgressPolling() {
        progressTimer?.invalidate()
        progressTimer = nil
        // Reset button title
        if let button = statusItem.button {
            button.title = ""
        }
    }

    func updateProgressDisplay() {
        guard isBackupRunning else {
            stopProgressPolling()
            return
        }

        if let progress = loadJSON(progressPath, as: BackupProgress.self) {
            if let button = statusItem.button {
                switch progress.phase {
                case "counting":
                    button.title = " ..."
                case "sync":
                    button.title = " \(progress.percent)%"
                case "done":
                    button.title = ""
                default:
                    button.title = ""
                }
            }
        }

        // Also refresh menu in case it's open
        refreshMenu()
    }

    // MARK: - Menu

    func refreshMenu() {
        let menu = NSMenu()

        // Header
        let header = NSMenuItem(title: "Backup dev", action: nil, keyEquivalent: "")
        header.attributedTitle = NSAttributedString(
            string: "Backup dev",
            attributes: [.font: NSFont.boldSystemFont(ofSize: 13)]
        )
        menu.addItem(header)
        menu.addItem(.separator())

        // Progress section (shown during backup)
        if isBackupRunning {
            if let p = loadJSON(progressPath, as: BackupProgress.self) {
                switch p.phase {
                case "counting":
                    addInfoItem(menu, "Analizando cambios...")
                    addProgressBar(menu, percent: -1) // indeterminate
                case "sync":
                    addInfoItem(menu, "Sincronizando: \(p.current) / \(p.total) items")
                    addProgressBar(menu, percent: p.percent)
                case "done":
                    addInfoItem(menu, "Finalizando...")
                    addProgressBar(menu, percent: 100)
                default:
                    addInfoItem(menu, "Ejecutando...")
                }
            } else {
                addInfoItem(menu, "Iniciando backup...")
            }
            menu.addItem(.separator())
        }

        // Permission warning
        let needsPermissions = checkNeedsPermissions()
        if needsPermissions {
            let warnItem = NSMenuItem(title: "! Sin permisos de disco", action: nil, keyEquivalent: "")
            warnItem.isEnabled = false
            warnItem.attributedTitle = NSAttributedString(
                string: "  Sin permisos de disco",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 12, weight: .medium),
                    .foregroundColor: NSColor.systemOrange
                ]
            )
            menu.addItem(warnItem)
            addActionItem(menu, "Configurar permisos...", #selector(openPermissions), "p")
            menu.addItem(.separator())
        }

        // Last backup status
        if let s = loadJSON(statusPath, as: BackupStatus.self) {
            let indicator: String
            switch s.status {
            case "ok":    indicator = "[OK]"
            case "skip":  indicator = "[SKIP]"
            case "error": indicator = "[ERR]"
            default:      indicator = "[?]"
            }
            addInfoItem(menu, "Ultima copia:  \(s.lastRun)")
            addInfoItem(menu, "Estado:  \(indicator)  |  Archivos: \(s.filesTransferred)")
            addInfoItem(menu, "Tamano:  \(s.totalSize)")

            let diskStr = s.diskConnected ? "Conectado" : "No conectado"
            let destPath = loadJSON(configPath, as: BackupConfig.self)?.destination ?? "/Volumes/Toshiba/dev_apps/"
            let volumePath = destPath.split(separator: "/").prefix(2).map { String($0) }.joined(separator: "/")
            let diskLive = FileManager.default.fileExists(atPath: "/\(volumePath)")
            let nowStr = diskLive ? "Conectado" : "No conectado"
            if diskStr != nowStr {
                addInfoItem(menu, "Disco (ultimo):  \(diskStr)  |  Ahora:  \(nowStr)")
            } else {
                addInfoItem(menu, "Disco:  \(nowStr)")
            }
        } else {
            addInfoItem(menu, "Sin datos de backup aun")
        }

        // Schedule info
        if let config = loadJSON(configPath, as: BackupConfig.self) {
            let timeStr = String(format: "%02d:%02d", config.hour, config.minute)
            let daysStr: String
            if config.days.isEmpty {
                daysStr = "Cada dia"
            } else {
                daysStr = config.days.sorted().map { dayNames[$0] }.joined(separator: ", ")
            }
            menu.addItem(.separator())
            addInfoItem(menu, "Horario:  \(timeStr)  |  \(daysStr)")
        }

        menu.addItem(.separator())

        // Actions
        if isBackupRunning {
            let runningItem = NSMenuItem(title: "Backup en curso...", action: nil, keyEquivalent: "")
            runningItem.isEnabled = false
            menu.addItem(runningItem)
        } else {
            addActionItem(menu, "Ejecutar backup ahora", #selector(runBackup), "b")
            addActionItem(menu, "Copia completa (sin analisis)", #selector(runFullBackup), "f")
        }

        addActionItem(menu, "Ajustes...", #selector(openConfig), ",")
        addActionItem(menu, "Ver log", #selector(openLog), "l")
        addActionItem(menu, "Abrir carpeta backup", #selector(openBackupFolder), "o")

        menu.addItem(.separator())
        addActionItem(menu, "Salir", #selector(quit), "q")

        statusItem.menu = menu
    }

    func addInfoItem(_ menu: NSMenu, _ title: String) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        item.attributedTitle = NSAttributedString(
            string: title,
            attributes: [.font: NSFont.monospacedSystemFont(ofSize: 11.5, weight: .regular)]
        )
        menu.addItem(item)
    }

    func addProgressBar(_ menu: NSMenu, percent: Int) {
        let barWidth = 20
        let filled: Int
        let barStr: String

        if percent < 0 {
            // Indeterminate
            barStr = "[" + String(repeating: "=", count: 3) + String(repeating: " ", count: barWidth - 3) + "]  ..."
        } else {
            filled = max(0, min(barWidth, percent * barWidth / 100))
            let empty = barWidth - filled
            barStr = "[" + String(repeating: "#", count: filled) + String(repeating: ".", count: empty) + "]  \(percent)%"
        }

        let item = NSMenuItem(title: barStr, action: nil, keyEquivalent: "")
        item.isEnabled = false
        item.attributedTitle = NSAttributedString(
            string: barStr,
            attributes: [.font: NSFont.monospacedSystemFont(ofSize: 11.5, weight: .medium)]
        )
        menu.addItem(item)
    }

    func addActionItem(_ menu: NSMenu, _ title: String, _ action: Selector, _ key: String) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
    }

    // MARK: - Actions

    @objc func runBackup() {
        startBackup(args: [scriptPath])
    }

    @objc func runFullBackup() {
        startBackup(args: [scriptPath, "--full"])
    }

    func startBackup(args: [String]) {
        guard !isBackupRunning else { return }
        isBackupRunning = true
        refreshMenu()
        startProgressPolling()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = args
            self?.backupProcess = process

            try? process.run()
            process.waitUntilExit()

            DispatchQueue.main.async {
                self?.isBackupRunning = false
                self?.backupProcess = nil
                self?.stopProgressPolling()
                self?.refreshMenu()
            }
        }
    }

    func checkNeedsPermissions() -> Bool {
        guard let config = loadJSON(configPath, as: BackupConfig.self) else { return false }
        let dest = config.destination

        // Extract volume root (e.g. /Volumes/Toshiba)
        let volumePath = "/" + dest.split(separator: "/").prefix(2).map { String($0) }.joined(separator: "/")
        guard FileManager.default.fileExists(atPath: volumePath) else { return false }

        // Test using /bin/ls via Process (same context as rsync/bash)
        // GUI apps have implicit permissions that terminal processes don't
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ls")
        process.arguments = [volumePath]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus != 0
        } catch {
            return true
        }
    }

    @objc func openPermissions() {
        let alert = NSAlert()
        alert.messageText = "Permisos de disco necesarios"
        alert.informativeText = """
        macOS requiere "Acceso total al disco" para que \
        rsync pueda leer y escribir en discos externos.

        Al pulsar "Abrir Ajustes" se abrira el panel correcto:

        1. Pulsa + y anade estas dos apps:
           /usr/bin/rsync  (Cmd+Shift+G para escribir la ruta)
           /bin/bash
        2. Si usas Terminal o iTerm, anadeslo tambien

        Tras anadirlos, cierra y vuelve a abrir la app.
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Abrir Ajustes")
        alert.addButton(withTitle: "Cancelar")

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()

        if response == .alertFirstButtonReturn {
            // Open Full Disk Access in System Settings
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    @objc func openLog() {
        NSWorkspace.shared.open(URL(fileURLWithPath: logPath))
    }

    @objc func openBackupFolder() {
        let dest = loadJSON(configPath, as: BackupConfig.self)?.destination ?? "/Volumes/Toshiba/dev_apps/"
        if FileManager.default.fileExists(atPath: dest) {
            NSWorkspace.shared.open(URL(fileURLWithPath: dest))
        } else {
            let alert = NSAlert()
            alert.messageText = "Carpeta no disponible"
            alert.informativeText = "El disco de backup no esta montado."
            alert.alertStyle = .warning
            alert.runModal()
        }
    }

    @objc func quit() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Config Window

    @objc func openConfig() {
        if configWindow != nil {
            configWindow?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let config = loadJSON(configPath, as: BackupConfig.self) ?? BackupConfig(
            hour: 10, minute: 0, days: [],
            source: "\(home)/dev/",
            destination: "/Volumes/Toshiba/dev/"
        )

        let windowWidth: CGFloat = 500
        let windowHeight: CGFloat = 340
        let padding: CGFloat = 20
        let rowHeight: CGFloat = 28
        let labelWidth: CGFloat = 80
        let browseWidth: CGFloat = 30

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Configurar Backup"
        window.center()
        window.isReleasedWhenClosed = false

        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight))
        window.contentView = contentView

        var y = windowHeight - padding - rowHeight

        // Source path
        let srcLabel = NSTextField(labelWithString: "Origen:")
        srcLabel.frame = NSRect(x: padding, y: y, width: labelWidth, height: rowHeight)
        srcLabel.font = .systemFont(ofSize: 13, weight: .medium)
        contentView.addSubview(srcLabel)

        let srcFieldWidth = windowWidth - padding - labelWidth - browseWidth - padding - 8
        sourceField = NSTextField(frame: NSRect(x: padding + labelWidth, y: y, width: srcFieldWidth, height: rowHeight))
        sourceField.stringValue = config.source
        sourceField.font = .systemFont(ofSize: 12)
        sourceField.lineBreakMode = .byTruncatingMiddle
        contentView.addSubview(sourceField)

        let srcBrowse = NSButton(title: "...", target: self, action: #selector(browseSource))
        srcBrowse.frame = NSRect(x: windowWidth - padding - browseWidth, y: y, width: browseWidth, height: rowHeight)
        srcBrowse.bezelStyle = .rounded
        contentView.addSubview(srcBrowse)

        // Destination path
        y -= rowHeight + 8
        let dstLabel = NSTextField(labelWithString: "Destino:")
        dstLabel.frame = NSRect(x: padding, y: y, width: labelWidth, height: rowHeight)
        dstLabel.font = .systemFont(ofSize: 13, weight: .medium)
        contentView.addSubview(dstLabel)

        destField = NSTextField(frame: NSRect(x: padding + labelWidth, y: y, width: srcFieldWidth, height: rowHeight))
        destField.stringValue = config.destination
        destField.font = .systemFont(ofSize: 12)
        destField.lineBreakMode = .byTruncatingMiddle
        contentView.addSubview(destField)

        let dstBrowse = NSButton(title: "...", target: self, action: #selector(browseDestination))
        dstBrowse.frame = NSRect(x: windowWidth - padding - browseWidth, y: y, width: browseWidth, height: rowHeight)
        dstBrowse.bezelStyle = .rounded
        contentView.addSubview(dstBrowse)

        // Time section
        y -= rowHeight + 16
        let timeLabel = NSTextField(labelWithString: "Hora:")
        timeLabel.frame = NSRect(x: padding, y: y, width: labelWidth, height: rowHeight)
        timeLabel.font = .systemFont(ofSize: 13, weight: .medium)
        contentView.addSubview(timeLabel)

        hourField = NSTextField(frame: NSRect(x: padding + labelWidth, y: y, width: 45, height: rowHeight))
        hourField.integerValue = config.hour
        hourField.alignment = .center
        hourField.formatter = createNumberFormatter(min: 0, max: 23)
        contentView.addSubview(hourField)

        let colon = NSTextField(labelWithString: ":")
        colon.frame = NSRect(x: padding + labelWidth + 48, y: y, width: 10, height: rowHeight)
        colon.font = .boldSystemFont(ofSize: 14)
        contentView.addSubview(colon)

        minuteField = NSTextField(frame: NSRect(x: padding + labelWidth + 60, y: y, width: 45, height: rowHeight))
        minuteField.integerValue = config.minute
        minuteField.alignment = .center
        minuteField.formatter = createNumberFormatter(min: 0, max: 59)
        contentView.addSubview(minuteField)

        // Days section
        y -= rowHeight + 12
        let daysLabel = NSTextField(labelWithString: "Dias:")
        daysLabel.frame = NSRect(x: padding, y: y, width: labelWidth, height: rowHeight)
        daysLabel.font = .systemFont(ofSize: 13, weight: .medium)
        contentView.addSubview(daysLabel)

        let daysHint = NSTextField(labelWithString: "(vacio = cada dia)")
        daysHint.frame = NSRect(x: padding + labelWidth, y: y, width: 200, height: rowHeight)
        daysHint.font = .systemFont(ofSize: 11)
        daysHint.textColor = .secondaryLabelColor
        contentView.addSubview(daysHint)

        y -= rowHeight + 4
        dayCheckboxes = []
        let checkWidth: CGFloat = 48

        // Row 1: Lun-Jue (1-4)
        for i in 0..<4 {
            let dayIndex = i + 1
            let cb = NSButton(checkboxWithTitle: dayNames[dayIndex], target: nil, action: nil)
            cb.frame = NSRect(x: padding + labelWidth + CGFloat(i) * (checkWidth + 16), y: y, width: checkWidth + 12, height: rowHeight)
            cb.tag = dayIndex
            cb.state = config.days.contains(dayIndex) ? .on : .off
            contentView.addSubview(cb)
            dayCheckboxes.append(cb)
        }

        // Row 2: Vie-Dom (5, 6, 0)
        y -= rowHeight + 2
        let row2Days = [5, 6, 0]
        for (i, dayIndex) in row2Days.enumerated() {
            let cb = NSButton(checkboxWithTitle: dayNames[dayIndex], target: nil, action: nil)
            cb.frame = NSRect(x: padding + labelWidth + CGFloat(i) * (checkWidth + 16), y: y, width: checkWidth + 12, height: rowHeight)
            cb.tag = dayIndex
            cb.state = config.days.contains(dayIndex) ? .on : .off
            contentView.addSubview(cb)
            dayCheckboxes.append(cb)
        }

        // Buttons
        y -= rowHeight + 16

        let saveBtn = NSButton(title: "Guardar", target: self, action: #selector(saveConfig))
        saveBtn.frame = NSRect(x: windowWidth - padding - 90, y: y, width: 90, height: 30)
        saveBtn.bezelStyle = .rounded
        saveBtn.keyEquivalent = "\r"
        contentView.addSubview(saveBtn)

        let cancelBtn = NSButton(title: "Cancelar", target: self, action: #selector(closeConfig))
        cancelBtn.frame = NSRect(x: windowWidth - padding - 190, y: y, width: 90, height: 30)
        cancelBtn.bezelStyle = .rounded
        cancelBtn.keyEquivalent = "\u{1b}"
        contentView.addSubview(cancelBtn)

        configWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func browseSource() {
        if let path = browseFolder(title: "Seleccionar carpeta de origen", current: sourceField.stringValue) {
            sourceField.stringValue = path
        }
    }

    @objc func browseDestination() {
        if let path = browseFolder(title: "Seleccionar carpeta de destino", current: destField.stringValue) {
            destField.stringValue = path
        }
    }

    func browseFolder(title: String, current: String) -> String? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        if FileManager.default.fileExists(atPath: current) {
            panel.directoryURL = URL(fileURLWithPath: current)
        }
        return panel.runModal() == .OK ? panel.url?.path.appending("/") : nil
    }

    @objc func saveConfig() {
        var config = loadJSON(configPath, as: BackupConfig.self) ?? BackupConfig(
            hour: 10, minute: 0, days: [],
            source: "\(home)/Desktop/dev_apps/",
            destination: "/Volumes/Toshiba/dev_apps/"
        )

        config.hour = hourField.integerValue
        config.minute = minuteField.integerValue
        config.days = dayCheckboxes.filter { $0.state == .on }.map { $0.tag }
        config.source = sourceField.stringValue
        config.destination = destField.stringValue

        saveJSON(config, to: configPath)
        regeneratePlist(config: config)
        refreshMenu()
        closeConfig()
    }

    @objc func closeConfig() {
        configWindow?.close()
        configWindow = nil
    }

    func createNumberFormatter(min: Int, max: Int) -> NumberFormatter {
        let f = NumberFormatter()
        f.minimum = NSNumber(value: min)
        f.maximum = NSNumber(value: max)
        f.allowsFloats = false
        f.maximumIntegerDigits = 2
        return f
    }
}

// MARK: - Main

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()

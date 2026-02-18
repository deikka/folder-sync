PREFIX ?= /usr/local
APP_NAME = BackupMenu
APP_BUNDLE = $(APP_NAME).app
SCRIPT_NAME = folder-sync-backup

.PHONY: build install uninstall clean

build:
	@echo "Compilando $(APP_NAME)..."
	swiftc -O -o $(APP_NAME) app/main.swift -framework Cocoa
	@mkdir -p $(APP_BUNDLE)/Contents/MacOS
	@mkdir -p $(APP_BUNDLE)/Contents/Resources
	@mv $(APP_NAME) $(APP_BUNDLE)/Contents/MacOS/
	@cp app/Info.plist $(APP_BUNDLE)/Contents/
	@echo "Build completado: $(APP_BUNDLE)"

install: build
	@echo "Instalando..."
	@mkdir -p $(PREFIX)/bin
	@mkdir -p "$(HOME)/.local/share/backup-dev-apps"
	@mkdir -p "$(HOME)/.local/logs"
	@cp -r $(APP_BUNDLE) $(PREFIX)/bin/
	@cp scripts/backup-dev-apps.sh $(PREFIX)/bin/$(SCRIPT_NAME)
	@chmod +x $(PREFIX)/bin/$(SCRIPT_NAME)
	@if [ ! -f "$(HOME)/.local/share/backup-dev-apps/config.json" ]; then \
		echo '{"hour":10,"minute":0,"days":[],"source":"","destination":""}' \
		> "$(HOME)/.local/share/backup-dev-apps/config.json"; \
	fi
	@echo "Instalado en $(PREFIX)/bin/"
	@echo "  App:    $(PREFIX)/bin/$(APP_BUNDLE)"
	@echo "  Script: $(PREFIX)/bin/$(SCRIPT_NAME)"
	@echo ""
	@echo "Ejecutar: open $(PREFIX)/bin/$(APP_BUNDLE)"

uninstall:
	rm -rf $(PREFIX)/bin/$(APP_BUNDLE)
	rm -f $(PREFIX)/bin/$(SCRIPT_NAME)
	@echo "Desinstalado"

clean:
	rm -rf $(APP_BUNDLE)
	rm -f $(APP_NAME)

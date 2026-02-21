.PHONY: demo demo-clean mdns-clean ui-build help

UI_SCRIPTS_DIR := macos/swiftui/Scripts
UI_LOG := /tmp/cyberspace-testbed-ui.log

mdns-clean:
	@echo "Stopping all _cyberspace._tcp mDNS registrations..."
	@pkill -f "dns-sd -R.*_cyberspace" || true
	@echo "mDNS cleanup done."

demo: mdns-clean
	@echo "Stopping any running CyberspaceMac instances..."
	@pkill -f CyberspaceMac || true
	@echo "Cleaning testbed data..."
	@./$(UI_SCRIPTS_DIR)/realm-harness.sh clean 2>/dev/null || true
	@echo "Launching Testbed UI (logs: $(UI_LOG))..."
	@SPKI_UI_AUDIENCE=builder ./$(UI_SCRIPTS_DIR)/run-local.sh >$(UI_LOG) 2>&1 & \
	pid=$$!; \
	echo "Started PID $$pid"

demo-clean: mdns-clean
	@echo "Stopping any running CyberspaceMac instances..."
	@pkill -f CyberspaceMac || true
	@echo "Removing testbed data..."
	@./$(UI_SCRIPTS_DIR)/realm-harness.sh clean 2>/dev/null || true

ui-build:
	@echo "Building CyberspaceMac UI..."
	@cd macos/swiftui && swift build -c debug --product CyberspaceMac

help:
	@echo "Local Demo Commands:"
	@echo "  make demo        - Stop running UI, clean testbed, relaunch in background"
	@echo "  make demo-clean  - Stop UI and remove testbed data"
	@echo "  make ui-build    - Build CyberspaceMac UI (swift build -c debug --product CyberspaceMac)"
	@echo "  make mdns-clean  - Kill stale _cyberspace._tcp mDNS registrations"

# ==============================================================================
# pi.mk — Reusable Raspberry Pi deploy & admin targets
# Requires in your project's .env: PI, PI_HOST, BINARY_NAME, DB_PATH, SQLITE_RSYNC
# ==============================================================================

PI_HOME := $(shell ssh $(PI) "echo \$$HOME" 2>/dev/null)
APP_DIR  := $(PI_HOME)/apps/$(BINARY_NAME)
SERVICE_NAME := $(BINARY_NAME).service
DB_NAME := $(notdir $(DB_PATH))


.PHONY: setup-pi build-pi setup-service deploy status logs clear-logs db-push db-pull db-optimize-remote db-shell-remote pi-reboot pi-ping pi-health bench

## ---: --- Pi/VPS targets (uncomment 'include ..' in Makefile) ---

## setup-pi: Prepare the Pi with app directories and sqlite3_rsync
setup-pi:
	@if [ -z "$(PI_HOME)" ]; then echo "Error: Could not connect to Pi at '$(PI)'"; exit 1; fi
	@echo "Creating app directory structure..."
	ssh $(PI) "mkdir -p $(APP_DIR) && mkdir -p $(PI_HOME)/.local/bin"
	@echo "Initializing log file..."
	ssh $(PI) "touch $(APP_DIR)/$(BINARY_NAME).log && chmod 666 $(APP_DIR)/$(BINARY_NAME).log"
	@echo "Checking for sqlite3_rsync on Pi..."
	@ssh $(PI) "command -v sqlite3_rsync >/dev/null 2>&1 || { \
		echo 'sqlite3_rsync not found. Installing to ~/.local/bin...'; \
		curl -L https://raw.githubusercontent.com/tcurdt/sqlite3-rsync/main/sqlite3-rsync \
			-o $(PI_HOME)/.local/bin/sqlite3_rsync && \
		chmod +x $(PI_HOME)/.local/bin/sqlite3_rsync; \
	}"
	@echo "\033[0;32mPi is ready!\033[0m"

## build-pi: Compile the binary for Raspberry Pi (linux/arm64)
build-pi: .check-tools
	@mkdir -p tmp
	@if [ -n "$$(git status --porcelain)" ]; then \
		echo "WARNING: There are uncommitted changes"; \
		read "ans?Continue anyway? [y/N]: "; \
		if [[ "$$ans" != "y" ]]; then \
			echo "Build aborted."; \
			exit 1; \
		fi; \
	fi
	@echo "Generating Templ files..."
	@templ generate
	@echo "Building Tailwind CSS..."
	@npx tailwindcss -i ./ui/css/input.css -o ./ui/css/output.css --minify
	@echo "Compiling Go binary for linux/arm64..."
	@GOOS=linux GOARCH=arm64 go build -tags prod $(LDFLAGS) -o $(BINARY_NAME)
	@echo "\033[0;32mBuild complete: ./$(BINARY_NAME)\033[0m"

## setup-service: Install / update the systemd service on the Pi
setup-service:
	@if [ -z "$(PI_HOME)" ]; then echo "Error: Could not connect to Pi at '$(PI)'"; exit 1; fi
	@echo "Checking if service '$(BINARY_NAME)' is already running..."
	@ssh $(PI) "systemctl is-active $(BINARY_NAME) --quiet" && \
		(read "ans?Service is RUNNING. Overwrite config and reload? [y/N]: "; \
		if [[ "$$ans" != "y" ]]; then echo "Aborted."; exit 1; fi) || \
		echo "Service not running. Proceeding..."
	@echo "Uploading service file..."
	@scp ./$(SERVICE_NAME) $(PI):/tmp/$(SERVICE_NAME)
	@echo "Installing and enabling service..."
	@ssh -t $(PI) "sudo mv /tmp/$(SERVICE_NAME) /etc/systemd/system/$(SERVICE_NAME) && \
		sudo systemctl daemon-reload && \
		sudo systemctl enable $(SERVICE_NAME) && \
		sudo systemctl start $(SERVICE_NAME)"
	@echo "\033[0;32mService installed and started!\033[0m"

## deploy: Build for Pi and rsync the binary to the production folder
deploy: .check-tools build-pi
	$(call CHECK_COMMAND,rsync)
	@if [ -z "$(PI_HOME)" ]; then echo "Error: Could not connect to Pi at '$(PI)'"; exit 1; fi
	@echo "Stopping remote service..."
	-@ssh $(PI) "sudo systemctl stop $(BINARY_NAME) 2>/dev/null || true"
	@echo "Deploying $(BINARY_NAME) to $(PI):$(APP_DIR)..."
	rsync -avz ./$(BINARY_NAME) $(PI):$(APP_DIR)/
	@echo "Fixing permissions and restarting..."
	@ssh -t $(PI) "chmod +x $(APP_DIR)/$(BINARY_NAME) && sudo systemctl start $(BINARY_NAME)"
	@echo "\033[0;32mDONE: $(BINARY_NAME) is live on the Pi.\033[0m"

## status: Check service, DB size, disk space, and recent logs
status:
	@if [ -z "$(PI_HOME)" ]; then echo "Error: Could not connect to Pi at '$(PI)'"; exit 1; fi
	@echo "--- Pi Status: $(BINARY_NAME) ---"
	@echo "\nService:"
	@ssh $(PI) "systemctl is-active $(BINARY_NAME) --quiet \
		&& echo '\033[0;32m● Running\033[0m' \
		|| echo '\033[0;31m○ Stopped\033[0m'"
	@echo "\nFiles:"
	@ssh $(PI) "ls -lh $(APP_DIR)/$(DB_NAME) $(APP_DIR)/$(BINARY_NAME).log 2>/dev/null \
		| awk '{printf \"%-40s | Size: %s\n\", \$$9, \$$5}'"
	@echo "\nDisk usage:"
	@ssh $(PI) "df -h / | awk 'NR==2 {print \"Used: \" \$$3 \" / \" \$$2 \" (\" \$$5 \" full)\"}'"
	@echo "\nLast 5 log lines:"
	@ssh $(PI) "tail -n 5 $(APP_DIR)/$(BINARY_NAME).log 2>/dev/null || echo 'Log not found.'"

## logs: Tail the app log in real-time
logs:
	@if [ -z "$(PI_HOME)" ]; then echo "Error: Could not connect to Pi at '$(PI)'"; exit 1; fi
	ssh $(PI) "tail -f $(APP_DIR)/$(BINARY_NAME).log"

## clear-logs: Truncate the app log on the Pi
clear-logs:
	@if [ -z "$(PI_HOME)" ]; then echo "Error: Could not connect to Pi at '$(PI)'"; exit 1; fi
	ssh $(PI) "truncate -s 0 $(APP_DIR)/$(BINARY_NAME).log"
	@echo "Logs cleared."

## db-push: Push the local database to the Pi (Mac -> Pi)
db-push:
	@if [ -z "$(PI_HOME)" ]; then echo "Error: Could not connect to Pi at '$(PI)'"; exit 1; fi
	@echo "Creating remote backup first..."
	ssh $(PI) "cp $(APP_DIR)/$(DB_NAME) $(APP_DIR)/$(DB_NAME).bak 2>/dev/null || true"
	@read "ans?Overwrite production database on Pi? [y/N]: "; \
	if [[ "$$ans" != "y" ]]; then echo "Aborted."; exit 1; fi
	$(SQLITE_RSYNC) ./$(DB_NAME) $(PI):$(APP_DIR)/$(DB_NAME) \
		--exe "$(PI_HOME)/.local/bin/sqlite3_rsync"
	@echo "\033[0;32mDatabase pushed.\033[0m"

## db-pull: Pull the Pi database to local (Pi -> Mac)
db-pull:
	@if [ -z "$(PI_HOME)" ]; then echo "Error: Could not connect to Pi at '$(PI)'"; exit 1; fi
	@echo "Backing up local database..."
	@cp ./$(DB_NAME) ./$(DB_NAME).bak 2>/dev/null || true
	$(SQLITE_RSYNC) $(PI):$(APP_DIR)/$(DB_NAME) ./$(DB_NAME).debug \
		--exe "$(PI_HOME)/.local/bin/sqlite3_rsync"
	@echo "\033[0;32mDatabase pulled to ./$(DB_NAME).debug\033[0m"

## db-optimize-remote: Run VACUUM and ANALYZE on the Pi database
db-optimize-remote:
	@if [ -z "$(PI_HOME)" ]; then echo "Error: Could not connect to Pi at '$(PI)'"; exit 1; fi
	@echo "Optimizing $(DB_NAME) on Pi..."
	@ssh $(PI) "sqlite3 $(APP_DIR)/$(DB_NAME) 'VACUUM; ANALYZE;'"
	@echo "\033[0;32mOptimization complete.\033[0m"
	@ssh $(PI) "ls -lh $(APP_DIR)/$(DB_NAME) | awk '{print \"New size: \" \$$5}'"

## db-shell-remote: Open a SQLite shell on the Pi database
db-shell-remote:
	@if [ -z "$(PI_HOME)" ]; then echo "Error: Could not connect to Pi at '$(PI)'"; exit 1; fi
	ssh -t $(PI) "sqlite3 -column -header $(APP_DIR)/$(DB_NAME)"


## bench: Run a 500MB sequential write benchmark on the Pi NVMe drive
bench:
	@if [ -z "$(PI_HOME)" ]; then echo "Error: Could not connect to Pi at '$(PI)'"; exit 1; fi
	@echo "Running 500MB write benchmark..."
	@ssh $(PI) "dd if=/dev/zero of=$(APP_DIR)/.bench bs=1M count=500 conv=fdatasync 2>&1 | grep 'copied'"
	@ssh $(PI) "rm -f $(APP_DIR)/.bench"

## pi-reboot: Gracefully stop the app, sync, and reboot the Pi
pi-reboot:
	@if [ -z "$(PI_HOME)" ]; then echo "Error: Could not connect to Pi at '$(PI)'"; exit 1; fi
	@read "ans?This will reboot the Pi. Continue? [y/N]: "; \
	if [[ "$$ans" != "y" ]]; then echo "Aborted."; exit 1; fi
	@echo "Stopping $(SERVICE_NAME)..."
	-@ssh $(PI) "sudo systemctl stop $(BINARY_NAME)"
	@echo "Syncing filesystem..."
	@ssh $(PI) "sync"
	@echo "\033[0;33mRebooting Pi. Connection will close.\033[0m"
	-@ssh $(PI) "sudo reboot"
	@sleep 5
	@$(MAKE) pi-ping


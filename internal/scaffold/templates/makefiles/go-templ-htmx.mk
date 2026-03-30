# ==============================================================================
# go-templ-htmx.mk — Reusable build targets for Go + Templ + HTMX projects
# Requires in your project's .env: BINARY_NAME, APP_PORT
# ==============================================================================

SHELL := /bin/zsh

GIT_HASH := $(shell git rev-parse --short HEAD 2>/dev/null || echo "no-git")
DATE     := $(shell date +%Y-%m-%d_%H:%M:%S)
LDFLAGS  := -ldflags "-s -w -X 'main.Version=$(GIT_HASH)' -X 'main.BuildTime=$(DATE)'"

.PHONY: dev build-pi build-mac clean .check-tools

# Helper to check if a command exists
CHECK_COMMAND = @command -v $(1) >/dev/null 2>&1 || { echo "\033[0;31mError: $(1) is not installed.\033[0m"; exit 1; }

.check-tools:
	$(call CHECK_COMMAND,go)
	$(call CHECK_COMMAND,templ)
	$(call CHECK_COMMAND,npx)
	$(call CHECK_COMMAND,air)
	$(call CHECK_COMMAND,sqlite3_rsync)

## dev: Start the dev environment with hot-reloading
dev: .check-tools
	@mkdir -p tmp
	@if [ -n "$(PORT)" ]; then \
		echo "Clearing port $(PORT)…"; \
		lsof -ti:$(PORT) | xargs kill -9 2>/dev/null || true; \
	fi
	@templ generate
	@npx tailwindcss -i ./static/css/input.css -o ./static/css/output.css
	@echo "Starting development mode..."
	@APP_ENV=dev npx tailwindcss -i ./ui/css/input.css -o ./ui/css/output.css --watch & \
	APP_ENV=dev air; \
	kill %1

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

## build-mac: Compile the binary for macOS
build-mac: .check-tools
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
	@echo "Compiling Go binary for macOS..."
	@go build $(LDFLAGS) -o $(BINARY_NAME)
	@echo "\033[0;32mBuild complete: ./$(BINARY_NAME)\033[0m"

## clean: Remove temp files, binary, and generated Templ code
clean:
	@echo "Cleaning up..."
	rm -rf tmp/
	rm -f $(BINARY_NAME)
	find . -name "*_templ.go" -delete
	@echo "Cleaned."

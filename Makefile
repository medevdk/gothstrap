BINARY := gothstrap

.PHONY: setup build run install test clean help

## setup: fetch dependencies and build
setup:
	go mod tidy
	go build -o $(BINARY) .
	@echo "✅ Ready. Run ./$(BINARY) or 'make install' to install globally."

## build: compile the gothstrap binary
build:
	go build -o $(BINARY) .

## run: build and run interactively
run: build
	./$(BINARY)

## install: install to $GOPATH/bin
install:
	go install .

## test: run all tests
test:
	go test ./...

## clean: remove binary
clean:
	rm -f $(BINARY)

## help: display this help message
help:
	@grep -E '^##' $(MAKEFILE_LIST) | sed -e 's/## //g' | column -t -s ':'

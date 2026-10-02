PREFIX ?= /usr/local
DIR = $(PREFIX)/libexec/container-plugins/netpath

build:
	swift build -c release

test:
	swift test

# Run `make build` first, as your user. This step only copies files.
install:
	install -d $(DIR)/bin
	install .build/release/netpath $(DIR)/bin/netpath
	install -m 644 config.toml $(DIR)/config.toml

uninstall:
	rm -rf $(DIR)

.PHONY: build test install uninstall

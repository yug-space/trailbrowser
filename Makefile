# Build TrailBrowser. `make` auto-selects the native target for your OS.

UNAME_S := $(shell uname -s)
CC ?= cc
OBJCFLAGS = -Wall -Wextra -O2 -fobjc-arc
CFLAGS = -Wall -Wextra -Os

APP_NAME = TrailBrowser
APP_BUNDLE = $(APP_NAME).app
APP_BIN = $(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)
APP_PLIST = $(APP_BUNDLE)/Contents/Info.plist
APP_RESOURCES_DIR = $(APP_BUNDLE)/Contents/Resources
APP_SOURCES = mac-browser/main.m \
              mac-browser/BrowserAppDelegate.m \
              mac-browser/BrowserTab.m \
              mac-browser/BrowserTabViews.m \
              mac-browser/TBControls.m \
              mac-browser/TBTheme.m \
              mac-browser/ChromeCookieImporter.m
APP_HEADERS = mac-browser/BrowserAppDelegate.h \
              mac-browser/BrowserTab.h \
              mac-browser/BrowserTabViews.h \
              mac-browser/TBControls.h \
              mac-browser/TBTheme.h \
              mac-browser/ChromeCookieImporter.h
APP_HOME_RESOURCES = mac-browser/home/Home.html mac-browser/home/Home.css mac-browser/home/Home.js \
                     mac-browser/home/Settings.html mac-browser/home/Settings.css mac-browser/home/Settings.js
APP_FRAMEWORKS = -framework Cocoa -framework WebKit -framework Security -framework QuartzCore
APP_LIBS = -lsqlite3

LINUX_BIN = trailbrowser
LINUX_SOURCE = linux-browser/trailbrowser.c
PKG_CONFIG ?= pkg-config
MCP_DIR = mcp-history-server

ifeq ($(UNAME_S),Linux)
WEBKITGTK_PKG := $(shell $(PKG_CONFIG) --exists webkit2gtk-4.1 2>/dev/null && echo webkit2gtk-4.1 || echo webkit2gtk-4.0)
LINUX_CFLAGS = $(CFLAGS) $(shell $(PKG_CONFIG) --cflags gtk+-3.0 $(WEBKITGTK_PKG) 2>/dev/null)
LINUX_LIBS = $(shell $(PKG_CONFIG) --libs gtk+-3.0 $(WEBKITGTK_PKG) 2>/dev/null)
endif

ifeq ($(UNAME_S),Darwin)
all: mac
else ifeq ($(UNAME_S),Linux)
all: linux
else
all:
	$(error Unsupported OS: $(UNAME_S))
endif

mac: $(APP_BIN) $(APP_PLIST) mac-resources # Build native macOS WebKit browser app
mini_browser: mac                  # Backward-compatible alias

$(APP_BIN): $(APP_SOURCES) $(APP_HEADERS)
	mkdir -p $(APP_BUNDLE)/Contents/MacOS
	$(CC) $(OBJCFLAGS) $(APP_FRAMEWORKS) $(APP_LIBS) -o $(APP_BIN) $(APP_SOURCES)

$(APP_PLIST): mac-browser/Info.plist
	mkdir -p $(APP_BUNDLE)/Contents
	cp mac-browser/Info.plist $(APP_PLIST)

mac-resources: $(APP_HOME_RESOURCES)
	mkdir -p $(APP_RESOURCES_DIR)/home
	cp $(APP_HOME_RESOURCES) $(APP_RESOURCES_DIR)/home/

linux: $(LINUX_BIN)                # Build lightweight Linux GTK/WebKitGTK app

$(LINUX_BIN): $(LINUX_SOURCE)
	@$(PKG_CONFIG) --exists gtk+-3.0 $(WEBKITGTK_PKG) || \
		(echo "Missing Linux deps. Install: sudo apt install build-essential pkg-config libgtk-3-dev libwebkit2gtk-4.1-dev"; exit 1)
	$(CC) $(LINUX_CFLAGS) -o $(LINUX_BIN) $(LINUX_SOURCE) $(LINUX_LIBS)

run-browser: all                   # Open/run the native app for this OS
ifeq ($(UNAME_S),Darwin)
	open $(APP_BUNDLE)
else ifeq ($(UNAME_S),Linux)
	./$(LINUX_BIN)
else
	$(error Unsupported OS: $(UNAME_S))
endif

mcp-install:                       # Install MCP server dependencies
	cd $(MCP_DIR) && npm install

run-history-mcp:                   # Run read-only history MCP server over stdio
	cd $(MCP_DIR) && npm start

clean:                             # Remove built binaries
	rm -rf $(APP_BUNDLE)
	rm -f $(LINUX_BIN)

.PHONY: all mac linux mini_browser mac-resources run-browser mcp-install run-history-mcp clean

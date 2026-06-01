# Build TrailBrowser — a native macOS WebKit browser shell.

CC ?= cc
OBJCFLAGS = -Wall -Wextra -O2 -fobjc-arc

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
                     mac-browser/home/Settings.html mac-browser/home/Settings.css mac-browser/home/Settings.js \
                     mac-browser/home/Onboarding.html mac-browser/home/Onboarding.css mac-browser/home/Onboarding.js
APP_FRAMEWORKS = -framework Cocoa -framework WebKit -framework Security -framework QuartzCore -framework UniformTypeIdentifiers
APP_LIBS = -lsqlite3

APP_ICON = assets/TrailBrowser.icns

MCP_DIR = mcp-history-server

all: mac                           # Build the native macOS WebKit browser app

mac: $(APP_BIN) $(APP_PLIST) mac-resources mac-icon

$(APP_BIN): $(APP_SOURCES) $(APP_HEADERS)
	mkdir -p $(APP_BUNDLE)/Contents/MacOS
	$(CC) $(OBJCFLAGS) -o $(APP_BIN) $(APP_SOURCES) $(APP_FRAMEWORKS) $(APP_LIBS)

$(APP_PLIST): mac-browser/Info.plist
	mkdir -p $(APP_BUNDLE)/Contents
	cp mac-browser/Info.plist $(APP_PLIST)

mac-resources: $(APP_HOME_RESOURCES)
	mkdir -p $(APP_RESOURCES_DIR)/home
	cp $(APP_HOME_RESOURCES) $(APP_RESOURCES_DIR)/home/

mac-icon: $(APP_ICON)
	mkdir -p $(APP_RESOURCES_DIR)
	cp $(APP_ICON) $(APP_RESOURCES_DIR)/TrailBrowser.icns

# Regenerate the .icns from the source SVG (needs rsvg-convert + iconutil).
icon: assets/trailbrowser-icon.svg
	rm -rf $(APP_NAME).iconset && mkdir -p $(APP_NAME).iconset
	for sz in 16 32 128 256 512; do \
	  rsvg-convert -w $$sz -h $$sz assets/trailbrowser-icon.svg -o $(APP_NAME).iconset/icon_$${sz}x$${sz}.png; \
	  rsvg-convert -w $$((sz*2)) -h $$((sz*2)) assets/trailbrowser-icon.svg -o $(APP_NAME).iconset/icon_$${sz}x$${sz}@2x.png; \
	done
	iconutil -c icns $(APP_NAME).iconset -o $(APP_ICON)
	rm -rf $(APP_NAME).iconset

run-browser: all                   # Build and open the app
	open $(APP_BUNDLE)

mcp-install:                       # Install MCP server dependencies
	cd $(MCP_DIR) && npm install

run-history-mcp:                   # Run read-only history MCP server over stdio
	cd $(MCP_DIR) && npm start

clean:                             # Remove the built app and MCP dependencies
	rm -rf $(APP_BUNDLE) $(MCP_DIR)/node_modules

.PHONY: all mac mac-resources mac-icon icon run-browser mcp-install run-history-mcp clean

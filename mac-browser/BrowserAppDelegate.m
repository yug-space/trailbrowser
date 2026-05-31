#import "BrowserAppDelegate.h"

#import <QuartzCore/QuartzCore.h>

#import "BrowserTab.h"
#import "BrowserTabViews.h"
#import "ChromeCookieImporter.h"
#import "TBControls.h"
#import "TBTheme.h"

@interface BrowserAppDelegate ()
@property (nonatomic, assign) NSInteger tabActivationCounter;
@property (nonatomic, strong) dispatch_source_t memoryPressureSource;
@property (nonatomic, strong) NSMutableArray<BrowserTab *> *preloadQueue;
@property (nonatomic, strong) NSMutableSet<WKWebView *> *preloadingWebViews;
@end

@implementation BrowserAppDelegate

static const NSInteger kMaxLiveTabs = 24;
static const NSInteger kMaxConcurrentPreloads = 2;

static void *BrowserProgressContext = &BrowserProgressContext;
static void *BrowserURLContext = &BrowserURLContext;
static void *BrowserCanGoBackContext = &BrowserCanGoBackContext;
static void *BrowserCanGoForwardContext = &BrowserCanGoForwardContext;

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    (void)notification;

    [self buildMenu];
    [self buildWindow];
    [self writeBrowserStateRunning:YES];
    [self startMemoryPressureMonitor];

    NSArray<NSString *> *urlArgs = [self launchURLArguments];
    if (urlArgs.count > 0) {
        for (NSUInteger i = 0; i < urlArgs.count; i++) {
            [self newTabWithURLString:urlArgs[i] select:(i == urlArgs.count - 1)];
        }
        return;
    }

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    BOOL onboarded = [defaults boolForKey:@"TBHasOnboarded"];
    if (!onboarded) {
        [defaults setBool:YES forKey:@"TBHasOnboarded"];
        [self newTabWithURLString:[self onboardingURLString] select:YES];
    } else {
        [self newTabWithURLString:[self homeURLString] select:YES];
    }
}

- (NSArray<NSString *> *)launchURLArguments {
    NSMutableArray<NSString *> *urls = [NSMutableArray array];
    for (NSString *arg in [NSProcessInfo processInfo].arguments) {
        if ([arg hasPrefix:@"http://"] || [arg hasPrefix:@"https://"]) [urls addObject:arg];
    }
    return urls;
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    (void)sender;
    return YES;
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    (void)notification;
    [self writeBrowserStateRunning:NO];
}

- (void)dealloc {
    for (BrowserTab *tab in self.tabs) {
        [self removeObserversFromWebView:tab.webView];
        [tab.webView stopLoading];
    }
}

- (void)buildMenu {
    NSMenu *mainMenu = [[NSMenu alloc] initWithTitle:@""];

    NSMenuItem *appMenuItem = [[NSMenuItem alloc] initWithTitle:@"TrailBrowser"
                                                         action:nil
                                                  keyEquivalent:@""];
    [mainMenu addItem:appMenuItem];

    NSMenu *appMenu = [[NSMenu alloc] initWithTitle:@"TrailBrowser"];
    [self addMenuItem:@"Settings…" action:@selector(openSettings:) key:@"," menu:appMenu];
    [self addMenuItem:@"Import Cookies from Chrome…"
               action:@selector(importChromeCookies:)
                  key:@""
                 menu:appMenu];
    [appMenu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *quitItem = [[NSMenuItem alloc] initWithTitle:@"Quit TrailBrowser"
                                                      action:@selector(terminate:)
                                               keyEquivalent:@"q"];
    [appMenu addItem:quitItem];
    [appMenuItem setSubmenu:appMenu];

    NSMenuItem *navMenuItem = [[NSMenuItem alloc] initWithTitle:@"Navigate"
                                                         action:nil
                                                  keyEquivalent:@""];
    [mainMenu addItem:navMenuItem];

    NSMenu *navMenu = [[NSMenu alloc] initWithTitle:@"Navigate"];
    [self addMenuItem:@"Open Location" action:@selector(focusAddressBar:) key:@"l" menu:navMenu];
    [self addMenuItem:@"Toggle Sidebar" action:@selector(toggleSidebar:) key:@"b" menu:navMenu];
    [self addMenuItem:@"New Tab" action:@selector(newTab:) key:@"t" menu:navMenu];
    [self addMenuItem:@"Close Tab" action:@selector(closeCurrentTab:) key:@"w" menu:navMenu];
    [navMenu addItem:[NSMenuItem separatorItem]];
    [self addMenuItem:@"Home" action:@selector(goHome:) key:@"" menu:navMenu];
    [self addMenuItem:@"Reload" action:@selector(reloadPage:) key:@"r" menu:navMenu];
    [navMenu addItem:[NSMenuItem separatorItem]];
    [self addMenuItem:@"Back" action:@selector(goBack:) key:@"[" menu:navMenu];
    [self addMenuItem:@"Forward" action:@selector(goForward:) key:@"]" menu:navMenu];
    [navMenuItem setSubmenu:navMenu];

    NSMenuItem *editMenuItem = [[NSMenuItem alloc] initWithTitle:@"Edit" action:nil keyEquivalent:@""];
    [mainMenu addItem:editMenuItem];
    NSMenu *editMenu = [[NSMenu alloc] initWithTitle:@"Edit"];
    [self addEditItem:@"Undo" action:@selector(undo:) key:@"z" shift:NO menu:editMenu];
    [self addEditItem:@"Redo" action:@selector(redo:) key:@"z" shift:YES menu:editMenu];
    [editMenu addItem:[NSMenuItem separatorItem]];
    [self addEditItem:@"Cut" action:@selector(cut:) key:@"x" shift:NO menu:editMenu];
    [self addEditItem:@"Copy" action:@selector(copy:) key:@"c" shift:NO menu:editMenu];
    [self addEditItem:@"Paste" action:@selector(paste:) key:@"v" shift:NO menu:editMenu];
    [self addEditItem:@"Select All" action:@selector(selectAll:) key:@"a" shift:NO menu:editMenu];
    [editMenuItem setSubmenu:editMenu];

    [NSApp setMainMenu:mainMenu];
}

- (void)addMenuItem:(NSString *)title action:(SEL)action key:(NSString *)key menu:(NSMenu *)menu {
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:action keyEquivalent:key];
    item.target = self;
    item.keyEquivalentModifierMask = NSEventModifierFlagCommand;
    [menu addItem:item];
}

- (void)addEditItem:(NSString *)title action:(SEL)action key:(NSString *)key shift:(BOOL)shift menu:(NSMenu *)menu {
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:action keyEquivalent:key];
    item.keyEquivalentModifierMask = shift
        ? (NSEventModifierFlagCommand | NSEventModifierFlagShift)
        : NSEventModifierFlagCommand;
    [menu addItem:item];
}

- (void)buildWindow {
    self.tabs = [NSMutableArray array];
    self.activeTabIndex = -1;
    self.sidebarVisible = YES;

    NSRect frame = NSMakeRect(0, 0, 1200, 760);
    NSWindowStyleMask style = NSWindowStyleMaskTitled |
                              NSWindowStyleMaskClosable |
                              NSWindowStyleMaskMiniaturizable |
                              NSWindowStyleMaskResizable |
                              NSWindowStyleMaskFullSizeContentView;

    self.window = [[NSWindow alloc] initWithContentRect:frame
                                              styleMask:style
                                                backing:NSBackingStoreBuffered
                                                  defer:NO];
    self.window.title = @"TrailBrowser";
    self.window.titleVisibility = NSWindowTitleHidden;
    self.window.titlebarAppearsTransparent = YES;
    self.window.minSize = NSMakeSize(860, 560);
    if (@available(macOS 11.0, *)) {
        self.window.toolbarStyle = NSWindowToolbarStyleUnifiedCompact;
        self.window.titlebarSeparatorStyle = NSTitlebarSeparatorStyleNone;
    }
    [self.window center];

    self.window.backgroundColor = TBBg();
    self.window.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];

    NSView *root = [[NSView alloc] initWithFrame:NSZeroRect];
    root.translatesAutoresizingMaskIntoConstraints = NO;
    root.wantsLayer = YES;
    root.layer.backgroundColor = TBBg().CGColor;
    self.window.contentView = root;

    NSView *toolbar = [[NSView alloc] initWithFrame:NSZeroRect];
    toolbar.translatesAutoresizingMaskIntoConstraints = NO;
    toolbar.wantsLayer = YES;
    toolbar.layer.backgroundColor = TBSurface().CGColor;
    self.toolbar = toolbar;
    [root addSubview:toolbar];

    NSView *toolbarHairline = [self hairlineView];
    [toolbar addSubview:toolbarHairline];

    self.backButton = [self toolbarButtonWithSymbol:@"chevron.left"
                                           fallback:@"<"
                                            tooltip:@"Back"
                                             action:@selector(goBack:)];
    self.forwardButton = [self toolbarButtonWithSymbol:@"chevron.right"
                                              fallback:@">"
                                               tooltip:@"Forward"
                                                action:@selector(goForward:)];
    self.sidebarToggleButton = [self toolbarButtonWithSymbol:@"sidebar.left"
                                                    fallback:@"S"
                                                     tooltip:@"Toggle Sidebar"
                                                      action:@selector(toggleSidebar:)];
    self.reloadButton = [self toolbarButtonWithSymbol:@"arrow.clockwise"
                                             fallback:@"R"
                                              tooltip:@"Reload"
                                               action:@selector(reloadPage:)];
    self.plusButton = [self toolbarButtonWithSymbol:@"plus"
                                             fallback:@"+"
                                              tooltip:@"New Tab"
                                               action:@selector(newTab:)];

    NSView *navDivider = [self hairlineView];
    [toolbar addSubview:navDivider];

    self.addressContainer = [[TBFieldContainer alloc] initWithFrame:NSZeroRect];
    self.addressContainer.translatesAutoresizingMaskIntoConstraints = NO;
    [toolbar addSubview:self.addressContainer];

    NSImageView *addressIcon = [[NSImageView alloc] initWithFrame:NSZeroRect];
    addressIcon.translatesAutoresizingMaskIntoConstraints = NO;
    addressIcon.imageScaling = NSImageScaleProportionallyDown;
    if (@available(macOS 11.0, *)) {
        NSImage *glyph = [NSImage imageWithSystemSymbolName:@"magnifyingglass" accessibilityDescription:@"Search"];
        glyph.template = YES;
        addressIcon.image = glyph;
    }
    if (@available(macOS 10.14, *)) addressIcon.contentTintColor = TBFaint();
    [self.addressContainer addSubview:addressIcon];

    self.addressField = [[NSTextField alloc] initWithFrame:NSZeroRect];
    self.addressField.translatesAutoresizingMaskIntoConstraints = NO;
    self.addressField.bezeled = NO;
    self.addressField.bordered = NO;
    self.addressField.drawsBackground = NO;
    self.addressField.focusRingType = NSFocusRingTypeNone;
    self.addressField.editable = YES;
    self.addressField.selectable = YES;
    self.addressField.textColor = TBText();
    self.addressField.font = [NSFont systemFontOfSize:13.5 weight:NSFontWeightRegular];
    self.addressField.placeholderAttributedString =
        [[NSAttributedString alloc] initWithString:@"Search or enter website name"
                                        attributes:@{ NSForegroundColorAttributeName: TBFaint(),
                                                      NSFontAttributeName: [NSFont systemFontOfSize:13.5 weight:NSFontWeightRegular] }];
    self.addressField.delegate = self;
    self.addressField.target = self;
    self.addressField.action = @selector(loadFromAddressField:);
    if (@available(macOS 10.12.2, *)) self.addressField.allowsCharacterPickerTouchBarItem = NO;
    [self.addressContainer addSubview:self.addressField];

    ((TBFlatButton *)self.sidebarToggleButton).active = self.sidebarVisible;

    self.statusDot = [[NSView alloc] initWithFrame:NSZeroRect];
    self.statusDot.translatesAutoresizingMaskIntoConstraints = NO;
    self.statusDot.wantsLayer = YES;
    self.statusDot.layer.cornerRadius = 3.0;
    self.statusDot.layer.backgroundColor = TBOk().CGColor;
    self.statusDot.toolTip = @"Ready";
    [toolbar addSubview:self.statusDot];

    self.askButton = [[TBPillButton alloc] initWithFrame:NSZeroRect];
    self.askButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.askButton.pillStyle = TBPillStyleAccent;
    self.askButton.title = @"Ask";
    self.askButton.toolTip = @"Open assistant";
    self.askButton.target = self;
    self.askButton.action = @selector(openAssistant:);
    [toolbar addSubview:self.askButton];

    self.settingsButton = [self toolbarButtonWithSymbol:@"gearshape"
                                               fallback:@"S"
                                                tooltip:@"Settings"
                                                 action:@selector(openSettings:)];
    [toolbar addSubview:self.settingsButton];

    self.progressBar = [[TBProgressBar alloc] initWithFrame:NSZeroRect];
    self.progressBar.translatesAutoresizingMaskIntoConstraints = NO;
    self.progressBar.hidden = YES;
    [toolbar addSubview:self.progressBar];

    NSView *contentArea = [[NSView alloc] initWithFrame:NSZeroRect];
    contentArea.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:contentArea];

    self.sidebar = [[NSView alloc] initWithFrame:NSZeroRect];
    self.sidebar.translatesAutoresizingMaskIntoConstraints = NO;
    self.sidebar.wantsLayer = YES;
    self.sidebar.layer.backgroundColor = TBSurface().CGColor;
    [contentArea addSubview:self.sidebar];

    self.sidebarSeparator = [self hairlineView];
    [contentArea addSubview:self.sidebarSeparator];

    self.webContainer = [[NSView alloc] initWithFrame:NSZeroRect];
    self.webContainer.translatesAutoresizingMaskIntoConstraints = NO;
    self.webContainer.wantsLayer = YES;
    self.webContainer.layer.backgroundColor = TBBg().CGColor;
    [contentArea addSubview:self.webContainer];
    [self buildAssistantOverlay];

    NSView *tabHeader = [[NSView alloc] initWithFrame:NSZeroRect];
    tabHeader.translatesAutoresizingMaskIntoConstraints = NO;
    [self.sidebar addSubview:tabHeader];

    NSTextField *tabTitle = [self sectionHeaderLabel:@"TABS"];
    [tabHeader addSubview:tabTitle];

    self.tabCountLabel = [NSTextField labelWithString:@"0"];
    self.tabCountLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.tabCountLabel.font = [NSFont monospacedDigitSystemFontOfSize:11.0 weight:NSFontWeightSemibold];
    self.tabCountLabel.textColor = TBFaint();
    [tabHeader addSubview:self.tabCountLabel];

    self.addTabButton = [self sidebarButtonWithSymbol:@"plus"
                                             fallback:@"+"
                                              tooltip:@"New Tab"
                                               action:@selector(newTab:)];
    self.closeTabButton = [self sidebarButtonWithSymbol:@"xmark"
                                               fallback:@"x"
                                                tooltip:@"Close Tab"
                                                 action:@selector(closeCurrentTab:)];
    [tabHeader addSubview:self.addTabButton];
    [tabHeader addSubview:self.closeTabButton];

    self.tabTable = [[NSTableView alloc] initWithFrame:NSZeroRect];
    self.tabTable.translatesAutoresizingMaskIntoConstraints = NO;
    self.tabTable.headerView = nil;
    self.tabTable.rowHeight = 46.0;
    self.tabTable.intercellSpacing = NSMakeSize(0, 2);
    self.tabTable.selectionHighlightStyle = NSTableViewSelectionHighlightStyleNone;
    self.tabTable.backgroundColor = NSColor.clearColor;
    self.tabTable.usesAlternatingRowBackgroundColors = NO;
    self.tabTable.allowsEmptySelection = NO;
    self.tabTable.focusRingType = NSFocusRingTypeNone;
    self.tabTable.dataSource = self;
    self.tabTable.delegate = self;

    if (@available(macOS 11.0, *)) self.tabTable.style = NSTableViewStylePlain;

    NSTableColumn *tabColumn = [[NSTableColumn alloc] initWithIdentifier:@"TabColumn"];
    tabColumn.resizingMask = NSTableColumnAutoresizingMask;
    tabColumn.width = 200.0;
    [self.tabTable addTableColumn:tabColumn];

    NSScrollView *tabScrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    tabScrollView.translatesAutoresizingMaskIntoConstraints = NO;
    tabScrollView.documentView = self.tabTable;
    tabScrollView.hasVerticalScroller = YES;
    tabScrollView.autohidesScrollers = YES;
    tabScrollView.scrollerStyle = NSScrollerStyleOverlay;
    tabScrollView.borderType = NSNoBorder;
    tabScrollView.drawsBackground = NO;
    [self.sidebar addSubview:tabScrollView];

    NSView *settingsDivider = [self hairlineView];
    [self.sidebar addSubview:settingsDivider];

    TBFlatButton *settingsRow = [self sidebarRowWithSymbol:@"gearshape"
                                                     title:@"Settings"
                                                    action:@selector(openSettings:)];
    [self.sidebar addSubview:settingsRow];

    for (NSView *view in @[ self.sidebarToggleButton, self.backButton, self.forwardButton,
                           self.addressContainer, self.reloadButton, self.statusDot, self.plusButton,
                           self.askButton, self.settingsButton, self.progressBar ]) {
        [toolbar addSubview:view];
    }

    self.sidebarWidthConstraint = [self.sidebar.widthAnchor constraintEqualToConstant:240.0];

    NSLayoutConstraint *addressCenter = [self.addressContainer.centerXAnchor constraintEqualToAnchor:toolbar.centerXAnchor];
    addressCenter.priority = NSLayoutPriorityDefaultHigh - 1;
    NSLayoutConstraint *addressWidth = [self.addressContainer.widthAnchor constraintEqualToConstant:620.0];
    addressWidth.priority = NSLayoutPriorityDefaultHigh;

    [NSLayoutConstraint activateConstraints:@[
        [toolbar.topAnchor constraintEqualToAnchor:root.topAnchor],
        [toolbar.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],
        [toolbar.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],
        [toolbar.heightAnchor constraintEqualToConstant:46.0],

        [toolbarHairline.leadingAnchor constraintEqualToAnchor:toolbar.leadingAnchor],
        [toolbarHairline.trailingAnchor constraintEqualToAnchor:toolbar.trailingAnchor],
        [toolbarHairline.bottomAnchor constraintEqualToAnchor:toolbar.bottomAnchor],
        [toolbarHairline.heightAnchor constraintEqualToConstant:1.0],

        [self.sidebarToggleButton.leadingAnchor constraintEqualToAnchor:toolbar.leadingAnchor constant:88.0],
        [self.sidebarToggleButton.centerYAnchor constraintEqualToAnchor:toolbar.centerYAnchor],

        [self.backButton.leadingAnchor constraintEqualToAnchor:self.sidebarToggleButton.trailingAnchor constant:8.0],
        [self.backButton.centerYAnchor constraintEqualToAnchor:toolbar.centerYAnchor],

        [navDivider.leadingAnchor constraintEqualToAnchor:self.backButton.trailingAnchor constant:5.0],
        [navDivider.centerYAnchor constraintEqualToAnchor:toolbar.centerYAnchor],
        [navDivider.widthAnchor constraintEqualToConstant:1.0],
        [navDivider.heightAnchor constraintEqualToConstant:14.0],

        [self.forwardButton.leadingAnchor constraintEqualToAnchor:navDivider.trailingAnchor constant:5.0],
        [self.forwardButton.centerYAnchor constraintEqualToAnchor:toolbar.centerYAnchor],

        addressCenter,
        addressWidth,
        [self.addressContainer.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.forwardButton.trailingAnchor constant:16.0],
        [self.addressContainer.trailingAnchor constraintLessThanOrEqualToAnchor:self.reloadButton.leadingAnchor constant:-16.0],
        [self.addressContainer.centerYAnchor constraintEqualToAnchor:toolbar.centerYAnchor],
        [self.addressContainer.heightAnchor constraintEqualToConstant:32.0],

        [addressIcon.leadingAnchor constraintEqualToAnchor:self.addressContainer.leadingAnchor constant:12.0],
        [addressIcon.centerYAnchor constraintEqualToAnchor:self.addressContainer.centerYAnchor],
        [addressIcon.widthAnchor constraintEqualToConstant:14.0],
        [addressIcon.heightAnchor constraintEqualToConstant:14.0],

        [self.addressField.leadingAnchor constraintEqualToAnchor:addressIcon.trailingAnchor constant:8.0],
        [self.addressField.trailingAnchor constraintEqualToAnchor:self.addressContainer.trailingAnchor constant:-12.0],
        [self.addressField.centerYAnchor constraintEqualToAnchor:self.addressContainer.centerYAnchor],

        [self.settingsButton.trailingAnchor constraintEqualToAnchor:toolbar.trailingAnchor constant:-14.0],
        [self.settingsButton.centerYAnchor constraintEqualToAnchor:toolbar.centerYAnchor],

        [self.askButton.trailingAnchor constraintEqualToAnchor:self.settingsButton.leadingAnchor constant:-8.0],
        [self.askButton.centerYAnchor constraintEqualToAnchor:toolbar.centerYAnchor],
        [self.askButton.widthAnchor constraintEqualToConstant:56.0],
        [self.askButton.heightAnchor constraintEqualToConstant:30.0],

        [self.plusButton.trailingAnchor constraintEqualToAnchor:self.askButton.leadingAnchor constant:-6.0],
        [self.plusButton.centerYAnchor constraintEqualToAnchor:toolbar.centerYAnchor],

        [self.statusDot.trailingAnchor constraintEqualToAnchor:self.plusButton.leadingAnchor constant:-10.0],
        [self.statusDot.centerYAnchor constraintEqualToAnchor:toolbar.centerYAnchor],
        [self.statusDot.widthAnchor constraintEqualToConstant:6.0],
        [self.statusDot.heightAnchor constraintEqualToConstant:6.0],

        [self.reloadButton.trailingAnchor constraintEqualToAnchor:self.statusDot.leadingAnchor constant:-10.0],
        [self.reloadButton.centerYAnchor constraintEqualToAnchor:toolbar.centerYAnchor],

        [self.progressBar.leadingAnchor constraintEqualToAnchor:toolbar.leadingAnchor],
        [self.progressBar.trailingAnchor constraintEqualToAnchor:toolbar.trailingAnchor],
        [self.progressBar.bottomAnchor constraintEqualToAnchor:toolbar.bottomAnchor],
        [self.progressBar.heightAnchor constraintEqualToConstant:2.0],

        [contentArea.topAnchor constraintEqualToAnchor:toolbar.bottomAnchor],
        [contentArea.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],
        [contentArea.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],
        [contentArea.bottomAnchor constraintEqualToAnchor:root.bottomAnchor],

        [self.sidebar.topAnchor constraintEqualToAnchor:contentArea.topAnchor],
        [self.sidebar.leadingAnchor constraintEqualToAnchor:contentArea.leadingAnchor],
        [self.sidebar.bottomAnchor constraintEqualToAnchor:contentArea.bottomAnchor],
        self.sidebarWidthConstraint,

        [self.sidebarSeparator.topAnchor constraintEqualToAnchor:contentArea.topAnchor],
        [self.sidebarSeparator.leadingAnchor constraintEqualToAnchor:self.sidebar.trailingAnchor],
        [self.sidebarSeparator.bottomAnchor constraintEqualToAnchor:contentArea.bottomAnchor],
        [self.sidebarSeparator.widthAnchor constraintEqualToConstant:1.0],

        [self.webContainer.topAnchor constraintEqualToAnchor:contentArea.topAnchor],
        [self.webContainer.leadingAnchor constraintEqualToAnchor:self.sidebarSeparator.trailingAnchor],
        [self.webContainer.trailingAnchor constraintEqualToAnchor:contentArea.trailingAnchor],
        [self.webContainer.bottomAnchor constraintEqualToAnchor:contentArea.bottomAnchor],

        [tabHeader.topAnchor constraintEqualToAnchor:self.sidebar.topAnchor constant:16.0],
        [tabHeader.leadingAnchor constraintEqualToAnchor:self.sidebar.leadingAnchor constant:18.0],
        [tabHeader.trailingAnchor constraintEqualToAnchor:self.sidebar.trailingAnchor constant:-12.0],
        [tabHeader.heightAnchor constraintEqualToConstant:24.0],

        [tabTitle.leadingAnchor constraintEqualToAnchor:tabHeader.leadingAnchor],
        [tabTitle.centerYAnchor constraintEqualToAnchor:tabHeader.centerYAnchor],

        [self.tabCountLabel.leadingAnchor constraintEqualToAnchor:tabTitle.trailingAnchor constant:8.0],
        [self.tabCountLabel.centerYAnchor constraintEqualToAnchor:tabHeader.centerYAnchor],

        [self.closeTabButton.trailingAnchor constraintEqualToAnchor:tabHeader.trailingAnchor],
        [self.closeTabButton.centerYAnchor constraintEqualToAnchor:tabHeader.centerYAnchor],

        [self.addTabButton.trailingAnchor constraintEqualToAnchor:self.closeTabButton.leadingAnchor constant:-4.0],
        [self.addTabButton.centerYAnchor constraintEqualToAnchor:tabHeader.centerYAnchor],

        [tabScrollView.topAnchor constraintEqualToAnchor:tabHeader.bottomAnchor constant:6.0],
        [tabScrollView.leadingAnchor constraintEqualToAnchor:self.sidebar.leadingAnchor constant:8.0],
        [tabScrollView.trailingAnchor constraintEqualToAnchor:self.sidebar.trailingAnchor constant:-8.0],
        [tabScrollView.bottomAnchor constraintEqualToAnchor:settingsDivider.topAnchor constant:-10.0],

        [settingsDivider.leadingAnchor constraintEqualToAnchor:self.sidebar.leadingAnchor constant:12.0],
        [settingsDivider.trailingAnchor constraintEqualToAnchor:self.sidebar.trailingAnchor constant:-12.0],
        [settingsDivider.heightAnchor constraintEqualToConstant:1.0],
        [settingsDivider.bottomAnchor constraintEqualToAnchor:settingsRow.topAnchor constant:-8.0],

        [settingsRow.leadingAnchor constraintEqualToAnchor:self.sidebar.leadingAnchor constant:16.0],
        [settingsRow.trailingAnchor constraintEqualToAnchor:self.sidebar.trailingAnchor constant:-12.0],
        [settingsRow.bottomAnchor constraintEqualToAnchor:self.sidebar.bottomAnchor constant:-14.0]
    ]];

    [self updateTabCount];
    [self updateControls];
    self.window.delegate = self;
    self.window.initialFirstResponder = self.addressField;
    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
    [self positionTrafficLights];

    [self.window makeFirstResponder:self.addressField];
}

- (void)positionTrafficLights {
    NSButton *close = [self.window standardWindowButton:NSWindowCloseButton];
    NSButton *minimize = [self.window standardWindowButton:NSWindowMiniaturizeButton];
    NSButton *zoom = [self.window standardWindowButton:NSWindowZoomButton];
    if (!close || !close.superview) return;

    CGFloat toolbarHeight = 46.0;
    CGFloat titleBarHeight = NSHeight(close.superview.frame);
    for (NSButton *button in @[ close, minimize, zoom ]) {
        NSRect frame = button.frame;
        frame.origin.y = titleBarHeight - toolbarHeight / 2.0 - NSHeight(frame) / 2.0;
        [button setFrameOrigin:frame.origin];
    }
}

- (void)windowDidResize:(NSNotification *)notification {
    (void)notification;
    [self positionTrafficLights];
}

- (NSView *)hairlineView {
    NSView *line = [[NSView alloc] initWithFrame:NSZeroRect];
    line.translatesAutoresizingMaskIntoConstraints = NO;
    line.wantsLayer = YES;
    line.layer.backgroundColor = TBBorder().CGColor;
    return line;
}

- (NSTextField *)sectionHeaderLabel:(NSString *)text {
    NSMutableParagraphStyle *paragraph = [[NSMutableParagraphStyle alloc] init];
    NSAttributedString *attributed = [[NSAttributedString alloc] initWithString:text attributes:@{
        NSFontAttributeName: [NSFont systemFontOfSize:11.0 weight:NSFontWeightSemibold],
        NSForegroundColorAttributeName: TBMuted(),
        NSKernAttributeName: @(0.6),
        NSParagraphStyleAttributeName: paragraph
    }];
    NSTextField *label = [NSTextField labelWithAttributedString:attributed];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    return label;
}

- (TBFlatButton *)sidebarRowWithSymbol:(NSString *)symbol title:(NSString *)title action:(SEL)action {
    TBFlatButton *button = [[TBFlatButton alloc] initWithFrame:NSZeroRect];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    button.cornerRadius = 8.0;
    button.target = self;
    button.action = action;
    button.imagePosition = NSImageLeft;
    button.imageScaling = NSImageScaleProportionallyDown;
    button.imageHugsTitle = YES;
    button.alignment = NSTextAlignmentLeft;
    button.toolTip = title;

    if (@available(macOS 11.0, *)) {
        NSImage *image = [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:title];
        NSImageSymbolConfiguration *config = [NSImageSymbolConfiguration configurationWithPointSize:13.0
                                                                                             weight:NSFontWeightMedium];
        image = [image imageWithSymbolConfiguration:config] ?: image;
        image.template = YES;
        button.image = image;
    }
    if (@available(macOS 10.14, *)) button.contentTintColor = TBMuted();

    NSMutableParagraphStyle *paragraph = [[NSMutableParagraphStyle alloc] init];
    paragraph.alignment = NSTextAlignmentLeft;
    button.attributedTitle = [[NSAttributedString alloc] initWithString:[@"   " stringByAppendingString:title]
                                                             attributes:@{
        NSFontAttributeName: [NSFont systemFontOfSize:13.0 weight:NSFontWeightMedium],
        NSForegroundColorAttributeName: TBText(),
        NSParagraphStyleAttributeName: paragraph
    }];

    [button.heightAnchor constraintEqualToConstant:34.0].active = YES;
    [button.widthAnchor constraintGreaterThanOrEqualToConstant:200.0].active = YES;
    return button;
}

- (void)updateTabCount {
    self.tabCountLabel.stringValue = [NSString stringWithFormat:@"%lu", (unsigned long)self.tabs.count];
}

- (void)setStatusText:(NSString *)text {
    NSColor *dotColor = TBMuted();
    if ([text isEqualToString:@"Ready"]) {
        dotColor = TBOk();
    } else if ([text isEqualToString:@"Loading"]) {
        dotColor = TBAccent();
    } else if (text.length > 0) {
        dotColor = TBError();
    }
    self.statusDot.layer.backgroundColor = dotColor.CGColor;
    self.statusDot.toolTip = text.length ? text : @"Ready";
}

- (NSButton *)toolbarButtonWithSymbol:(NSString *)symbol
                             fallback:(NSString *)fallback
                              tooltip:(NSString *)tooltip
                               action:(SEL)action {
    TBFlatButton *button = [[TBFlatButton alloc] initWithFrame:NSZeroRect];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    button.target = self;
    button.action = action;
    button.cornerRadius = 7.0;
    button.imagePosition = NSImageOnly;
    button.imageScaling = NSImageScaleProportionallyDown;
    button.toolTip = tooltip;

    if (@available(macOS 11.0, *)) {
        NSImage *image = [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:tooltip];
        NSImageSymbolConfiguration *config = [NSImageSymbolConfiguration configurationWithPointSize:15.0
                                                                                             weight:NSFontWeightMedium];
        image = [image imageWithSymbolConfiguration:config] ?: image;
        image.template = YES;
        button.image = image;
    }
    if (@available(macOS 10.14, *)) button.contentTintColor = TBMuted();

    if (!button.image) {
        button.imagePosition = NSNoImage;
        button.attributedTitle = [[NSAttributedString alloc] initWithString:fallback attributes:@{
            NSFontAttributeName: [NSFont systemFontOfSize:14.0 weight:NSFontWeightSemibold],
            NSForegroundColorAttributeName: TBMuted()
        }];
    }

    [button.widthAnchor constraintEqualToConstant:32.0].active = YES;
    [button.heightAnchor constraintEqualToConstant:30.0].active = YES;
    return button;
}

- (NSButton *)sidebarButtonWithSymbol:(NSString *)symbol
                              fallback:(NSString *)fallback
                               tooltip:(NSString *)tooltip
                                action:(SEL)action {
    TBFlatButton *button = [[TBFlatButton alloc] initWithFrame:NSZeroRect];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    button.target = self;
    button.action = action;
    button.cornerRadius = 6.0;
    button.imagePosition = NSImageOnly;
    button.imageScaling = NSImageScaleProportionallyDown;
    button.toolTip = tooltip;

    if (@available(macOS 11.0, *)) {
        NSImage *image = [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:tooltip];
        NSImageSymbolConfiguration *config = [NSImageSymbolConfiguration configurationWithPointSize:12.0
                                                                                             weight:NSFontWeightSemibold];
        image = [image imageWithSymbolConfiguration:config] ?: image;
        image.template = YES;
        button.image = image;
    }
    if (@available(macOS 10.14, *)) button.contentTintColor = TBMuted();

    if (!button.image) {
        button.imagePosition = NSNoImage;
        button.attributedTitle = [[NSAttributedString alloc] initWithString:fallback attributes:@{
            NSFontAttributeName: [NSFont systemFontOfSize:13.0 weight:NSFontWeightSemibold],
            NSForegroundColorAttributeName: TBMuted()
        }];
    }

    [button.widthAnchor constraintEqualToConstant:26.0].active = YES;
    [button.heightAnchor constraintEqualToConstant:24.0].active = YES;
    return button;
}

- (void)buildAssistantOverlay {
    self.assistantBar = [[NSVisualEffectView alloc] initWithFrame:NSZeroRect];
    self.assistantBar.translatesAutoresizingMaskIntoConstraints = NO;
    self.assistantBar.material = NSVisualEffectMaterialHUDWindow;
    self.assistantBar.blendingMode = NSVisualEffectBlendingModeWithinWindow;
    self.assistantBar.state = NSVisualEffectStateActive;
    self.assistantBar.appearance = [NSAppearance appearanceNamed:NSAppearanceNameVibrantDark];
    self.assistantBar.wantsLayer = YES;
    self.assistantBar.layer.cornerRadius = 14.0;
    self.assistantBar.layer.masksToBounds = YES;
    self.assistantBar.layer.borderWidth = 1.0;
    self.assistantBar.layer.borderColor = TBBorder().CGColor;
    self.assistantBar.layer.backgroundColor = TBSurface().CGColor;
    self.assistantBar.hidden = YES;
    [self.webContainer addSubview:self.assistantBar];

    self.assistantModeControl = [[TBSegmentedControl alloc] initWithFrame:NSZeroRect];
    self.assistantModeControl.translatesAutoresizingMaskIntoConstraints = NO;
    self.assistantModeControl.titles = @[ @"Ask", @"Edit" ];
    self.assistantModeControl.selectedIndex = 0;
    self.assistantModeControl.target = self;
    self.assistantModeControl.action = @selector(assistantModeChanged:);
    [self.assistantBar addSubview:self.assistantModeControl];

    self.assistantPromptField = [[NSTextField alloc] initWithFrame:NSZeroRect];
    self.assistantPromptField.translatesAutoresizingMaskIntoConstraints = NO;
    self.assistantPromptField.placeholderString = @"Ask about this page";
    self.assistantPromptField.font = [NSFont systemFontOfSize:13.0 weight:NSFontWeightRegular];
    self.assistantPromptField.controlSize = NSControlSizeRegular;
    self.assistantPromptField.bezeled = NO;
    self.assistantPromptField.bordered = NO;
    self.assistantPromptField.drawsBackground = NO;
    self.assistantPromptField.focusRingType = NSFocusRingTypeNone;
    self.assistantPromptField.usesSingleLineMode = YES;
    self.assistantPromptField.cell.usesSingleLineMode = YES;
    self.assistantPromptField.cell.lineBreakMode = NSLineBreakByTruncatingTail;
    [self.assistantPromptField.cell setScrollable:YES];
    self.assistantPromptField.textColor = TBText();
    self.assistantPromptField.placeholderAttributedString =
        [[NSAttributedString alloc] initWithString:@"Ask about this page"
                                        attributes:@{ NSForegroundColorAttributeName: TBFaint(),
                                                      NSFontAttributeName: [NSFont systemFontOfSize:13.0 weight:NSFontWeightRegular] }];
    self.assistantPromptField.target = self;
    self.assistantPromptField.action = @selector(runPageAssistant:);
    [self.assistantBar addSubview:self.assistantPromptField];

    self.assistantSpinner = [[NSProgressIndicator alloc] initWithFrame:NSZeroRect];
    self.assistantSpinner.translatesAutoresizingMaskIntoConstraints = NO;
    self.assistantSpinner.style = NSProgressIndicatorStyleSpinning;
    self.assistantSpinner.controlSize = NSControlSizeSmall;
    self.assistantSpinner.displayedWhenStopped = NO;
    self.assistantSpinner.hidden = YES;
    [self.assistantBar addSubview:self.assistantSpinner];

    self.assistantRunButton = [self toolbarButtonWithSymbol:@"arrow.up"
                                                   fallback:@"Go"
                                                    tooltip:@"Run"
                                                     action:@selector(runPageAssistant:)];
    if (@available(macOS 10.14, *)) self.assistantRunButton.contentTintColor = TBAccent();
    [self.assistantBar addSubview:self.assistantRunButton];

    self.assistantCollapseButton = [self sidebarButtonWithSymbol:@"xmark"
                                                        fallback:@"x"
                                                         tooltip:@"Collapse"
                                                          action:@selector(collapseAssistant:)];
    [self.assistantBar addSubview:self.assistantCollapseButton];

    self.assistantResultPanel = [[NSVisualEffectView alloc] initWithFrame:NSZeroRect];
    self.assistantResultPanel.translatesAutoresizingMaskIntoConstraints = NO;
    self.assistantResultPanel.material = NSVisualEffectMaterialHUDWindow;
    self.assistantResultPanel.blendingMode = NSVisualEffectBlendingModeWithinWindow;
    self.assistantResultPanel.state = NSVisualEffectStateActive;
    self.assistantResultPanel.appearance = [NSAppearance appearanceNamed:NSAppearanceNameVibrantDark];
    self.assistantResultPanel.hidden = YES;
    self.assistantResultPanel.wantsLayer = YES;
    self.assistantResultPanel.layer.cornerRadius = 14.0;
    self.assistantResultPanel.layer.masksToBounds = YES;
    self.assistantResultPanel.layer.borderWidth = 1.0;
    self.assistantResultPanel.layer.borderColor = TBBorder().CGColor;
    self.assistantResultPanel.layer.backgroundColor = TBSurface().CGColor;
    [self.webContainer addSubview:self.assistantResultPanel positioned:NSWindowBelow relativeTo:self.assistantBar];

    self.assistantResultCloseButton = [self sidebarButtonWithSymbol:@"xmark"
                                                           fallback:@"x"
                                                            tooltip:@"Close"
                                                             action:@selector(closeAssistantResult:)];
    [self.assistantResultPanel addSubview:self.assistantResultCloseButton];

    NSScrollView *resultScrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    resultScrollView.translatesAutoresizingMaskIntoConstraints = NO;
    resultScrollView.borderType = NSNoBorder;
    resultScrollView.drawsBackground = NO;
    resultScrollView.hasVerticalScroller = YES;
    resultScrollView.autohidesScrollers = YES;
    resultScrollView.scrollerStyle = NSScrollerStyleOverlay;
    [self.assistantResultPanel addSubview:resultScrollView];

    self.assistantResultTextView = [[NSTextView alloc] initWithFrame:NSZeroRect];
    self.assistantResultTextView.editable = NO;
    self.assistantResultTextView.selectable = YES;
    self.assistantResultTextView.drawsBackground = NO;
    self.assistantResultTextView.font = [NSFont systemFontOfSize:13.0 weight:NSFontWeightRegular];
    self.assistantResultTextView.textColor = TBText();
    self.assistantResultTextView.textContainerInset = NSMakeSize(0.0, 2.0);
    resultScrollView.documentView = self.assistantResultTextView;

    [NSLayoutConstraint activateConstraints:@[
        [self.assistantBar.centerXAnchor constraintEqualToAnchor:self.webContainer.centerXAnchor],
        [self.assistantBar.bottomAnchor constraintEqualToAnchor:self.webContainer.bottomAnchor constant:-18.0],
        [self.assistantBar.widthAnchor constraintLessThanOrEqualToConstant:760.0],
        [self.assistantBar.widthAnchor constraintGreaterThanOrEqualToConstant:620.0],
        [self.assistantBar.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.webContainer.leadingAnchor constant:28.0],
        [self.assistantBar.trailingAnchor constraintLessThanOrEqualToAnchor:self.webContainer.trailingAnchor constant:-28.0],
        [self.assistantBar.heightAnchor constraintEqualToConstant:46.0],

        [self.assistantModeControl.leadingAnchor constraintEqualToAnchor:self.assistantBar.leadingAnchor constant:8.0],
        [self.assistantModeControl.centerYAnchor constraintEqualToAnchor:self.assistantBar.centerYAnchor],
        [self.assistantModeControl.widthAnchor constraintEqualToConstant:108.0],
        [self.assistantModeControl.heightAnchor constraintEqualToConstant:30.0],

        [self.assistantRunButton.trailingAnchor constraintEqualToAnchor:self.assistantBar.trailingAnchor constant:-10.0],
        [self.assistantRunButton.centerYAnchor constraintEqualToAnchor:self.assistantBar.centerYAnchor],

        [self.assistantCollapseButton.trailingAnchor constraintEqualToAnchor:self.assistantRunButton.leadingAnchor constant:-8.0],
        [self.assistantCollapseButton.centerYAnchor constraintEqualToAnchor:self.assistantBar.centerYAnchor],

        [self.assistantPromptField.leadingAnchor constraintEqualToAnchor:self.assistantModeControl.trailingAnchor constant:12.0],
        [self.assistantPromptField.trailingAnchor constraintEqualToAnchor:self.assistantCollapseButton.leadingAnchor constant:-12.0],
        [self.assistantPromptField.centerYAnchor constraintEqualToAnchor:self.assistantBar.centerYAnchor],

        [self.assistantSpinner.trailingAnchor constraintEqualToAnchor:self.assistantCollapseButton.leadingAnchor constant:-8.0],
        [self.assistantSpinner.centerYAnchor constraintEqualToAnchor:self.assistantBar.centerYAnchor],
        [self.assistantSpinner.widthAnchor constraintEqualToConstant:18.0],
        [self.assistantSpinner.heightAnchor constraintEqualToConstant:18.0],

        [self.assistantResultPanel.centerXAnchor constraintEqualToAnchor:self.assistantBar.centerXAnchor],
        [self.assistantResultPanel.widthAnchor constraintEqualToAnchor:self.assistantBar.widthAnchor],
        [self.assistantResultPanel.bottomAnchor constraintEqualToAnchor:self.assistantBar.topAnchor constant:-10.0],
        [self.assistantResultPanel.heightAnchor constraintEqualToConstant:220.0],

        [self.assistantResultCloseButton.topAnchor constraintEqualToAnchor:self.assistantResultPanel.topAnchor constant:10.0],
        [self.assistantResultCloseButton.trailingAnchor constraintEqualToAnchor:self.assistantResultPanel.trailingAnchor constant:-10.0],

        [resultScrollView.topAnchor constraintEqualToAnchor:self.assistantResultPanel.topAnchor constant:12.0],
        [resultScrollView.leadingAnchor constraintEqualToAnchor:self.assistantResultPanel.leadingAnchor constant:14.0],
        [resultScrollView.trailingAnchor constraintEqualToAnchor:self.assistantResultCloseButton.leadingAnchor constant:-8.0],
        [resultScrollView.bottomAnchor constraintEqualToAnchor:self.assistantResultPanel.bottomAnchor constant:-12.0]
    ]];
}

- (WKWebView *)createWebViewWithConfiguration:(WKWebViewConfiguration *)configuration {
    WKWebViewConfiguration *config = configuration ?: [[WKWebViewConfiguration alloc] init];
    [self configureForLowMemory:config];
    WKWebView *webView = [[WKWebView alloc] initWithFrame:NSZeroRect configuration:config];
    webView.translatesAutoresizingMaskIntoConstraints = NO;
    webView.navigationDelegate = self;
    webView.UIDelegate = self;
    webView.allowsBackForwardNavigationGestures = YES;
    webView.hidden = YES;
    if (self.assistantResultPanel) {
        [self.webContainer addSubview:webView positioned:NSWindowBelow relativeTo:self.assistantResultPanel];
    } else {
        [self.webContainer addSubview:webView];
    }

    [NSLayoutConstraint activateConstraints:@[
        [webView.topAnchor constraintEqualToAnchor:self.webContainer.topAnchor],
        [webView.leadingAnchor constraintEqualToAnchor:self.webContainer.leadingAnchor],
        [webView.trailingAnchor constraintEqualToAnchor:self.webContainer.trailingAnchor],
        [webView.bottomAnchor constraintEqualToAnchor:self.webContainer.bottomAnchor]
    ]];

    if (self.assistantResultPanel) {
        [self.webContainer addSubview:self.assistantResultPanel positioned:NSWindowAbove relativeTo:webView];
        [self.webContainer addSubview:self.assistantBar positioned:NSWindowAbove relativeTo:self.assistantResultPanel];
    }

    [self addObserversToWebView:webView];
    return webView;
}

- (void)addObserversToWebView:(WKWebView *)webView {
    [webView addObserver:self
              forKeyPath:@"estimatedProgress"
                 options:NSKeyValueObservingOptionNew
                 context:BrowserProgressContext];
    [webView addObserver:self
              forKeyPath:@"URL"
                 options:NSKeyValueObservingOptionNew
                 context:BrowserURLContext];
    [webView addObserver:self
              forKeyPath:@"canGoBack"
                 options:NSKeyValueObservingOptionNew
                 context:BrowserCanGoBackContext];
    [webView addObserver:self
              forKeyPath:@"canGoForward"
                 options:NSKeyValueObservingOptionNew
                 context:BrowserCanGoForwardContext];
}

- (void)removeObserversFromWebView:(WKWebView *)webView {
    if (!webView) return;
    @try {
        [webView removeObserver:self forKeyPath:@"estimatedProgress"];
        [webView removeObserver:self forKeyPath:@"URL"];
        [webView removeObserver:self forKeyPath:@"canGoBack"];
        [webView removeObserver:self forKeyPath:@"canGoForward"];
    } @catch (NSException *exception) {
        (void)exception;
    }
}

- (void)configureForLowMemory:(WKWebViewConfiguration *)configuration {

    configuration.websiteDataStore = [WKWebsiteDataStore defaultDataStore];
    configuration.suppressesIncrementalRendering = YES;
    configuration.allowsAirPlayForMediaPlayback = NO;
    configuration.mediaTypesRequiringUserActionForPlayback = WKAudiovisualMediaTypeAll;
}

- (BrowserTab *)newTabWithURLString:(NSString *)urlString select:(BOOL)select {
    return [self newTabWithConfiguration:nil URLString:urlString select:select];
}

- (BrowserTab *)newTabWithConfiguration:(WKWebViewConfiguration *)configuration
                              URLString:(NSString *)urlString
                                 select:(BOOL)select {
    BrowserTab *tab = [[BrowserTab alloc] init];
    tab.title = @"New Tab";
    tab.urlString = urlString ?: [self homeURLString];
    if (configuration) tab.webView = [self createWebViewWithConfiguration:configuration];
    [self.tabs addObject:tab];
    [self.tabTable reloadData];
    [self updateTabCount];

    NSInteger index = (NSInteger)self.tabs.count - 1;
    if (select) {
        [self selectTabAtIndex:index];
    } else if (configuration == nil) {
        [self preloadTab:tab];
        [self enforceLiveTabBudget];
    }

    return tab;
}

- (BrowserTab *)activeTab {
    if (self.activeTabIndex < 0 || self.activeTabIndex >= (NSInteger)self.tabs.count) return nil;
    return self.tabs[(NSUInteger)self.activeTabIndex];
}

- (BrowserTab *)tabForWebView:(WKWebView *)webView {
    for (BrowserTab *tab in self.tabs) {
        if (tab.webView == webView) return tab;
    }
    return nil;
}

- (WKWebView *)ensureWebViewForTab:(BrowserTab *)tab {
    if (!tab.webView) {
        tab.webView = [self createWebViewWithConfiguration:nil];
    }
    return tab.webView;
}

- (void)sleepTabAtIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)self.tabs.count) return;
    [self sleepTab:self.tabs[(NSUInteger)index]];
}

- (void)sleepTab:(BrowserTab *)tab {
    WKWebView *webView = tab.webView;
    if (!webView) return;

    [self.preloadQueue removeObject:tab];
    if (webView.URL.absoluteString.length > 0) tab.urlString = webView.URL.absoluteString;
    if (webView.title.length > 0) tab.title = webView.title;

    [webView stopLoading];
    [self removeObserversFromWebView:webView];
    [webView removeFromSuperview];
    tab.webView = nil;
    [self preloadFinishedForWebView:webView];
}

- (void)startMemoryPressureMonitor {
    dispatch_source_t source = dispatch_source_create(DISPATCH_SOURCE_TYPE_MEMORYPRESSURE,
                                                      0,
                                                      DISPATCH_MEMORYPRESSURE_WARN | DISPATCH_MEMORYPRESSURE_CRITICAL,
                                                      dispatch_get_main_queue());
    __weak BrowserAppDelegate *weakSelf = self;
    dispatch_source_set_event_handler(source, ^{
        [weakSelf sleepAllInactiveTabs];
    });
    dispatch_resume(source);
    self.memoryPressureSource = source;
}

- (void)sleepAllInactiveTabs {
    BrowserTab *active = [self activeTab];
    for (BrowserTab *tab in self.tabs) {
        if (tab != active && tab.webView) [self sleepTab:tab];
    }
    if (self.tabs.count > 0) {
        NSIndexSet *rows = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, self.tabs.count)];
        [self.tabTable reloadDataForRowIndexes:rows columnIndexes:[NSIndexSet indexSetWithIndex:0]];
    }
}

- (void)enforceLiveTabBudget {
    NSMutableArray<BrowserTab *> *live = [NSMutableArray array];
    for (BrowserTab *tab in self.tabs) {
        if (tab.webView && tab != [self activeTab]) [live addObject:tab];
    }
    if ((NSInteger)live.count <= kMaxLiveTabs - 1) return;

    [live sortUsingComparator:^NSComparisonResult(BrowserTab *a, BrowserTab *b) {
        if (a.lastActiveSeq < b.lastActiveSeq) return NSOrderedAscending;
        if (a.lastActiveSeq > b.lastActiveSeq) return NSOrderedDescending;
        return NSOrderedSame;
    }];

    NSInteger excess = (NSInteger)live.count - (kMaxLiveTabs - 1);
    for (NSInteger i = 0; i < excess; i++) {
        [self sleepTab:live[(NSUInteger)i]];
    }
}

- (void)loadContentForTab:(BrowserTab *)tab {
    WKWebView *webView = tab.webView;
    if (!webView || webView.URL != nil || tab.urlString.length == 0) return;
    if ([self isHomeURLString:tab.urlString]) {
        [self loadNativeHomePageInWebView:webView];
    } else if ([self isSettingsURLString:tab.urlString]) {
        [self loadNativeSettingsPageInWebView:webView];
    } else if ([self isOnboardingURLString:tab.urlString]) {
        [self loadNativeOnboardingPageInWebView:webView];
    } else {
        NSURL *url = [self URLForUserInput:tab.urlString];
        if (url) [webView loadRequest:[NSURLRequest requestWithURL:url]];
    }
}

- (void)preloadTab:(BrowserTab *)tab {
    if (tab.webView) return;
    if (!self.preloadQueue) self.preloadQueue = [NSMutableArray array];
    if (!self.preloadingWebViews) self.preloadingWebViews = [NSMutableSet set];
    if (![self.preloadQueue containsObject:tab]) [self.preloadQueue addObject:tab];
    [self pumpPreloadQueue];
}

- (void)pumpPreloadQueue {
    while ((NSInteger)self.preloadingWebViews.count < kMaxConcurrentPreloads && self.preloadQueue.count > 0) {
        BrowserTab *tab = self.preloadQueue.firstObject;
        [self.preloadQueue removeObjectAtIndex:0];
        if (tab.webView) continue;
        WKWebView *webView = [self ensureWebViewForTab:tab];
        [self.preloadingWebViews addObject:webView];
        [self loadContentForTab:tab];
    }
}

- (void)preloadFinishedForWebView:(WKWebView *)webView {
    if (![self.preloadingWebViews containsObject:webView]) return;
    [self.preloadingWebViews removeObject:webView];
    [self pumpPreloadQueue];
}

- (void)selectTabAtIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)self.tabs.count) return;
    if (index == self.activeTabIndex && self.webView == self.tabs[(NSUInteger)index].webView) return;

    self.webView.hidden = YES;
    self.activeTabIndex = index;
    BrowserTab *tab = [self activeTab];
    tab.lastActiveSeq = ++self.tabActivationCounter;
    self.webView = [self ensureWebViewForTab:tab];
    self.webView.hidden = NO;

    [self enforceLiveTabBudget];

    NSIndexSet *selection = [NSIndexSet indexSetWithIndex:(NSUInteger)index];
    [self.tabTable selectRowIndexes:selection byExtendingSelection:NO];
    [self.tabTable scrollRowToVisible:index];
    if (self.tabs.count > 0) {
        NSIndexSet *rows = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, self.tabs.count)];
        NSIndexSet *columns = [NSIndexSet indexSetWithIndex:0];
        [self.tabTable reloadDataForRowIndexes:rows columnIndexes:columns];
    }
    [self refreshActiveRowHighlight];

    [self loadContentForTab:tab];

    if (self.webView.URL) {
        [self syncAddressBarWithWebView];
    } else if (tab.urlString.length > 0) {
        self.addressField.stringValue = tab.urlString;
    }
    [self updateControls];
    [self setStatusText:self.webView.loading ? @"Loading" : @"Ready"];
    self.progressBar.progress = self.webView.estimatedProgress;
    self.progressBar.hidden = !self.webView.loading || self.webView.estimatedProgress >= 1.0;
}

- (void)newTab:(id)sender {
    (void)sender;
    [self newTabWithURLString:[self homeURLString] select:YES];
}

- (void)closeCurrentTab:(id)sender {
    (void)sender;
    [self closeTabAtIndex:self.activeTabIndex];
}

- (void)closeTabAtIndex:(NSInteger)closingIndex {
    if (self.tabs.count == 0) return;
    if (closingIndex < 0 || closingIndex >= (NSInteger)self.tabs.count) closingIndex = self.activeTabIndex;
    if (closingIndex < 0 || closingIndex >= (NSInteger)self.tabs.count) closingIndex = 0;

    BOOL closingActive = (closingIndex == self.activeTabIndex);
    BrowserTab *closingTab = self.tabs[(NSUInteger)closingIndex];

    [self.preloadQueue removeObject:closingTab];
    if (closingTab.webView) [self.preloadingWebViews removeObject:closingTab.webView];
    [self removeObserversFromWebView:closingTab.webView];
    [closingTab.webView stopLoading];
    [closingTab.webView removeFromSuperview];
    [self.tabs removeObjectAtIndex:(NSUInteger)closingIndex];
    [self updateTabCount];

    if (self.tabs.count == 0) {
        self.webView = nil;
        self.activeTabIndex = -1;
        [self.tabTable reloadData];
        [self newTabWithURLString:[self homeURLString] select:YES];
        return;
    }

    if (closingActive) {
        self.webView = nil;
        self.activeTabIndex = -1;
        [self.tabTable reloadData];
        NSInteger nextIndex = MIN(closingIndex, (NSInteger)self.tabs.count - 1);
        [self selectTabAtIndex:nextIndex];
        return;
    }

    if (closingIndex < self.activeTabIndex) self.activeTabIndex -= 1;
    [self.tabTable reloadData];
    [self.tabTable selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)self.activeTabIndex]
               byExtendingSelection:NO];
    [self refreshActiveRowHighlight];
    [self updateControls];
}

- (void)loadFromAddressField:(id)sender {
    (void)sender;
    self.userEditingAddress = NO;
    [self loadURLString:self.addressField.stringValue];
}

- (void)loadURLString:(NSString *)input {
    if (!self.webView) {
        [self newTabWithURLString:input select:YES];
        return;
    }

    if ([self isHomeURLString:input]) {
        [self loadNativeHomePageInWebView:self.webView];
        return;
    }

    if ([self isSettingsURLString:input]) {
        [self loadNativeSettingsPageInWebView:self.webView];
        return;
    }

    if ([self isOnboardingURLString:input]) {
        [self loadNativeOnboardingPageInWebView:self.webView];
        return;
    }

    NSURL *url = [self URLForUserInput:input];
    if (!url) {
        NSBeep();
        return;
    }

    self.addressField.stringValue = url.absoluteString;
    BrowserTab *tab = [self activeTab];
    tab.urlString = url.absoluteString;
    [self setStatusText:@"Loading"];
    [self.webView loadRequest:[NSURLRequest requestWithURL:url]];
}

- (NSString *)homeURLString {
    return @"trailbrowser://home";
}

- (NSString *)settingsURLString {
    return @"trailbrowser://settings";
}

- (NSString *)onboardingURLString {
    return @"trailbrowser://welcome";
}

- (BOOL)isHomeURLString:(NSString *)input {
    NSString *trimmed = [[input ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] lowercaseString];
    return [trimmed isEqualToString:@"trailbrowser://home"] ||
           [trimmed isEqualToString:@"trailbrowser://home/"] ||
           [trimmed isEqualToString:@"about:trailbrowser"];
}

- (BOOL)isSettingsURLString:(NSString *)input {
    NSString *trimmed = [[input ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] lowercaseString];
    return [trimmed isEqualToString:@"trailbrowser://settings"] ||
           [trimmed isEqualToString:@"trailbrowser://settings/"];
}

- (BOOL)isOnboardingURLString:(NSString *)input {
    NSString *trimmed = [[input ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] lowercaseString];
    return [trimmed isEqualToString:@"trailbrowser://welcome"] ||
           [trimmed isEqualToString:@"trailbrowser://welcome/"];
}

- (NSString *)resourceStringNamed:(NSString *)name extension:(NSString *)extension {
    NSURL *url = [[NSBundle mainBundle] URLForResource:name withExtension:extension subdirectory:@"home"];
    return url ? [NSString stringWithContentsOfURL:url encoding:NSUTF8StringEncoding error:nil] : nil;
}

- (NSString *)nativeResourceHTMLNamed:(NSString *)name {
    NSString *html = [self resourceStringNamed:name extension:@"html"];
    if (html.length == 0) {
        return @"<!doctype html><title>TrailBrowser</title><body style='background:#0a0a0b'></body>";
    }

    NSString *css = [self resourceStringNamed:name extension:@"css"];
    if (css.length > 0) {
        NSString *link = [NSString stringWithFormat:@"<link rel=\"stylesheet\" href=\"%@.css\">", name];
        html = [html stringByReplacingOccurrencesOfString:link
                                               withString:[NSString stringWithFormat:@"<style>\n%@\n</style>", css]];
    }
    NSString *js = [self resourceStringNamed:name extension:@"js"];
    if (js.length > 0) {
        NSString *tag = [NSString stringWithFormat:@"<script src=\"%@.js\"></script>", name];
        html = [html stringByReplacingOccurrencesOfString:tag
                                               withString:[NSString stringWithFormat:@"<script>\n%@\n</script>", js]];
    }
    return html;
}

- (NSString *)queryValueNamed:(NSString *)name inURL:(NSURL *)url {
    NSURLComponents *components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    for (NSURLQueryItem *item in components.queryItems ?: @[]) {
        if ([item.name isEqualToString:name]) return item.value ?: @"";
    }
    return @"";
}

- (BOOL)handleInternalURL:(NSURL *)url {
    if (![url.scheme.lowercaseString isEqualToString:@"trailbrowser"]) return NO;

    NSString *host = url.host.lowercaseString ?: @"";
    if ([host isEqualToString:@"open"]) {
        NSString *input = [self queryValueNamed:@"input" inURL:url];
        if (input.length > 0) [self loadURLString:input];
        return YES;
    }

    if ([host isEqualToString:@"deep-search"]) {
        NSString *query = [self queryValueNamed:@"q" inURL:url];
        if (query.length > 0) [self runWebpageSearchForQuery:query];
        return YES;
    }

    if ([host isEqualToString:@"assistant"]) {
        [self openAssistant:nil];
        return YES;
    }

    if ([host isEqualToString:@"settings"]) {
        if (self.webView) [self loadNativeSettingsPageInWebView:self.webView];
        return YES;
    }

    if ([host isEqualToString:@"welcome"]) {
        if (self.webView) [self loadNativeOnboardingPageInWebView:self.webView];
        return YES;
    }

    if ([host isEqualToString:@"sync-cookies"]) {
        [self importChromeCookies:nil];
        return YES;
    }

    if ([host isEqualToString:@"set-pref"]) {
        NSString *key = [self queryValueNamed:@"key" inURL:url];
        NSString *value = [self queryValueNamed:@"value" inURL:url];
        NSDictionary<NSString *, NSString *> *allowed = @{ @"aiEngine": @"TBAIEngine",
                                                           @"codexModel": @"TBCodexModel",
                                                           @"claudeModel": @"TBClaudeModel",
                                                           @"codexEffort": @"TBCodexEffort" };
        NSString *defaultsKey = allowed[key];
        if (defaultsKey) {
            [[NSUserDefaults standardUserDefaults] setObject:value forKey:defaultsKey];
        }
        return YES;
    }

    if ([host isEqualToString:@"home"] || host.length == 0) {
        if (self.webView) [self loadNativeHomePageInWebView:self.webView];
        return YES;
    }

    return NO;
}

- (void)loadNativeHomePageInWebView:(WKWebView *)webView {
    BrowserTab *tab = [self tabForWebView:webView];
    if (tab) {
        tab.title = @"TrailBrowser Home";
        tab.urlString = [self homeURLString];
        tab.favicon = nil;
        [self reloadSidebarRowForTab:tab];
    }
    self.addressField.stringValue = [self homeURLString];
    self.renderingInternalPage = YES;
    [self setStatusText:@"Ready"];
    NSString *html = [[self nativeResourceHTMLNamed:@"Home"]
                      stringByReplacingOccurrencesOfString:@"</head>"
                                                withString:[self aiPrefsScript]];
    [webView loadHTMLString:html baseURL:[NSURL URLWithString:[self homeURLString]]];
}

- (NSString *)aiPrefsScript {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *engine = [defaults stringForKey:@"TBAIEngine"] ?: @"codex";
    NSString *codexModel = [defaults stringForKey:@"TBCodexModel"] ?: @"";
    NSString *claudeModel = [defaults stringForKey:@"TBClaudeModel"] ?: @"";
    NSString *effort = [defaults stringForKey:@"TBCodexEffort"] ?: @"";
    return [NSString stringWithFormat:
        @"<script>window.__tbEngine=\"%@\";window.__tbCodexModel=\"%@\";"
         "window.__tbClaudeModel=\"%@\";window.__tbEffort=\"%@\";</script></head>",
        engine, codexModel, claudeModel, effort];
}

- (void)loadNativeSettingsPageInWebView:(WKWebView *)webView {
    BrowserTab *tab = [self tabForWebView:webView];
    if (tab) {
        tab.title = @"Settings";
        tab.urlString = [self settingsURLString];
        tab.favicon = nil;
        [self reloadSidebarRowForTab:tab];
    }
    self.addressField.stringValue = [self settingsURLString];
    [self setStatusText:@"Ready"];

    NSString *html = [[self nativeResourceHTMLNamed:@"Settings"]
                      stringByReplacingOccurrencesOfString:@"</head>" withString:[self aiPrefsScript]];

    self.renderingInternalPage = YES;
    [webView loadHTMLString:html baseURL:[NSURL URLWithString:[self settingsURLString]]];
}

- (void)loadNativeOnboardingPageInWebView:(WKWebView *)webView {
    BrowserTab *tab = [self tabForWebView:webView];
    if (tab) {
        tab.title = @"Welcome";
        tab.urlString = [self onboardingURLString];
        tab.favicon = nil;
        [self reloadSidebarRowForTab:tab];
    }
    self.addressField.stringValue = [self onboardingURLString];
    self.renderingInternalPage = YES;
    [self setStatusText:@"Ready"];
    [webView loadHTMLString:[self nativeResourceHTMLNamed:@"Onboarding"]
                    baseURL:[NSURL URLWithString:[self onboardingURLString]]];
}

- (void)openSettings:(id)sender {
    (void)sender;
    if (!self.webView) {
        [self newTabWithURLString:[self settingsURLString] select:YES];
        return;
    }
    [self loadNativeSettingsPageInWebView:self.webView];
}

- (NSURL *)URLForUserInput:(NSString *)input {
    NSString *trimmed = [input stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmed.length == 0) return nil;

    if ([self inputContainsWhitespace:trimmed]) {
        return [self searchURLForQuery:trimmed];
    }

    NSURLComponents *components = [NSURLComponents componentsWithString:trimmed];
    if ([self isSupportedExplicitScheme:components.scheme] || [trimmed containsString:@"://"]) {
        return components.URL;
    }

    if ([self inputLooksLikeHostOrLocalAddress:trimmed]) {
        NSString *scheme = [self inputLooksLocal:trimmed] ? @"http://" : @"https://";
        return [NSURL URLWithString:[scheme stringByAppendingString:trimmed]];
    }

    return [self searchURLForQuery:trimmed];
}

- (BOOL)isSupportedExplicitScheme:(NSString *)scheme {
    NSString *lower = scheme.lowercaseString;
    return [lower isEqualToString:@"http"] ||
           [lower isEqualToString:@"https"] ||
           [lower isEqualToString:@"file"] ||
           [lower isEqualToString:@"about"];
}

- (BOOL)inputContainsWhitespace:(NSString *)input {
    return [input rangeOfCharacterFromSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].location != NSNotFound;
}

- (BOOL)inputLooksLocal:(NSString *)input {
    NSString *lower = input.lowercaseString;
    return [lower hasPrefix:@"localhost"] ||
           [lower hasPrefix:@"127."] ||
           [lower hasPrefix:@"0.0.0.0"] ||
           [lower hasPrefix:@"::1"] ||
           [lower hasPrefix:@"["];
}

- (BOOL)inputLooksLikeHostOrLocalAddress:(NSString *)input {
    if ([self inputLooksLocal:input]) return YES;

    NSString *pattern =
        @"^(([A-Za-z0-9-]+\\.)+[A-Za-z]{2,}|\\d{1,3}(\\.\\d{1,3}){3})"
         "(:[0-9]{1,5})?([/?#].*)?$";
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern
                                                                           options:0
                                                                             error:nil];
    NSRange fullRange = NSMakeRange(0, input.length);
    NSTextCheckingResult *match = [regex firstMatchInString:input options:0 range:fullRange];
    return match && NSEqualRanges(match.range, fullRange);
}

- (NSURL *)searchURLForQuery:(NSString *)query {
    NSURLComponents *components = [[NSURLComponents alloc] init];
    components.scheme = @"https";
    components.host = @"www.google.com";
    components.path = @"/search";
    components.queryItems = @[ [NSURLQueryItem queryItemWithName:@"q" value:query] ];
    return components.URL;
}

- (NSString *)supportDirectoryPath {
    NSArray<NSString *> *paths = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory,
                                                                     NSUserDomainMask,
                                                                     YES);
    NSString *base = paths.firstObject ?: NSTemporaryDirectory();
    NSString *directory = [base stringByAppendingPathComponent:@"TrailBrowser"];

    NSError *error = nil;
    [[NSFileManager defaultManager] createDirectoryAtPath:directory
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:&error];
    if (error) {
        NSLog(@"Could not create TrailBrowser support directory: %@", error.localizedDescription);
    }

    return directory;
}

- (NSString *)historyFilePath {
    return [[self supportDirectoryPath] stringByAppendingPathComponent:@"history.jsonl"];
}

- (NSString *)stateFilePath {
    return [[self supportDirectoryPath] stringByAppendingPathComponent:@"state.json"];
}

- (BOOL)isSensitiveQueryName:(NSString *)name {
    NSString *lower = name.lowercaseString;
    NSArray<NSString *> *markers = @[ @"token", @"secret", @"password", @"passwd",
                                      @"pass", @"auth", @"session", @"sid", @"key",
                                      @"credential", @"code" ];
    for (NSString *marker in markers) {
        if ([lower containsString:marker]) return YES;
    }
    return NO;
}

- (NSString *)redactedURLStringForURL:(NSURL *)url {
    NSURLComponents *components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    if (!components) return url.absoluteString ?: @"";

    NSMutableArray<NSURLQueryItem *> *redactedItems = [NSMutableArray array];
    for (NSURLQueryItem *item in components.queryItems ?: @[]) {
        NSString *value = [self isSensitiveQueryName:item.name] ? @"[redacted]" : item.value;
        [redactedItems addObject:[NSURLQueryItem queryItemWithName:item.name value:value]];
    }
    if (redactedItems.count > 0) {
        components.queryItems = redactedItems;
    }

    return components.URL.absoluteString ?: url.absoluteString ?: @"";
}

- (void)appendJSONLine:(NSDictionary<NSString *, id> *)entry toPath:(NSString *)path {
    if (![NSJSONSerialization isValidJSONObject:entry]) return;

    NSError *error = nil;
    NSData *json = [NSJSONSerialization dataWithJSONObject:entry options:0 error:&error];
    if (!json) {
        NSLog(@"Could not encode JSON line: %@", error.localizedDescription);
        return;
    }

    NSMutableData *line = [json mutableCopy];
    const char newline = '\n';
    [line appendBytes:&newline length:1];

    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        if (![line writeToFile:path options:NSDataWritingAtomic error:&error]) {
            NSLog(@"Could not create %@: %@", path, error.localizedDescription);
        }
        return;
    }

    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
    if (!handle) return;
    @try {
        [handle seekToEndOfFile];
        [handle writeData:line];
    } @catch (NSException *exception) {
        NSLog(@"Could not append history: %@", exception.reason);
    } @finally {
        [handle closeFile];
    }
}

- (NSDateFormatter *)historyDateFormatter {
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    formatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ssZZZZZ";
    return formatter;
}

- (void)recordHistoryEntryForWebView:(WKWebView *)webView {
    NSURL *url = webView.URL;
    if (!url) return;

    NSString *urlString = [self redactedURLStringForURL:url];
    if (urlString.length == 0) return;

    BrowserTab *tab = [self tabForWebView:webView];
    NSString *lastRecordedURL = tab ? tab.lastRecordedURL : self.lastRecordedURL;
    if ([lastRecordedURL isEqualToString:urlString]) return;
    if (tab) {
        tab.lastRecordedURL = urlString;
    } else {
        self.lastRecordedURL = urlString;
    }

    NSDictionary<NSString *, id> *entry = @{
        @"timestamp": [[self historyDateFormatter] stringFromDate:[NSDate date]],
        @"url": urlString,
        @"title": webView.title ?: @"",
        @"host": url.host ?: @"",
        @"source": @"TrailBrowser"
    };

    [self appendJSONLine:entry toPath:[self historyFilePath]];
}

- (void)writeBrowserStateRunning:(BOOL)running {
    NSDictionary<NSString *, id> *state = @{
        @"running": @(running),
        @"updatedAt": [[self historyDateFormatter] stringFromDate:[NSDate date]],
        @"historyFile": [self historyFilePath],
        @"cookiesExposed": @NO
    };

    NSError *error = nil;
    NSData *json = [NSJSONSerialization dataWithJSONObject:state
                                                   options:NSJSONWritingPrettyPrinted
                                                     error:&error];
    if (!json) return;
    [json writeToFile:[self stateFilePath] options:NSDataWritingAtomic error:nil];
}

- (void)toggleSidebar:(id)sender {
    (void)sender;
    self.sidebarVisible = !self.sidebarVisible;
    if (self.sidebarVisible) {
        self.sidebar.hidden = NO;
        self.sidebarSeparator.hidden = NO;
    }
    ((TBFlatButton *)self.sidebarToggleButton).active = self.sidebarVisible;

    self.sidebarWidthConstraint.constant = self.sidebarVisible ? 240.0 : 0.0;
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = 0.2;
        context.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
        [self.window.contentView layoutSubtreeIfNeeded];
    } completionHandler:^{
        if (!self.sidebarVisible) {
            self.sidebar.hidden = YES;
            self.sidebarSeparator.hidden = YES;
        }
    }];
    [self updateControls];
}

- (void)goBack:(id)sender {
    (void)sender;
    if (self.webView.canGoBack) [self.webView goBack];
}

- (void)goForward:(id)sender {
    (void)sender;
    if (self.webView.canGoForward) [self.webView goForward];
}

- (void)goHome:(id)sender {
    (void)sender;
    [self loadURLString:[self homeURLString]];
}

- (void)reloadPage:(id)sender {
    (void)sender;
    if (!self.webView) return;
    if (self.webView.loading) {
        [self.webView stopLoading];
    } else {
        [self.webView reload];
    }
}

- (void)focusAddressBar:(id)sender {
    (void)sender;
    [self.window makeFirstResponder:self.addressField];
    [self.addressField selectText:nil];
}

- (void)controlTextDidBeginEditing:(NSNotification *)notification {
    if (notification.object == self.addressField) {
        self.userEditingAddress = YES;
        self.addressContainer.focused = YES;
        [self.addressContainer setNeedsDisplay:YES];
    }
}

- (void)controlTextDidEndEditing:(NSNotification *)notification {
    if (notification.object == self.addressField) {
        self.userEditingAddress = NO;
        self.addressContainer.focused = NO;
        [self.addressContainer setNeedsDisplay:YES];
    }
}

#pragma mark - Page assistant

- (void)assistantModeChanged:(id)sender {
    (void)sender;
    BOOL editMode = self.assistantModeControl.selectedIndex == 1;
    NSString *text = editMode ? @"Change this page" : @"Ask about this page";
    self.assistantPromptField.placeholderAttributedString =
        [[NSAttributedString alloc] initWithString:text
                                        attributes:@{ NSForegroundColorAttributeName: TBFaint(),
                                                      NSFontAttributeName: [NSFont systemFontOfSize:13.0 weight:NSFontWeightRegular] }];
}

- (void)closeAssistantResult:(id)sender {
    (void)sender;
    self.assistantResultPanel.hidden = YES;
}

- (void)openAssistant:(id)sender {
    (void)sender;
    [self.webContainer addSubview:self.assistantResultPanel positioned:NSWindowAbove relativeTo:self.webView];
    [self.webContainer addSubview:self.assistantBar positioned:NSWindowAbove relativeTo:self.assistantResultPanel];
    if (self.assistantBar.hidden) {
        self.assistantBar.alphaValue = 0.0;
        self.assistantBar.hidden = NO;
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
            context.duration = 0.18;
            context.allowsImplicitAnimation = YES;
            self.assistantBar.animator.alphaValue = 1.0;
        } completionHandler:nil];
    }
    [self.window makeFirstResponder:self.assistantPromptField];
}

- (void)collapseAssistant:(id)sender {
    (void)sender;
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = 0.15;
        self.assistantBar.animator.alphaValue = 0.0;
        self.assistantResultPanel.animator.alphaValue = 0.0;
    } completionHandler:^{
        self.assistantBar.hidden = YES;
        self.assistantResultPanel.hidden = YES;
        self.assistantBar.alphaValue = 1.0;
        self.assistantResultPanel.alphaValue = 1.0;
    }];
}

- (NSError *)assistantErrorWithMessage:(NSString *)message {
    return [NSError errorWithDomain:@"TrailBrowserAssistant"
                               code:1
                           userInfo:@{ NSLocalizedDescriptionKey: message ?: @"Assistant failed" }];
}

- (void)setAssistantWorking:(BOOL)working {
    self.assistantPromptField.enabled = !working;
    self.assistantModeControl.enabled = !working;
    self.assistantRunButton.enabled = !working;
    self.assistantSpinner.hidden = !working;
    if (working) {
        [self.assistantSpinner startAnimation:nil];
    } else {
        [self.assistantSpinner stopAnimation:nil];
    }
}

- (void)clearAssistantPromptField {
    self.assistantPromptField.stringValue = @"";
    NSText *editor = [self.assistantPromptField currentEditor];
    if (editor) editor.string = @"";
}

- (void)showAssistantMessage:(NSString *)message {
    [self openAssistant:nil];
    self.assistantResultPanel.hidden = NO;
    self.assistantResultTextView.string = message ?: @"";
}

- (NSString *)htmlEscaped:(NSString *)text {
    NSString *value = text ?: @"";
    value = [value stringByReplacingOccurrencesOfString:@"&" withString:@"&amp;"];
    value = [value stringByReplacingOccurrencesOfString:@"<" withString:@"&lt;"];
    value = [value stringByReplacingOccurrencesOfString:@">" withString:@"&gt;"];
    return value;
}

- (NSString *)statusPageHTMLForQuery:(NSString *)query
                              title:(NSString *)heading
                               note:(NSString *)note
                            spinning:(BOOL)spinning {
    NSString *q = [self htmlEscaped:query];
    NSString *spinner = spinning
        ? @"<div class='spin'></div>"
        : @"<div class='dot'></div>";
    return [NSString stringWithFormat:
        @"<!doctype html><html><head><meta charset='utf-8'><style>"
         "html,body{height:100%%;margin:0}"
         "body{display:grid;place-items:center;background:#0a0a0b;color:#f3f3f4;"
         "font-family:-apple-system,BlinkMacSystemFont,'SF Pro Display','Inter',sans-serif}"
         ".box{text-align:center;max-width:520px;padding:0 24px}"
         ".spin{width:34px;height:34px;margin:0 auto 22px;border-radius:50%%;"
         "border:3px solid rgba(255,255,255,0.12);border-top-color:#f76b1c;animation:s 0.8s linear infinite}"
         ".dot{width:14px;height:14px;margin:0 auto 22px;border-radius:50%%;background:#ff4d4d}"
         "@keyframes s{to{transform:rotate(360deg)}}"
         "h1{font-size:20px;font-weight:600;margin:0 0 8px}"
         "p{color:#8a8a90;font-size:14px;line-height:1.5;margin:0}"
         ".q{color:#f76b1c}"
         "</style></head><body><div class='box'>%@"
         "<h1>%@</h1><p class='q'>%@</p><p>%@</p></div></body></html>",
        spinner, [self htmlEscaped:heading], q, [self htmlEscaped:note]];
}

- (NSString *)contentFragmentFromCodexOutput:(NSString *)output {
    NSString *trimmed = [output stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];

    NSRegularExpression *fence =
        [NSRegularExpression regularExpressionWithPattern:@"```(?:html)?\\s*(.*?)```"
                                                  options:NSRegularExpressionCaseInsensitive | NSRegularExpressionDotMatchesLineSeparators
                                                    error:nil];
    NSTextCheckingResult *match = [fence firstMatchInString:trimmed options:0 range:NSMakeRange(0, trimmed.length)];
    if (match && match.numberOfRanges > 1) {
        trimmed = [[trimmed substringWithRange:[match rangeAtIndex:1]]
                   stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    }

    NSString *(^stripTag)(NSString *, NSString *) = ^NSString *(NSString *html, NSString *tag) {
        NSString *pattern = [NSString stringWithFormat:@"<%@[^>]*>.*?</%@>", tag, tag];
        NSRegularExpression *re =
            [NSRegularExpression regularExpressionWithPattern:pattern
                                                      options:NSRegularExpressionCaseInsensitive | NSRegularExpressionDotMatchesLineSeparators
                                                        error:nil];
        return [re stringByReplacingMatchesInString:html options:0 range:NSMakeRange(0, html.length) withTemplate:@""];
    };
    trimmed = stripTag(trimmed, @"script");
    trimmed = stripTag(trimmed, @"style");

    NSRegularExpression *bodyRe =
        [NSRegularExpression regularExpressionWithPattern:@"<body[^>]*>(.*?)</body>"
                                                  options:NSRegularExpressionCaseInsensitive | NSRegularExpressionDotMatchesLineSeparators
                                                    error:nil];
    NSTextCheckingResult *bodyMatch = [bodyRe firstMatchInString:trimmed options:0 range:NSMakeRange(0, trimmed.length)];
    if (bodyMatch && bodyMatch.numberOfRanges > 1) {
        trimmed = [trimmed substringWithRange:[bodyMatch rangeAtIndex:1]];
    }

    return [trimmed stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

- (NSString *)articlePageHTMLWithQuery:(NSString *)query contentHTML:(NSString *)contentHTML {
    return [NSString stringWithFormat:
        @"<!doctype html><html lang='en'><head><meta charset='utf-8'>"
         "<meta name='viewport' content='width=device-width, initial-scale=1'>"
         "<title>%@</title><style>"
         ":root{color-scheme:dark}"
         "*{box-sizing:border-box}"
         "html,body{margin:0}"
         "body{background:#0a0a0b;color:#f3f3f4;"
         "font-family:-apple-system,BlinkMacSystemFont,'SF Pro Display','Inter',sans-serif;"
         "line-height:1.7;font-size:16px;"
         "background-image:radial-gradient(900px 500px at 50%% -8%%,rgba(247,107,28,0.10),transparent 70%%)}"
         ".wrap{max-width:760px;margin:0 auto;padding:64px 28px 96px}"
         "header.page{border-bottom:1px solid rgba(255,255,255,0.09);padding-bottom:22px;margin-bottom:34px}"
         ".eyebrow{display:inline-flex;align-items:center;gap:7px;color:#f76b1c;font-size:12px;"
         "font-weight:700;letter-spacing:0.6px;text-transform:uppercase;margin:0 0 12px}"
         ".eyebrow::before{content:'';width:7px;height:7px;border-radius:50%%;background:#f76b1c}"
         "h1{font-size:30px;line-height:1.2;font-weight:700;letter-spacing:-0.5px;margin:0}"
         "article{animation:rise .4s cubic-bezier(.22,.61,.36,1) both}"
         "@keyframes rise{from{opacity:0;transform:translateY(10px)}to{opacity:1;transform:none}}"
         "h2{font-size:21px;font-weight:650;letter-spacing:-0.3px;margin:38px 0 12px}"
         "h3{font-size:17px;font-weight:650;margin:26px 0 8px}"
         "p{margin:0 0 16px;color:#e7e7ea}"
         "a{color:#ff8330;text-decoration:none;border-bottom:1px solid rgba(255,131,48,0.35)}"
         "a:hover{border-bottom-color:#ff8330}"
         "ul,ol{margin:0 0 18px;padding-left:22px}li{margin:6px 0;color:#e7e7ea}"
         "strong{color:#fff}"
         "blockquote{margin:20px 0;padding:4px 18px;border-left:3px solid #f76b1c;color:#c9c9cf}"
         "code{background:#1b1b1f;padding:2px 6px;border-radius:5px;font-size:0.92em}"
         "pre{background:#111113;border:1px solid rgba(255,255,255,0.09);border-radius:10px;"
         "padding:16px;overflow:auto}pre code{background:none;padding:0}"
         "table{width:100%%;border-collapse:collapse;margin:18px 0;font-size:14.5px}"
         "th,td{text-align:left;padding:10px 12px;border-bottom:1px solid rgba(255,255,255,0.09)}"
         "th{color:#8a8a90;font-weight:600;text-transform:uppercase;letter-spacing:0.4px;font-size:12px}"
         "hr{border:0;border-top:1px solid rgba(255,255,255,0.09);margin:34px 0}"
         "img{max-width:100%%;border-radius:10px}"
         "svg{display:block;max-width:100%%;height:auto;margin:8px auto 4px}"
         "@media(prefers-reduced-motion:reduce){article{animation:none}}"
         "</style></head><body><div class='wrap'>"
         "<header class='page'><p class='eyebrow'>TrailBrowser AI</p><h1>%@</h1></header>"
         "<article>%@</article></div></body></html>",
        [self htmlEscaped:query], [self htmlEscaped:query], contentHTML];
}

- (void)runWebpageSearchForQuery:(NSString *)query {
    NSString *trimmed = [query stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmed.length == 0) {
        NSBeep();
        return;
    }
    if (!self.webView) {
        [self newTabWithURLString:[self homeURLString] select:YES];
    }

    BrowserTab *tab = [self activeTab];
    if (tab) {
        tab.title = trimmed;
        tab.favicon = nil;
        [self reloadSidebarRowForTab:tab];
    }
    self.addressField.stringValue = trimmed;
    [self setStatusText:@"Loading"];
    [self.webView loadHTMLString:[self statusPageHTMLForQuery:trimmed
                                                        title:@"Generating a page for"
                                                         note:@"TrailBrowser AI is building a page with Codex…"
                                                     spinning:YES]
                         baseURL:nil];

    NSString *prompt = [NSString stringWithFormat:
        @"You are TrailBrowser AI. Respond to the user's query by returning an HTML body fragment that a styled template will display.\n"
         "Output format — IMPORTANT:\n"
         "- Return ONLY an HTML body fragment. No <!doctype>, <html>, <head>, <body>, <script>, <img>, external resources, or markdown code fences.\n"
         "- Do NOT repeat the query as a top-level <h1>; the template already shows the title.\n"
         "Pick the right mode for the query:\n"
         "- If it asks to DRAW, illustrate, visualize, render, or show a picture/diagram of something: output a self-contained inline <svg> illustration. Use a viewBox, shapes, paths, <defs> with radialGradient/linearGradient/filter for depth, and presentation attributes (fill, stroke) or inline style attributes for color. Make it detailed and visually convincing. You may add one short <p> caption below. Do NOT write an article in this case.\n"
         "- Otherwise: write a clear, accurate article — a short intro <p>, then sections with <h2> headings, <ul>/<ol>/<table> where useful, and a brief summary. Use accurate up-to-date facts; use live web search when helpful and link sources with <a href>.\n\n"
         "User query:\n%@\n",
        trimmed];

    [self runAIWithPrompt:prompt enableSearch:YES effortOverride:@"minimal" completion:^(NSString *output, NSError *error) {
        if (error) {
            [self setStatusText:error.localizedDescription ?: @"Failed"];
            [self.webView loadHTMLString:[self statusPageHTMLForQuery:trimmed
                                                                title:@"Could not generate a page"
                                                                 note:error.localizedDescription ?: @"Codex is unavailable. Is the codex CLI installed and on PATH?"
                                                             spinning:NO]
                                 baseURL:nil];
            return;
        }
        NSString *fragment = [self contentFragmentFromCodexOutput:output];
        if (fragment.length == 0) {
            [self setStatusText:@"Failed"];
            [self.webView loadHTMLString:[self statusPageHTMLForQuery:trimmed
                                                                title:@"No page was generated"
                                                                 note:@"The AI returned no usable content for this query. Try rephrasing it."
                                                             spinning:NO]
                                 baseURL:nil];
            return;
        }
        [self setStatusText:@"Ready"];
        [self.webView loadHTMLString:[self articlePageHTMLWithQuery:trimmed contentHTML:fragment] baseURL:nil];
        BrowserTab *active = [self activeTab];
        if (active) {
            active.title = trimmed;
            [self reloadSidebarRowForTab:active];
        }
    }];
}

- (void)runPageAssistant:(id)sender {
    (void)sender;
    NSString *request = [self.assistantPromptField.stringValue stringByTrimmingCharactersInSet:
                         NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (request.length == 0) {
        NSBeep();
        return;
    }
    if (!self.webView) {
        [self showAssistantMessage:@"No active page."];
        return;
    }

    BOOL editMode = self.assistantModeControl.selectedIndex == 1;
    [self clearAssistantPromptField];
    [self setAssistantWorking:YES];
    if (!editMode) {
        [self showAssistantMessage:@"Codex is reading the page and writing an answer..."];
    }

    [self pageSnapshotWithCompletion:^(NSString *snapshot, NSError *snapshotError) {
        if (snapshotError) {
            [self setAssistantWorking:NO];
            [self showAssistantMessage:snapshotError.localizedDescription];
            return;
        }

        NSString *prompt = [self codexPromptForRequest:request
                                              snapshot:snapshot
                                              editMode:editMode];
        [self runAIWithPrompt:prompt enableSearch:NO completion:^(NSString *output, NSError *codexError) {
            [self setAssistantWorking:NO];
            if (codexError) {
                [self showAssistantMessage:codexError.localizedDescription];
                return;
            }

            if (editMode) {
                [self applyAssistantJavaScript:[self editJavaScriptFromCodexOutput:output]];
            } else {
                [self showAssistantMessage:[output stringByTrimmingCharactersInSet:
                                            NSCharacterSet.whitespaceAndNewlineCharacterSet]];
            }
        }];
    }];
}

- (void)pageSnapshotWithCompletion:(void (^)(NSString *snapshot, NSError *error))completion {
    NSString *script =
        @"(() => {"
         "const clipText = (value, limit) => String(value || '').replace(/\\s+/g, ' ').trim().slice(0, limit);"
         "const clipRaw = (value, limit) => String(value || '').slice(0, limit);"
         "const sensitive = /(token|secret|password|passwd|auth|session|sid|key|credential|cookie|bearer)/i;"
         "const clone = document.documentElement ? document.documentElement.cloneNode(true) : null;"
         "if (clone) {"
         "clone.querySelectorAll('script,noscript,iframe').forEach(node => node.remove());"
         "clone.querySelectorAll('input,textarea,select').forEach(node => {"
         "node.removeAttribute('value');"
         "if (node.tagName === 'TEXTAREA') node.textContent = '';"
         "});"
         "clone.querySelectorAll('*').forEach(node => {"
         "Array.from(node.attributes || []).forEach(attr => {"
         "if (sensitive.test(attr.name) || sensitive.test(attr.value)) node.setAttribute(attr.name, '[redacted]');"
         "});"
         "});"
         "}"
         "const metas = Array.from(document.querySelectorAll('meta[name=\"description\"],meta[property=\"og:description\"]'))"
         ".map(m => m.content).filter(Boolean).slice(0, 3).join('\\n');"
         "const headings = Array.from(document.querySelectorAll('h1,h2,h3'))"
         ".map(h => h.innerText).filter(Boolean).slice(0, 40).join('\\n');"
         "const selection = String(window.getSelection ? window.getSelection() : '');"
         "const text = document.body ? document.body.innerText : '';"
         "const stylesheetLinks = Array.from(document.querySelectorAll('link[rel~=\"stylesheet\"][href]'))"
         ".map(link => link.href).slice(0, 20);"
         "const inlineStyles = Array.from(document.querySelectorAll('style'))"
         ".map(style => style.textContent || '').join('\\n\\n');"
         "return JSON.stringify({"
         "url: location.href,"
         "title: document.title,"
         "selection: clipText(selection, 4000),"
         "description: clipText(metas, 2000),"
         "headings: clipText(headings, 4000),"
         "visibleText: clipText(text, 20000),"
         "stylesheetLinks,"
         "inlineStyles: clipRaw(inlineStyles, 12000),"
         "sanitizedHTML: clipRaw(clone ? clone.outerHTML : '', 70000)"
         "});"
         "})()";

    [self.webView evaluateJavaScript:script completionHandler:^(id result, NSError *error) {
        if (error) {
            completion(nil, error);
            return;
        }
        if (![result isKindOfClass:NSString.class]) {
            completion(nil, [self assistantErrorWithMessage:@"Could not read page text."]);
            return;
        }
        completion(result, nil);
    }];
}

- (NSString *)codexPromptForRequest:(NSString *)request
                            snapshot:(NSString *)snapshot
                            editMode:(BOOL)editMode {
    if (editMode) {
        return [NSString stringWithFormat:
                @"You are TrailBrowser's page editing assistant.\n"
                 "Return strict JSON only. No markdown, no explanation.\n"
                 "Schema: {\"html\": string|null, \"css\": string|null, \"js\": string|null, \"summary\": string|null}.\n"
                 "TrailBrowser applies html first, then css, then js to the current WKWebView.\n"
                 "Use html when replacing the page body or whole document. Use css for styling. Use js for behavior, DOM patches, or incremental changes.\n"
                 "The html field may be a complete HTML document or a body fragment.\n"
                 "The css field should be raw CSS only.\n"
                 "The js field should be raw JavaScript only. Use it only when needed.\n"
                 "Use the sanitizedHTML field for structural edits and the visibleText/headings fields for content edits.\n"
                 "Do not fetch remote URLs, navigate, submit forms, read cookies, read localStorage/sessionStorage/indexedDB, use clipboard APIs, or exfiltrate data.\n"
                 "The edit is temporary and should keep the page usable. Make substantial changes when requested, including full redesigns.\n\n"
                 "User request:\n%@\n\n"
                 "Current page snapshot JSON:\n%@\n",
                request, snapshot ?: @"{}"];
    }

    return [NSString stringWithFormat:
            @"You are TrailBrowser's page question assistant.\n"
             "Answer using only the current page snapshot JSON. You can use visibleText, headings, sanitizedHTML, stylesheetLinks, and inlineStyles.\n"
             "If the answer is not present, say that it is not visible on the page.\n"
             "Give a useful, detailed answer with concrete observations from the page. Structure it with short paragraphs or bullets when helpful.\n\n"
             "User question:\n%@\n\n"
             "Current page snapshot JSON:\n%@\n",
            request, snapshot ?: @"{}"];
}

- (NSString *)shellQuotedString:(NSString *)string {
    NSString *escaped = [string stringByReplacingOccurrencesOfString:@"'"
                                                         withString:@"'\\''"];
    return [NSString stringWithFormat:@"'%@'", escaped];
}

- (void)runAIWithPrompt:(NSString *)prompt
           enableSearch:(BOOL)enableSearch
             completion:(void (^)(NSString *output, NSError *error))completion {
    [self runAIWithPrompt:prompt enableSearch:enableSearch effortOverride:nil completion:completion];
}

- (void)runAIWithPrompt:(NSString *)prompt
           enableSearch:(BOOL)enableSearch
         effortOverride:(NSString *)effortOverride
             completion:(void (^)(NSString *output, NSError *error))completion {
    NSString *supportPath = [self supportDirectoryPath];
    NSString *uuid = NSUUID.UUID.UUIDString;
    NSString *outputPath = [supportPath stringByAppendingPathComponent:
                            [NSString stringWithFormat:@"codex-%@.txt", uuid]];
    NSString *logPath = [supportPath stringByAppendingPathComponent:
                         [NSString stringWithFormat:@"codex-%@.log", uuid]];
    [[NSFileManager defaultManager] createFileAtPath:logPath contents:nil attributes:nil];

    NSFileHandle *logHandle = [NSFileHandle fileHandleForWritingAtPath:logPath];
    NSPipe *inputPipe = [NSPipe pipe];

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *engine = [defaults stringForKey:@"TBAIEngine"] ?: @"codex";
    NSString *pathSetup =
        @"for d in \"$HOME\"/.nvm/versions/node/*/bin /opt/homebrew/bin /usr/local/bin; do "
         "[ -d \"$d\" ] && PATH=\"$d:$PATH\"; done; export PATH; ";

    NSString *command;
    if ([engine isEqualToString:@"claude"]) {
        NSString *model = [defaults stringForKey:@"TBClaudeModel"];
        NSString *modelFlag = model.length > 0
            ? [NSString stringWithFormat:@"--model %@ ", [self shellQuotedString:model]]
            : @"";

        command = [pathSetup stringByAppendingFormat:@"claude -p %@--output-format text", modelFlag];
    } else {
        NSString *searchFlag = enableSearch ? @"--search " : @"";
        NSString *model = [defaults stringForKey:@"TBCodexModel"];
        NSString *modelFlag = model.length > 0
            ? [NSString stringWithFormat:@"-m %@ ", [self shellQuotedString:model]]
            : @"";
        NSString *effort = [defaults stringForKey:@"TBCodexEffort"];
        if (effort.length == 0) effort = effortOverride.length > 0 ? effortOverride : @"minimal";
        if (enableSearch && [effort isEqualToString:@"minimal"]) effort = @"low";
        NSString *effortFlag = [NSString stringWithFormat:@"-c model_reasoning_effort=%@ ",
                                [self shellQuotedString:effort]];
        command = [pathSetup stringByAppendingFormat:
                   @"codex %@exec %@%@--skip-git-repo-check --sandbox read-only "
                    "--ephemeral --color never --output-last-message %@ -",
                   searchFlag, modelFlag, effortFlag, [self shellQuotedString:outputPath]];
    }

    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:@"/bin/zsh"];
    task.arguments = @[ @"-lc", command ];
    task.currentDirectoryURL = [NSURL fileURLWithPath:NSHomeDirectory()];
    task.standardInput = inputPipe;
    task.standardOutput = logHandle;
    task.standardError = logHandle;
    task.terminationHandler = ^(NSTask *finishedTask) {
        [logHandle closeFile];
        NSData *outputData = [NSData dataWithContentsOfFile:outputPath];
        NSData *logData = [NSData dataWithContentsOfFile:logPath];
        NSString *output = [[NSString alloc] initWithData:outputData ?: [NSData data]
                                                 encoding:NSUTF8StringEncoding] ?: @"";
        NSString *log = [[NSString alloc] initWithData:logData ?: [NSData data]
                                             encoding:NSUTF8StringEncoding] ?: @"";

        [[NSFileManager defaultManager] removeItemAtPath:outputPath error:nil];
        [[NSFileManager defaultManager] removeItemAtPath:logPath error:nil];

        NSString *finalOutput = output.length ? output : log;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (finishedTask.terminationStatus != 0) {
                NSString *message = log.length ? log : @"Codex command failed.";
                completion(nil, [self assistantErrorWithMessage:message]);
                return;
            }
            completion(finalOutput, nil);
        });
    };

    NSError *launchError = nil;
    if (![task launchAndReturnError:&launchError]) {
        [logHandle closeFile];
        completion(nil, launchError);
        return;
    }

    NSData *promptData = [prompt dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data];
    [[inputPipe fileHandleForWriting] writeData:promptData];
    [[inputPipe fileHandleForWriting] closeFile];
}

- (NSString *)javaScriptStringLiteralForString:(NSString *)string {
    NSData *json = [NSJSONSerialization dataWithJSONObject:@[ string ?: @"" ]
                                                   options:0
                                                     error:nil];
    NSString *arrayLiteral = [[NSString alloc] initWithData:json ?: [NSData data]
                                                   encoding:NSUTF8StringEncoding] ?: @"[\"\"]";
    if (arrayLiteral.length < 2) return @"\"\"";
    return [arrayLiteral substringWithRange:NSMakeRange(1, arrayLiteral.length - 2)];
}

- (NSString *)scriptForReplacingDocumentWithHTML:(NSString *)html {
    NSString *literal = [self javaScriptStringLiteralForString:html ?: @""];
    return [NSString stringWithFormat:
            @"(() => { document.open(); document.write(%@); document.close(); })();",
            literal];
}

- (NSString *)scriptForInjectingCSS:(NSString *)css {
    NSString *literal = [self javaScriptStringLiteralForString:css ?: @""];
    return [NSString stringWithFormat:
            @"(() => {"
             "let style = document.getElementById('__trailbrowser_codex_style__');"
             "if (!style) { style = document.createElement('style'); style.id = '__trailbrowser_codex_style__'; document.head.appendChild(style); }"
             "style.textContent = %@;"
             "})();",
            literal];
}

- (NSString *)scriptForStructuredPageUpdate:(NSDictionary<NSString *, id> *)payload {
    id htmlValue = payload[@"html"];
    id cssValue = payload[@"css"];
    id jsValue = payload[@"js"];
    NSString *html = [htmlValue isKindOfClass:NSString.class] ? htmlValue : @"";
    NSString *css = [cssValue isKindOfClass:NSString.class] ? cssValue : @"";
    NSString *js = [jsValue isKindOfClass:NSString.class] ? jsValue : @"";

    NSString *jsonLiteral = [self javaScriptStringLiteralForString:
                             [[NSString alloc] initWithData:
                              [NSJSONSerialization dataWithJSONObject:@{
                                  @"html": html ?: @"",
                                  @"css": css ?: @"",
                                  @"js": js ?: @""
                              }
                                                              options:0
                                                                error:nil] ?: [NSData data]
                                                       encoding:NSUTF8StringEncoding] ?: @"{}"];

    return [NSString stringWithFormat:
            @"(() => {"
             "const payload = JSON.parse(%@);"
             "const html = String(payload.html || '');"
             "const css = String(payload.css || '');"
             "const js = String(payload.js || '');"
             "if (html.trim()) {"
             "const lower = html.trim().slice(0, 80).toLowerCase();"
             "if (lower.startsWith('<!doctype') || lower.startsWith('<html')) {"
             "document.open(); document.write(html); document.close();"
             "} else {"
             "if (!document.body) document.documentElement.appendChild(document.createElement('body'));"
             "document.body.innerHTML = html;"
             "}"
             "}"
             "if (css.trim()) {"
             "let style = document.getElementById('__trailbrowser_codex_style__');"
             "if (!style) { style = document.createElement('style'); style.id = '__trailbrowser_codex_style__'; document.head.appendChild(style); }"
             "style.textContent = css;"
             "}"
             "if (js.trim()) { (new Function(js))(); }"
             "})();",
            jsonLiteral];
}

- (BOOL)looksLikeHTML:(NSString *)text {
    NSString *trimmed = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *lower = trimmed.lowercaseString;
    return [lower hasPrefix:@"<!doctype"] ||
           [lower hasPrefix:@"<html"] ||
           [lower hasPrefix:@"<body"] ||
           ([lower hasPrefix:@"<"] && [lower containsString:@">"] && [lower containsString:@"</"]);
}

- (BOOL)looksLikeCSS:(NSString *)text {
    NSString *trimmed = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if ([self looksLikeHTML:trimmed]) return NO;
    if ([trimmed containsString:@"=>"] || [trimmed containsString:@"function"] || [trimmed containsString:@"document."]) return NO;
    return ([trimmed containsString:@"{"] && [trimmed containsString:@"}"] && [trimmed containsString:@":"]);
}

- (NSString *)editJavaScriptFromCodexOutput:(NSString *)output {
    NSString *trimmed = [output stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSRegularExpression *regex =
        [NSRegularExpression regularExpressionWithPattern:@"```([A-Za-z0-9_-]+)?\\s*(.*?)```"
                                                  options:NSRegularExpressionCaseInsensitive | NSRegularExpressionDotMatchesLineSeparators
                                                    error:nil];
    NSTextCheckingResult *match = [regex firstMatchInString:trimmed
                                                    options:0
                                                      range:NSMakeRange(0, trimmed.length)];
    NSString *language = @"";
    NSString *code = trimmed;
    if (match.numberOfRanges > 2) {
        NSRange languageRange = [match rangeAtIndex:1];
        NSRange codeRange = [match rangeAtIndex:2];
        if (languageRange.location != NSNotFound) {
            language = [[trimmed substringWithRange:languageRange] lowercaseString];
        }
        code = [[trimmed substringWithRange:codeRange]
                stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    }

    NSData *jsonData = [code dataUsingEncoding:NSUTF8StringEncoding];
    id json = jsonData ? [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:nil] : nil;
    if ([json isKindOfClass:NSDictionary.class]) {
        return [self scriptForStructuredPageUpdate:json];
    }

    if ([language isEqualToString:@"json"]) {
        return @"";
    } else if ([language isEqualToString:@"html"] || [self looksLikeHTML:code]) {
        return [self scriptForReplacingDocumentWithHTML:code];
    }
    if ([language isEqualToString:@"css"] || [self looksLikeCSS:code]) {
        return [self scriptForInjectingCSS:code];
    }
    return code;
}

- (void)applyAssistantJavaScript:(NSString *)script {
    if (script.length == 0) {
        [self showAssistantMessage:@"Codex did not return JavaScript."];
        return;
    }

    [self.webView evaluateJavaScript:script completionHandler:^(id result, NSError *error) {
        (void)result;
        if (error) {
            [self showAssistantMessage:error.localizedDescription ?: @"Could not apply page edit."];
        }
    }];
}

#pragma mark - Sidebar tabs

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    (void)tableView;
    return (NSInteger)self.tabs.count;
}

- (NSTableRowView *)tableView:(NSTableView *)tableView rowViewForRow:(NSInteger)row {
    (void)tableView;
    BrowserTabRowView *rowView = [[BrowserTabRowView alloc] initWithFrame:NSZeroRect];
    rowView.activeTab = (row == self.activeTabIndex);
    return rowView;
}

- (void)refreshActiveRowHighlight {
    [self.tabTable enumerateAvailableRowViewsUsingBlock:^(NSTableRowView *rowView, NSInteger row) {
        if ([rowView isKindOfClass:BrowserTabRowView.class]) {
            ((BrowserTabRowView *)rowView).activeTab = (row == self.activeTabIndex);
        }
    }];
}

- (NSString *)subtitleForTab:(BrowserTab *)tab {
    NSURL *url = [NSURL URLWithString:tab.urlString ?: @""];
    if (url.host.length > 0) return url.host;
    if (tab.urlString.length > 0) return tab.urlString;
    return @"New tab";
}

- (void)reloadSidebarRowForTab:(BrowserTab *)tab {
    NSUInteger index = [self.tabs indexOfObject:tab];
    if (index == NSNotFound) return;

    [self.tabTable reloadDataForRowIndexes:[NSIndexSet indexSetWithIndex:index]
                             columnIndexes:[NSIndexSet indexSetWithIndex:0]];
}

- (BOOL)isHTTPURL:(NSURL *)url {
    NSString *scheme = url.scheme.lowercaseString;
    return [scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"];
}

- (NSURL *)defaultFaviconURLForPageURL:(NSURL *)pageURL {
    if (![self isHTTPURL:pageURL]) return nil;

    NSURLComponents *components = [NSURLComponents componentsWithURL:pageURL
                                             resolvingAgainstBaseURL:NO];
    components.path = @"/favicon.ico";
    components.query = nil;
    components.fragment = nil;
    return components.URL;
}

- (void)fetchFaviconForWebView:(WKWebView *)webView {
    BrowserTab *tab = [self tabForWebView:webView];
    NSURL *pageURL = webView.URL;
    NSURL *fallbackURL = [self defaultFaviconURLForPageURL:pageURL];
    if (!tab || !fallbackURL) return;

    NSString *script =
        @"(() => {"
         "const links = Array.from(document.querySelectorAll('link[rel][href]'));"
         "const rel = /(apple-touch-icon|shortcut icon|icon)/i;"
         "const picked = links.find(link => rel.test(link.rel));"
         "return picked ? picked.href : (location.origin + '/favicon.ico');"
         "})()";

    [webView evaluateJavaScript:script completionHandler:^(id result, NSError *error) {
        (void)error;
        NSString *faviconString = [result isKindOfClass:NSString.class] ? result : nil;
        NSURL *faviconURL = faviconString.length > 0 ? [NSURL URLWithString:faviconString] : fallbackURL;
        if (![self isHTTPURL:faviconURL]) faviconURL = fallbackURL;
        [self requestFaviconAtURL:faviconURL fallbackURL:fallbackURL forTab:tab];
    }];
}

- (void)requestFaviconAtURL:(NSURL *)faviconURL
                fallbackURL:(NSURL *)fallbackURL
                     forTab:(BrowserTab *)tab {
    if (![self isHTTPURL:faviconURL]) return;

    NSString *faviconURLString = faviconURL.absoluteString;
    if ([tab.faviconURLString isEqualToString:faviconURLString] && tab.favicon) return;
    if ([tab.pendingFaviconURLString isEqualToString:faviconURLString]) return;

    tab.pendingFaviconURLString = faviconURLString;
    NSURLSessionDataTask *task = [NSURLSession.sharedSession dataTaskWithURL:faviconURL
                                                           completionHandler:^(NSData *data,
                                                                               NSURLResponse *response,
                                                                               NSError *error) {
        (void)response;
        NSImage *image = nil;
        if (!error && data.length > 0 && data.length < 512 * 1024) {
            image = [[NSImage alloc] initWithData:data];
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            if ([self.tabs indexOfObject:tab] == NSNotFound) return;

            tab.pendingFaviconURLString = nil;
            if (!image) {
                BOOL canTryFallback = fallbackURL &&
                    ![fallbackURL.absoluteString isEqualToString:faviconURLString];
                if (canTryFallback) {
                    [self requestFaviconAtURL:fallbackURL fallbackURL:nil forTab:tab];
                }
                return;
            }

            image.template = NO;
            tab.favicon = image;
            tab.faviconURLString = faviconURLString;
            [self reloadSidebarRowForTab:tab];
        });
    }];
    [task resume];
}

- (NSView *)tableView:(NSTableView *)tableView
   viewForTableColumn:(NSTableColumn *)tableColumn
                  row:(NSInteger)row {
    (void)tableColumn;
    if (row < 0 || row >= (NSInteger)self.tabs.count) return nil;

    static NSString *identifier = @"TrailBrowserTabCell";
    BrowserTabCellView *cell = (BrowserTabCellView *)[tableView makeViewWithIdentifier:identifier owner:self];

    if (!cell) {
        cell = [[BrowserTabCellView alloc] initWithFrame:NSZeroRect];
        cell.identifier = identifier;

        NSImageView *icon = [[NSImageView alloc] initWithFrame:NSZeroRect];
        icon.translatesAutoresizingMaskIntoConstraints = NO;
        icon.imageScaling = NSImageScaleProportionallyDown;
        icon.wantsLayer = YES;
        icon.layer.cornerRadius = 4.0;
        icon.layer.masksToBounds = YES;
        if (@available(macOS 11.0, *)) {
            NSImage *image = [NSImage imageWithSystemSymbolName:@"globe" accessibilityDescription:@"Tab"];
            image.template = YES;
            icon.image = image;
        }
        if (@available(macOS 10.14, *)) {
            icon.contentTintColor = TBFaint();
        }
        [cell addSubview:icon];
        cell.tabIconView = icon;
        cell.imageView = icon;

        NSTextField *title = [NSTextField labelWithString:@""];
        title.translatesAutoresizingMaskIntoConstraints = NO;
        title.font = [NSFont systemFontOfSize:13.0 weight:NSFontWeightMedium];
        title.lineBreakMode = NSLineBreakByTruncatingTail;
        title.maximumNumberOfLines = 1;
        [cell addSubview:title];
        cell.titleLabel = title;
        cell.textField = title;

        NSTextField *subtitle = [NSTextField labelWithString:@""];
        subtitle.translatesAutoresizingMaskIntoConstraints = NO;
        subtitle.font = [NSFont systemFontOfSize:11.0 weight:NSFontWeightRegular];
        subtitle.lineBreakMode = NSLineBreakByTruncatingMiddle;
        subtitle.maximumNumberOfLines = 1;
        [cell addSubview:subtitle];
        cell.subtitleLabel = subtitle;

        TBFlatButton *close = [[TBFlatButton alloc] initWithFrame:NSZeroRect];
        close.translatesAutoresizingMaskIntoConstraints = NO;
        close.cornerRadius = 5.0;
        close.imagePosition = NSImageOnly;
        close.imageScaling = NSImageScaleProportionallyDown;
        close.toolTip = @"Close Tab";
        close.hidden = YES;
        close.target = self;
        close.action = @selector(closeTabFromButton:);
        if (@available(macOS 11.0, *)) {
            NSImage *image = [NSImage imageWithSystemSymbolName:@"xmark" accessibilityDescription:@"Close Tab"];
            NSImageSymbolConfiguration *config = [NSImageSymbolConfiguration configurationWithPointSize:10.0
                                                                                                 weight:NSFontWeightSemibold];
            image = [image imageWithSymbolConfiguration:config] ?: image;
            image.template = YES;
            close.image = image;
        }
        if (@available(macOS 10.14, *)) close.contentTintColor = TBMuted();
        [cell addSubview:close];
        cell.closeButton = close;

        [NSLayoutConstraint activateConstraints:@[
            [icon.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:22.0],
            [icon.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
            [icon.widthAnchor constraintEqualToConstant:16.0],
            [icon.heightAnchor constraintEqualToConstant:16.0],

            [title.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:10.0],
            [title.trailingAnchor constraintEqualToAnchor:close.leadingAnchor constant:-6.0],
            [title.topAnchor constraintEqualToAnchor:cell.topAnchor constant:8.0],

            [subtitle.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
            [subtitle.trailingAnchor constraintEqualToAnchor:title.trailingAnchor],
            [subtitle.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:1.0],

            [close.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-10.0],
            [close.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
            [close.widthAnchor constraintEqualToConstant:20.0],
            [close.heightAnchor constraintEqualToConstant:20.0]
        ]];
    }

    BrowserTab *tab = self.tabs[(NSUInteger)row];
    BOOL selected = row == self.activeTabIndex;
    cell.closeButton.tag = row;
    cell.closeButton.hidden = !cell.hovering;

    BOOL sleeping = (!selected && tab.webView == nil);
    cell.titleLabel.stringValue = tab.title.length ? tab.title : @"New Tab";
    cell.subtitleLabel.stringValue = [self subtitleForTab:tab];
    cell.titleLabel.textColor = selected ? TBText() : TBMuted();
    cell.subtitleLabel.textColor = TBFaint();
    cell.tabIconView.alphaValue = sleeping ? 0.55 : 1.0;

    if (tab.favicon) {
        tab.favicon.template = NO;
        cell.tabIconView.image = tab.favicon;
        if (@available(macOS 10.14, *)) cell.tabIconView.contentTintColor = nil;
    } else {
        if (@available(macOS 11.0, *)) {
            NSImage *image = [NSImage imageWithSystemSymbolName:@"globe" accessibilityDescription:@"Website"];
            image.template = YES;
            cell.tabIconView.image = image;
        }
        if (@available(macOS 10.14, *)) {
            cell.tabIconView.contentTintColor = selected ? TBAccent() : TBFaint();
        }
    }
    return cell;
}

- (void)closeTabFromButton:(id)sender {
    NSInteger row = [sender tag];
    [self closeTabAtIndex:row];
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    if (notification.object != self.tabTable) return;
    NSInteger row = self.tabTable.selectedRow;
    if (row >= 0 && row != self.activeTabIndex) {
        [self selectTabAtIndex:row];
    }
}

- (void)updateSidebarTitleForWebView:(WKWebView *)webView {
    BrowserTab *tab = [self tabForWebView:webView];
    if (!tab) return;

    if ([self isHomeURLString:tab.urlString]) {
        tab.title = @"TrailBrowser Home";
        [self reloadSidebarRowForTab:tab];
        return;
    }

    if ([self isSettingsURLString:tab.urlString]) {
        tab.title = @"Settings";
        [self reloadSidebarRowForTab:tab];
        return;
    }

    if ([self isOnboardingURLString:tab.urlString]) {
        tab.title = @"Welcome";
        [self reloadSidebarRowForTab:tab];
        return;
    }

    NSString *previousHost = [NSURL URLWithString:tab.urlString ?: @""].host.lowercaseString;
    NSString *currentHost = webView.URL.host.lowercaseString;
    if (previousHost.length > 0 &&
        currentHost.length > 0 &&
        ![previousHost isEqualToString:currentHost]) {
        tab.favicon = nil;
        tab.faviconURLString = nil;
        tab.pendingFaviconURLString = nil;
    }

    NSString *title = webView.title;
    if (title.length == 0) {
        title = webView.URL.host.length ? webView.URL.host : @"New Tab";
    }
    tab.title = title;
    if (webView.URL.absoluteString.length > 0) tab.urlString = webView.URL.absoluteString;

    [self reloadSidebarRowForTab:tab];
}

#pragma mark - Chrome cookie import

- (void)importChromeCookies:(id)sender {
    (void)sender;

    if (![ChromeCookieImporter isChromeInstalled]) {
        [self showImportAlertWithStyle:NSAlertStyleInformational
                                 title:@"Google Chrome not found"
                               message:@"No Google Chrome data was found for your user account."];
        return;
    }

    NSArray<ChromeProfile *> *profiles = [ChromeCookieImporter availableProfiles];
    if (profiles.count == 0) {
        [self showImportAlertWithStyle:NSAlertStyleInformational
                                 title:@"No Chrome profiles found"
                               message:@"TrailBrowser could not find any Chrome profiles with cookies."];
        return;
    }

    ChromeProfile *profile = [self promptForProfileFrom:profiles];
    if (!profile) return;

    [self performCookieImportForProfile:profile];
}

- (ChromeProfile *)promptForProfileFrom:(NSArray<ChromeProfile *> *)profiles {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.alertStyle = NSAlertStyleInformational;
    alert.messageText = @"Import cookies from Chrome";
    alert.informativeText =
        @"TrailBrowser will copy cookies from your Chrome profile into this browser "
         "so you stay signed in to your sites. macOS may ask permission to read "
         "\"Chrome Safe Storage\" from your Keychain.";
    [alert addButtonWithTitle:@"Import"];
    [alert addButtonWithTitle:@"Cancel"];

    NSPopUpButton *picker = nil;
    if (profiles.count > 1) {
        picker = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, 0, 280, 26)
                                            pullsDown:NO];
        for (ChromeProfile *profile in profiles) {
            NSString *label = profile.email.length
                ? [NSString stringWithFormat:@"%@ (%@)", profile.displayName, profile.email]
                : profile.displayName;
            [picker addItemWithTitle:label];
        }
        [picker selectItemAtIndex:0];
        alert.accessoryView = picker;
    }

    NSModalResponse response = [alert runModal];
    if (response != NSAlertFirstButtonReturn) return nil;

    NSUInteger index = picker ? (NSUInteger)picker.indexOfSelectedItem : 0;
    if (index >= profiles.count) index = 0;
    return profiles[index];
}

- (void)performCookieImportForProfile:(ChromeProfile *)profile {
    [self setStatusText:@"Importing cookies…"];

    WKHTTPCookieStore *store = self.webView.configuration.websiteDataStore.httpCookieStore;
    [ChromeCookieImporter importProfileDirectory:profile.directory
                                 intoCookieStore:store
                                      completion:^(ChromeCookieImportResult *result, NSError *error) {
        [self setStatusText:@"Ready"];

        if (error) {
            [self showImportAlertWithStyle:NSAlertStyleWarning
                                     title:@"Could not import cookies"
                                   message:error.localizedDescription ?: @"An unknown error occurred."];
            return;
        }

        NSString *message = [NSString stringWithFormat:
                             @"Imported %lu cookie%@ from \"%@\".\n\n"
                              "Reload the current page to use them.",
                             (unsigned long)result.imported,
                             result.imported == 1 ? @"" : @"s",
                             profile.displayName];
        [self showImportAlertWithStyle:NSAlertStyleInformational
                                 title:@"Cookies imported"
                               message:message];

        if (self.webView.URL) [self.webView reload];
    }];
}

- (void)showImportAlertWithStyle:(NSAlertStyle)style
                           title:(NSString *)title
                         message:(NSString *)message {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.alertStyle = style;
    alert.messageText = title;
    alert.informativeText = message;
    [alert addButtonWithTitle:@"OK"];
    [alert runModal];
}

- (void)updateControls {
    self.backButton.enabled = self.webView && self.webView.canGoBack;
    self.forwardButton.enabled = self.webView && self.webView.canGoForward;
    self.closeTabButton.enabled = self.tabs.count > 1;

    BOOL loading = self.webView && self.webView.loading;
    self.reloadButton.toolTip = loading ? @"Stop" : @"Reload";
    if (@available(macOS 11.0, *)) {
        NSString *symbol = loading ? @"xmark" : @"arrow.clockwise";
        NSImage *image = [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:self.reloadButton.toolTip];
        image.template = YES;
        self.reloadButton.image = image;

        NSString *sidebarSymbol = self.sidebarVisible ? @"sidebar.left" : @"sidebar.leading";
        NSImage *sidebarImage = [NSImage imageWithSystemSymbolName:sidebarSymbol
                                         accessibilityDescription:self.sidebarToggleButton.toolTip];
        if (sidebarImage) {
            sidebarImage.template = YES;
            self.sidebarToggleButton.image = sidebarImage;
        }
    } else {
        self.reloadButton.title = loading ? @"X" : @"R";
    }

    self.progressBar.hidden = !loading;
    if (!loading) self.progressBar.progress = 0.0;
}

- (void)syncAddressBarWithWebView {
    if ([self isAddressFieldBeingEdited]) return;

    BrowserTab *tab = [self activeTab];
    if ([self isHomeURLString:tab.urlString]) {
        self.addressField.stringValue = [self homeURLString];
        return;
    }
    if ([self isSettingsURLString:tab.urlString]) {
        self.addressField.stringValue = [self settingsURLString];
        return;
    }
    if ([self isOnboardingURLString:tab.urlString]) {
        self.addressField.stringValue = [self onboardingURLString];
        return;
    }

    NSURL *url = self.webView.URL;
    if (url) self.addressField.stringValue = url.absoluteString;
}

- (BOOL)isAddressFieldBeingEdited {
    return self.userEditingAddress ||
           self.window.firstResponder == self.addressField ||
           self.window.firstResponder == self.addressField.currentEditor;
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary<NSKeyValueChangeKey, id> *)change
                       context:(void *)context {
    (void)change;
    WKWebView *observedWebView = [object isKindOfClass:WKWebView.class] ? object : nil;

    if (context == BrowserProgressContext) {
        if (observedWebView != self.webView) return;
        double progress = self.webView.estimatedProgress;
        self.progressBar.progress = progress;
        self.progressBar.hidden = !self.webView.loading || progress >= 1.0;
        return;
    }

    if (context == BrowserURLContext) {
        if (observedWebView) [self updateSidebarTitleForWebView:observedWebView];
        if (observedWebView == self.webView) [self syncAddressBarWithWebView];
        return;
    }

    if (context == BrowserCanGoBackContext || context == BrowserCanGoForwardContext) {
        if (observedWebView == self.webView) [self updateControls];
        return;
    }

    [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}

- (void)webView:(WKWebView *)webView didStartProvisionalNavigation:(WKNavigation *)navigation {
    (void)navigation;
    if (webView != self.webView) return;
    [self setStatusText:@"Loading"];
    [self updateControls];
}

- (void)webView:(WKWebView *)webView didCommitNavigation:(WKNavigation *)navigation {
    (void)navigation;
    [self updateSidebarTitleForWebView:webView];
    if (webView == self.webView) [self syncAddressBarWithWebView];
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    (void)navigation;
    [self preloadFinishedForWebView:webView];
    [self updateSidebarTitleForWebView:webView];
    [self fetchFaviconForWebView:webView];
    if (webView == self.webView) {
        [self setStatusText:@"Ready"];
        [self syncAddressBarWithWebView];
    }
    [self recordHistoryEntryForWebView:webView];
    [self writeBrowserStateRunning:YES];
    if (webView == self.webView) [self updateControls];
}

- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    (void)navigation;
    [self preloadFinishedForWebView:webView];
    if (webView != self.webView) return;
    [self setStatusText:error.localizedDescription ?: @"Failed"];
    [self updateControls];
}

- (void)webView:(WKWebView *)webView
decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction
decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    (void)webView;
    NSURL *url = navigationAction.request.URL;

    if ([url.scheme.lowercaseString isEqualToString:@"trailbrowser"]) {
        NSString *host = url.host.lowercaseString ?: @"";
        BOOL pageHost = host.length == 0 ||
                        [host isEqualToString:@"home"] ||
                        [host isEqualToString:@"settings"] ||
                        [host isEqualToString:@"welcome"];

        if (pageHost && self.renderingInternalPage) {
            self.renderingInternalPage = NO;
            decisionHandler(WKNavigationActionPolicyAllow);
            return;
        }
        if ([self handleInternalURL:url]) {
            decisionHandler(WKNavigationActionPolicyCancel);
            return;
        }
    }

    decisionHandler(WKNavigationActionPolicyAllow);
}

- (void)webView:(WKWebView *)webView
didFailProvisionalNavigation:(WKNavigation *)navigation
      withError:(NSError *)error {
    [self webView:webView didFailNavigation:navigation withError:error];
}

- (WKWebView *)webView:(WKWebView *)webView
createWebViewWithConfiguration:(WKWebViewConfiguration *)configuration
   forNavigationAction:(WKNavigationAction *)navigationAction
        windowFeatures:(WKWindowFeatures *)windowFeatures {
    (void)webView;
    (void)windowFeatures;

    if (!navigationAction.targetFrame) {
        BrowserTab *tab = [self newTabWithConfiguration:configuration URLString:nil select:YES];
        return tab.webView;
    }
    return nil;
}

@end

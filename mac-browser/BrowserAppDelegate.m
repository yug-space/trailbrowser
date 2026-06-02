#import "BrowserAppDelegate.h"

#import <AuthenticationServices/AuthenticationServices.h>
#import <QuartzCore/QuartzCore.h>
#import <Security/Security.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#import "BrowserTab.h"
#import "BrowserTabViews.h"
#import "ChromeCookieImporter.h"
#import "TBControls.h"
#import "TBTheme.h"

@interface BrowserAppDelegate () <NSMenuDelegate>
@property (nonatomic, assign) NSInteger tabActivationCounter;
@property (nonatomic, strong) dispatch_source_t memoryPressureSource;
@property (nonatomic, strong) NSMutableArray<BrowserTab *> *preloadQueue;
@property (nonatomic, strong) NSMutableSet<WKWebView *> *preloadingWebViews;
@property (nonatomic, strong) NSMutableArray<NSDictionary<NSString *, id> *> *recentlyClosedTabs;
@property (nonatomic, strong) NSMutableSet<WKDownload *> *activeDownloads;
@property (nonatomic, strong) NSMapTable<WKDownload *, NSMutableDictionary<NSString *, id> *> *downloadMetadata;
@property (nonatomic, strong) NSTimer *downloadRefreshTimer;
@property (nonatomic, strong) NSVisualEffectView *addressSuggestionsPanel;
@property (nonatomic, strong) NSStackView *addressSuggestionsStack;
@property (nonatomic, strong) NSLayoutConstraint *addressSuggestionsHeightConstraint;
@property (nonatomic, copy) NSArray<NSDictionary<NSString *, NSString *> *> *addressSuggestions;
@property (nonatomic, assign) NSInteger addressSuggestionIndex;
@property (nonatomic, strong) NSButton *siteInfoButton;
@property (nonatomic, strong) NSButton *bookmarkButton;
@property (nonatomic, strong) NSButton *bookmarksButton;
@property (nonatomic, strong) NSPopover *bookmarksPopover;
@property (nonatomic, strong) NSView *bookmarkBar;
@property (nonatomic, strong) NSStackView *bookmarkBarStack;
@property (nonatomic, strong) NSLayoutConstraint *bookmarkBarHeightConstraint;
@property (nonatomic, assign) BOOL bookmarkBarVisible;
@property (nonatomic, strong) NSButton *downloadsButton;
@property (nonatomic, strong) NSPopover *downloadsPopover;
@property (nonatomic, strong) NSMenu *tabContextMenu;
@property (nonatomic, strong) TBPillButton *autofillButton;
@property (nonatomic, strong) NSLayoutConstraint *autofillButtonWidthConstraint;
@property (nonatomic, strong) NSVisualEffectView *findBar;
@property (nonatomic, strong) NSTextField *findField;
@property (nonatomic, strong) NSTextField *findStatusLabel;
@property (nonatomic, strong) NSButton *findPreviousButton;
@property (nonatomic, strong) NSButton *findNextButton;
@property (nonatomic, strong) NSButton *findCloseButton;
@property (nonatomic, strong) id tabSwitcherEventMonitor;
@property (nonatomic, strong) NSVisualEffectView *tabSwitcherPanel;
@property (nonatomic, strong) NSStackView *tabSwitcherStack;
@property (nonatomic, strong) NSLayoutConstraint *tabSwitcherWidthConstraint;
@property (nonatomic, assign) BOOL tabSwitcherVisible;
@property (nonatomic, assign) NSInteger tabSwitcherIndex;
@property (nonatomic, assign) BOOL pageHasFillableForms;
@property (nonatomic, assign) BOOL formAutofillInProgress;
@property (nonatomic, copy, nullable) NSString *pendingAutofillInstructionsAfterNavigation;
@property (nonatomic, strong, nullable) id passkeyCredentialManager;
@property (nonatomic, assign) BOOL passkeyAccessRequestInProgress;
@property (nonatomic, assign) BOOL restoringSession;
@property (nonatomic, assign) BOOL suppressTabSelectionChange;
@property (nonatomic, strong) NSView *rootView;
@property (nonatomic, strong) NSMutableArray<NSView *> *themeHairlines;
- (NSString *)sitePermissionSummaryForURL:(NSURL *)url;
@end

@implementation BrowserAppDelegate

static const NSInteger kMemorySaverMaxLiveTabs = 6;
static const NSInteger kMaxConcurrentPreloads = 2;
static const NSInteger kMaxVisibleSwitcherTabs = 9;
static const NSInteger kMaxRecentlyClosedTabs = 20;
static const unsigned short kTabKeyCode = 48;
static const unsigned short kEscapeKeyCode = 53;
static const unsigned short kReturnKeyCode = 36;
static const unsigned short kLeftArrowKeyCode = 123;
static const unsigned short kRightArrowKeyCode = 124;
static NSString * const TBSitePermissionCamera = @"camera";
static NSString * const TBSitePermissionMicrophone = @"microphone";
static NSString * const TBSitePermissionAsk = @"ask";
static NSString * const TBSitePermissionAllow = @"allow";
static NSString * const TBSitePermissionDeny = @"deny";
static NSString * const TBTabDragPasteboardType = @"com.trailbrowser.tab-row";
static NSString * const TBBookmarkBarVisibleKey = @"TBBookmarkBarVisible";
static NSString * const TBBookmarkBarUserConfiguredKey = @"TBBookmarkBarUserConfigured";
static NSString * const TBThemeModeDefaultsKey = @"TBThemeMode";
static NSString * const TBKeepTabsLoadedKey = @"TBKeepTabsLoaded";
static NSString * const TBPasskeyAccessPromptedKey = @"TBPasskeyAccessPrompted";

static void *BrowserProgressContext = &BrowserProgressContext;
static void *BrowserURLContext = &BrowserURLContext;
static void *BrowserCanGoBackContext = &BrowserCanGoBackContext;
static void *BrowserCanGoForwardContext = &BrowserCanGoForwardContext;

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    (void)notification;

    [self loadSavedThemeMode];
    [self buildMenu];
    [self buildWindow];
    [self startMemoryPressureMonitor];
    [self restoreRecentlyClosedTabsFromDictionary:[self browserStateDictionary]];
    [self requestPasskeyAccessAtLaunchIfNeeded];

    NSArray<NSString *> *urlArgs = [self launchURLArguments];
    if (urlArgs.count > 0) {
        for (NSUInteger i = 0; i < urlArgs.count; i++) {
            [self newTabWithURLString:urlArgs[i] select:(i == urlArgs.count - 1)];
        }
        [self writeBrowserStateRunning:YES];
        return;
    }

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    BOOL onboarded = [defaults boolForKey:@"TBHasOnboarded"];
    if (!onboarded) {
        [defaults setBool:YES forKey:@"TBHasOnboarded"];
        [self newTabWithURLString:[self onboardingURLString] select:YES];
    } else if (![self restorePreviousSessionIfAvailable]) {
        [self newTabWithURLString:[self homeURLString] select:YES];
    }
    [self writeBrowserStateRunning:YES];
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
    if (_memoryPressureSource) dispatch_source_cancel(_memoryPressureSource);
    if (_tabSwitcherEventMonitor) [NSEvent removeMonitor:_tabSwitcherEventMonitor];
    [_downloadRefreshTimer invalidate];
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

    NSMenuItem *fileMenuItem = [[NSMenuItem alloc] initWithTitle:@"File"
                                                          action:nil
                                                   keyEquivalent:@""];
    [mainMenu addItem:fileMenuItem];
    NSMenu *fileMenu = [[NSMenu alloc] initWithTitle:@"File"];
    [self addMenuItem:@"Open File…" action:@selector(openFile:) key:@"o" menu:fileMenu];
    [self addMenuItem:@"Save Page as PDF…" action:@selector(exportPageAsPDF:) key:@"s" menu:fileMenu];
    [self addMenuItem:@"Print…" action:@selector(printPage:) key:@"p" menu:fileMenu];
    [fileMenuItem setSubmenu:fileMenu];

    NSMenuItem *navMenuItem = [[NSMenuItem alloc] initWithTitle:@"Navigate"
                                                         action:nil
                                                  keyEquivalent:@""];
    [mainMenu addItem:navMenuItem];

    NSMenu *navMenu = [[NSMenu alloc] initWithTitle:@"Navigate"];
    [self addMenuItem:@"Open Location" action:@selector(focusAddressBar:) key:@"l" menu:navMenu];
    [self addMenuItem:@"Toggle Sidebar" action:@selector(toggleSidebar:) key:@"b" menu:navMenu];
    [self addMenuItem:@"New Tab" action:@selector(newTab:) key:@"t" menu:navMenu];
    [self addMenuItem:@"New Private Tab"
               action:@selector(newPrivateTab:)
                  key:@"n"
            modifiers:(NSEventModifierFlagCommand | NSEventModifierFlagShift)
                 menu:navMenu];
    [self addMenuItem:@"Close Tab" action:@selector(closeCurrentTab:) key:@"w" menu:navMenu];
    [self addMenuItem:@"Duplicate Tab" action:@selector(duplicateCurrentTab:) key:@"" menu:navMenu];
    [self addMenuItem:@"Pin Tab" action:@selector(toggleCurrentTabPinned:) key:@"" menu:navMenu];
    [self addMenuItem:@"Move Tab Up" action:@selector(moveCurrentTabUp:) key:@"" menu:navMenu];
    [self addMenuItem:@"Move Tab Down" action:@selector(moveCurrentTabDown:) key:@"" menu:navMenu];
    [self addMenuItem:@"Close Other Tabs" action:@selector(closeOtherTabsForCurrentTab:) key:@"" menu:navMenu];
    [self addMenuItem:@"Close Tabs to the Right" action:@selector(closeTabsToRightForCurrentTab:) key:@"" menu:navMenu];
    [self addMenuItem:@"Reopen Closed Tab"
               action:@selector(reopenClosedTab:)
                  key:@"t"
            modifiers:(NSEventModifierFlagCommand | NSEventModifierFlagShift)
                 menu:navMenu];
    [self addMenuItem:@"Bookmark This Page" action:@selector(toggleBookmarkCurrentPage:) key:@"d" menu:navMenu];
    [self addMenuItem:@"Switch Tabs"
               action:@selector(showTabSwitcherFromMenu:)
                  key:@"\t"
            modifiers:(NSEventModifierFlagCommand | NSEventModifierFlagOption)
                 menu:navMenu];
    [self addMenuItem:@"Next Tab"
               action:@selector(selectNextTab:)
                  key:@"\t"
            modifiers:NSEventModifierFlagControl
                 menu:navMenu];
    [self addMenuItem:@"Previous Tab"
               action:@selector(selectPreviousTab:)
                  key:@"\t"
            modifiers:(NSEventModifierFlagControl | NSEventModifierFlagShift)
                 menu:navMenu];
    [navMenu addItem:[NSMenuItem separatorItem]];
    [self addMenuItem:@"Home" action:@selector(goHome:) key:@"" menu:navMenu];
    [self addMenuItem:@"Reload" action:@selector(reloadPage:) key:@"r" menu:navMenu];
    [navMenu addItem:[NSMenuItem separatorItem]];
    [self addMenuItem:@"Back" action:@selector(goBack:) key:@"[" menu:navMenu];
    [self addMenuItem:@"Forward" action:@selector(goForward:) key:@"]" menu:navMenu];
    [navMenuItem setSubmenu:navMenu];

    NSMenuItem *viewMenuItem = [[NSMenuItem alloc] initWithTitle:@"View" action:nil keyEquivalent:@""];
    [mainMenu addItem:viewMenuItem];
    NSMenu *viewMenu = [[NSMenu alloc] initWithTitle:@"View"];
    [self addMenuItem:@"Page Info" action:@selector(showPageInfo:) key:@"" menu:viewMenu];
    [self addMenuItem:@"View Source"
               action:@selector(viewSource:)
                  key:@"u"
            modifiers:(NSEventModifierFlagCommand | NSEventModifierFlagOption)
                 menu:viewMenu];
    [viewMenu addItem:[NSMenuItem separatorItem]];
    [self addMenuItem:@"Use Dark Mode" action:@selector(toggleDarkMode:) key:@"" menu:viewMenu];
    [viewMenu addItem:[NSMenuItem separatorItem]];
    [self addMenuItem:@"Enter Full Screen"
               action:@selector(toggleFullScreen:)
                  key:@"f"
            modifiers:(NSEventModifierFlagCommand | NSEventModifierFlagControl)
                 menu:viewMenu];
    [viewMenu addItem:[NSMenuItem separatorItem]];
    [self addMenuItem:@"Show Bookmarks Bar"
               action:@selector(toggleBookmarkBar:)
                  key:@"b"
            modifiers:(NSEventModifierFlagCommand | NSEventModifierFlagShift)
                 menu:viewMenu];
    [viewMenu addItem:[NSMenuItem separatorItem]];
    [self addMenuItem:@"Actual Size" action:@selector(resetPageZoom:) key:@"0" menu:viewMenu];
    [self addMenuItem:@"Zoom In" action:@selector(zoomIn:) key:@"=" menu:viewMenu];
    [self addMenuItem:@"Zoom Out" action:@selector(zoomOut:) key:@"-" menu:viewMenu];
    [viewMenuItem setSubmenu:viewMenu];

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
    [editMenu addItem:[NSMenuItem separatorItem]];
    [self addEditItem:@"Find…" action:@selector(showFindBar:) key:@"f" shift:NO menu:editMenu];
    [self addEditItem:@"Find Next" action:@selector(findNext:) key:@"g" shift:NO menu:editMenu];
    [self addEditItem:@"Find Previous" action:@selector(findPrevious:) key:@"g" shift:YES menu:editMenu];
    [editMenuItem setSubmenu:editMenu];

    [NSApp setMainMenu:mainMenu];
}

- (void)addMenuItem:(NSString *)title action:(SEL)action key:(NSString *)key menu:(NSMenu *)menu {
    [self addMenuItem:title
               action:action
                  key:key
            modifiers:NSEventModifierFlagCommand
                 menu:menu];
}

- (void)addMenuItem:(NSString *)title
             action:(SEL)action
                key:(NSString *)key
          modifiers:(NSEventModifierFlags)modifiers
               menu:(NSMenu *)menu {
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:action keyEquivalent:key];
    item.target = self;
    item.keyEquivalentModifierMask = modifiers;
    [menu addItem:item];
}

- (void)addEditItem:(NSString *)title action:(SEL)action key:(NSString *)key shift:(BOOL)shift menu:(NSMenu *)menu {
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:action keyEquivalent:key];
    item.keyEquivalentModifierMask = shift
        ? (NSEventModifierFlagCommand | NSEventModifierFlagShift)
        : NSEventModifierFlagCommand;
    [menu addItem:item];
}

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
    if (menuItem.action == @selector(toggleBookmarkBar:)) {
        menuItem.state = self.bookmarkBarVisible ? NSControlStateValueOn : NSControlStateValueOff;
        menuItem.title = self.bookmarkBarVisible ? @"Hide Bookmarks Bar" : @"Show Bookmarks Bar";
    }
    if (menuItem.action == @selector(toggleDarkMode:)) {
        menuItem.state = TBThemeIsDark() ? NSControlStateValueOn : NSControlStateValueOff;
        menuItem.title = TBThemeIsDark() ? @"Use Light Mode" : @"Use Dark Mode";
    }
    if (menuItem.action == @selector(toggleFullScreen:)) {
        BOOL fullScreen = (self.window.styleMask & NSWindowStyleMaskFullScreen) == NSWindowStyleMaskFullScreen;
        menuItem.title = fullScreen ? @"Exit Full Screen" : @"Enter Full Screen";
    }
    if (menuItem.action == @selector(reopenClosedTab:)) {
        return self.recentlyClosedTabs.count > 0;
    }
    if (menuItem.action == @selector(duplicateCurrentTab:)) {
        return self.activeTabIndex >= 0 && self.activeTabIndex < (NSInteger)self.tabs.count;
    }
    if (menuItem.action == @selector(toggleCurrentTabPinned:)) {
        BrowserTab *tab = [self activeTab];
        menuItem.title = tab.pinned ? @"Unpin Tab" : @"Pin Tab";
        return tab != nil;
    }
    if (menuItem.action == @selector(closeOtherTabsForCurrentTab:)) {
        return self.tabs.count > 1 && self.activeTabIndex >= 0;
    }
    if (menuItem.action == @selector(closeTabsToRightForCurrentTab:)) {
        return self.activeTabIndex >= 0 && self.activeTabIndex < (NSInteger)self.tabs.count - 1;
    }
    if (menuItem.action == @selector(moveCurrentTabUp:)) {
        return self.activeTabIndex > 0;
    }
    if (menuItem.action == @selector(moveCurrentTabDown:)) {
        return self.activeTabIndex >= 0 && self.activeTabIndex < (NSInteger)self.tabs.count - 1;
    }
    if (menuItem.action == @selector(reloadTabFromMenu:) ||
        menuItem.action == @selector(duplicateTabFromMenu:) ||
        menuItem.action == @selector(closeTabFromMenu:)) {
        NSInteger row = menuItem.tag;
        return row >= 0 && row < (NSInteger)self.tabs.count;
    }
    if (menuItem.action == @selector(toggleTabPinnedFromMenu:)) {
        NSInteger row = menuItem.tag;
        return row >= 0 && row < (NSInteger)self.tabs.count;
    }
    if (menuItem.action == @selector(closeOtherTabsFromMenu:)) {
        NSInteger row = menuItem.tag;
        return row >= 0 && row < (NSInteger)self.tabs.count && self.tabs.count > 1;
    }
    if (menuItem.action == @selector(closeTabsToRightFromMenu:)) {
        NSInteger row = menuItem.tag;
        return row >= 0 && row < (NSInteger)self.tabs.count - 1;
    }
    if (menuItem.action == @selector(moveTabUpFromMenu:)) {
        NSInteger row = menuItem.tag;
        return row > 0 && row < (NSInteger)self.tabs.count;
    }
    if (menuItem.action == @selector(moveTabDownFromMenu:)) {
        NSInteger row = menuItem.tag;
        return row >= 0 && row < (NSInteger)self.tabs.count - 1;
    }
    return YES;
}

- (void)buildWindow {
    self.tabs = [NSMutableArray array];
    self.recentlyClosedTabs = [NSMutableArray array];
    self.activeTabIndex = -1;
    self.sidebarVisible = YES;
    self.bookmarkBarVisible = [self initialBookmarkBarVisible];
    self.themeHairlines = [NSMutableArray array];

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
    self.window.appearance = [self themeWindowAppearance];

    NSView *root = [[NSView alloc] initWithFrame:NSZeroRect];
    root.translatesAutoresizingMaskIntoConstraints = NO;
    root.wantsLayer = YES;
    root.layer.backgroundColor = TBBg().CGColor;
    self.window.contentView = root;
    self.rootView = root;

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

    NSView *navDivider = [self hairlineView];
    [toolbar addSubview:navDivider];

    self.addressContainer = [[TBFieldContainer alloc] initWithFrame:NSZeroRect];
    self.addressContainer.translatesAutoresizingMaskIntoConstraints = NO;
    [toolbar addSubview:self.addressContainer];

    self.siteInfoButton = [[TBFlatButton alloc] initWithFrame:NSZeroRect];
    self.siteInfoButton.translatesAutoresizingMaskIntoConstraints = NO;
    ((TBFlatButton *)self.siteInfoButton).cornerRadius = 6.0;
    self.siteInfoButton.imagePosition = NSImageOnly;
    self.siteInfoButton.imageScaling = NSImageScaleProportionallyDown;
    self.siteInfoButton.target = self;
    self.siteInfoButton.action = @selector(showPageInfo:);
    self.siteInfoButton.toolTip = @"Page info";
    if (@available(macOS 11.0, *)) {
        NSImage *glyph = [NSImage imageWithSystemSymbolName:@"magnifyingglass" accessibilityDescription:@"Page info"];
        glyph.template = YES;
        self.siteInfoButton.image = glyph;
    }
    if (@available(macOS 10.14, *)) self.siteInfoButton.contentTintColor = TBFaint();
    [self.addressContainer addSubview:self.siteInfoButton];

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

    self.askButton = [[TBPillButton alloc] initWithFrame:NSZeroRect];
    self.askButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.askButton.pillStyle = TBPillStyleSecondary;
    self.askButton.title = @"Ask AI";
    self.askButton.toolTip = @"Open assistant";
    self.askButton.target = self;
    self.askButton.action = @selector(openAssistant:);
    [toolbar addSubview:self.askButton];

    self.autofillButton = [[TBPillButton alloc] initWithFrame:NSZeroRect];
    self.autofillButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.autofillButton.pillStyle = TBPillStyleSecondary;
    self.autofillButton.title = @"Fill AI";
    self.autofillButton.toolTip = @"Autofill this form with AI";
    self.autofillButton.target = self;
    self.autofillButton.action = @selector(autofillFormsWithAI:);
    self.autofillButton.hidden = YES;
    [toolbar addSubview:self.autofillButton];

    self.settingsButton = [self toolbarButtonWithSymbol:@"gearshape"
                                               fallback:@"S"
                                                tooltip:@"Settings"
                                                 action:@selector(openSettings:)];
    [toolbar addSubview:self.settingsButton];

    self.bookmarkButton = [self toolbarButtonWithSymbol:@"star"
                                               fallback:@"*"
                                                tooltip:@"Bookmark this page"
                                                 action:@selector(toggleBookmarkCurrentPage:)];
    [toolbar addSubview:self.bookmarkButton];

    self.bookmarksButton = [self toolbarButtonWithSymbol:@"book.closed"
                                                fallback:@"B"
                                                 tooltip:@"Bookmarks"
                                                  action:@selector(showBookmarksPopover:)];
    [toolbar addSubview:self.bookmarksButton];

    self.downloadsButton = [self toolbarButtonWithSymbol:@"arrow.down.circle"
                                                fallback:@"D"
                                                 tooltip:@"Downloads"
                                                  action:@selector(showDownloadsPopover:)];
    [toolbar addSubview:self.downloadsButton];

    self.progressBar = [[TBProgressBar alloc] initWithFrame:NSZeroRect];
    self.progressBar.translatesAutoresizingMaskIntoConstraints = NO;
    self.progressBar.hidden = YES;
    [toolbar addSubview:self.progressBar];

    self.bookmarkBar = [[NSView alloc] initWithFrame:NSZeroRect];
    self.bookmarkBar.translatesAutoresizingMaskIntoConstraints = NO;
    self.bookmarkBar.wantsLayer = YES;
    self.bookmarkBar.layer.backgroundColor = TBSurface().CGColor;
    self.bookmarkBar.layer.masksToBounds = YES;
    self.bookmarkBar.hidden = !self.bookmarkBarVisible;
    [root addSubview:self.bookmarkBar];

    NSView *bookmarkBarHairline = [self hairlineView];
    [self.bookmarkBar addSubview:bookmarkBarHairline];

    self.bookmarkBarStack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    self.bookmarkBarStack.translatesAutoresizingMaskIntoConstraints = NO;
    self.bookmarkBarStack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    self.bookmarkBarStack.alignment = NSLayoutAttributeCenterY;
    self.bookmarkBarStack.distribution = NSStackViewDistributionFill;
    self.bookmarkBarStack.spacing = 6.0;
    [self.bookmarkBar addSubview:self.bookmarkBarStack];

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
    [self buildFindBar];
    [self buildTabSwitcherOverlay];
    [self buildAddressSuggestionsOverlayInView:root];

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
    self.tabContextMenu = [[NSMenu alloc] initWithTitle:@"Tab"];
    self.tabContextMenu.delegate = self;
    self.tabTable.menu = self.tabContextMenu;
    [self.tabTable registerForDraggedTypes:@[ TBTabDragPasteboardType ]];

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
                           self.addressContainer, self.reloadButton,
                           self.autofillButton, self.askButton, self.bookmarkButton, self.bookmarksButton, self.downloadsButton,
                           self.settingsButton, self.progressBar ]) {
        [toolbar addSubview:view];
    }

    self.sidebarWidthConstraint = [self.sidebar.widthAnchor constraintEqualToConstant:240.0];
    self.bookmarkBarHeightConstraint = [self.bookmarkBar.heightAnchor constraintEqualToConstant:self.bookmarkBarVisible ? 34.0 : 0.0];
    self.autofillButtonWidthConstraint = [self.autofillButton.widthAnchor constraintEqualToConstant:0.0];

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

        [self.siteInfoButton.leadingAnchor constraintEqualToAnchor:self.addressContainer.leadingAnchor constant:8.0],
        [self.siteInfoButton.centerYAnchor constraintEqualToAnchor:self.addressContainer.centerYAnchor],
        [self.siteInfoButton.widthAnchor constraintEqualToConstant:24.0],
        [self.siteInfoButton.heightAnchor constraintEqualToConstant:24.0],

        [self.addressField.leadingAnchor constraintEqualToAnchor:self.siteInfoButton.trailingAnchor constant:6.0],
        [self.addressField.trailingAnchor constraintEqualToAnchor:self.addressContainer.trailingAnchor constant:-12.0],
        [self.addressField.centerYAnchor constraintEqualToAnchor:self.addressContainer.centerYAnchor],

        [self.settingsButton.trailingAnchor constraintEqualToAnchor:toolbar.trailingAnchor constant:-14.0],
        [self.settingsButton.centerYAnchor constraintEqualToAnchor:toolbar.centerYAnchor],

        [self.downloadsButton.trailingAnchor constraintEqualToAnchor:self.settingsButton.leadingAnchor constant:-8.0],
        [self.downloadsButton.centerYAnchor constraintEqualToAnchor:toolbar.centerYAnchor],

        [self.bookmarksButton.trailingAnchor constraintEqualToAnchor:self.downloadsButton.leadingAnchor constant:-8.0],
        [self.bookmarksButton.centerYAnchor constraintEqualToAnchor:toolbar.centerYAnchor],

        [self.bookmarkButton.trailingAnchor constraintEqualToAnchor:self.bookmarksButton.leadingAnchor constant:-8.0],
        [self.bookmarkButton.centerYAnchor constraintEqualToAnchor:toolbar.centerYAnchor],

        [self.askButton.trailingAnchor constraintEqualToAnchor:self.bookmarkButton.leadingAnchor constant:-8.0],
        [self.askButton.centerYAnchor constraintEqualToAnchor:toolbar.centerYAnchor],
        [self.askButton.widthAnchor constraintEqualToConstant:68.0],
        [self.askButton.heightAnchor constraintEqualToConstant:28.0],

        [self.autofillButton.trailingAnchor constraintEqualToAnchor:self.askButton.leadingAnchor constant:-8.0],
        [self.autofillButton.centerYAnchor constraintEqualToAnchor:toolbar.centerYAnchor],
        self.autofillButtonWidthConstraint,
        [self.autofillButton.heightAnchor constraintEqualToConstant:28.0],

        [self.reloadButton.trailingAnchor constraintEqualToAnchor:self.autofillButton.leadingAnchor constant:-10.0],
        [self.reloadButton.centerYAnchor constraintEqualToAnchor:toolbar.centerYAnchor],

        [self.progressBar.leadingAnchor constraintEqualToAnchor:toolbar.leadingAnchor],
        [self.progressBar.trailingAnchor constraintEqualToAnchor:toolbar.trailingAnchor],
        [self.progressBar.bottomAnchor constraintEqualToAnchor:toolbar.bottomAnchor],
        [self.progressBar.heightAnchor constraintEqualToConstant:2.0],

        [self.bookmarkBar.topAnchor constraintEqualToAnchor:toolbar.bottomAnchor],
        [self.bookmarkBar.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],
        [self.bookmarkBar.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],
        self.bookmarkBarHeightConstraint,

        [bookmarkBarHairline.leadingAnchor constraintEqualToAnchor:self.bookmarkBar.leadingAnchor],
        [bookmarkBarHairline.trailingAnchor constraintEqualToAnchor:self.bookmarkBar.trailingAnchor],
        [bookmarkBarHairline.bottomAnchor constraintEqualToAnchor:self.bookmarkBar.bottomAnchor],
        [bookmarkBarHairline.heightAnchor constraintEqualToConstant:1.0],

        [self.bookmarkBarStack.leadingAnchor constraintEqualToAnchor:self.bookmarkBar.leadingAnchor constant:14.0],
        [self.bookmarkBarStack.trailingAnchor constraintLessThanOrEqualToAnchor:self.bookmarkBar.trailingAnchor constant:-14.0],
        [self.bookmarkBarStack.centerYAnchor constraintEqualToAnchor:self.bookmarkBar.centerYAnchor],
        [self.bookmarkBarStack.heightAnchor constraintEqualToConstant:26.0],

        [contentArea.topAnchor constraintEqualToAnchor:self.bookmarkBar.bottomAnchor],
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
    [self reloadBookmarkBarItems];
    [self updateControls];
    self.window.delegate = self;
    self.window.initialFirstResponder = self.addressField;
    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
    [self positionTrafficLights];

    [self.window makeFirstResponder:self.addressField];
    [self installTabSwitcherEventMonitor];
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
    if (!self.restoringSession) [self writeBrowserStateRunning:YES];
}

- (NSAppearance *)themeWindowAppearance {
    return [NSAppearance appearanceNamed:TBThemeIsDark() ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua];
}

- (NSAppearance *)themeVibrantAppearance {
    return [NSAppearance appearanceNamed:TBThemeIsDark() ? NSAppearanceNameVibrantDark : NSAppearanceNameVibrantLight];
}

- (void)loadSavedThemeMode {
    NSString *name = [[NSUserDefaults standardUserDefaults] stringForKey:TBThemeModeDefaultsKey] ?: @"light";
    TBThemeSetMode(TBThemeModeFromString(name));
}

- (NSAttributedString *)placeholderWithString:(NSString *)string size:(CGFloat)size {
    return [[NSAttributedString alloc] initWithString:string attributes:@{
        NSForegroundColorAttributeName: TBFaint(),
        NSFontAttributeName: [NSFont systemFontOfSize:size weight:NSFontWeightRegular]
    }];
}

- (void)refreshButtonTitleColor:(NSButton *)button {
    if (button.imagePosition == NSImageOnly) return;
    NSAttributedString *title = button.attributedTitle;
    if (title.length == 0) return;
    NSString *plainTitle = title.string ?: @"";
    if (plainTitle.length == 0 || [plainTitle isEqualToString:@"Button"]) return;
    NSMutableAttributedString *updated = [title mutableCopy];
    [updated addAttribute:NSForegroundColorAttributeName
                    value:TBText()
                    range:NSMakeRange(0, updated.length)];
    button.attributedTitle = updated;
}

- (void)refreshThemeForViewTree:(NSView *)view {
    if ([view isKindOfClass:TBFlatButton.class]) {
        [(TBFlatButton *)view refreshTheme];
        [self refreshButtonTitleColor:(NSButton *)view];
    } else if ([view isKindOfClass:TBPillButton.class]) {
        [(TBPillButton *)view refreshTheme];
    } else if ([view isKindOfClass:TBProgressBar.class]) {
        [(TBProgressBar *)view refreshTheme];
    } else if ([view isKindOfClass:TBFieldContainer.class]) {
        [(TBFieldContainer *)view refreshTheme];
    } else if ([view isKindOfClass:TBSegmentedControl.class]) {
        [(TBSegmentedControl *)view refreshTheme];
    } else if ([view isKindOfClass:NSButton.class]) {
        [self refreshButtonTitleColor:(NSButton *)view];
    }

    if (@available(macOS 10.14, *)) {
        if ([view isKindOfClass:NSButton.class]) {
            NSButton *button = (NSButton *)view;
            if (button.image && button.contentTintColor) button.contentTintColor = TBMuted();
        }
    }

    for (NSView *subview in view.subviews) {
        [self refreshThemeForViewTree:subview];
    }
}

- (void)applyTheme {
    self.window.backgroundColor = TBBg();
    self.window.appearance = [self themeWindowAppearance];
    self.rootView.layer.backgroundColor = TBBg().CGColor;
    self.toolbar.layer.backgroundColor = TBSurface().CGColor;
    self.bookmarkBar.layer.backgroundColor = TBSurface().CGColor;
    self.sidebar.layer.backgroundColor = TBSurface().CGColor;
    self.webContainer.layer.backgroundColor = TBBg().CGColor;

    for (NSView *line in self.themeHairlines) {
        line.layer.backgroundColor = TBBorder().CGColor;
    }

    self.assistantBar.appearance = [self themeVibrantAppearance];
    self.assistantBar.layer.borderColor = TBBorder().CGColor;
    self.assistantBar.layer.backgroundColor = TBSurface().CGColor;
    self.assistantResultPanel.appearance = [self themeVibrantAppearance];
    self.assistantResultPanel.layer.borderColor = TBBorder().CGColor;
    self.assistantResultPanel.layer.backgroundColor = TBSurface().CGColor;
    self.findBar.appearance = [self themeVibrantAppearance];
    self.findBar.layer.borderColor = TBBorder().CGColor;
    self.findBar.layer.backgroundColor = TBSurface().CGColor;
    self.addressSuggestionsPanel.appearance = [self themeVibrantAppearance];
    self.addressSuggestionsPanel.layer.borderColor = TBBorder().CGColor;
    self.addressSuggestionsPanel.layer.backgroundColor = [TBSurface() colorWithAlphaComponent:0.96].CGColor;
    self.tabSwitcherPanel.appearance = [self themeVibrantAppearance];
    self.tabSwitcherPanel.layer.borderColor = TBBorder().CGColor;
    self.tabSwitcherPanel.layer.backgroundColor = [TBSurface() colorWithAlphaComponent:0.92].CGColor;

    self.addressField.textColor = TBText();
    self.addressField.placeholderAttributedString = [self placeholderWithString:@"Search or enter website name" size:13.5];
    self.assistantPromptField.textColor = TBText();
    self.assistantPromptField.placeholderAttributedString = [self placeholderWithString:@"Ask about this page" size:13.0];
    self.findField.textColor = TBText();
    self.findField.placeholderAttributedString = [self placeholderWithString:@"Find in page" size:13.0];
    self.findStatusLabel.textColor = TBFaint();
    self.assistantResultTextView.textColor = TBText();
    self.tabCountLabel.textColor = TBFaint();

    [self refreshThemeForViewTree:self.rootView];
    if (@available(macOS 10.14, *)) self.assistantRunButton.contentTintColor = TBAccent();
    [self reloadBookmarkBarItems];
    [self.tabTable reloadData];
    [self renderAddressSuggestions];
    if (self.tabSwitcherVisible) [self refreshTabSwitcher];
    [self updateControls];
}

- (void)reloadCurrentInternalPageForTheme {
    BrowserTab *tab = [self activeTab];
    if (!self.webView || !tab) return;
    NSString *tabURL = tab.urlString ?: @"";
    NSString *webURL = self.webView.URL.absoluteString ?: @"";
    if ([self isSettingsURLString:tabURL] ||
        [self isSettingsURLString:webURL] ||
        [tab.title hasPrefix:@"Settings"]) {
        [self loadNativeSettingsPageInWebView:self.webView];
    } else if ([self isHomeURLString:tabURL] ||
               [self isHomeURLString:webURL] ||
               [tab.title hasPrefix:@"TrailBrowser Home"]) {
        [self loadNativeHomePageInWebView:self.webView];
    } else if ([self isOnboardingURLString:tabURL] ||
               [self isOnboardingURLString:webURL] ||
               [tab.title hasPrefix:@"Welcome"]) {
        [self loadNativeOnboardingPageInWebView:self.webView];
    }
}

- (void)setThemeModeName:(NSString *)name persist:(BOOL)persist {
    TBThemeMode mode = TBThemeModeFromString(name);
    if (persist) {
        [[NSUserDefaults standardUserDefaults] setObject:TBThemeModeName(mode) forKey:TBThemeModeDefaultsKey];
    }
    if (mode == TBThemeCurrentMode()) return;
    TBThemeSetMode(mode);
    [self applyTheme];
    [self reloadCurrentInternalPageForTheme];
}

- (void)toggleDarkMode:(id)sender {
    (void)sender;
    [self setThemeModeName:(TBThemeIsDark() ? @"light" : @"dark") persist:YES];
}

- (void)toggleFullScreen:(id)sender {
    [self.window toggleFullScreen:sender];
}

- (NSView *)hairlineView {
    NSView *line = [[NSView alloc] initWithFrame:NSZeroRect];
    line.translatesAutoresizingMaskIntoConstraints = NO;
    line.wantsLayer = YES;
    line.layer.backgroundColor = TBBorder().CGColor;
    [self.themeHairlines addObject:line];
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
        NSFontAttributeName: [NSFont systemFontOfSize:13.0 weight:NSFontWeightRegular],
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
    self.addressContainer.toolTip = text.length ? text : @"Ready";
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
        NSImageSymbolConfiguration *config = [NSImageSymbolConfiguration configurationWithPointSize:14.0
                                                                                             weight:NSFontWeightRegular];
        image = [image imageWithSymbolConfiguration:config] ?: image;
        image.template = YES;
        button.image = image;
    }
    if (@available(macOS 10.14, *)) button.contentTintColor = TBMuted();

    if (!button.image) {
        button.imagePosition = NSNoImage;
        button.attributedTitle = [[NSAttributedString alloc] initWithString:fallback attributes:@{
            NSFontAttributeName: [NSFont systemFontOfSize:13.0 weight:NSFontWeightMedium],
            NSForegroundColorAttributeName: TBMuted()
        }];
    }

    [button.widthAnchor constraintEqualToConstant:30.0].active = YES;
    [button.heightAnchor constraintEqualToConstant:28.0].active = YES;
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
    self.assistantBar.appearance = [self themeVibrantAppearance];
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
    self.assistantResultPanel.appearance = [self themeVibrantAppearance];
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

#pragma mark - Find in page

- (void)buildFindBar {
    self.findBar = [[NSVisualEffectView alloc] initWithFrame:NSZeroRect];
    self.findBar.translatesAutoresizingMaskIntoConstraints = NO;
    self.findBar.material = NSVisualEffectMaterialHUDWindow;
    self.findBar.blendingMode = NSVisualEffectBlendingModeWithinWindow;
    self.findBar.state = NSVisualEffectStateActive;
    self.findBar.appearance = [self themeVibrantAppearance];
    self.findBar.hidden = YES;
    self.findBar.wantsLayer = YES;
    self.findBar.layer.cornerRadius = 12.0;
    self.findBar.layer.masksToBounds = YES;
    self.findBar.layer.borderWidth = 1.0;
    self.findBar.layer.borderColor = TBBorder().CGColor;
    self.findBar.layer.backgroundColor = TBSurface().CGColor;
    self.findBar.layer.zPosition = 180.0;
    [self.webContainer addSubview:self.findBar];

    self.findField = [[NSTextField alloc] initWithFrame:NSZeroRect];
    self.findField.translatesAutoresizingMaskIntoConstraints = NO;
    self.findField.bezeled = NO;
    self.findField.bordered = NO;
    self.findField.drawsBackground = NO;
    self.findField.focusRingType = NSFocusRingTypeNone;
    self.findField.usesSingleLineMode = YES;
    self.findField.cell.usesSingleLineMode = YES;
    self.findField.cell.lineBreakMode = NSLineBreakByTruncatingTail;
    [self.findField.cell setScrollable:YES];
    self.findField.textColor = TBText();
    self.findField.font = [NSFont systemFontOfSize:13.0 weight:NSFontWeightRegular];
    self.findField.placeholderAttributedString =
        [[NSAttributedString alloc] initWithString:@"Find in page"
                                        attributes:@{ NSForegroundColorAttributeName: TBFaint(),
                                                      NSFontAttributeName: [NSFont systemFontOfSize:13.0] }];
    self.findField.delegate = self;
    self.findField.target = self;
    self.findField.action = @selector(findNext:);
    [self.findBar addSubview:self.findField];

    self.findStatusLabel = [NSTextField labelWithString:@""];
    self.findStatusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.findStatusLabel.font = [NSFont systemFontOfSize:11.0 weight:NSFontWeightMedium];
    self.findStatusLabel.textColor = TBFaint();
    self.findStatusLabel.alignment = NSTextAlignmentRight;
    [self.findBar addSubview:self.findStatusLabel];

    self.findPreviousButton = [self sidebarButtonWithSymbol:@"chevron.up"
                                                   fallback:@"^"
                                                    tooltip:@"Previous match"
                                                     action:@selector(findPrevious:)];
    self.findNextButton = [self sidebarButtonWithSymbol:@"chevron.down"
                                               fallback:@"v"
                                                tooltip:@"Next match"
                                                 action:@selector(findNext:)];
    self.findCloseButton = [self sidebarButtonWithSymbol:@"xmark"
                                                fallback:@"x"
                                                 tooltip:@"Close find"
                                                  action:@selector(closeFindBar:)];
    [self.findBar addSubview:self.findPreviousButton];
    [self.findBar addSubview:self.findNextButton];
    [self.findBar addSubview:self.findCloseButton];

    [NSLayoutConstraint activateConstraints:@[
        [self.findBar.topAnchor constraintEqualToAnchor:self.webContainer.topAnchor constant:14.0],
        [self.findBar.trailingAnchor constraintEqualToAnchor:self.webContainer.trailingAnchor constant:-18.0],
        [self.findBar.widthAnchor constraintEqualToConstant:430.0],
        [self.findBar.heightAnchor constraintEqualToConstant:42.0],

        [self.findField.leadingAnchor constraintEqualToAnchor:self.findBar.leadingAnchor constant:14.0],
        [self.findField.centerYAnchor constraintEqualToAnchor:self.findBar.centerYAnchor],

        [self.findStatusLabel.leadingAnchor constraintEqualToAnchor:self.findField.trailingAnchor constant:8.0],
        [self.findStatusLabel.centerYAnchor constraintEqualToAnchor:self.findBar.centerYAnchor],
        [self.findStatusLabel.widthAnchor constraintEqualToConstant:72.0],

        [self.findPreviousButton.leadingAnchor constraintEqualToAnchor:self.findStatusLabel.trailingAnchor constant:8.0],
        [self.findPreviousButton.centerYAnchor constraintEqualToAnchor:self.findBar.centerYAnchor],

        [self.findNextButton.leadingAnchor constraintEqualToAnchor:self.findPreviousButton.trailingAnchor constant:4.0],
        [self.findNextButton.centerYAnchor constraintEqualToAnchor:self.findBar.centerYAnchor],

        [self.findCloseButton.leadingAnchor constraintEqualToAnchor:self.findNextButton.trailingAnchor constant:6.0],
        [self.findCloseButton.trailingAnchor constraintEqualToAnchor:self.findBar.trailingAnchor constant:-8.0],
        [self.findCloseButton.centerYAnchor constraintEqualToAnchor:self.findBar.centerYAnchor]
    ]];
}

- (void)showFindBar:(id)sender {
    (void)sender;
    if (!self.webView) return;
    [self.webContainer addSubview:self.findBar positioned:NSWindowAbove relativeTo:self.webView];
    self.findBar.hidden = NO;
    self.findBar.alphaValue = 1.0;
    [self.window makeFirstResponder:self.findField];
    [self.findField selectText:nil];
    if (self.findField.stringValue.length > 0) [self runFindBackwards:NO];
}

- (void)closeFindBar:(id)sender {
    (void)sender;
    self.findBar.hidden = YES;
    self.findStatusLabel.stringValue = @"";
    [self.window makeFirstResponder:self.webView];
}

- (void)findNext:(id)sender {
    (void)sender;
    if (self.findBar.hidden) [self showFindBar:nil];
    [self runFindBackwards:NO];
}

- (void)findPrevious:(id)sender {
    (void)sender;
    if (self.findBar.hidden) [self showFindBar:nil];
    [self runFindBackwards:YES];
}

- (void)runFindBackwards:(BOOL)backwards {
    NSString *query = [self.findField.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (query.length == 0 || !self.webView) {
        self.findStatusLabel.stringValue = @"";
        return;
    }

    if (@available(macOS 11.0, *)) {
        WKFindConfiguration *configuration = [[WKFindConfiguration alloc] init];
        configuration.backwards = backwards;
        configuration.wraps = YES;
        __weak BrowserAppDelegate *weakSelf = self;
        [self.webView findString:query withConfiguration:configuration completionHandler:^(WKFindResult *result) {
            BrowserAppDelegate *strongSelf = weakSelf;
            if (!strongSelf) return;
            strongSelf.findStatusLabel.stringValue = result.matchFound ? @"Match" : @"No match";
            strongSelf.findStatusLabel.textColor = result.matchFound ? TBFaint() : TBError();
        }];
    } else {
        NSString *literal = [self javaScriptStringLiteralForString:query];
        NSString *script = [NSString stringWithFormat:@"window.find(%@, false, %@, true, false, false, false)",
                            literal, backwards ? @"true" : @"false"];
        [self.webView evaluateJavaScript:script completionHandler:^(id result, NSError *error) {
            (void)error;
            BOOL found = [result respondsToSelector:@selector(boolValue)] ? [result boolValue] : NO;
            self.findStatusLabel.stringValue = found ? @"Match" : @"No match";
            self.findStatusLabel.textColor = found ? TBFaint() : TBError();
        }];
    }
}

#pragma mark - Page info

- (NSURL *)currentDisplayURL {
    NSURL *url = self.webView.URL;
    if (url) return url;

    NSString *urlString = [self activeTab].urlString ?: @"";
    return urlString.length > 0 ? [NSURL URLWithString:urlString] : nil;
}

- (NSString *)siteInfoSymbolForURL:(NSURL *)url {
    NSString *scheme = url.scheme.lowercaseString ?: @"";
    NSString *urlString = url.absoluteString ?: @"";
    if (urlString.length == 0) return @"magnifyingglass";
    if ([self isHomeURLString:urlString]) return @"house";
    if ([self isSettingsURLString:urlString]) return @"gearshape";
    if ([self isOnboardingURLString:urlString]) return @"sparkles";
    if ([scheme isEqualToString:@"https"]) return @"lock.fill";
    if ([scheme isEqualToString:@"http"]) return @"exclamationmark.triangle.fill";
    if ([scheme isEqualToString:@"file"]) return @"doc";
    return @"globe";
}

- (NSString *)connectionSummaryForURL:(NSURL *)url {
    NSString *scheme = url.scheme.lowercaseString ?: @"";
    NSString *urlString = url.absoluteString ?: @"";
    NSString *privacyNote = [self activeTab].privateBrowsing
        ? @"\n\nPrivate tab: TrailBrowser will not save this tab to history or session restore, and WebKit uses temporary website storage."
        : @"";
    NSString *permissionsNote = [self sitePermissionSummaryForURL:url];
    if (permissionsNote.length > 0) {
        permissionsNote = [@"\n\n" stringByAppendingString:permissionsNote];
    }
    if ([self isHomeURLString:urlString] ||
        [self isSettingsURLString:urlString] ||
        [self isOnboardingURLString:urlString]) {
        return [@"TrailBrowser internal page. No network connection is used." stringByAppendingString:privacyNote];
    }
    if ([scheme isEqualToString:@"https"]) {
        NSMutableArray<NSString *> *parts = [NSMutableArray arrayWithObject:@"Secure HTTPS connection."];
        if (@available(macOS 10.12, *)) {
            SecTrustRef trust = self.webView.serverTrust;
            if (trust) {
                CFErrorRef trustError = NULL;
                BOOL trusted = SecTrustEvaluateWithError(trust, &trustError);
                if (trustError) CFRelease(trustError);
                [parts addObject:trusted ? @"Certificate is trusted by macOS." : @"Certificate could not be fully verified."];
                if (@available(macOS 12.0, *)) {
                    CFArrayRef chain = SecTrustCopyCertificateChain(trust);
                    SecCertificateRef leaf = chain && CFArrayGetCount(chain) > 0
                        ? (SecCertificateRef)CFArrayGetValueAtIndex(chain, 0)
                        : NULL;
                    if (leaf) {
                        NSString *summary = CFBridgingRelease(SecCertificateCopySubjectSummary(leaf));
                        if (summary.length > 0) [parts addObject:[NSString stringWithFormat:@"Certificate: %@", summary]];
                    }
                    if (chain) CFRelease(chain);
                }
            }
        }
        return [[[parts componentsJoinedByString:@"\n"] stringByAppendingString:permissionsNote] stringByAppendingString:privacyNote];
    }
    if ([scheme isEqualToString:@"http"]) {
        return [[@"Not secure. This page is loaded over HTTP, so traffic is not encrypted." stringByAppendingString:permissionsNote] stringByAppendingString:privacyNote];
    }
    if ([scheme isEqualToString:@"file"]) {
        return [@"Local file opened from this Mac." stringByAppendingString:privacyNote];
    }
    if (urlString.length > 0) {
        return [@"Connection details are not available for this URL scheme." stringByAppendingString:privacyNote];
    }
    return [@"No page is loaded." stringByAppendingString:privacyNote];
}

- (void)updateSiteInfoButton {
    NSURL *url = [self currentDisplayURL];
    NSString *symbol = [self activeTab].privateBrowsing ? @"eye.slash" : [self siteInfoSymbolForURL:url];
    NSString *summary = [self connectionSummaryForURL:url];
    self.siteInfoButton.toolTip = summary.length ? summary : @"Page info";
    if (@available(macOS 11.0, *)) {
        NSImage *image = [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:@"Page info"];
        image.template = YES;
        self.siteInfoButton.image = image;
    }
    if (@available(macOS 10.14, *)) {
        NSString *scheme = url.scheme.lowercaseString ?: @"";
        if ([self activeTab].privateBrowsing) {
            self.siteInfoButton.contentTintColor = TBAccent();
        } else if ([scheme isEqualToString:@"https"]) {
            self.siteInfoButton.contentTintColor = TBOk();
        } else if ([scheme isEqualToString:@"http"]) {
            self.siteInfoButton.contentTintColor = TBError();
        } else {
            self.siteInfoButton.contentTintColor = TBFaint();
        }
    }
}

- (void)showPageInfo:(id)sender {
    (void)sender;
    NSURL *url = [self currentDisplayURL];
    NSString *urlString = url.absoluteString ?: self.addressField.stringValue ?: @"";
    BrowserTab *tab = [self activeTab];

    NSAlert *alert = [[NSAlert alloc] init];
    alert.alertStyle = NSAlertStyleInformational;
    alert.messageText = tab.title.length ? tab.title : @"Page Info";
    alert.informativeText = [NSString stringWithFormat:@"%@\n\n%@",
                             urlString.length ? urlString : @"No URL",
                             [self connectionSummaryForURL:url]];
    [alert addButtonWithTitle:@"OK"];
    [alert beginSheetModalForWindow:self.window completionHandler:nil];
}

#pragma mark - Address suggestions

- (void)buildAddressSuggestionsOverlayInView:(NSView *)root {
    self.addressSuggestionsPanel = [[NSVisualEffectView alloc] initWithFrame:NSZeroRect];
    self.addressSuggestionsPanel.translatesAutoresizingMaskIntoConstraints = NO;
    self.addressSuggestionsPanel.material = NSVisualEffectMaterialHUDWindow;
    self.addressSuggestionsPanel.blendingMode = NSVisualEffectBlendingModeWithinWindow;
    self.addressSuggestionsPanel.state = NSVisualEffectStateActive;
    self.addressSuggestionsPanel.appearance = [self themeVibrantAppearance];
    self.addressSuggestionsPanel.hidden = YES;
    self.addressSuggestionsPanel.alphaValue = 0.0;
    self.addressSuggestionsPanel.wantsLayer = YES;
    self.addressSuggestionsPanel.layer.cornerRadius = 10.0;
    self.addressSuggestionsPanel.layer.masksToBounds = YES;
    self.addressSuggestionsPanel.layer.borderWidth = 1.0;
    self.addressSuggestionsPanel.layer.borderColor = TBBorder().CGColor;
    self.addressSuggestionsPanel.layer.backgroundColor = [TBSurface() colorWithAlphaComponent:0.96].CGColor;
    self.addressSuggestionsPanel.layer.zPosition = 250.0;
    [root addSubview:self.addressSuggestionsPanel];

    self.addressSuggestionsStack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    self.addressSuggestionsStack.translatesAutoresizingMaskIntoConstraints = NO;
    self.addressSuggestionsStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    self.addressSuggestionsStack.alignment = NSLayoutAttributeLeading;
    self.addressSuggestionsStack.distribution = NSStackViewDistributionFill;
    self.addressSuggestionsStack.spacing = 2.0;
    [self.addressSuggestionsPanel addSubview:self.addressSuggestionsStack];

    self.addressSuggestionsHeightConstraint = [self.addressSuggestionsPanel.heightAnchor constraintEqualToConstant:0.0];
    [NSLayoutConstraint activateConstraints:@[
        [self.addressSuggestionsPanel.topAnchor constraintEqualToAnchor:self.toolbar.bottomAnchor constant:6.0],
        [self.addressSuggestionsPanel.leadingAnchor constraintEqualToAnchor:self.addressContainer.leadingAnchor],
        [self.addressSuggestionsPanel.widthAnchor constraintEqualToAnchor:self.addressContainer.widthAnchor],
        self.addressSuggestionsHeightConstraint,

        [self.addressSuggestionsStack.topAnchor constraintEqualToAnchor:self.addressSuggestionsPanel.topAnchor constant:6.0],
        [self.addressSuggestionsStack.leadingAnchor constraintEqualToAnchor:self.addressSuggestionsPanel.leadingAnchor constant:6.0],
        [self.addressSuggestionsStack.trailingAnchor constraintEqualToAnchor:self.addressSuggestionsPanel.trailingAnchor constant:-6.0],
        [self.addressSuggestionsStack.bottomAnchor constraintEqualToAnchor:self.addressSuggestionsPanel.bottomAnchor constant:-6.0]
    ]];
}

- (void)showAddressSuggestionsPanel {
    if (!self.addressSuggestionsPanel.hidden) return;
    self.addressSuggestionsPanel.hidden = NO;
    self.addressSuggestionsPanel.alphaValue = 0.0;
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = 0.08;
        self.addressSuggestionsPanel.animator.alphaValue = 1.0;
    } completionHandler:nil];
}

- (void)hideAddressSuggestionsPanel {
    if (self.addressSuggestionsPanel.hidden) return;
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = 0.08;
        self.addressSuggestionsPanel.animator.alphaValue = 0.0;
    } completionHandler:^{
        self.addressSuggestionsPanel.hidden = YES;
        self.addressSuggestionIndex = -1;
    }];
}

- (void)updateAddressSuggestions {
    NSString *input = [self.addressField.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (input.length == 0 || ![self isAddressFieldBeingEdited]) {
        self.addressSuggestions = @[];
        [self renderAddressSuggestions];
        [self hideAddressSuggestionsPanel];
        return;
    }

    self.addressSuggestions = [self suggestionsForAddressInput:input limit:6];
    self.addressSuggestionIndex = self.addressSuggestions.count > 0 ? 0 : -1;
    [self renderAddressSuggestions];
    if (self.addressSuggestions.count > 0) {
        [self showAddressSuggestionsPanel];
    } else {
        [self hideAddressSuggestionsPanel];
    }
}

- (NSArray<NSDictionary<NSString *, NSString *> *> *)suggestionsForAddressInput:(NSString *)input limit:(NSUInteger)limit {
    NSMutableArray<NSDictionary<NSString *, NSString *> *> *suggestions = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    NSString *needle = input.lowercaseString;

    NSURL *searchURL = [self searchURLForQuery:input];
    [suggestions addObject:@{ @"kind": @"search",
                              @"title": [NSString stringWithFormat:@"Search Google for \"%@\"", input],
                              @"subtitle": @"Search",
                              @"input": input,
                              @"url": searchURL.absoluteString ?: @"" }];
    [seen addObject:[@"search:" stringByAppendingString:needle]];

    NSArray<NSDictionary<NSString *, id> *> *searches = [self JSONLinesAtPath:[self searchHistoryFilePath] newestFirst:YES];
    for (NSDictionary<NSString *, id> *entry in searches) {
        if (suggestions.count >= limit) break;
        NSString *query = [entry[@"query"] isKindOfClass:NSString.class] ? entry[@"query"] : @"";
        NSString *url = [entry[@"url"] isKindOfClass:NSString.class] ? entry[@"url"] : @"";
        if (query.length == 0) continue;
        if (![query.lowercaseString containsString:needle]) continue;
        NSString *key = [@"search:" stringByAppendingString:query.lowercaseString];
        if ([seen containsObject:key]) continue;
        [seen addObject:key];
        [suggestions addObject:@{ @"kind": @"search",
                                  @"title": query,
                                  @"subtitle": @"Previous search",
                                  @"input": query,
                                  @"url": url.length ? url : ([self searchURLForQuery:query].absoluteString ?: @"") }];
    }

    NSArray<NSDictionary<NSString *, id> *> *history = [self JSONLinesAtPath:[self historyFilePath] newestFirst:YES];
    for (NSDictionary<NSString *, id> *entry in history) {
        if (suggestions.count >= limit) break;
        NSString *url = [entry[@"url"] isKindOfClass:NSString.class] ? entry[@"url"] : @"";
        NSString *title = [entry[@"title"] isKindOfClass:NSString.class] ? entry[@"title"] : @"";
        NSString *host = [entry[@"host"] isKindOfClass:NSString.class] ? entry[@"host"] : @"";
        NSString *haystack = [[@[ title ?: @"", url ?: @"", host ?: @"" ] componentsJoinedByString:@" "] lowercaseString];
        if (url.length == 0 || ![haystack containsString:needle]) continue;
        NSString *key = [@"url:" stringByAppendingString:url.lowercaseString];
        if ([seen containsObject:key]) continue;
        [seen addObject:key];
        [suggestions addObject:@{ @"kind": @"url",
                                  @"title": title.length ? title : (host.length ? host : url),
                                  @"subtitle": url,
                                  @"input": url,
                                  @"url": url }];
    }

    return suggestions;
}

- (void)renderAddressSuggestions {
    for (NSView *view in self.addressSuggestionsStack.arrangedSubviews.copy) {
        [self.addressSuggestionsStack removeArrangedSubview:view];
        [view removeFromSuperview];
    }

    NSUInteger count = self.addressSuggestions.count;
    self.addressSuggestionsHeightConstraint.constant = count ? (CGFloat)(count * 44 + 12) : 0.0;

    for (NSUInteger i = 0; i < count; i++) {
        NSView *row = [self addressSuggestionRowAtIndex:(NSInteger)i
                                             suggestion:self.addressSuggestions[i]
                                               selected:((NSInteger)i == self.addressSuggestionIndex)];
        [self.addressSuggestionsStack addArrangedSubview:row];
        [row.widthAnchor constraintEqualToAnchor:self.addressSuggestionsStack.widthAnchor].active = YES;
    }
}

- (NSView *)addressSuggestionRowAtIndex:(NSInteger)index
                             suggestion:(NSDictionary<NSString *, NSString *> *)suggestion
                               selected:(BOOL)selected {
    NSButton *row = [[NSButton alloc] initWithFrame:NSZeroRect];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    row.bordered = NO;
    row.title = @"";
    row.focusRingType = NSFocusRingTypeNone;
    row.target = self;
    row.action = @selector(chooseAddressSuggestion:);
    row.tag = index;
    row.wantsLayer = YES;
    row.layer.cornerRadius = 7.0;
    row.layer.backgroundColor = selected ? [TBElevated() colorWithAlphaComponent:0.96].CGColor
                                         : NSColor.clearColor.CGColor;

    NSImageView *icon = [[NSImageView alloc] initWithFrame:NSZeroRect];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    icon.imageScaling = NSImageScaleProportionallyDown;
    if (@available(macOS 11.0, *)) {
        NSString *symbol = [suggestion[@"kind"] isEqualToString:@"search"] ? @"magnifyingglass" : @"clock.arrow.circlepath";
        NSImage *image = [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:nil];
        image.template = YES;
        icon.image = image;
    }
    if (@available(macOS 10.14, *)) icon.contentTintColor = selected ? TBAccent() : TBMuted();
    [row addSubview:icon];

    NSTextField *title = [NSTextField labelWithString:suggestion[@"title"] ?: @""];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.font = [NSFont systemFontOfSize:13.0 weight:NSFontWeightMedium];
    title.textColor = selected ? TBText() : TBMuted();
    title.lineBreakMode = NSLineBreakByTruncatingTail;
    title.maximumNumberOfLines = 1;
    [row addSubview:title];

    NSTextField *subtitle = [NSTextField labelWithString:suggestion[@"subtitle"] ?: @""];
    subtitle.translatesAutoresizingMaskIntoConstraints = NO;
    subtitle.font = [NSFont systemFontOfSize:11.0 weight:NSFontWeightRegular];
    subtitle.textColor = TBFaint();
    subtitle.lineBreakMode = NSLineBreakByTruncatingMiddle;
    subtitle.maximumNumberOfLines = 1;
    [row addSubview:subtitle];

    [NSLayoutConstraint activateConstraints:@[
        [row.heightAnchor constraintEqualToConstant:42.0],

        [icon.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:10.0],
        [icon.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [icon.widthAnchor constraintEqualToConstant:16.0],
        [icon.heightAnchor constraintEqualToConstant:16.0],

        [title.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:10.0],
        [title.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-10.0],
        [title.topAnchor constraintEqualToAnchor:row.topAnchor constant:6.0],

        [subtitle.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [subtitle.trailingAnchor constraintEqualToAnchor:title.trailingAnchor],
        [subtitle.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:1.0]
    ]];

    return row;
}

- (void)chooseAddressSuggestion:(id)sender {
    NSInteger index = [sender tag];
    [self acceptAddressSuggestionAtIndex:index];
}

- (void)moveAddressSuggestionSelectionBy:(NSInteger)delta {
    if (self.addressSuggestions.count == 0) return;
    NSInteger count = (NSInteger)self.addressSuggestions.count;
    self.addressSuggestionIndex = (self.addressSuggestionIndex + delta + count) % count;
    [self renderAddressSuggestions];
}

- (void)acceptAddressSuggestionAtIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)self.addressSuggestions.count) return;
    NSDictionary<NSString *, NSString *> *suggestion = self.addressSuggestions[(NSUInteger)index];
    NSString *input = suggestion[@"input"] ?: suggestion[@"url"] ?: @"";
    if (input.length == 0) return;
    self.addressField.stringValue = input;
    [self hideAddressSuggestionsPanel];
    self.userEditingAddress = NO;
    [self loadURLString:input];
}

#pragma mark - Tab switcher

- (void)buildTabSwitcherOverlay {
    self.tabSwitcherPanel = [[NSVisualEffectView alloc] initWithFrame:NSZeroRect];
    self.tabSwitcherPanel.translatesAutoresizingMaskIntoConstraints = NO;
    self.tabSwitcherPanel.material = NSVisualEffectMaterialPopover;
    self.tabSwitcherPanel.blendingMode = NSVisualEffectBlendingModeWithinWindow;
    self.tabSwitcherPanel.state = NSVisualEffectStateActive;
    self.tabSwitcherPanel.appearance = [self themeVibrantAppearance];
    self.tabSwitcherPanel.hidden = YES;
    self.tabSwitcherPanel.alphaValue = 0.0;
    self.tabSwitcherPanel.wantsLayer = YES;
    self.tabSwitcherPanel.layer.cornerRadius = 22.0;
    self.tabSwitcherPanel.layer.masksToBounds = YES;
    self.tabSwitcherPanel.layer.borderWidth = 1.0;
    self.tabSwitcherPanel.layer.borderColor = TBBorder().CGColor;
    self.tabSwitcherPanel.layer.backgroundColor = [TBSurface() colorWithAlphaComponent:0.92].CGColor;
    self.tabSwitcherPanel.layer.zPosition = 200.0;
    [self.webContainer addSubview:self.tabSwitcherPanel];

    self.tabSwitcherStack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    self.tabSwitcherStack.translatesAutoresizingMaskIntoConstraints = NO;
    self.tabSwitcherStack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    self.tabSwitcherStack.alignment = NSLayoutAttributeCenterY;
    self.tabSwitcherStack.distribution = NSStackViewDistributionGravityAreas;
    self.tabSwitcherStack.spacing = 8.0;
    [self.tabSwitcherPanel addSubview:self.tabSwitcherStack];

    self.tabSwitcherWidthConstraint = [self.tabSwitcherPanel.widthAnchor constraintEqualToConstant:320.0];
    [NSLayoutConstraint activateConstraints:@[
        [self.tabSwitcherPanel.centerXAnchor constraintEqualToAnchor:self.webContainer.centerXAnchor],
        [self.tabSwitcherPanel.centerYAnchor constraintEqualToAnchor:self.webContainer.centerYAnchor constant:-24.0],
        self.tabSwitcherWidthConstraint,
        [self.tabSwitcherPanel.heightAnchor constraintEqualToConstant:116.0],

        [self.tabSwitcherStack.leadingAnchor constraintEqualToAnchor:self.tabSwitcherPanel.leadingAnchor constant:18.0],
        [self.tabSwitcherStack.trailingAnchor constraintEqualToAnchor:self.tabSwitcherPanel.trailingAnchor constant:-18.0],
        [self.tabSwitcherStack.topAnchor constraintEqualToAnchor:self.tabSwitcherPanel.topAnchor constant:14.0],
        [self.tabSwitcherStack.bottomAnchor constraintEqualToAnchor:self.tabSwitcherPanel.bottomAnchor constant:-12.0]
    ]];
}

- (void)installTabSwitcherEventMonitor {
    if (self.tabSwitcherEventMonitor) return;

    __weak BrowserAppDelegate *weakSelf = self;
    self.tabSwitcherEventMonitor =
        [NSEvent addLocalMonitorForEventsMatchingMask:(NSEventMaskKeyDown | NSEventMaskFlagsChanged)
                                              handler:^NSEvent *(NSEvent *event) {
        BrowserAppDelegate *strongSelf = weakSelf;
        if (!strongSelf) return event;
        return [strongSelf handleTabSwitcherEvent:event];
    }];
}

- (NSEvent *)handleTabSwitcherEvent:(NSEvent *)event {
    if (event.window && event.window != self.window) return event;

    if (event.type == NSEventTypeKeyDown) {
        if ([self isCommandOptionTabEvent:event]) {
            BOOL backward = (event.modifierFlags & NSEventModifierFlagShift) != 0;
            [self beginOrAdvanceTabSwitcherBackward:backward];
            return nil;
        }

        if ([self isControlTabEvent:event]) {
            BOOL backward = (event.modifierFlags & NSEventModifierFlagShift) != 0;
            [self cycleActiveTabBy:backward ? -1 : 1];
            return nil;
        }

        if (self.tabSwitcherVisible) {
            if (event.keyCode == kEscapeKeyCode) {
                [self cancelTabSwitcher];
                return nil;
            }
            if (event.keyCode == kReturnKeyCode) {
                [self commitTabSwitcher];
                return nil;
            }
            if (event.keyCode == kLeftArrowKeyCode || event.keyCode == kRightArrowKeyCode) {
                [self advanceTabSwitcherBy:(event.keyCode == kLeftArrowKeyCode) ? -1 : 1];
                return nil;
            }
        }
        return event;
    }

    if (event.type == NSEventTypeFlagsChanged && self.tabSwitcherVisible) {
        NSEventModifierFlags flags = event.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask;
        BOOL stillHoldingSwitcher = (flags & NSEventModifierFlagCommand) &&
                                    (flags & NSEventModifierFlagOption);
        if (!stillHoldingSwitcher) {
            [self commitTabSwitcher];
        }
        return nil;
    }

    return event;
}

- (BOOL)isCommandOptionTabEvent:(NSEvent *)event {
    NSEventModifierFlags flags = event.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask;
    return event.keyCode == kTabKeyCode &&
           (flags & NSEventModifierFlagCommand) &&
           (flags & NSEventModifierFlagOption);
}

- (BOOL)isControlTabEvent:(NSEvent *)event {
    NSEventModifierFlags flags = event.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask;
    return event.keyCode == kTabKeyCode &&
           (flags & NSEventModifierFlagControl) &&
           !(flags & NSEventModifierFlagCommand) &&
           !(flags & NSEventModifierFlagOption);
}

- (void)showTabSwitcherFromMenu:(id)sender {
    (void)sender;
    [self beginOrAdvanceTabSwitcherBackward:NO];
    [self commitTabSwitcher];
}

- (void)selectNextTab:(id)sender {
    (void)sender;
    [self cycleActiveTabBy:1];
}

- (void)selectPreviousTab:(id)sender {
    (void)sender;
    [self cycleActiveTabBy:-1];
}

- (void)cycleActiveTabBy:(NSInteger)delta {
    if (self.tabs.count <= 1) return;
    if (self.tabSwitcherVisible) [self cancelTabSwitcher];

    NSInteger count = (NSInteger)self.tabs.count;
    NSInteger current = self.activeTabIndex >= 0 ? self.activeTabIndex : 0;
    NSInteger next = (current + delta + count) % count;
    [self selectTabAtIndex:next];
}

- (void)beginOrAdvanceTabSwitcherBackward:(BOOL)backward {
    if (self.tabs.count <= 1) return;

    if (!self.tabSwitcherVisible) {
        self.tabSwitcherIndex = self.activeTabIndex >= 0 ? self.activeTabIndex : 0;
        [self showTabSwitcher];
    }

    [self advanceTabSwitcherBy:backward ? -1 : 1];
}

- (void)advanceTabSwitcherBy:(NSInteger)delta {
    if (self.tabs.count == 0) return;

    NSInteger count = (NSInteger)self.tabs.count;
    self.tabSwitcherIndex = (self.tabSwitcherIndex + delta + count) % count;
    [self refreshTabSwitcher];
}

- (void)showTabSwitcher {
    self.tabSwitcherVisible = YES;
    self.tabSwitcherPanel.hidden = NO;
    self.tabSwitcherPanel.alphaValue = 0.0;
    self.tabSwitcherPanel.layer.transform = CATransform3DMakeScale(0.98, 0.98, 1.0);
    [self.webContainer addSubview:self.tabSwitcherPanel positioned:NSWindowAbove relativeTo:nil];
    [self refreshTabSwitcher];

    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = 0.12;
        context.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
        self.tabSwitcherPanel.animator.alphaValue = 1.0;
        self.tabSwitcherPanel.layer.transform = CATransform3DIdentity;
    } completionHandler:nil];
}

- (void)hideTabSwitcher {
    self.tabSwitcherVisible = NO;
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = 0.10;
        context.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
        self.tabSwitcherPanel.animator.alphaValue = 0.0;
    } completionHandler:^{
        if (!self.tabSwitcherVisible) self.tabSwitcherPanel.hidden = YES;
    }];
}

- (void)commitTabSwitcher {
    if (!self.tabSwitcherVisible) return;
    NSInteger index = self.tabSwitcherIndex;
    [self hideTabSwitcher];
    [self selectTabAtIndex:index];
}

- (void)cancelTabSwitcher {
    if (!self.tabSwitcherVisible) return;
    [self hideTabSwitcher];
}

- (void)chooseTabFromSwitcherItem:(id)sender {
    NSInteger index = [sender tag];
    if (index < 0 || index >= (NSInteger)self.tabs.count) return;
    self.tabSwitcherIndex = index;
    [self commitTabSwitcher];
}

- (void)refreshTabSwitcher {
    if (!self.tabSwitcherPanel) return;

    for (NSView *view in self.tabSwitcherStack.arrangedSubviews.copy) {
        [self.tabSwitcherStack removeArrangedSubview:view];
        [view removeFromSuperview];
    }

    NSInteger count = (NSInteger)self.tabs.count;
    if (count == 0) return;

    NSInteger visibleCount = MIN(count, kMaxVisibleSwitcherTabs);
    NSInteger start = self.tabSwitcherIndex - visibleCount / 2;
    if (start < 0) start = 0;
    if (start + visibleCount > count) start = count - visibleCount;

    CGFloat itemWidth = 86.0;
    CGFloat horizontalPadding = 36.0;
    CGFloat maxWidth = MAX(260.0, NSWidth(self.webContainer.bounds) - 72.0);
    NSInteger fittingCount = (NSInteger)floor((maxWidth - horizontalPadding + self.tabSwitcherStack.spacing) /
                                              (itemWidth + self.tabSwitcherStack.spacing));
    visibleCount = MAX(1, MIN(visibleCount, fittingCount));
    if (start + visibleCount > count) start = count - visibleCount;

    CGFloat width = horizontalPadding + visibleCount * itemWidth +
                    MAX(0, visibleCount - 1) * self.tabSwitcherStack.spacing;
    self.tabSwitcherWidthConstraint.constant = MIN(width, maxWidth);

    for (NSInteger i = 0; i < visibleCount; i++) {
        NSInteger tabIndex = start + i;
        NSView *item = [self tabSwitcherItemForIndex:tabIndex selected:(tabIndex == self.tabSwitcherIndex)];
        [self.tabSwitcherStack addArrangedSubview:item];
    }
}

- (NSView *)tabSwitcherItemForIndex:(NSInteger)index selected:(BOOL)selected {
    BrowserTab *tab = self.tabs[(NSUInteger)index];

    NSButton *item = [[NSButton alloc] initWithFrame:NSZeroRect];
    item.translatesAutoresizingMaskIntoConstraints = NO;
    item.bordered = NO;
    item.title = @"";
    item.focusRingType = NSFocusRingTypeNone;
    item.target = self;
    item.action = @selector(chooseTabFromSwitcherItem:);
    item.tag = index;
    item.wantsLayer = YES;
    item.layer.cornerRadius = 12.0;
    item.layer.masksToBounds = YES;
    item.layer.backgroundColor = selected ? [TBAccent() colorWithAlphaComponent:0.13].CGColor
                                          : [TBElevated() colorWithAlphaComponent:0.42].CGColor;
    item.layer.borderWidth = 1.0;
    item.layer.borderColor = selected ? [TBAccent() colorWithAlphaComponent:0.55].CGColor
                                      : [TBBorder() colorWithAlphaComponent:0.35].CGColor;

    NSView *iconWell = [[NSView alloc] initWithFrame:NSZeroRect];
    iconWell.translatesAutoresizingMaskIntoConstraints = NO;
    iconWell.wantsLayer = YES;
    iconWell.layer.cornerRadius = 12.0;
    iconWell.layer.masksToBounds = YES;
    iconWell.layer.backgroundColor = selected ? [TBElevated() colorWithAlphaComponent:0.86].CGColor
                                              : [TBSurface() colorWithAlphaComponent:0.72].CGColor;
    [item addSubview:iconWell];

    NSImageView *icon = [[NSImageView alloc] initWithFrame:NSZeroRect];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    icon.imageScaling = NSImageScaleProportionallyDown;
    icon.image = [self switcherIconForTab:tab];
    icon.alphaValue = tab.webView || selected ? 1.0 : 0.58;
    if (!tab.favicon) {
        if (@available(macOS 10.14, *)) {
            icon.contentTintColor = selected ? TBAccent() : TBMuted();
        }
    }
    [iconWell addSubview:icon];

    NSTextField *label = [NSTextField labelWithString:[self switcherTitleForTab:tab]];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.font = [NSFont systemFontOfSize:10.5 weight:NSFontWeightRegular];
    label.textColor = selected ? TBText() : TBMuted();
    label.alignment = NSTextAlignmentCenter;
    label.lineBreakMode = NSLineBreakByTruncatingTail;
    label.maximumNumberOfLines = 2;
    [item addSubview:label];

    [NSLayoutConstraint activateConstraints:@[
        [item.widthAnchor constraintEqualToConstant:86.0],
        [item.heightAnchor constraintEqualToConstant:88.0],

        [iconWell.topAnchor constraintEqualToAnchor:item.topAnchor constant:8.0],
        [iconWell.centerXAnchor constraintEqualToAnchor:item.centerXAnchor],
        [iconWell.widthAnchor constraintEqualToConstant:52.0],
        [iconWell.heightAnchor constraintEqualToConstant:52.0],

        [icon.centerXAnchor constraintEqualToAnchor:iconWell.centerXAnchor],
        [icon.centerYAnchor constraintEqualToAnchor:iconWell.centerYAnchor],
        [icon.widthAnchor constraintEqualToConstant:32.0],
        [icon.heightAnchor constraintEqualToConstant:32.0],

        [label.leadingAnchor constraintEqualToAnchor:item.leadingAnchor constant:7.0],
        [label.trailingAnchor constraintEqualToAnchor:item.trailingAnchor constant:-7.0],
        [label.topAnchor constraintEqualToAnchor:iconWell.bottomAnchor constant:5.0],
        [label.bottomAnchor constraintLessThanOrEqualToAnchor:item.bottomAnchor constant:-5.0]
    ]];

    return item;
}

- (NSImage *)switcherIconForTab:(BrowserTab *)tab {
    if (tab.favicon) {
        tab.favicon.template = NO;
        return tab.favicon;
    }

    if (@available(macOS 11.0, *)) {
        NSString *symbol = tab.privateBrowsing ? @"eye.slash" : @"globe";
        if (tab.privateBrowsing) {
            symbol = @"eye.slash";
        } else if ([self isHomeURLString:tab.urlString]) {
            symbol = @"house";
        } else if ([self isSettingsURLString:tab.urlString]) {
            symbol = @"gearshape";
        } else if ([self isOnboardingURLString:tab.urlString]) {
            symbol = @"sparkles";
        }

        NSImage *image = [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:@"Tab"];
        NSImageSymbolConfiguration *config = [NSImageSymbolConfiguration configurationWithPointSize:24.0
                                                                                             weight:NSFontWeightMedium];
        image = [image imageWithSymbolConfiguration:config] ?: image;
        image.template = YES;
        return image;
    }

    return [NSImage imageNamed:NSImageNameNetwork];
}

- (NSString *)switcherTitleForTab:(BrowserTab *)tab {
    NSString *title = tab.title.length ? tab.title : nil;
    if (title.length == 0 || [title isEqualToString:@"New Tab"]) {
        title = [self subtitleForTab:tab];
    }
    if (title.length == 0) return @"New Tab";
    return title;
}

- (WKWebView *)createWebViewWithConfiguration:(WKWebViewConfiguration *)configuration {
    WKWebViewConfiguration *config = configuration ?: [self defaultWebViewConfiguration];
    [self configureForLowMemory:config];
    WKWebView *webView = [[WKWebView alloc] initWithFrame:NSZeroRect configuration:config];
    webView.translatesAutoresizingMaskIntoConstraints = NO;
    webView.navigationDelegate = self;
    webView.UIDelegate = self;
    webView.allowsBackForwardNavigationGestures = YES;
    webView.hidden = YES;
    if (@available(macOS 13.3, *)) {
        webView.inspectable = YES;
    }
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
    if (self.findBar) {
        [self.webContainer addSubview:self.findBar positioned:NSWindowAbove relativeTo:webView];
    }
    if (self.tabSwitcherPanel) {
        [self.webContainer addSubview:self.tabSwitcherPanel positioned:NSWindowAbove relativeTo:self.findBar ?: webView];
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
    configuration.suppressesIncrementalRendering = YES;
    configuration.allowsAirPlayForMediaPlayback = NO;
    configuration.mediaTypesRequiringUserActionForPlayback = WKAudiovisualMediaTypeAll;
}

- (WKWebViewConfiguration *)defaultWebViewConfiguration {
    WKWebViewConfiguration *configuration = [[WKWebViewConfiguration alloc] init];
    configuration.websiteDataStore = [WKWebsiteDataStore defaultDataStore];
    return configuration;
}

- (WKWebViewConfiguration *)privateWebViewConfiguration {
    WKWebViewConfiguration *configuration = [[WKWebViewConfiguration alloc] init];
    configuration.websiteDataStore = [WKWebsiteDataStore nonPersistentDataStore];
    return configuration;
}

- (BrowserTab *)newTabWithURLString:(NSString *)urlString select:(BOOL)select {
    return [self newTabWithConfiguration:nil URLString:urlString select:select privateBrowsing:NO];
}

- (BrowserTab *)newTabWithConfiguration:(WKWebViewConfiguration *)configuration
                              URLString:(NSString *)urlString
                                 select:(BOOL)select {
    return [self newTabWithConfiguration:configuration
                               URLString:urlString
                                  select:select
                         privateBrowsing:NO];
}

- (BrowserTab *)newTabWithConfiguration:(WKWebViewConfiguration *)configuration
                              URLString:(NSString *)urlString
                                 select:(BOOL)select
                        privateBrowsing:(BOOL)privateBrowsing {
    return [self newTabWithConfiguration:configuration
                               URLString:urlString
                                  select:select
                         privateBrowsing:privateBrowsing
                             insertIndex:(NSInteger)self.tabs.count];
}

- (BrowserTab *)newTabWithConfiguration:(WKWebViewConfiguration *)configuration
                              URLString:(NSString *)urlString
                                 select:(BOOL)select
                        privateBrowsing:(BOOL)privateBrowsing
                            insertIndex:(NSInteger)insertIndex {
    BrowserTab *tab = [[BrowserTab alloc] init];
    tab.title = @"New Tab";
    tab.urlString = urlString ?: [self homeURLString];
    tab.privateBrowsing = privateBrowsing;
    if (configuration) tab.webView = [self createWebViewWithConfiguration:configuration];

    if (insertIndex < 0 || insertIndex > (NSInteger)self.tabs.count) insertIndex = (NSInteger)self.tabs.count;
    if (!select && self.activeTabIndex >= insertIndex) self.activeTabIndex += 1;
    [self.tabs insertObject:tab atIndex:(NSUInteger)insertIndex];
    [self.tabTable reloadData];
    [self updateTabCount];

    if (select) {
        [self selectTabAtIndex:insertIndex];
    } else if (configuration == nil && !privateBrowsing) {
        [self preloadTab:tab];
        [self enforceLiveTabBudget];
    }

    if (!self.restoringSession) [self writeBrowserStateRunning:YES];
    return tab;
}

- (BrowserTab *)newPrivateTabWithURLString:(NSString *)urlString select:(BOOL)select {
    return [self newTabWithConfiguration:[self privateWebViewConfiguration]
                               URLString:urlString ?: [self homeURLString]
                                  select:select
                         privateBrowsing:YES];
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
        WKWebViewConfiguration *configuration = tab.privateBrowsing ? [self privateWebViewConfiguration] : nil;
        tab.webView = [self createWebViewWithConfiguration:configuration];
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
        unsigned long pressure = dispatch_source_get_data(source);
        if ([weakSelf keepTabsLoaded] && !(pressure & DISPATCH_MEMORYPRESSURE_CRITICAL)) {
            return;
        }
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
    NSInteger liveTabBudget = [self liveTabBudget];
    if (liveTabBudget == NSIntegerMax) return;

    NSMutableArray<BrowserTab *> *live = [NSMutableArray array];
    for (BrowserTab *tab in self.tabs) {
        if (tab.webView && tab != [self activeTab]) [live addObject:tab];
    }
    if ((NSInteger)live.count <= liveTabBudget - 1) return;

    [live sortUsingComparator:^NSComparisonResult(BrowserTab *a, BrowserTab *b) {
        if (a.lastActiveSeq < b.lastActiveSeq) return NSOrderedAscending;
        if (a.lastActiveSeq > b.lastActiveSeq) return NSOrderedDescending;
        return NSOrderedSame;
    }];

    NSInteger excess = (NSInteger)live.count - (liveTabBudget - 1);
    for (NSInteger i = 0; i < excess; i++) {
        [self sleepTab:live[(NSUInteger)i]];
    }
}

- (BOOL)keepTabsLoaded {
    id value = [[NSUserDefaults standardUserDefaults] objectForKey:TBKeepTabsLoadedKey];
    return value ? [value boolValue] : YES;
}

- (NSInteger)liveTabBudget {
    return [self keepTabsLoaded] ? NSIntegerMax : kMemorySaverMaxLiveTabs;
}

- (void)preloadAllInactiveTabs {
    BrowserTab *active = [self activeTab];
    for (BrowserTab *tab in self.tabs) {
        if (tab == active) continue;
        if (tab.webView) {
            [self loadContentForTab:tab];
        } else {
            [self preloadTab:tab];
        }
    }
}

- (void)setKeepTabsLoaded:(BOOL)keepTabsLoaded {
    [[NSUserDefaults standardUserDefaults] setBool:keepTabsLoaded forKey:TBKeepTabsLoadedKey];
    if (keepTabsLoaded) {
        [self preloadAllInactiveTabs];
    } else {
        [self enforceLiveTabBudget];
    }
    if (self.tabs.count > 0) {
        NSIndexSet *rows = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, self.tabs.count)];
        [self.tabTable reloadDataForRowIndexes:rows columnIndexes:[NSIndexSet indexSetWithIndex:0]];
    }
    [self writeBrowserStateRunning:YES];
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
    [self scheduleFormDetectionForWebView:self.webView];
    if (!self.restoringSession) [self writeBrowserStateRunning:YES];
}

- (void)newTab:(id)sender {
    (void)sender;
    if ([self activeTab].privateBrowsing) {
        [self newPrivateTabWithURLString:[self homeURLString] select:YES];
    } else {
        [self newTabWithURLString:[self homeURLString] select:YES];
    }
}

- (void)newPrivateTab:(id)sender {
    (void)sender;
    [self newPrivateTabWithURLString:[self homeURLString] select:YES];
}

- (void)closeCurrentTab:(id)sender {
    (void)sender;
    [self closeTabAtIndex:self.activeTabIndex];
}

- (NSString *)URLStringForTab:(BrowserTab *)tab {
    return tab.webView.URL.absoluteString ?: tab.urlString ?: @"";
}

- (void)reloadTabAtIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)self.tabs.count) {
        NSBeep();
        return;
    }

    BrowserTab *tab = self.tabs[(NSUInteger)index];
    if (tab.webView) {
        [tab.webView reload];
        [self setStatusText:@"Reloading tab"];
        return;
    }

    [self preloadTab:tab];
    [self setStatusText:@"Reloading tab"];
}

- (BrowserTab *)duplicateTabAtIndex:(NSInteger)index select:(BOOL)select {
    if (index < 0 || index >= (NSInteger)self.tabs.count) {
        NSBeep();
        return nil;
    }

    BrowserTab *source = self.tabs[(NSUInteger)index];
    NSString *urlString = [self URLStringForTab:source];
    if (urlString.length == 0) urlString = [self homeURLString];

    NSInteger insertIndex = MIN(index + 1, (NSInteger)self.tabs.count);
    WKWebViewConfiguration *configuration = source.privateBrowsing ? [self privateWebViewConfiguration] : nil;
    BrowserTab *duplicate = [self newTabWithConfiguration:configuration
                                                URLString:urlString
                                                   select:select
                                          privateBrowsing:source.privateBrowsing
                                              insertIndex:insertIndex];
    duplicate.title = source.title.length ? source.title : @"New Tab";
    duplicate.favicon = source.favicon;
    duplicate.faviconURLString = source.faviconURLString;
    duplicate.pinned = source.pinned;
    [self reloadSidebarRowForTab:duplicate];
    [self setStatusText:@"Duplicated tab"];
    return duplicate;
}

- (void)duplicateCurrentTab:(id)sender {
    (void)sender;
    [self duplicateTabAtIndex:self.activeTabIndex select:YES];
}

- (NSInteger)pinnedTabCountExcludingIndex:(NSInteger)excludedIndex {
    NSInteger count = 0;
    for (NSInteger i = 0; i < (NSInteger)self.tabs.count; i++) {
        if (i == excludedIndex) continue;
        if (self.tabs[(NSUInteger)i].pinned) count += 1;
    }
    return count;
}

- (void)refreshTabTableAfterMetadataChangeWithStatus:(NSString *)status {
    self.suppressTabSelectionChange = YES;
    [self.tabTable reloadData];
    if (self.activeTabIndex >= 0 && self.activeTabIndex < (NSInteger)self.tabs.count) {
        [self.tabTable selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)self.activeTabIndex]
                   byExtendingSelection:NO];
    }
    self.suppressTabSelectionChange = NO;
    [self refreshActiveRowHighlight];
    if (self.tabSwitcherVisible) [self refreshTabSwitcher];
    if (status.length > 0) [self setStatusText:status];
    if (!self.restoringSession) [self writeBrowserStateRunning:YES];
}

- (void)setPinned:(BOOL)pinned forTabAtIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)self.tabs.count) {
        NSBeep();
        return;
    }

    BrowserTab *tab = self.tabs[(NSUInteger)index];
    if (tab.pinned == pinned) return;

    NSInteger pinnedCount = [self pinnedTabCountExcludingIndex:index];
    NSInteger dropIndex = pinned ? pinnedCount : pinnedCount + 1;
    tab.pinned = pinned;

    BOOL moved = [self moveTabFromIndex:index toDropIndex:dropIndex];
    NSString *status = pinned ? @"Pinned tab" : @"Unpinned tab";
    if (moved) {
        [self setStatusText:status];
    } else {
        [self refreshTabTableAfterMetadataChangeWithStatus:status];
    }
}

- (void)togglePinnedForTabAtIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)self.tabs.count) {
        NSBeep();
        return;
    }
    BrowserTab *tab = self.tabs[(NSUInteger)index];
    [self setPinned:!tab.pinned forTabAtIndex:index];
}

- (void)toggleCurrentTabPinned:(id)sender {
    (void)sender;
    [self togglePinnedForTabAtIndex:self.activeTabIndex];
}

- (BOOL)moveTabFromIndex:(NSInteger)sourceIndex toDropIndex:(NSInteger)dropIndex {
    if (sourceIndex < 0 || sourceIndex >= (NSInteger)self.tabs.count) return NO;

    NSInteger boundedDropIndex = MIN(MAX(dropIndex, 0), (NSInteger)self.tabs.count);
    if (boundedDropIndex == sourceIndex || boundedDropIndex == sourceIndex + 1) return NO;

    BrowserTab *movingTab = self.tabs[(NSUInteger)sourceIndex];
    BrowserTab *activeTab = [self activeTab];
    [self.tabs removeObjectAtIndex:(NSUInteger)sourceIndex];

    NSInteger destinationIndex = boundedDropIndex;
    if (destinationIndex > sourceIndex) destinationIndex -= 1;
    destinationIndex = MIN(MAX(destinationIndex, 0), (NSInteger)self.tabs.count);
    [self.tabs insertObject:movingTab atIndex:(NSUInteger)destinationIndex];

    NSUInteger activeIndex = activeTab ? [self.tabs indexOfObject:activeTab] : NSNotFound;
    self.activeTabIndex = activeIndex == NSNotFound ? -1 : (NSInteger)activeIndex;
    self.suppressTabSelectionChange = YES;
    [self.tabTable reloadData];
    if (self.activeTabIndex >= 0) {
        [self.tabTable selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)self.activeTabIndex]
                   byExtendingSelection:NO];
    }
    self.suppressTabSelectionChange = NO;
    [self.tabTable scrollRowToVisible:destinationIndex];
    [self refreshActiveRowHighlight];
    if (self.tabSwitcherVisible) [self refreshTabSwitcher];
    [self setStatusText:@"Moved tab"];
    if (!self.restoringSession) [self writeBrowserStateRunning:YES];
    return YES;
}

- (void)moveCurrentTabUp:(id)sender {
    (void)sender;
    [self moveTabFromIndex:self.activeTabIndex toDropIndex:self.activeTabIndex - 1];
}

- (void)moveCurrentTabDown:(id)sender {
    (void)sender;
    [self moveTabFromIndex:self.activeTabIndex toDropIndex:self.activeTabIndex + 2];
}

- (void)closeTabsExceptIndex:(NSInteger)keepIndex {
    if (keepIndex < 0 || keepIndex >= (NSInteger)self.tabs.count) {
        NSBeep();
        return;
    }
    if (self.tabs.count <= 1) return;

    [self selectTabAtIndex:keepIndex];
    for (NSInteger i = (NSInteger)self.tabs.count - 1; i >= 0; i--) {
        if (i == keepIndex) continue;
        [self closeTabAtIndex:i];
        if (i < keepIndex) keepIndex -= 1;
    }
    [self setStatusText:@"Closed other tabs"];
}

- (void)closeTabsToRightOfIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)self.tabs.count) {
        NSBeep();
        return;
    }
    if (index >= (NSInteger)self.tabs.count - 1) return;

    for (NSInteger i = (NSInteger)self.tabs.count - 1; i > index; i--) {
        [self closeTabAtIndex:i];
    }
    [self setStatusText:@"Closed tabs to the right"];
}

- (void)closeOtherTabsForCurrentTab:(id)sender {
    (void)sender;
    [self closeTabsExceptIndex:self.activeTabIndex];
}

- (void)closeTabsToRightForCurrentTab:(id)sender {
    (void)sender;
    [self closeTabsToRightOfIndex:self.activeTabIndex];
}

- (NSDictionary<NSString *, id> *)recentlyClosedEntryForTab:(BrowserTab *)tab {
    if (!tab || tab.privateBrowsing) return nil;

    NSString *urlString = [self URLStringForTab:tab];
    if (urlString.length == 0 || [urlString hasPrefix:@"view-source:"]) return nil;

    NSString *title = tab.webView.title.length ? tab.webView.title : (tab.title ?: @"");
    return @{
        @"url": urlString,
        @"title": title ?: @"",
        @"closedAt": [[self historyDateFormatter] stringFromDate:[NSDate date]],
        @"pinned": @(tab.pinned)
    };
}

- (void)recordRecentlyClosedTab:(BrowserTab *)tab {
    NSDictionary<NSString *, id> *entry = [self recentlyClosedEntryForTab:tab];
    if (!entry) return;
    if (!self.recentlyClosedTabs) self.recentlyClosedTabs = [NSMutableArray array];

    [self.recentlyClosedTabs addObject:entry];
    while ((NSInteger)self.recentlyClosedTabs.count > kMaxRecentlyClosedTabs) {
        [self.recentlyClosedTabs removeObjectAtIndex:0];
    }
}

- (void)reopenClosedTab:(id)sender {
    (void)sender;
    if (self.recentlyClosedTabs.count == 0) {
        NSBeep();
        return;
    }

    NSDictionary<NSString *, id> *entry = self.recentlyClosedTabs.lastObject;
    [self.recentlyClosedTabs removeLastObject];

    NSString *urlString = [entry[@"url"] isKindOfClass:NSString.class] ? entry[@"url"] : @"";
    if (urlString.length == 0) {
        NSBeep();
        return;
    }

    BrowserTab *tab = [self newTabWithURLString:urlString select:YES];
    NSString *title = [entry[@"title"] isKindOfClass:NSString.class] ? entry[@"title"] : @"";
    if (title.length > 0) {
        tab.title = title;
        [self reloadSidebarRowForTab:tab];
    }
    if ([entry[@"pinned"] isKindOfClass:NSNumber.class]) {
        [self setPinned:[entry[@"pinned"] boolValue] forTabAtIndex:self.activeTabIndex];
    }
    [self setStatusText:@"Reopened closed tab"];
    if (!self.restoringSession) [self writeBrowserStateRunning:YES];
}

- (void)closeTabAtIndex:(NSInteger)closingIndex {
    if (self.tabs.count == 0) return;
    if (closingIndex < 0 || closingIndex >= (NSInteger)self.tabs.count) closingIndex = self.activeTabIndex;
    if (closingIndex < 0 || closingIndex >= (NSInteger)self.tabs.count) closingIndex = 0;

    BOOL closingActive = (closingIndex == self.activeTabIndex);
    BrowserTab *closingTab = self.tabs[(NSUInteger)closingIndex];
    [self recordRecentlyClosedTab:closingTab];

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
        if (!self.restoringSession) [self writeBrowserStateRunning:YES];
        return;
    }

    if (closingActive) {
        self.webView = nil;
        self.activeTabIndex = -1;
        [self.tabTable reloadData];
        NSInteger nextIndex = MIN(closingIndex, (NSInteger)self.tabs.count - 1);
        [self selectTabAtIndex:nextIndex];
        if (!self.restoringSession) [self writeBrowserStateRunning:YES];
        return;
    }

    if (closingIndex < self.activeTabIndex) self.activeTabIndex -= 1;
    [self.tabTable reloadData];
    [self.tabTable selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)self.activeTabIndex]
               byExtendingSelection:NO];
    [self refreshActiveRowHighlight];
    [self updateControls];
    if (!self.restoringSession) [self writeBrowserStateRunning:YES];
}

- (void)loadFromAddressField:(id)sender {
    (void)sender;
    if (self.addressSuggestionIndex >= 0 && self.addressSuggestionIndex < (NSInteger)self.addressSuggestions.count) {
        [self acceptAddressSuggestionAtIndex:self.addressSuggestionIndex];
        return;
    }
    [self hideAddressSuggestionsPanel];
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
        if (!self.restoringSession) [self writeBrowserStateRunning:YES];
        return;
    }

    if ([self isSettingsURLString:input]) {
        [self loadNativeSettingsPageInWebView:self.webView];
        if (!self.restoringSession) [self writeBrowserStateRunning:YES];
        return;
    }

    if ([self isOnboardingURLString:input]) {
        [self loadNativeOnboardingPageInWebView:self.webView];
        if (!self.restoringSession) [self writeBrowserStateRunning:YES];
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
    if (!tab.privateBrowsing) [self recordSearchInputIfNeeded:input resolvedURL:url];
    [self setStatusText:@"Loading"];
    [self.webView loadRequest:[NSURLRequest requestWithURL:url]];
    if (!self.restoringSession) [self writeBrowserStateRunning:YES];
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
        NSString *background = TBThemeIsDark() ? @"#0a0a0b" : @"#f7eef4";
        return [NSString stringWithFormat:@"<!doctype html><title>TrailBrowser</title><body style='background:%@'></body>", background];
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

    if ([host isEqualToString:@"request-passkey-access"]) {
        [self requestPasskeyAccessFromSettings];
        return YES;
    }

    if ([host isEqualToString:@"clear-history"]) {
        [self clearBrowsingHistory];
        if (self.webView) [self loadNativeSettingsPageInWebView:self.webView];
        return YES;
    }

    if ([host isEqualToString:@"cluster-history"]) {
        [self refreshHistoryClustersWithAI];
        return YES;
    }

    if ([host isEqualToString:@"clear-downloads"]) {
        [self clearDownloadHistory];
        if (self.webView) [self loadNativeSettingsPageInWebView:self.webView];
        return YES;
    }

    if ([host isEqualToString:@"clear-website-data"]) {
        [self clearWebsiteDataReloadSettings:YES];
        return YES;
    }

    if ([host isEqualToString:@"clear-all-browsing-data"]) {
        [self clearAllBrowsingData];
        return YES;
    }

    if ([host isEqualToString:@"set-permission"]) {
        NSString *origin = [self queryValueNamed:@"origin" inURL:url];
        NSString *kind = [self queryValueNamed:@"kind" inURL:url];
        NSString *value = [self queryValueNamed:@"value" inURL:url];
        [self setSitePermissionValue:value forOriginString:origin kind:kind];
        if (self.webView) [self loadNativeSettingsPageInWebView:self.webView];
        return YES;
    }

    if ([host isEqualToString:@"clear-permissions"]) {
        [self clearSitePermissions];
        if (self.webView) [self loadNativeSettingsPageInWebView:self.webView];
        return YES;
    }

    if ([host isEqualToString:@"reveal-download"]) {
        NSString *path = [self queryValueNamed:@"path" inURL:url];
        [self revealDownloadAtPath:path];
        return YES;
    }

    if ([host isEqualToString:@"cancel-download"]) {
        NSString *downloadID = [self queryValueNamed:@"id" inURL:url];
        [self cancelDownloadWithID:downloadID];
        return YES;
    }

    if ([host isEqualToString:@"resume-download"]) {
        NSString *downloadID = [self queryValueNamed:@"id" inURL:url];
        [self resumeDownloadWithID:downloadID];
        return YES;
    }

    if ([host isEqualToString:@"import-bookmarks"]) {
        [self importBookmarksFromHTML:nil];
        return YES;
    }

    if ([host isEqualToString:@"export-bookmarks"]) {
        [self exportBookmarksToHTML:nil];
        return YES;
    }

    if ([host isEqualToString:@"remove-bookmark"]) {
        NSString *urlString = [self queryValueNamed:@"url" inURL:url];
        [self removeBookmarkForURLString:urlString];
        if (self.webView) [self loadNativeSettingsPageInWebView:self.webView];
        return YES;
    }

    if ([host isEqualToString:@"update-bookmark"]) {
        NSString *oldURL = [self queryValueNamed:@"url" inURL:url];
        NSString *title = [self queryValueNamed:@"title" inURL:url];
        NSString *newURL = [self queryValueNamed:@"newUrl" inURL:url];
        [self updateBookmarkForURLString:oldURL title:title newURLString:newURL];
        if (self.webView) [self loadNativeSettingsPageInWebView:self.webView];
        return YES;
    }

    if ([host isEqualToString:@"move-bookmark"]) {
        NSString *urlString = [self queryValueNamed:@"url" inURL:url];
        NSString *beforeURLString = [self queryValueNamed:@"before" inURL:url];
        [self moveBookmarkURLString:urlString beforeURLString:beforeURLString];
        if (self.webView) [self loadNativeSettingsPageInWebView:self.webView];
        return YES;
    }

    if ([host isEqualToString:@"set-pref"]) {
        NSString *key = [self queryValueNamed:@"key" inURL:url];
        NSString *value = [self queryValueNamed:@"value" inURL:url];
        if ([key isEqualToString:@"bookmarkBar"]) {
            NSString *normalized = value.lowercaseString ?: @"";
            BOOL visible = [normalized isEqualToString:@"1"] ||
                           [normalized isEqualToString:@"true"] ||
                           [normalized isEqualToString:@"yes"];
            [self setBookmarkBarVisible:visible persist:YES];
            return YES;
        }
        if ([key isEqualToString:@"themeMode"]) {
            [self setThemeModeName:value persist:YES];
            return YES;
        }
        if ([key isEqualToString:@"keepTabsLoaded"]) {
            NSString *normalized = value.lowercaseString ?: @"";
            BOOL keepTabsLoaded = [normalized isEqualToString:@"1"] ||
                                  [normalized isEqualToString:@"true"] ||
                                  [normalized isEqualToString:@"yes"];
            [self setKeepTabsLoaded:keepTabsLoaded];
            return YES;
        }
        NSDictionary<NSString *, NSString *> *allowed = @{ @"aiEngine": @"TBAIEngine",
                                                           @"codexModel": @"TBCodexModel",
                                                           @"claudeModel": @"TBClaudeModel",
                                                           @"codexEffort": @"TBCodexEffort" };
        NSString *defaultsKey = allowed[key];
        if (defaultsKey) {
            if ([key isEqualToString:@"codexEffort"] && [value isEqualToString:@"minimal"]) {
                value = @"low";
            }
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
    NSString *effort = [defaults stringForKey:@"TBCodexEffort"] ?: @"low";
    if ([effort isEqualToString:@"minimal"]) effort = @"low";
    NSString *bookmarkBar = self.bookmarkBarVisible ? @"true" : @"false";
    NSString *keepTabsLoaded = [self keepTabsLoaded] ? @"true" : @"false";
    NSString *themeMode = TBThemeModeName(TBThemeCurrentMode());
    return [NSString stringWithFormat:
        @"<script>document.documentElement.dataset.theme=\"%@\";"
         "window.__tbThemeMode=\"%@\";window.__tbEngine=\"%@\";window.__tbCodexModel=\"%@\";"
         "window.__tbClaudeModel=\"%@\";window.__tbEffort=\"%@\";"
         "window.__tbBookmarkBarVisible=%@;window.__tbKeepTabsLoaded=%@;</script></head>",
        themeMode, themeMode, engine, codexModel, claudeModel, effort, bookmarkBar, keepTabsLoaded];
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
    html = [html stringByReplacingOccurrencesOfString:@"</head>" withString:[self settingsHistoryScript]];
    html = [html stringByReplacingOccurrencesOfString:@"</head>" withString:[self settingsHistoryClustersScript]];
    html = [html stringByReplacingOccurrencesOfString:@"</head>" withString:[self settingsBookmarksScript]];
    html = [html stringByReplacingOccurrencesOfString:@"</head>" withString:[self settingsDownloadsScript]];
    html = [html stringByReplacingOccurrencesOfString:@"</head>" withString:[self settingsPermissionsScript]];
    html = [html stringByReplacingOccurrencesOfString:@"</head>" withString:[self settingsPasskeysScript]];

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
    NSString *html = [[self nativeResourceHTMLNamed:@"Onboarding"]
                      stringByReplacingOccurrencesOfString:@"</head>"
                                                withString:[self aiPrefsScript]];
    [webView loadHTMLString:html
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

- (NSString *)searchHistoryFilePath {
    return [[self supportDirectoryPath] stringByAppendingPathComponent:@"searches.jsonl"];
}

- (NSString *)historyClustersFilePath {
    return [[self supportDirectoryPath] stringByAppendingPathComponent:@"history-clusters.json"];
}

- (NSString *)bookmarksFilePath {
    return [[self supportDirectoryPath] stringByAppendingPathComponent:@"bookmarks.json"];
}

- (NSString *)downloadsFilePath {
    return [[self supportDirectoryPath] stringByAppendingPathComponent:@"downloads.jsonl"];
}

- (NSString *)downloadResumeDataDirectoryPath {
    return [[self supportDirectoryPath] stringByAppendingPathComponent:@"download-resume-data"];
}

- (NSString *)permissionsFilePath {
    return [[self supportDirectoryPath] stringByAppendingPathComponent:@"permissions.json"];
}

- (NSString *)stateFilePath {
    return [[self supportDirectoryPath] stringByAppendingPathComponent:@"state.json"];
}

- (NSArray<NSDictionary<NSString *, id> *> *)JSONLinesAtPath:(NSString *)path newestFirst:(BOOL)newestFirst {
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data.length) return @[];

    NSString *content = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (content.length == 0) return @[];

    NSArray<NSString *> *lines = [content componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet];
    NSMutableArray<NSDictionary<NSString *, id> *> *entries = [NSMutableArray array];
    NSEnumerator<NSString *> *enumerator = newestFirst ? lines.reverseObjectEnumerator : lines.objectEnumerator;

    for (NSString *line in enumerator) {
        if (line.length == 0) continue;
        NSData *lineData = [line dataUsingEncoding:NSUTF8StringEncoding];
        if (!lineData) continue;
        id json = [NSJSONSerialization JSONObjectWithData:lineData options:0 error:nil];
        if ([json isKindOfClass:NSDictionary.class]) [entries addObject:json];
    }

    return entries;
}

- (BOOL)isSearchURL:(NSURL *)url {
    NSString *host = url.host.lowercaseString ?: @"";
    return ([host isEqualToString:@"www.google.com"] || [host isEqualToString:@"google.com"]) &&
           [url.path isEqualToString:@"/search"];
}

- (void)recordSearchInputIfNeeded:(NSString *)input resolvedURL:(NSURL *)url {
    NSString *trimmed = [input stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmed.length == 0 || ![self isSearchURL:url]) return;
    if ([trimmed hasPrefix:@"http://"] || [trimmed hasPrefix:@"https://"] || [trimmed containsString:@"://"]) return;
    if ([self inputLooksLikeHostOrLocalAddress:trimmed]) return;

    NSDictionary<NSString *, id> *entry = @{
        @"timestamp": [[self historyDateFormatter] stringFromDate:[NSDate date]],
        @"query": trimmed,
        @"url": url.absoluteString ?: @"",
        @"source": @"TrailBrowser"
    };
    [self appendJSONLine:entry toPath:[self searchHistoryFilePath]];
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
    BrowserTab *tab = [self tabForWebView:webView];
    if (tab.privateBrowsing) return;

    NSString *urlString = [self redactedURLStringForURL:url];
    if (urlString.length == 0) return;

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

- (NSDictionary<NSString *, id> *)browserStateDictionary {
    NSData *data = [NSData dataWithContentsOfFile:[self stateFilePath]];
    if (!data.length) return @{};

    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    return [json isKindOfClass:NSDictionary.class] ? json : @{};
}

- (NSArray<NSDictionary<NSString *, id> *> *)stateTabEntries {
    NSMutableArray<NSDictionary<NSString *, id> *> *entries = [NSMutableArray array];
    for (BrowserTab *tab in self.tabs) {
        if (tab.privateBrowsing) continue;
        NSString *urlString = tab.webView.URL.absoluteString ?: tab.urlString ?: @"";
        if (urlString.length == 0) continue;
        if ([urlString hasPrefix:@"view-source:"]) continue;
        NSString *title = tab.webView.title.length ? tab.webView.title : (tab.title ?: @"");
        [entries addObject:@{
            @"url": urlString,
            @"title": title ?: @"",
            @"lastActiveSeq": @(tab.lastActiveSeq),
            @"pinned": @(tab.pinned)
        }];
    }
    return entries;
}

- (NSArray<NSDictionary<NSString *, id> *> *)sanitizedRecentlyClosedTabsFromStateValue:(id)value {
    NSArray *items = [value isKindOfClass:NSArray.class] ? value : @[];
    NSMutableArray<NSDictionary<NSString *, id> *> *entries = [NSMutableArray array];

    for (id item in items) {
        if (![item isKindOfClass:NSDictionary.class]) continue;
        NSDictionary<NSString *, id> *entry = item;
        NSString *urlString = [entry[@"url"] isKindOfClass:NSString.class] ? entry[@"url"] : @"";
        if (urlString.length == 0 || [urlString hasPrefix:@"view-source:"]) continue;
        NSString *title = [entry[@"title"] isKindOfClass:NSString.class] ? entry[@"title"] : @"";
        NSString *closedAt = [entry[@"closedAt"] isKindOfClass:NSString.class] ? entry[@"closedAt"] : @"";
        BOOL pinned = [entry[@"pinned"] isKindOfClass:NSNumber.class] ? [entry[@"pinned"] boolValue] : NO;
        [entries addObject:@{
            @"url": urlString,
            @"title": title ?: @"",
            @"closedAt": closedAt ?: @"",
            @"pinned": @(pinned)
        }];
    }

    if ((NSInteger)entries.count > kMaxRecentlyClosedTabs) {
        NSRange range = NSMakeRange(entries.count - kMaxRecentlyClosedTabs, kMaxRecentlyClosedTabs);
        return [entries subarrayWithRange:range];
    }
    return entries;
}

- (NSArray<NSDictionary<NSString *, id> *> *)stateRecentlyClosedTabEntries {
    return self.recentlyClosedTabs ? [self.recentlyClosedTabs copy] : @[];
}

- (NSInteger)stateActiveTabIndex {
    NSInteger stateIndex = 0;
    for (NSInteger i = 0; i < (NSInteger)self.tabs.count; i++) {
        BrowserTab *tab = self.tabs[(NSUInteger)i];
        if (tab.privateBrowsing) continue;
        if (i == self.activeTabIndex) return stateIndex;
        stateIndex += 1;
    }
    return 0;
}

- (BOOL)windowFrameLooksUsable:(NSRect)frame {
    if (NSWidth(frame) < 480.0 || NSHeight(frame) < 320.0) return NO;
    for (NSScreen *screen in NSScreen.screens) {
        if (NSIntersectsRect(frame, screen.visibleFrame)) return YES;
    }
    return NO;
}

- (void)restoreWindowStateFromDictionary:(NSDictionary<NSString *, id> *)state {
    id frameValue = state[@"windowFrame"];
    if ([frameValue isKindOfClass:NSString.class]) {
        NSRect frame = NSRectFromString(frameValue);
        if ([self windowFrameLooksUsable:frame]) {
            [self.window setFrame:frame display:YES];
        }
    }

    id sidebarValue = state[@"sidebarVisible"];
    if ([sidebarValue isKindOfClass:NSNumber.class]) {
        BOOL visible = [sidebarValue boolValue];
        if (visible != self.sidebarVisible) {
            self.sidebarVisible = visible;
            self.sidebar.hidden = !visible;
            self.sidebarSeparator.hidden = !visible;
            self.sidebarWidthConstraint.constant = visible ? 240.0 : 0.0;
            ((TBFlatButton *)self.sidebarToggleButton).active = visible;
            [self.window.contentView layoutSubtreeIfNeeded];
        }
    }

    id bookmarkBarValue = state[@"bookmarkBarVisible"];
    if ([bookmarkBarValue isKindOfClass:NSNumber.class]) {
        BOOL visible = [bookmarkBarValue boolValue];
        if ([self bookmarkEntries].count == 0) {
            visible = NO;
        }
        if (![self bookmarkBarVisibilityUserConfigured] && [self bookmarkEntries].count > 0) {
            visible = YES;
        }
        if (visible != self.bookmarkBarVisible) {
            self.bookmarkBarVisible = visible;
            if ([self bookmarkBarVisibilityUserConfigured]) {
                [[NSUserDefaults standardUserDefaults] setBool:visible forKey:TBBookmarkBarVisibleKey];
            }
            self.bookmarkBar.hidden = !visible;
            self.bookmarkBarHeightConstraint.constant = visible ? 34.0 : 0.0;
            [self.window.contentView layoutSubtreeIfNeeded];
        }
    }

    [self restoreRecentlyClosedTabsFromDictionary:state];
}

- (void)restoreRecentlyClosedTabsFromDictionary:(NSDictionary<NSString *, id> *)state {
    NSArray<NSDictionary<NSString *, id> *> *entries = [self sanitizedRecentlyClosedTabsFromStateValue:state[@"recentlyClosedTabs"]];
    self.recentlyClosedTabs = [entries mutableCopy];
}

- (BOOL)restorePreviousSessionIfAvailable {
    NSDictionary<NSString *, id> *state = [self browserStateDictionary];
    NSArray *tabs = [state[@"tabs"] isKindOfClass:NSArray.class] ? state[@"tabs"] : @[];
    if (tabs.count == 0) return NO;

    [self restoreWindowStateFromDictionary:state];

    NSInteger activeIndex = [state[@"activeTabIndex"] isKindOfClass:NSNumber.class]
        ? [state[@"activeTabIndex"] integerValue]
        : 0;
    if (activeIndex < 0 || activeIndex >= (NSInteger)tabs.count) activeIndex = 0;

    self.restoringSession = YES;
    for (NSUInteger i = 0; i < tabs.count; i++) {
        id item = tabs[i];
        if (![item isKindOfClass:NSDictionary.class]) continue;
        NSDictionary<NSString *, id> *entry = item;
        NSString *urlString = [entry[@"url"] isKindOfClass:NSString.class] ? entry[@"url"] : @"";
        if (urlString.length == 0) continue;
        BrowserTab *tab = [self newTabWithURLString:urlString select:((NSInteger)i == activeIndex)];
        NSString *title = [entry[@"title"] isKindOfClass:NSString.class] ? entry[@"title"] : @"";
        if (title.length > 0) tab.title = title;
        if ([entry[@"pinned"] isKindOfClass:NSNumber.class]) tab.pinned = [entry[@"pinned"] boolValue];
    }
    self.restoringSession = NO;

    if (self.tabs.count == 0) return NO;
    if (self.activeTabIndex < 0) [self selectTabAtIndex:0];
    [self.tabTable reloadData];
    return YES;
}

- (void)writeBrowserStateRunning:(BOOL)running {
    NSDictionary<NSString *, id> *state = @{
        @"running": @(running),
        @"updatedAt": [[self historyDateFormatter] stringFromDate:[NSDate date]],
        @"historyFile": [self historyFilePath],
        @"searchHistoryFile": [self searchHistoryFilePath],
        @"historyClustersFile": [self historyClustersFilePath],
        @"bookmarksFile": [self bookmarksFilePath],
        @"downloadsFile": [self downloadsFilePath],
        @"downloadResumeDataDirectory": [self downloadResumeDataDirectoryPath],
        @"permissionsFile": [self permissionsFilePath],
        @"tabs": [self stateTabEntries],
        @"recentlyClosedTabs": [self stateRecentlyClosedTabEntries],
        @"activeTabIndex": @([self stateActiveTabIndex]),
        @"sidebarVisible": @(self.sidebarVisible),
        @"bookmarkBarVisible": @(self.bookmarkBarVisible),
        @"keepTabsLoaded": @([self keepTabsLoaded]),
        @"windowFrame": self.window ? NSStringFromRect(self.window.frame) : @"",
        @"cookiesExposed": @NO
    };

    NSError *error = nil;
    NSData *json = [NSJSONSerialization dataWithJSONObject:state
                                                   options:NSJSONWritingPrettyPrinted
                                                     error:&error];
    if (!json) return;
    [json writeToFile:[self stateFilePath] options:NSDataWritingAtomic error:nil];
}

- (NSArray<NSDictionary<NSString *, id> *> *)settingsHistoryEntries {
    NSArray<NSDictionary<NSString *, id> *> *history = [self JSONLinesAtPath:[self historyFilePath] newestFirst:YES];
    NSMutableArray<NSDictionary<NSString *, id> *> *entries = [NSMutableArray arrayWithCapacity:history.count];

    for (NSDictionary<NSString *, id> *entry in history) {
        NSString *url = [entry[@"url"] isKindOfClass:NSString.class] ? entry[@"url"] : @"";
        if (url.length == 0) continue;
        [entries addObject:@{
            @"timestamp": [entry[@"timestamp"] isKindOfClass:NSString.class] ? entry[@"timestamp"] : @"",
            @"title": [entry[@"title"] isKindOfClass:NSString.class] ? entry[@"title"] : @"",
            @"url": url,
            @"host": [entry[@"host"] isKindOfClass:NSString.class] ? entry[@"host"] : @""
        }];
    }
    return entries;
}

- (NSString *)settingsHistoryScript {
    NSArray<NSDictionary<NSString *, id> *> *history = [self settingsHistoryEntries];
    NSData *json = [NSJSONSerialization dataWithJSONObject:history options:0 error:nil];
    NSString *jsonString = json ? [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding] : @"[]";
    return [NSString stringWithFormat:@"<script>window.__tbHistory=%@;</script></head>", jsonString ?: @"[]"];
}

- (NSDictionary<NSString *, id> *)cachedHistoryClusters {
    NSData *data = [NSData dataWithContentsOfFile:[self historyClustersFilePath]];
    if (!data.length) return @{};

    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    return [json isKindOfClass:NSDictionary.class] ? json : @{};
}

- (NSString *)settingsHistoryClustersScript {
    NSDictionary<NSString *, id> *clusters = [self cachedHistoryClusters];
    NSData *json = [NSJSONSerialization dataWithJSONObject:clusters.count ? clusters : @{}
                                                   options:0
                                                     error:nil];
    NSString *jsonString = json ? [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding] : @"{}";
    return [NSString stringWithFormat:@"<script>window.__tbHistoryClusters=%@;</script></head>", jsonString ?: @"{}"];
}

- (void)clearBrowsingHistory {
    [[NSFileManager defaultManager] removeItemAtPath:[self historyFilePath] error:NULL];
    [[NSFileManager defaultManager] removeItemAtPath:[self searchHistoryFilePath] error:NULL];
    [[NSFileManager defaultManager] removeItemAtPath:[self historyClustersFilePath] error:NULL];
    for (BrowserTab *tab in self.tabs) tab.lastRecordedURL = nil;
    self.lastRecordedURL = nil;
    [self writeBrowserStateRunning:YES];
}

- (NSArray<NSDictionary<NSString *, id> *> *)historyEntriesForAIClustering {
    NSArray<NSDictionary<NSString *, id> *> *history = [self settingsHistoryEntries];
    NSUInteger limit = MIN(history.count, 120);
    NSMutableArray<NSDictionary<NSString *, id> *> *entries = [NSMutableArray arrayWithCapacity:limit];
    for (NSUInteger i = 0; i < limit; i++) {
        NSDictionary<NSString *, id> *entry = history[i];
        NSString *url = [entry[@"url"] isKindOfClass:NSString.class] ? entry[@"url"] : @"";
        if (url.length == 0) continue;
        [entries addObject:@{
            @"title": [entry[@"title"] isKindOfClass:NSString.class] ? entry[@"title"] : @"",
            @"url": url,
            @"host": [entry[@"host"] isKindOfClass:NSString.class] ? entry[@"host"] : @"",
            @"timestamp": [entry[@"timestamp"] isKindOfClass:NSString.class] ? entry[@"timestamp"] : @""
        }];
    }
    return entries;
}

- (id)JSONObjectFromAIOutput:(NSString *)output {
    NSString *trimmed = [output stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSRegularExpression *fence =
        [NSRegularExpression regularExpressionWithPattern:@"```(?:json)?\\s*(.*?)```"
                                                  options:NSRegularExpressionCaseInsensitive | NSRegularExpressionDotMatchesLineSeparators
                                                    error:nil];
    NSTextCheckingResult *match = [fence firstMatchInString:trimmed options:0 range:NSMakeRange(0, trimmed.length)];
    if (match && match.numberOfRanges > 1) {
        trimmed = [[trimmed substringWithRange:[match rangeAtIndex:1]]
                   stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    }
    NSData *data = [trimmed dataUsingEncoding:NSUTF8StringEncoding];
    return data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
}

- (NSArray<NSDictionary<NSString *, id> *> *)sanitizedHistoryClustersFromJSON:(id)json
                                                                       entries:(NSArray<NSDictionary<NSString *, id> *> *)entries {
    NSDictionary *root = [json isKindOfClass:NSDictionary.class] ? json : nil;
    NSArray *clusters = [root[@"clusters"] isKindOfClass:NSArray.class] ? root[@"clusters"] : nil;
    if (clusters.count == 0) return @[];

    NSMutableSet<NSString *> *knownURLs = [NSMutableSet set];
    for (NSDictionary<NSString *, id> *entry in entries) {
        NSString *url = [entry[@"url"] isKindOfClass:NSString.class] ? entry[@"url"] : @"";
        if (url.length > 0) [knownURLs addObject:url];
    }

    NSMutableArray<NSDictionary<NSString *, id> *> *clean = [NSMutableArray array];
    for (id item in clusters) {
        if (![item isKindOfClass:NSDictionary.class]) continue;
        NSDictionary *cluster = item;
        NSString *label = [cluster[@"label"] isKindOfClass:NSString.class] ? cluster[@"label"] : @"";
        NSString *reason = [cluster[@"reason"] isKindOfClass:NSString.class] ? cluster[@"reason"] : @"";
        NSArray *urls = [cluster[@"urls"] isKindOfClass:NSArray.class] ? cluster[@"urls"] : @[];
        if (label.length == 0 || urls.count == 0) continue;

        NSMutableArray<NSString *> *cleanURLs = [NSMutableArray array];
        for (id rawURL in urls) {
            if (![rawURL isKindOfClass:NSString.class]) continue;
            if (![knownURLs containsObject:rawURL]) continue;
            if (![cleanURLs containsObject:rawURL]) [cleanURLs addObject:rawURL];
        }
        if (cleanURLs.count == 0) continue;
        [clean addObject:@{
            @"label": label,
            @"reason": reason.length ? reason : @"AI grouped these pages by topic and intent.",
            @"urls": cleanURLs
        }];
        if (clean.count >= 8) break;
    }
    return clean;
}

- (void)writeHistoryClusters:(NSArray<NSDictionary<NSString *, id> *> *)clusters source:(NSString *)source {
    NSDictionary<NSString *, id> *payload = @{
        @"updatedAt": [[self historyDateFormatter] stringFromDate:[NSDate date]],
        @"source": source ?: @"ai",
        @"historyCount": @([self settingsHistoryEntries].count),
        @"clusters": clusters ?: @[]
    };
    if (![NSJSONSerialization isValidJSONObject:payload]) return;
    NSData *data = [NSJSONSerialization dataWithJSONObject:payload
                                                   options:NSJSONWritingPrettyPrinted
                                                     error:nil];
    if (!data) return;
    [data writeToFile:[self historyClustersFilePath] options:NSDataWritingAtomic error:nil];
}

- (void)refreshHistoryClustersWithAI {
    NSArray<NSDictionary<NSString *, id> *> *entries = [self historyEntriesForAIClustering];
    if (entries.count == 0) {
        [self setStatusText:@"No history to cluster"];
        NSBeep();
        return;
    }

    NSData *json = [NSJSONSerialization dataWithJSONObject:entries options:0 error:nil];
    NSString *historyJSON = json ? [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding] : @"[]";
    NSString *prompt = [NSString stringWithFormat:
        @"You are TrailBrowser's history clustering engine.\n"
         "Group browsing history into 4 to 8 useful clusters for a browser History UI.\n"
         "Return strict JSON only, no markdown, matching this shape:\n"
         "{\"clusters\":[{\"label\":\"short topic\",\"reason\":\"one short human sentence\",\"urls\":[\"exact URL from input\"]}]}\n"
         "Rules:\n"
         "- Use only URLs from the input, copied exactly.\n"
         "- Prefer intent/topic clusters over raw domains when possible.\n"
         "- Put each URL in at most one cluster.\n"
         "- Keep labels under 28 characters.\n"
         "- Ignore duplicate or trivial internal pages unless they help a cluster.\n\n"
         "History JSON:\n%@",
        historyJSON ?: @"[]"];

    [self setStatusText:@"Clustering history"];
    [self runAIWithPrompt:prompt enableSearch:NO effortOverride:@"low" completion:^(NSString *output, NSError *error) {
        if (error) {
            [self setStatusText:error.localizedDescription ?: @"History clustering failed"];
            return;
        }
        id parsed = [self JSONObjectFromAIOutput:output];
        NSArray<NSDictionary<NSString *, id> *> *clusters = [self sanitizedHistoryClustersFromJSON:parsed entries:entries];
        if (clusters.count == 0) {
            [self setStatusText:@"History clustering returned no groups"];
            return;
        }
        [self writeHistoryClusters:clusters source:@"ai"];
        [self setStatusText:@"History clusters updated"];
        if (self.webView && [self isSettingsURLString:self.webView.URL.absoluteString]) {
            [self loadNativeSettingsPageInWebView:self.webView];
        }
        [self writeBrowserStateRunning:YES];
    }];
}

- (void)clearWebsiteDataReloadSettings:(BOOL)reloadSettings {
    [self setStatusText:@"Clearing website data…"];
    NSSet<NSString *> *types = [WKWebsiteDataStore allWebsiteDataTypes];
    NSDate *date = [NSDate dateWithTimeIntervalSince1970:0];
    [[WKWebsiteDataStore defaultDataStore] removeDataOfTypes:types
                                               modifiedSince:date
                                           completionHandler:^{
        dispatch_async(dispatch_get_main_queue(), ^{
            [self setStatusText:@"Website data cleared"];
            if (reloadSettings && self.webView) [self loadNativeSettingsPageInWebView:self.webView];
        });
    }];
}

- (void)clearAllBrowsingData {
    [self clearBrowsingHistory];
    [self clearDownloadHistory];
    [self clearSitePermissions];
    [self clearWebsiteDataReloadSettings:YES];
}

#pragma mark - Passkeys

- (nullable id)passkeyManager {
    if (@available(macOS 13.3, *)) {
        if (!self.passkeyCredentialManager) {
            self.passkeyCredentialManager = [[ASAuthorizationWebBrowserPublicKeyCredentialManager alloc] init];
        }
        return self.passkeyCredentialManager;
    }
    return nil;
}

- (BOOL)hasBrowserPasskeyEntitlement {
    SecTaskRef task = SecTaskCreateFromSelf(kCFAllocatorDefault);
    if (!task) return NO;

    CFTypeRef value = SecTaskCopyValueForEntitlement(task,
                                                     CFSTR("com.apple.developer.web-browser.public-key-credential"),
                                                     NULL);
    CFRelease(task);
    BOOL entitled = value && CFGetTypeID(value) == CFBooleanGetTypeID() && CFBooleanGetValue((CFBooleanRef)value);
    if (value) CFRelease(value);
    return entitled;
}

- (NSDictionary<NSString *, id> *)passkeyStatusDictionary {
    if (@available(macOS 13.3, *)) {
        if (![self hasBrowserPasskeyEntitlement]) {
            return @{
                @"supported": @YES,
                @"state": @"needsEntitlement",
                @"label": @"Needs signed build",
                @"message": @"This build is not signed with Apple's browser passkey entitlement. Passkeys require an approved browser build.",
                @"canRequest": @NO,
                @"requestInProgress": @NO
            };
        }

        ASAuthorizationWebBrowserPublicKeyCredentialManager *manager =
            (ASAuthorizationWebBrowserPublicKeyCredentialManager *)[self passkeyManager];
        ASAuthorizationWebBrowserPublicKeyCredentialManagerAuthorizationState state =
            manager.authorizationStateForPlatformCredentials;

        NSString *stateKey = @"notDetermined";
        NSString *label = @"Not allowed yet";
        NSString *message = @"Allow TrailBrowser to use passkeys stored in iCloud Keychain and credential manager apps.";
        BOOL canRequest = YES;

        if (state == ASAuthorizationWebBrowserPublicKeyCredentialManagerAuthorizationStateAuthorized) {
            stateKey = @"authorized";
            label = @"Allowed";
            message = @"WebKit can ask for your fingerprint, face, or screen lock when a website requests a passkey.";
            canRequest = NO;
        } else if (state == ASAuthorizationWebBrowserPublicKeyCredentialManagerAuthorizationStateDenied) {
            stateKey = @"denied";
            label = @"Blocked";
            message = @"Allow TrailBrowser in System Settings > Privacy & Security > Passkeys Access for Web Browsers.";
            canRequest = YES;
        }

        return @{
            @"supported": @YES,
            @"state": stateKey,
            @"label": label,
            @"message": message,
            @"canRequest": @(canRequest && !self.passkeyAccessRequestInProgress),
            @"requestInProgress": @(self.passkeyAccessRequestInProgress)
        };
    }

    return @{
        @"supported": @NO,
        @"state": @"unsupported",
        @"label": @"Unsupported",
        @"message": @"Passkeys in browser apps require macOS 13.3 or later.",
        @"canRequest": @NO,
        @"requestInProgress": @NO
    };
}

- (NSString *)settingsPasskeysScript {
    NSDictionary<NSString *, id> *status = [self passkeyStatusDictionary];
    NSData *json = [NSJSONSerialization dataWithJSONObject:status options:0 error:nil];
    NSString *jsonString = json ? [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding] : @"{}";
    return [NSString stringWithFormat:@"<script>window.__tbPasskeys=%@;</script></head>", jsonString ?: @"{}"];
}

- (void)requestPasskeyAccessAtLaunchIfNeeded {
    if (@available(macOS 13.3, *)) {
        if (![self hasBrowserPasskeyEntitlement]) return;
        if ([[NSUserDefaults standardUserDefaults] boolForKey:TBPasskeyAccessPromptedKey]) return;
        ASAuthorizationWebBrowserPublicKeyCredentialManager *manager =
            (ASAuthorizationWebBrowserPublicKeyCredentialManager *)[self passkeyManager];
        if (manager.authorizationStateForPlatformCredentials !=
            ASAuthorizationWebBrowserPublicKeyCredentialManagerAuthorizationStateNotDetermined) {
            return;
        }

        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:TBPasskeyAccessPromptedKey];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self requestPasskeyAccessReloadSettings:NO];
        });
    }
}

- (void)requestPasskeyAccessFromSettings {
    [self requestPasskeyAccessReloadSettings:YES];
}

- (void)requestPasskeyAccessReloadSettings:(BOOL)reloadSettings {
    if (@available(macOS 13.3, *)) {
        if (![self hasBrowserPasskeyEntitlement]) {
            [self setStatusText:@"Passkeys need an entitled browser build"];
            if (reloadSettings) [self reloadSettingsIfVisible];
            NSBeep();
            return;
        }
        if (self.passkeyAccessRequestInProgress) return;

        ASAuthorizationWebBrowserPublicKeyCredentialManager *manager =
            (ASAuthorizationWebBrowserPublicKeyCredentialManager *)[self passkeyManager];
        ASAuthorizationWebBrowserPublicKeyCredentialManagerAuthorizationState state =
            manager.authorizationStateForPlatformCredentials;
        if (state == ASAuthorizationWebBrowserPublicKeyCredentialManagerAuthorizationStateAuthorized) {
            [self setStatusText:@"Passkeys allowed"];
            if (reloadSettings) [self reloadSettingsIfVisible];
            return;
        }

        self.passkeyAccessRequestInProgress = YES;
        if (reloadSettings) [self reloadSettingsIfVisible];
        [self setStatusText:@"Requesting passkey access"];

        [manager requestAuthorizationForPublicKeyCredentials:
         ^(ASAuthorizationWebBrowserPublicKeyCredentialManagerAuthorizationState authorizationState) {
            dispatch_async(dispatch_get_main_queue(), ^{
                self.passkeyAccessRequestInProgress = NO;
                if (authorizationState == ASAuthorizationWebBrowserPublicKeyCredentialManagerAuthorizationStateAuthorized) {
                    [self setStatusText:@"Passkeys allowed"];
                } else if (authorizationState == ASAuthorizationWebBrowserPublicKeyCredentialManagerAuthorizationStateDenied) {
                    [self setStatusText:@"Passkeys blocked in System Settings"];
                } else {
                    [self setStatusText:@"Passkey access not set"];
                }
                if (reloadSettings) [self reloadSettingsIfVisible];
            });
        }];
    } else {
        [self setStatusText:@"Passkeys require macOS 13.3+"];
        NSBeep();
    }
}

#pragma mark - Site permissions

- (NSArray<NSString *> *)sitePermissionKinds {
    return @[ TBSitePermissionCamera, TBSitePermissionMicrophone ];
}

- (BOOL)isSupportedSitePermissionKind:(NSString *)kind {
    return [[self sitePermissionKinds] containsObject:kind ?: @""];
}

- (BOOL)isExplicitSitePermissionValue:(NSString *)value {
    return [value isEqualToString:TBSitePermissionAllow] ||
           [value isEqualToString:TBSitePermissionDeny];
}

- (BOOL)isSupportedSitePermissionValue:(NSString *)value {
    return [value isEqualToString:TBSitePermissionAsk] ||
           [self isExplicitSitePermissionValue:value];
}

- (NSString *)normalizedOriginStringWithScheme:(NSString *)scheme
                                          host:(NSString *)host
                                          port:(NSInteger)port {
    NSString *lowerScheme = scheme.lowercaseString ?: @"";
    NSString *lowerHost = host.lowercaseString ?: @"";
    if ((! [lowerScheme isEqualToString:@"http"] && ![lowerScheme isEqualToString:@"https"]) ||
        lowerHost.length == 0) {
        return nil;
    }

    NSURLComponents *components = [[NSURLComponents alloc] init];
    components.scheme = lowerScheme;
    components.host = lowerHost;
    BOOL defaultPort = ([lowerScheme isEqualToString:@"http"] && port == 80) ||
                       ([lowerScheme isEqualToString:@"https"] && port == 443);
    if (port > 0 && !defaultPort) components.port = @(port);
    return components.URL.absoluteString;
}

- (NSString *)normalizedOriginStringFromString:(NSString *)originString {
    if (originString.length == 0) return nil;
    NSURLComponents *components = [NSURLComponents componentsWithString:originString];
    return [self normalizedOriginStringWithScheme:components.scheme
                                             host:components.host
                                             port:components.port.integerValue];
}

- (NSString *)originStringForURL:(NSURL *)url {
    if (!url) return nil;
    NSURLComponents *components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    return [self normalizedOriginStringWithScheme:components.scheme
                                             host:components.host
                                             port:components.port.integerValue];
}

- (NSString *)originStringForSecurityOrigin:(WKSecurityOrigin *)origin {
    if (!origin) return nil;
    return [self normalizedOriginStringWithScheme:origin.protocol
                                             host:origin.host
                                             port:origin.port];
}

- (NSDictionary<NSString *, NSDictionary<NSString *, NSString *> *> *)sitePermissionsByOrigin {
    NSData *data = [NSData dataWithContentsOfFile:[self permissionsFilePath]];
    if (!data.length) return @{};

    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![json isKindOfClass:NSDictionary.class]) return @{};

    NSDictionary *rawPermissions = (NSDictionary *)json;
    NSMutableDictionary<NSString *, NSDictionary<NSString *, NSString *> *> *clean = [NSMutableDictionary dictionary];
    for (id rawOrigin in rawPermissions) {
        if (![rawOrigin isKindOfClass:NSString.class]) continue;
        NSString *origin = [self normalizedOriginStringFromString:(NSString *)rawOrigin];
        if (origin.length == 0) continue;

        id rawEntry = rawPermissions[rawOrigin];
        if (![rawEntry isKindOfClass:NSDictionary.class]) continue;

        NSMutableDictionary<NSString *, NSString *> *entry = [NSMutableDictionary dictionary];
        NSDictionary *rawEntryDictionary = (NSDictionary *)rawEntry;
        for (NSString *kind in [self sitePermissionKinds]) {
            NSString *value = [rawEntryDictionary[kind] isKindOfClass:NSString.class] ? rawEntryDictionary[kind] : nil;
            if ([self isExplicitSitePermissionValue:value]) entry[kind] = value;
        }
        NSString *updatedAt = [rawEntryDictionary[@"updatedAt"] isKindOfClass:NSString.class] ? rawEntryDictionary[@"updatedAt"] : nil;
        if (updatedAt.length > 0 && entry.count > 0) entry[@"updatedAt"] = updatedAt;
        if (entry.count > 0) clean[origin] = entry;
    }
    return clean;
}

- (void)writeSitePermissionsByOrigin:(NSDictionary<NSString *, NSDictionary<NSString *, NSString *> *> *)permissions {
    if (permissions.count == 0) {
        [[NSFileManager defaultManager] removeItemAtPath:[self permissionsFilePath] error:NULL];
        return;
    }

    if (![NSJSONSerialization isValidJSONObject:permissions]) return;
    NSData *data = [NSJSONSerialization dataWithJSONObject:permissions
                                                   options:NSJSONWritingPrettyPrinted
                                                     error:nil];
    if (!data) return;
    [data writeToFile:[self permissionsFilePath] options:NSDataWritingAtomic error:nil];
}

- (NSString *)sitePermissionValueForOriginString:(NSString *)originString kind:(NSString *)kind {
    if (![self isSupportedSitePermissionKind:kind]) return TBSitePermissionAsk;
    NSString *origin = [self normalizedOriginStringFromString:originString];
    if (origin.length == 0) return TBSitePermissionAsk;

    NSDictionary<NSString *, NSString *> *entry = [self sitePermissionsByOrigin][origin];
    NSString *value = entry[kind];
    return [self isExplicitSitePermissionValue:value] ? value : TBSitePermissionAsk;
}

- (void)setSitePermissionValue:(NSString *)value
               forOriginString:(NSString *)originString
                           kind:(NSString *)kind {
    NSString *origin = [self normalizedOriginStringFromString:originString];
    if (origin.length == 0 ||
        ![self isSupportedSitePermissionKind:kind] ||
        ![self isSupportedSitePermissionValue:value]) {
        NSBeep();
        return;
    }

    NSDictionary<NSString *, NSDictionary<NSString *, NSString *> *> *storedPermissions = [self sitePermissionsByOrigin];
    NSMutableDictionary<NSString *, NSMutableDictionary<NSString *, NSString *> *> *permissions = [NSMutableDictionary dictionary];
    for (NSString *storedOrigin in storedPermissions) {
        permissions[storedOrigin] = [storedPermissions[storedOrigin] mutableCopy];
    }

    NSMutableDictionary<NSString *, NSString *> *entry = permissions[origin] ?: [NSMutableDictionary dictionary];
    if ([self isExplicitSitePermissionValue:value]) {
        entry[kind] = value;
        entry[@"updatedAt"] = [[self historyDateFormatter] stringFromDate:[NSDate date]];
        permissions[origin] = entry;
        [self setStatusText:@"Site permission saved"];
    } else {
        [entry removeObjectForKey:kind];
        if (entry[TBSitePermissionCamera] || entry[TBSitePermissionMicrophone]) {
            entry[@"updatedAt"] = [[self historyDateFormatter] stringFromDate:[NSDate date]];
            permissions[origin] = entry;
        } else {
            [permissions removeObjectForKey:origin];
        }
        [self setStatusText:@"Site permission reset"];
    }

    [self writeSitePermissionsByOrigin:permissions];
    [self writeBrowserStateRunning:YES];
}

- (void)clearSitePermissions {
    [[NSFileManager defaultManager] removeItemAtPath:[self permissionsFilePath] error:NULL];
    [self setStatusText:@"Site permissions cleared"];
    [self writeBrowserStateRunning:YES];
}

- (NSString *)displayLabelForSitePermissionValue:(NSString *)value {
    if ([value isEqualToString:TBSitePermissionAllow]) return @"Allowed";
    if ([value isEqualToString:TBSitePermissionDeny]) return @"Blocked";
    return @"Ask every time";
}

- (NSString *)sitePermissionSummaryForURL:(NSURL *)url {
    NSString *origin = [self originStringForURL:url];
    if (origin.length == 0) return @"";

    NSString *camera = [self sitePermissionValueForOriginString:origin kind:TBSitePermissionCamera];
    NSString *microphone = [self sitePermissionValueForOriginString:origin kind:TBSitePermissionMicrophone];
    if ([camera isEqualToString:TBSitePermissionAsk] &&
        [microphone isEqualToString:TBSitePermissionAsk]) {
        return @"Camera and microphone permissions: ask when needed.";
    }

    return [NSString stringWithFormat:@"Site permissions for %@:\nCamera: %@\nMicrophone: %@",
            origin,
            [self displayLabelForSitePermissionValue:camera],
            [self displayLabelForSitePermissionValue:microphone]];
}

- (NSArray<NSDictionary<NSString *, id> *> *)settingsPermissionEntries {
    NSDictionary<NSString *, NSDictionary<NSString *, NSString *> *> *permissions = [self sitePermissionsByOrigin];
    NSArray<NSString *> *origins = [permissions.allKeys sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    NSMutableArray<NSDictionary<NSString *, id> *> *entries = [NSMutableArray arrayWithCapacity:origins.count];

    for (NSString *origin in origins) {
        NSDictionary<NSString *, NSString *> *entry = permissions[origin];
        [entries addObject:@{
            @"origin": origin,
            @"camera": entry[TBSitePermissionCamera] ?: TBSitePermissionAsk,
            @"microphone": entry[TBSitePermissionMicrophone] ?: TBSitePermissionAsk,
            @"updatedAt": entry[@"updatedAt"] ?: @""
        }];
    }
    return entries;
}

- (NSString *)settingsPermissionsScript {
    NSArray<NSDictionary<NSString *, id> *> *permissions = [self settingsPermissionEntries];
    NSData *json = [NSJSONSerialization dataWithJSONObject:permissions options:0 error:nil];
    NSString *jsonString = json ? [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding] : @"[]";
    return [NSString stringWithFormat:@"<script>window.__tbPermissions=%@;</script></head>", jsonString ?: @"[]"];
}

- (NSArray<NSString *> *)sitePermissionKindsForMediaCaptureType:(WKMediaCaptureType)type {
    switch (type) {
        case WKMediaCaptureTypeCamera:
            return @[ TBSitePermissionCamera ];
        case WKMediaCaptureTypeMicrophone:
            return @[ TBSitePermissionMicrophone ];
        case WKMediaCaptureTypeCameraAndMicrophone:
            return @[ TBSitePermissionCamera, TBSitePermissionMicrophone ];
    }
    return @[ TBSitePermissionCamera, TBSitePermissionMicrophone ];
}

- (NSString *)mediaCaptureLabelForType:(WKMediaCaptureType)type {
    switch (type) {
        case WKMediaCaptureTypeCamera:
            return @"camera";
        case WKMediaCaptureTypeMicrophone:
            return @"microphone";
        case WKMediaCaptureTypeCameraAndMicrophone:
            return @"camera and microphone";
    }
    return @"camera and microphone";
}

- (BOOL)allSitePermissionKindsAllowed:(NSArray<NSString *> *)kinds originString:(NSString *)originString {
    for (NSString *kind in kinds) {
        if (![[self sitePermissionValueForOriginString:originString kind:kind] isEqualToString:TBSitePermissionAllow]) {
            return NO;
        }
    }
    return YES;
}

- (BOOL)anySitePermissionKindDenied:(NSArray<NSString *> *)kinds originString:(NSString *)originString {
    for (NSString *kind in kinds) {
        if ([[self sitePermissionValueForOriginString:originString kind:kind] isEqualToString:TBSitePermissionDeny]) {
            return YES;
        }
    }
    return NO;
}

#pragma mark - Bookmarks

- (BOOL)bookmarkBarVisibilityUserConfigured {
    return [[NSUserDefaults standardUserDefaults] objectForKey:TBBookmarkBarUserConfiguredKey] != nil;
}

- (BOOL)initialBookmarkBarVisible {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if ([self bookmarkEntries].count == 0) return NO;
    if ([self bookmarkBarVisibilityUserConfigured]) {
        return [defaults boolForKey:TBBookmarkBarVisibleKey];
    }
    return [defaults boolForKey:TBBookmarkBarVisibleKey] || [self bookmarkEntries].count > 0;
}

- (void)syncBookmarkBarVisibilityWithBookmarks {
    BOOL hasBookmarks = [self bookmarkEntries].count > 0;
    if ([self bookmarkBarVisibilityUserConfigured] && hasBookmarks) return;
    BOOL shouldShow = hasBookmarks;
    if (shouldShow == self.bookmarkBarVisible) return;

    if (self.bookmarkBarHeightConstraint) {
        [self setBookmarkBarVisible:shouldShow persist:NO];
    } else {
        self.bookmarkBarVisible = shouldShow;
        self.bookmarkBar.hidden = !shouldShow;
    }
}

- (NSArray<NSDictionary<NSString *, id> *> *)bookmarkEntries {
    NSData *data = [NSData dataWithContentsOfFile:[self bookmarksFilePath]];
    if (!data.length) return @[];

    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![json isKindOfClass:NSArray.class]) return @[];

    NSMutableArray<NSDictionary<NSString *, id> *> *entries = [NSMutableArray array];
    for (id item in (NSArray *)json) {
        if ([item isKindOfClass:NSDictionary.class]) [entries addObject:item];
    }
    return entries;
}

- (void)writeBookmarkEntries:(NSArray<NSDictionary<NSString *, id> *> *)entries {
    if (![NSJSONSerialization isValidJSONObject:entries]) return;

    NSData *data = [NSJSONSerialization dataWithJSONObject:entries
                                                   options:NSJSONWritingPrettyPrinted
                                                     error:nil];
    if (!data) return;
    [data writeToFile:[self bookmarksFilePath] options:NSDataWritingAtomic error:nil];
    [self reloadBookmarkBarItems];
    [self syncBookmarkBarVisibilityWithBookmarks];
}

- (NSString *)bookmarkURLStringForCurrentPage {
    NSURL *url = self.webView.URL;
    if (!url) {
        NSString *tabURLString = [self activeTab].urlString ?: @"";
        url = [NSURL URLWithString:tabURLString];
    }
    NSString *scheme = url.scheme.lowercaseString;
    BOOL bookmarkable = [scheme isEqualToString:@"http"] ||
                        [scheme isEqualToString:@"https"] ||
                        [scheme isEqualToString:@"file"];
    return bookmarkable ? (url.absoluteString ?: @"") : @"";
}

- (BOOL)isURLStringBookmarked:(NSString *)urlString {
    if (urlString.length == 0) return NO;
    for (NSDictionary<NSString *, id> *entry in [self bookmarkEntries]) {
        NSString *url = [entry[@"url"] isKindOfClass:NSString.class] ? entry[@"url"] : @"";
        if ([url isEqualToString:urlString]) return YES;
    }
    return NO;
}

- (BOOL)isCurrentPageBookmarked {
    return [self isURLStringBookmarked:[self bookmarkURLStringForCurrentPage]];
}

- (void)toggleBookmarkCurrentPage:(id)sender {
    (void)sender;
    NSString *urlString = [self bookmarkURLStringForCurrentPage];
    if (urlString.length == 0) {
        NSBeep();
        return;
    }

    NSMutableArray<NSDictionary<NSString *, id> *> *entries = [[self bookmarkEntries] mutableCopy] ?: [NSMutableArray array];
    NSUInteger existingIndex = NSNotFound;
    for (NSUInteger i = 0; i < entries.count; i++) {
        NSString *url = [entries[i][@"url"] isKindOfClass:NSString.class] ? entries[i][@"url"] : @"";
        if ([url isEqualToString:urlString]) {
            existingIndex = i;
            break;
        }
    }

    if (existingIndex != NSNotFound) {
        [entries removeObjectAtIndex:existingIndex];
        [self setStatusText:@"Bookmark removed"];
    } else {
        NSURL *url = [NSURL URLWithString:urlString];
        BrowserTab *tab = [self activeTab];
        NSString *title = self.webView.title.length ? self.webView.title : tab.title;
        if (title.length == 0) title = url.host.length ? url.host : urlString;
        NSDictionary<NSString *, id> *entry = @{
            @"title": title ?: urlString,
            @"url": urlString,
            @"host": url.host ?: @"",
            @"createdAt": [[self historyDateFormatter] stringFromDate:[NSDate date]]
        };
        [entries insertObject:entry atIndex:0];
        [self setStatusText:@"Bookmarked"];
    }

    [self writeBookmarkEntries:entries];
    [self updateBookmarkButton];
}

- (void)removeBookmarkForURLString:(NSString *)urlString {
    if (urlString.length == 0) return;
    NSMutableArray<NSDictionary<NSString *, id> *> *entries = [[self bookmarkEntries] mutableCopy] ?: [NSMutableArray array];
    NSIndexSet *matches = [entries indexesOfObjectsPassingTest:^BOOL(NSDictionary<NSString *,id> *entry,
                                                                     NSUInteger idx,
                                                                     BOOL *stop) {
        (void)idx;
        (void)stop;
        NSString *url = [entry[@"url"] isKindOfClass:NSString.class] ? entry[@"url"] : @"";
        return [url isEqualToString:urlString];
    }];
    if (matches.count == 0) return;

    [entries removeObjectsAtIndexes:matches];
    [self writeBookmarkEntries:entries];
    [self updateBookmarkButton];
}

- (void)updateBookmarkForURLString:(NSString *)oldURLString
                              title:(NSString *)title
                       newURLString:(NSString *)newURLString {
    if (oldURLString.length == 0 || newURLString.length == 0) return;
    NSURL *url = [self URLForUserInput:newURLString];
    NSString *scheme = url.scheme.lowercaseString;
    BOOL supported = [scheme isEqualToString:@"http"] ||
                     [scheme isEqualToString:@"https"] ||
                     [scheme isEqualToString:@"file"];
    if (!supported) return;

    NSMutableArray<NSDictionary<NSString *, id> *> *entries = [[self bookmarkEntries] mutableCopy] ?: [NSMutableArray array];
    for (NSUInteger i = 0; i < entries.count; i++) {
        NSString *candidate = [entries[i][@"url"] isKindOfClass:NSString.class] ? entries[i][@"url"] : @"";
        if (![candidate isEqualToString:oldURLString]) continue;
        NSMutableDictionary<NSString *, id> *updated = [entries[i] mutableCopy];
        updated[@"title"] = title.length ? title : (url.host.length ? url.host : newURLString);
        updated[@"url"] = url.absoluteString ?: newURLString;
        updated[@"host"] = url.host ?: @"";
        updated[@"updatedAt"] = [[self historyDateFormatter] stringFromDate:[NSDate date]];
        entries[i] = updated;
        break;
    }

    [self writeBookmarkEntries:entries];
    [self updateBookmarkButton];
}

- (void)moveBookmarkURLString:(NSString *)urlString beforeURLString:(NSString *)beforeURLString {
    if (urlString.length == 0 || [urlString isEqualToString:beforeURLString]) return;

    NSMutableArray<NSDictionary<NSString *, id> *> *entries = [[self bookmarkEntries] mutableCopy] ?: [NSMutableArray array];
    NSUInteger sourceIndex = NSNotFound;
    NSDictionary<NSString *, id> *movingEntry = nil;

    for (NSUInteger i = 0; i < entries.count; i++) {
        NSString *candidate = [entries[i][@"url"] isKindOfClass:NSString.class] ? entries[i][@"url"] : @"";
        if ([candidate isEqualToString:urlString]) {
            sourceIndex = i;
            movingEntry = entries[i];
            break;
        }
    }
    if (sourceIndex == NSNotFound || !movingEntry) return;

    [entries removeObjectAtIndex:sourceIndex];

    NSUInteger destinationIndex = entries.count;
    if (beforeURLString.length > 0) {
        for (NSUInteger i = 0; i < entries.count; i++) {
            NSString *candidate = [entries[i][@"url"] isKindOfClass:NSString.class] ? entries[i][@"url"] : @"";
            if ([candidate isEqualToString:beforeURLString]) {
                destinationIndex = i;
                break;
            }
        }
    }

    NSMutableDictionary<NSString *, id> *updated = [movingEntry mutableCopy];
    updated[@"updatedAt"] = [[self historyDateFormatter] stringFromDate:[NSDate date]];
    [entries insertObject:updated atIndex:destinationIndex];
    [self writeBookmarkEntries:entries];
    [self setStatusText:@"Bookmark order updated"];
}

- (NSString *)stringByStrippingHTMLTags:(NSString *)html {
    if (html.length == 0) return @"";
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"<[^>]+>"
                                                                           options:0
                                                                             error:nil];
    NSString *plain = [regex stringByReplacingMatchesInString:html
                                                      options:0
                                                        range:NSMakeRange(0, html.length)
                                                 withTemplate:@""];
    return [plain stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

- (NSString *)stringByDecodingBasicHTMLEntities:(NSString *)text {
    if (text.length == 0) return @"";
    NSString *value = text;
    NSDictionary<NSString *, NSString *> *entities = @{
        @"&quot;": @"\"",
        @"&#34;": @"\"",
        @"&#39;": @"'",
        @"&apos;": @"'",
        @"&lt;": @"<",
        @"&gt;": @">",
        @"&amp;": @"&"
    };
    for (NSString *entity in entities) {
        value = [value stringByReplacingOccurrencesOfString:entity
                                                 withString:entities[entity]
                                                    options:NSCaseInsensitiveSearch
                                                      range:NSMakeRange(0, value.length)];
    }
    return value;
}

- (NSArray<NSDictionary<NSString *, id> *> *)bookmarkEntriesFromNetscapeHTML:(NSString *)html {
    if (html.length == 0) return @[];
    NSString *pattern = @"<A\\s+[^>]*HREF\\s*=\\s*([\"'])(.*?)\\1[^>]*>(.*?)</A>";
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern
                                                                           options:(NSRegularExpressionCaseInsensitive |
                                                                                    NSRegularExpressionDotMatchesLineSeparators)
                                                                             error:nil];
    NSArray<NSTextCheckingResult *> *matches = [regex matchesInString:html
                                                              options:0
                                                                range:NSMakeRange(0, html.length)];
    NSMutableArray<NSDictionary<NSString *, id> *> *entries = [NSMutableArray arrayWithCapacity:matches.count];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    NSString *timestamp = [[self historyDateFormatter] stringFromDate:[NSDate date]];

    for (NSTextCheckingResult *match in matches) {
        if (match.numberOfRanges < 4) continue;
        NSString *urlString = [html substringWithRange:[match rangeAtIndex:2]];
        urlString = [self stringByDecodingBasicHTMLEntities:urlString];
        NSURL *url = [NSURL URLWithString:urlString];
        NSString *scheme = url.scheme.lowercaseString;
        BOOL supported = [scheme isEqualToString:@"http"] ||
                         [scheme isEqualToString:@"https"] ||
                         [scheme isEqualToString:@"file"];
        if (!supported || url.absoluteString.length == 0) continue;
        if ([seen containsObject:url.absoluteString]) continue;

        NSString *title = [html substringWithRange:[match rangeAtIndex:3]];
        title = [self stringByStrippingHTMLTags:title];
        title = [self stringByDecodingBasicHTMLEntities:title];
        if (title.length == 0) title = url.host.length ? url.host : url.absoluteString;

        [seen addObject:url.absoluteString];
        [entries addObject:@{
            @"title": title ?: url.absoluteString,
            @"url": url.absoluteString,
            @"host": url.host ?: @"",
            @"createdAt": timestamp,
            @"source": @"import"
        }];
    }
    return entries;
}

- (void)importBookmarksFromHTML:(id)sender {
    (void)sender;
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.title = @"Import Bookmarks";
    panel.canChooseFiles = YES;
    panel.canChooseDirectories = NO;
    panel.allowsMultipleSelection = NO;
    panel.allowedContentTypes = @[ UTTypeHTML, UTTypePlainText ];

    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
        if (result != NSModalResponseOK || !panel.URL) return;
        NSError *error = nil;
        NSStringEncoding encoding = NSUTF8StringEncoding;
        NSString *html = [NSString stringWithContentsOfURL:panel.URL
                                              usedEncoding:&encoding
                                                     error:&error];
        if (html.length == 0 || error) {
            [self setStatusText:error.localizedDescription ?: @"Could not read bookmarks"];
            NSBeep();
            return;
        }

        NSArray<NSDictionary<NSString *, id> *> *incoming = [self bookmarkEntriesFromNetscapeHTML:html];
        if (incoming.count == 0) {
            [self setStatusText:@"No bookmarks found"];
            NSBeep();
            return;
        }

        NSArray<NSDictionary<NSString *, id> *> *existing = [self bookmarkEntries];
        NSMutableSet<NSString *> *existingURLs = [NSMutableSet set];
        for (NSDictionary<NSString *, id> *entry in existing) {
            NSString *url = [entry[@"url"] isKindOfClass:NSString.class] ? entry[@"url"] : @"";
            if (url.length > 0) [existingURLs addObject:url];
        }

        NSMutableArray<NSDictionary<NSString *, id> *> *merged = [NSMutableArray array];
        NSUInteger imported = 0;
        for (NSDictionary<NSString *, id> *entry in incoming) {
            NSString *url = [entry[@"url"] isKindOfClass:NSString.class] ? entry[@"url"] : @"";
            if (url.length == 0 || [existingURLs containsObject:url]) continue;
            [existingURLs addObject:url];
            [merged addObject:entry];
            imported += 1;
        }
        [merged addObjectsFromArray:existing];
        if (imported == 0) {
            [self setStatusText:@"Bookmarks already imported"];
            return;
        }

        [self writeBookmarkEntries:merged];
        [self updateBookmarkButton];
        [self writeBrowserStateRunning:YES];
        [self setStatusText:[NSString stringWithFormat:@"Imported %lu bookmark%@", (unsigned long)imported, imported == 1 ? @"" : @"s"]];
        if (self.webView && [self isSettingsURLString:self.webView.URL.absoluteString]) {
            [self loadNativeSettingsPageInWebView:self.webView];
        }
    }];
}

- (NSString *)htmlAttributeEscaped:(NSString *)text {
    NSString *value = [self htmlEscaped:text ?: @""];
    value = [value stringByReplacingOccurrencesOfString:@"\"" withString:@"&quot;"];
    return value;
}

- (NSInteger)unixTimestampForBookmarkDateString:(NSString *)dateString {
    if (dateString.length == 0) return (NSInteger)[NSDate date].timeIntervalSince1970;
    NSDate *date = [[self historyDateFormatter] dateFromString:dateString];
    return (NSInteger)(date ?: [NSDate date]).timeIntervalSince1970;
}

- (NSString *)bookmarksExportHTML {
    NSArray<NSDictionary<NSString *, id> *> *entries = [self bookmarkEntries];
    NSMutableString *html = [NSMutableString stringWithString:
        @"<!DOCTYPE NETSCAPE-Bookmark-file-1>\n"
         "<META HTTP-EQUIV=\"Content-Type\" CONTENT=\"text/html; charset=UTF-8\">\n"
         "<TITLE>Bookmarks</TITLE>\n"
         "<H1>TrailBrowser Bookmarks</H1>\n"
         "<DL><p>\n"];

    for (NSDictionary<NSString *, id> *entry in entries) {
        NSString *url = [entry[@"url"] isKindOfClass:NSString.class] ? entry[@"url"] : @"";
        if (url.length == 0) continue;
        NSString *title = [entry[@"title"] isKindOfClass:NSString.class] ? entry[@"title"] : @"";
        if (title.length == 0) title = url;
        NSString *createdAt = [entry[@"createdAt"] isKindOfClass:NSString.class] ? entry[@"createdAt"] : @"";
        [html appendFormat:@"    <DT><A HREF=\"%@\" ADD_DATE=\"%ld\">%@</A>\n",
         [self htmlAttributeEscaped:url],
         (long)[self unixTimestampForBookmarkDateString:createdAt],
         [self htmlEscaped:title]];
    }
    [html appendString:@"</DL><p>\n"];
    return html;
}

- (void)exportBookmarksToHTML:(id)sender {
    (void)sender;
    NSArray<NSDictionary<NSString *, id> *> *entries = [self bookmarkEntries];
    if (entries.count == 0) {
        [self setStatusText:@"No bookmarks to export"];
        NSBeep();
        return;
    }

    NSSavePanel *panel = [NSSavePanel savePanel];
    panel.title = @"Export Bookmarks";
    panel.nameFieldStringValue = @"TrailBrowser Bookmarks.html";
    panel.canCreateDirectories = YES;
    panel.allowedContentTypes = @[ UTTypeHTML ];

    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
        if (result != NSModalResponseOK || !panel.URL) return;
        NSError *error = nil;
        NSString *html = [self bookmarksExportHTML];
        if (![html writeToURL:panel.URL atomically:YES encoding:NSUTF8StringEncoding error:&error]) {
            [self setStatusText:error.localizedDescription ?: @"Could not export bookmarks"];
            NSBeep();
            return;
        }
        [self setStatusText:@"Bookmarks exported"];
    }];
}

- (NSArray<NSDictionary<NSString *, id> *> *)settingsBookmarkEntries {
    NSMutableArray<NSDictionary<NSString *, id> *> *entries = [NSMutableArray array];
    for (NSDictionary<NSString *, id> *entry in [self bookmarkEntries]) {
        NSString *url = [entry[@"url"] isKindOfClass:NSString.class] ? entry[@"url"] : @"";
        if (url.length == 0) continue;
        [entries addObject:@{
            @"title": [entry[@"title"] isKindOfClass:NSString.class] ? entry[@"title"] : @"",
            @"url": url,
            @"host": [entry[@"host"] isKindOfClass:NSString.class] ? entry[@"host"] : @"",
            @"createdAt": [entry[@"createdAt"] isKindOfClass:NSString.class] ? entry[@"createdAt"] : @""
        }];
    }
    return entries;
}

- (NSString *)settingsBookmarksScript {
    NSArray<NSDictionary<NSString *, id> *> *bookmarks = [self settingsBookmarkEntries];
    NSData *json = [NSJSONSerialization dataWithJSONObject:bookmarks options:0 error:nil];
    NSString *jsonString = json ? [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding] : @"[]";
    return [NSString stringWithFormat:@"<script>window.__tbBookmarks=%@;</script></head>", jsonString ?: @"[]"];
}

- (NSArray<NSDictionary<NSString *, id> *> *)recentBookmarkEntriesLimitedTo:(NSUInteger)limit {
    NSArray<NSDictionary<NSString *, id> *> *entries = [self settingsBookmarkEntries];
    if (entries.count <= limit) return entries;
    return [entries subarrayWithRange:NSMakeRange(0, limit)];
}

- (NSString *)shortBookmarkTitleForEntry:(NSDictionary<NSString *, id> *)entry {
    NSString *title = [entry[@"title"] isKindOfClass:NSString.class] ? entry[@"title"] : @"";
    if (title.length == 0) title = [entry[@"host"] isKindOfClass:NSString.class] ? entry[@"host"] : @"";
    if (title.length == 0) {
        NSString *urlString = [entry[@"url"] isKindOfClass:NSString.class] ? entry[@"url"] : @"";
        title = urlString.length ? urlString : @"Bookmark";
    }
    if (title.length > 28) title = [[title substringToIndex:27] stringByAppendingString:@"…"];
    return title;
}

- (NSButton *)bookmarkBarButtonForEntry:(NSDictionary<NSString *, id> *)entry {
    NSString *urlString = [entry[@"url"] isKindOfClass:NSString.class] ? entry[@"url"] : @"";
    NSString *title = [self shortBookmarkTitleForEntry:entry];

    TBFlatButton *button = [[TBFlatButton alloc] initWithFrame:NSZeroRect];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    button.cornerRadius = 7.0;
    button.target = self;
    button.action = @selector(openBookmarkFromBar:);
    button.identifier = urlString;
    button.toolTip = urlString.length ? urlString : title;
    button.imagePosition = NSImageLeft;
    button.imageScaling = NSImageScaleProportionallyDown;
    button.imageHugsTitle = YES;
    button.alignment = NSTextAlignmentLeft;
    if (@available(macOS 11.0, *)) {
        NSImage *image = [NSImage imageWithSystemSymbolName:@"globe" accessibilityDescription:title];
        NSImageSymbolConfiguration *config = [NSImageSymbolConfiguration configurationWithPointSize:11.0
                                                                                             weight:NSFontWeightRegular];
        image = [image imageWithSymbolConfiguration:config] ?: image;
        image.template = YES;
        button.image = image;
    }
    if (@available(macOS 10.14, *)) button.contentTintColor = TBFaint();

    NSMutableParagraphStyle *paragraph = [[NSMutableParagraphStyle alloc] init];
    paragraph.lineBreakMode = NSLineBreakByTruncatingTail;
    paragraph.alignment = NSTextAlignmentLeft;
    button.attributedTitle = [[NSAttributedString alloc] initWithString:[@"  " stringByAppendingString:title]
                                                             attributes:@{
        NSFontAttributeName: [NSFont systemFontOfSize:12.0 weight:NSFontWeightRegular],
        NSForegroundColorAttributeName: TBText(),
        NSParagraphStyleAttributeName: paragraph
    }];
    [button.heightAnchor constraintEqualToConstant:26.0].active = YES;
    [button.widthAnchor constraintGreaterThanOrEqualToConstant:74.0].active = YES;
    [button.widthAnchor constraintLessThanOrEqualToConstant:180.0].active = YES;
    return button;
}

- (NSButton *)bookmarkBarMoreButtonWithHiddenCount:(NSUInteger)hiddenCount {
    NSString *title = hiddenCount > 0
        ? [NSString stringWithFormat:@"%lu more", (unsigned long)hiddenCount]
        : @"Bookmarks";
    TBFlatButton *button = [[TBFlatButton alloc] initWithFrame:NSZeroRect];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    button.cornerRadius = 7.0;
    button.target = self;
    button.action = @selector(showBookmarksPopover:);
    button.toolTip = @"More bookmarks";
    NSMutableParagraphStyle *paragraph = [[NSMutableParagraphStyle alloc] init];
    paragraph.alignment = NSTextAlignmentCenter;
    button.attributedTitle = [[NSAttributedString alloc] initWithString:title attributes:@{
        NSFontAttributeName: [NSFont systemFontOfSize:12.0 weight:NSFontWeightRegular],
        NSForegroundColorAttributeName: TBMuted(),
        NSParagraphStyleAttributeName: paragraph
    }];
    [button.heightAnchor constraintEqualToConstant:26.0].active = YES;
    [button.widthAnchor constraintEqualToConstant:hiddenCount > 0 ? 78.0 : 92.0].active = YES;
    return button;
}

- (void)reloadBookmarkBarItems {
    if (!self.bookmarkBarStack) return;
    NSArray<NSView *> *existing = self.bookmarkBarStack.arrangedSubviews.copy;
    for (NSView *view in existing) {
        [self.bookmarkBarStack removeArrangedSubview:view];
        [view removeFromSuperview];
    }

    NSArray<NSDictionary<NSString *, id> *> *bookmarks = [self settingsBookmarkEntries];
    if (bookmarks.count == 0) {
        return;
    }

    NSUInteger visibleCount = MIN(bookmarks.count, 10);
    for (NSUInteger i = 0; i < visibleCount; i++) {
        [self.bookmarkBarStack addArrangedSubview:[self bookmarkBarButtonForEntry:bookmarks[i]]];
    }
    if (bookmarks.count > visibleCount) {
        [self.bookmarkBarStack addArrangedSubview:[self bookmarkBarMoreButtonWithHiddenCount:(bookmarks.count - visibleCount)]];
    }
}

- (NSString *)downloadIDForMetadata:(NSMutableDictionary<NSString *, id> *)metadata {
    NSString *downloadID = [metadata[@"id"] isKindOfClass:NSString.class] ? metadata[@"id"] : @"";
    if (downloadID.length == 0) {
        downloadID = NSUUID.UUID.UUIDString;
        metadata[@"id"] = downloadID;
    }
    return downloadID;
}

- (NSString *)downloadResumeDataPathForID:(NSString *)downloadID {
    NSString *safeID = downloadID.length ? downloadID : NSUUID.UUID.UUIDString;
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"];
    safeID = [[safeID componentsSeparatedByCharactersInSet:allowed.invertedSet] componentsJoinedByString:@"-"];
    if (safeID.length == 0) safeID = NSUUID.UUID.UUIDString;
    return [[self downloadResumeDataDirectoryPath] stringByAppendingPathComponent:
            [safeID stringByAppendingPathExtension:@"resumeData"]];
}

- (NSString *)storeResumeData:(NSData *)resumeData forDownloadID:(NSString *)downloadID {
    if (resumeData.length == 0 || downloadID.length == 0) return @"";

    NSFileManager *fm = [NSFileManager defaultManager];
    NSError *error = nil;
    [fm createDirectoryAtPath:[self downloadResumeDataDirectoryPath]
  withIntermediateDirectories:YES
                   attributes:nil
                        error:&error];
    if (error) return @"";

    NSString *path = [self downloadResumeDataPathForID:downloadID];
    if (![resumeData writeToFile:path options:NSDataWritingAtomic error:&error]) {
        NSLog(@"Could not write download resume data: %@", error.localizedDescription);
        return @"";
    }
    return path;
}

- (void)removeDownloadResumeDataAtPath:(NSString *)path {
    if (path.length == 0) return;
    [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
}

- (NSDictionary<NSString *, id> *)downloadProgressPayloadForDownload:(WKDownload *)download {
    NSProgress *progress = [(id<NSProgressReporting>)download progress];
    double fraction = progress.fractionCompleted;
    BOOL indeterminate = progress.isIndeterminate || !(fraction >= 0.0) || fraction > 1.0;
    if (indeterminate) fraction = 0.0;

    NSString *detail = progress.localizedAdditionalDescription.length
        ? progress.localizedAdditionalDescription
        : progress.localizedDescription;
    NSString *progressText = indeterminate
        ? (detail.length ? detail : @"Downloading")
        : [NSString stringWithFormat:@"Downloading %.0f%%", fraction * 100.0];

    return @{
        @"progress": @(fraction),
        @"progressIndeterminate": @(indeterminate),
        @"progressText": progressText ?: @"Downloading"
    };
}

- (NSArray<NSDictionary<NSString *, id> *> *)activeDownloadEntries {
    if (self.activeDownloads.count == 0) return @[];
    if (!self.downloadMetadata) self.downloadMetadata = [NSMapTable strongToStrongObjectsMapTable];

    NSMutableArray<NSDictionary<NSString *, id> *> *entries = [NSMutableArray arrayWithCapacity:self.activeDownloads.count];
    for (WKDownload *download in self.activeDownloads) {
        NSMutableDictionary<NSString *, id> *metadata = [self.downloadMetadata objectForKey:download];
        if (!metadata) {
            metadata = [@{
                @"timestamp": [[self historyDateFormatter] stringFromDate:[NSDate date]],
                @"status": @"started"
            } mutableCopy];
            [self.downloadMetadata setObject:metadata forKey:download];
        }

        NSString *downloadID = [self downloadIDForMetadata:metadata];
        NSString *path = [metadata[@"path"] isKindOfClass:NSString.class] ? metadata[@"path"] : @"";
        NSString *filename = [metadata[@"filename"] isKindOfClass:NSString.class] ? metadata[@"filename"] : @"";
        NSURL *sourceURL = download.originalRequest.URL;
        if (filename.length == 0) filename = sourceURL.lastPathComponent.length ? sourceURL.lastPathComponent : path.lastPathComponent;
        if (filename.length == 0) filename = @"download";

        NSMutableDictionary<NSString *, id> *entry = [@{
            @"id": downloadID,
            @"timestamp": [metadata[@"timestamp"] isKindOfClass:NSString.class] ? metadata[@"timestamp"] : @"",
            @"filename": filename,
            @"path": path ?: @"",
            @"status": [metadata[@"status"] isKindOfClass:NSString.class] ? metadata[@"status"] : @"started",
            @"active": @YES,
            @"sourceURL": sourceURL.absoluteString ?: @""
        } mutableCopy];
        [entry addEntriesFromDictionary:[self downloadProgressPayloadForDownload:download]];
        [entries addObject:entry];
    }

    [entries sortUsingDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"timestamp" ascending:NO]]];
    return entries;
}

- (NSArray<NSDictionary<NSString *, id> *> *)settingsDownloadEntries {
    NSArray<NSDictionary<NSString *, id> *> *downloads = [self JSONLinesAtPath:[self downloadsFilePath] newestFirst:YES];
    NSMutableArray<NSDictionary<NSString *, id> *> *entries = [[self activeDownloadEntries] mutableCopy];
    NSMutableSet<NSString *> *seenIDs = [NSMutableSet set];
    for (NSDictionary<NSString *, id> *entry in entries) {
        NSString *downloadID = [entry[@"id"] isKindOfClass:NSString.class] ? entry[@"id"] : @"";
        if (downloadID.length > 0) [seenIDs addObject:downloadID];
    }

    for (NSDictionary<NSString *, id> *entry in downloads) {
        NSString *downloadID = [entry[@"id"] isKindOfClass:NSString.class] ? entry[@"id"] : @"";
        if (downloadID.length > 0 && [seenIDs containsObject:downloadID]) continue;

        NSString *path = [entry[@"path"] isKindOfClass:NSString.class] ? entry[@"path"] : @"";
        NSString *filename = [entry[@"filename"] isKindOfClass:NSString.class] ? entry[@"filename"] : path.lastPathComponent;
        if (filename.length == 0 && path.length == 0) continue;

        NSString *resumeDataPath = [entry[@"resumeDataPath"] isKindOfClass:NSString.class] ? entry[@"resumeDataPath"] : @"";
        BOOL hasResumeData = resumeDataPath.length > 0 &&
                             [[NSFileManager defaultManager] fileExistsAtPath:resumeDataPath];

        NSMutableDictionary<NSString *, id> *clean = [@{
            @"id": downloadID ?: @"",
            @"timestamp": [entry[@"timestamp"] isKindOfClass:NSString.class] ? entry[@"timestamp"] : @"",
            @"filename": filename ?: @"",
            @"path": path ?: @"",
            @"status": [entry[@"status"] isKindOfClass:NSString.class] ? entry[@"status"] : @"",
            @"error": [entry[@"error"] isKindOfClass:NSString.class] ? entry[@"error"] : @"",
            @"active": @NO
        } mutableCopy];
        if (hasResumeData) clean[@"resumeDataPath"] = resumeDataPath;
        [entries addObject:clean];
        if (downloadID.length > 0) [seenIDs addObject:downloadID];
    }
    return entries;
}

- (NSArray<NSDictionary<NSString *, id> *> *)recentDownloadEntriesLimitedTo:(NSUInteger)limit {
    NSArray<NSDictionary<NSString *, id> *> *entries = [self settingsDownloadEntries];
    if (entries.count <= limit) return entries;
    return [entries subarrayWithRange:NSMakeRange(0, limit)];
}

- (NSString *)settingsDownloadsScript {
    NSArray<NSDictionary<NSString *, id> *> *downloads = [self settingsDownloadEntries];
    NSData *json = [NSJSONSerialization dataWithJSONObject:downloads options:0 error:nil];
    NSString *jsonString = json ? [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding] : @"[]";
    return [NSString stringWithFormat:@"<script>window.__tbDownloads=%@;</script></head>", jsonString ?: @"[]"];
}

- (void)clearDownloadHistory {
    [[NSFileManager defaultManager] removeItemAtPath:[self downloadsFilePath] error:NULL];
    [[NSFileManager defaultManager] removeItemAtPath:[self downloadResumeDataDirectoryPath] error:NULL];
    [self writeBrowserStateRunning:YES];
}

- (void)revealDownloadAtPath:(NSString *)path {
    if (path.length == 0 || ![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        NSBeep();
        return;
    }
    NSURL *url = [NSURL fileURLWithPath:path];
    [[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:@[ url ]];
}

- (void)recordDownloadEntry:(NSDictionary<NSString *, id> *)entry {
    if (entry.count == 0) return;
    [self appendJSONLine:entry toPath:[self downloadsFilePath]];
    [self writeBrowserStateRunning:YES];
}

- (NSDictionary<NSString *, id> *)downloadLogEntryWithID:(NSString *)downloadID {
    if (downloadID.length == 0) return nil;
    for (NSDictionary<NSString *, id> *entry in [self JSONLinesAtPath:[self downloadsFilePath] newestFirst:YES]) {
        NSString *candidate = [entry[@"id"] isKindOfClass:NSString.class] ? entry[@"id"] : @"";
        if ([candidate isEqualToString:downloadID]) return entry;
    }
    return nil;
}

- (WKDownload *)activeDownloadWithID:(NSString *)downloadID {
    if (downloadID.length == 0) return nil;
    for (WKDownload *download in self.activeDownloads) {
        NSDictionary<NSString *, id> *metadata = [self.downloadMetadata objectForKey:download];
        NSString *candidate = [metadata[@"id"] isKindOfClass:NSString.class] ? metadata[@"id"] : @"";
        if ([candidate isEqualToString:downloadID]) return download;
    }
    return nil;
}

- (void)reloadSettingsIfVisible {
    if (self.webView && [self isSettingsURLString:self.webView.URL.absoluteString]) {
        [self loadNativeSettingsPageInWebView:self.webView];
    }
}

- (void)refreshDownloadsPopoverIfOpen {
    if (!self.downloadsPopover.shown || !self.downloadsPopover.contentViewController) return;
    self.downloadsPopover.contentViewController.view = [self downloadsPopoverContentView];
}

- (void)downloadRefreshTimerFired:(NSTimer *)timer {
    (void)timer;
    if (self.activeDownloads.count == 0) {
        [self.downloadRefreshTimer invalidate];
        self.downloadRefreshTimer = nil;
        return;
    }
    [self updateDownloadsButton];
    [self refreshDownloadsPopoverIfOpen];
}

- (void)startDownloadRefreshTimerIfNeeded {
    if (self.downloadRefreshTimer || self.activeDownloads.count == 0) return;
    NSTimer *timer = [NSTimer timerWithTimeInterval:0.75
                                             target:self
                                           selector:@selector(downloadRefreshTimerFired:)
                                           userInfo:nil
                                            repeats:YES];
    [[NSRunLoop mainRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];
    self.downloadRefreshTimer = timer;
}

- (void)stopDownloadRefreshTimerIfIdle {
    if (self.activeDownloads.count > 0) return;
    [self.downloadRefreshTimer invalidate];
    self.downloadRefreshTimer = nil;
}

- (void)cancelDownloadWithID:(NSString *)downloadID {
    WKDownload *download = [self activeDownloadWithID:downloadID];
    if (!download) {
        NSBeep();
        return;
    }

    NSMutableDictionary<NSString *, id> *metadata = [self.downloadMetadata objectForKey:download];
    if (!metadata) {
        metadata = [@{ @"timestamp": [[self historyDateFormatter] stringFromDate:[NSDate date]] } mutableCopy];
        [self.downloadMetadata setObject:metadata forKey:download];
    }
    metadata[@"status"] = @"canceling";
    [self setStatusText:@"Canceling download"];
    [self updateDownloadsButton];
    [self refreshDownloadsPopoverIfOpen];
    [self reloadSettingsIfVisible];

    [download cancel:^(NSData *resumeData) {
        dispatch_async(dispatch_get_main_queue(), ^{
            NSMutableDictionary<NSString *, id> *entry = [[self.downloadMetadata objectForKey:download] mutableCopy] ?: [metadata mutableCopy];
            NSString *stableID = [self downloadIDForMetadata:entry];
            entry[@"timestamp"] = entry[@"timestamp"] ?: [[self historyDateFormatter] stringFromDate:[NSDate date]];
            entry[@"status"] = @"canceled";
            entry[@"error"] = @"Canceled";
            if (![entry[@"filename"] isKindOfClass:NSString.class]) entry[@"filename"] = @"download";

            [entry removeObjectForKey:@"resumeDataPath"];
            NSString *resumePath = [self storeResumeData:resumeData forDownloadID:stableID];
            if (resumePath.length > 0) entry[@"resumeDataPath"] = resumePath;

            [self recordDownloadEntry:entry];
            [self.downloadMetadata removeObjectForKey:download];
            [self.activeDownloads removeObject:download];
            [self setStatusText:resumePath.length > 0 ? @"Download canceled, can resume" : @"Download canceled"];
            [self updateDownloadsButton];
            [self stopDownloadRefreshTimerIfIdle];
            [self refreshDownloadsPopoverIfOpen];
            [self reloadSettingsIfVisible];
        });
    }];
}

- (void)resumeDownloadWithID:(NSString *)downloadID {
    if (@available(macOS 11.3, *)) {
        NSDictionary<NSString *, id> *entry = [self downloadLogEntryWithID:downloadID];
        NSString *resumeDataPath = [entry[@"resumeDataPath"] isKindOfClass:NSString.class] ? entry[@"resumeDataPath"] : @"";
        NSData *resumeData = resumeDataPath.length ? [NSData dataWithContentsOfFile:resumeDataPath] : nil;
        if (resumeData.length == 0) {
            [self setStatusText:@"Download cannot be resumed"];
            NSBeep();
            return;
        }

        BrowserTab *tab = [self activeTab];
        WKWebView *webView = self.webView ?: (tab ? [self ensureWebViewForTab:tab] : nil);
        if (!webView) {
            [self setStatusText:@"No web view available to resume download"];
            NSBeep();
            return;
        }

        [self setStatusText:@"Resuming download"];
        [webView resumeDownloadFromResumeData:resumeData completionHandler:^(WKDownload *download) {
            if (!download) {
                [self setStatusText:@"Download cannot be resumed"];
                NSBeep();
                return;
            }
            if (!self.downloadMetadata) self.downloadMetadata = [NSMapTable strongToStrongObjectsMapTable];
            NSMutableDictionary<NSString *, id> *metadata = [@{
                @"id": downloadID ?: NSUUID.UUID.UUIDString,
                @"timestamp": [[self historyDateFormatter] stringFromDate:[NSDate date]],
                @"status": @"resuming",
                @"filename": [entry[@"filename"] isKindOfClass:NSString.class] ? entry[@"filename"] : @"download",
                @"path": [entry[@"path"] isKindOfClass:NSString.class] ? entry[@"path"] : @"",
                @"resumeDataPath": resumeDataPath ?: @""
            } mutableCopy];
            [self.downloadMetadata setObject:metadata forKey:download];
            [self trackDownload:download];
            [self refreshDownloadsPopoverIfOpen];
            [self reloadSettingsIfVisible];
        }];
    } else {
        [self setStatusText:@"Resume downloads requires macOS 11.3+"];
        NSBeep();
    }
}

- (NSView *)bookmarkPopoverRowForEntry:(NSDictionary<NSString *, id> *)entry {
    NSView *row = [[NSView alloc] initWithFrame:NSZeroRect];
    row.translatesAutoresizingMaskIntoConstraints = NO;

    NSString *titleText = [entry[@"title"] isKindOfClass:NSString.class] ? entry[@"title"] : @"";
    NSString *urlString = [entry[@"url"] isKindOfClass:NSString.class] ? entry[@"url"] : @"";
    if (titleText.length == 0) titleText = [entry[@"host"] isKindOfClass:NSString.class] ? entry[@"host"] : urlString;

    NSTextField *title = [self popoverLabelWithString:titleText
                                                 font:[NSFont systemFontOfSize:12.5 weight:NSFontWeightSemibold]
                                                color:TBText()];
    [row addSubview:title];

    NSTextField *subtitle = [self popoverLabelWithString:urlString
                                                    font:[NSFont systemFontOfSize:11.0 weight:NSFontWeightRegular]
                                                   color:TBFaint()];
    [row addSubview:subtitle];

    NSButton *open = [self popoverButtonWithTitle:@"Open" action:@selector(openBookmarkFromPopover:)];
    open.identifier = urlString;
    [row addSubview:open];

    NSButton *remove = [self popoverButtonWithTitle:@"Remove" action:@selector(removeBookmarkFromPopover:)];
    remove.identifier = urlString;
    [row addSubview:remove];

    [NSLayoutConstraint activateConstraints:@[
        [row.heightAnchor constraintEqualToConstant:54.0],
        [title.leadingAnchor constraintEqualToAnchor:row.leadingAnchor],
        [title.trailingAnchor constraintEqualToAnchor:open.leadingAnchor constant:-10.0],
        [title.topAnchor constraintEqualToAnchor:row.topAnchor constant:7.0],
        [subtitle.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [subtitle.trailingAnchor constraintEqualToAnchor:title.trailingAnchor],
        [subtitle.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:2.0],
        [remove.trailingAnchor constraintEqualToAnchor:row.trailingAnchor],
        [remove.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [remove.widthAnchor constraintEqualToConstant:72.0],
        [open.trailingAnchor constraintEqualToAnchor:remove.leadingAnchor constant:-6.0],
        [open.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [open.widthAnchor constraintEqualToConstant:54.0]
    ]];

    return row;
}

- (NSView *)bookmarksPopoverContentView {
    NSView *content = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 390, 340)];
    content.translatesAutoresizingMaskIntoConstraints = NO;
    content.wantsLayer = YES;
    content.layer.backgroundColor = TBSurface().CGColor;

    NSTextField *title = [self popoverLabelWithString:@"Bookmarks"
                                                 font:[NSFont systemFontOfSize:14.0 weight:NSFontWeightSemibold]
                                                color:TBText()];
    [content addSubview:title];

    NSArray<NSDictionary<NSString *, id> *> *bookmarks = [self recentBookmarkEntriesLimitedTo:6];
    NSString *countText = bookmarks.count == 1 ? @"1 saved" : [NSString stringWithFormat:@"%lu saved", (unsigned long)[self bookmarkEntries].count];
    NSTextField *status = [self popoverLabelWithString:countText
                                                  font:[NSFont systemFontOfSize:11.0 weight:NSFontWeightMedium]
                                                 color:TBFaint()];
    status.alignment = NSTextAlignmentRight;
    [content addSubview:status];

    NSStackView *stack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.distribution = NSStackViewDistributionFill;
    stack.spacing = 4.0;
    [content addSubview:stack];

    if (bookmarks.count == 0) {
        NSTextField *empty = [self popoverLabelWithString:@"No bookmarks yet."
                                                     font:[NSFont systemFontOfSize:12.0 weight:NSFontWeightRegular]
                                                    color:TBFaint()];
        [stack addArrangedSubview:empty];
        [empty.widthAnchor constraintEqualToConstant:356.0].active = YES;
        [empty.heightAnchor constraintEqualToConstant:48.0].active = YES;
    } else {
        for (NSDictionary<NSString *, id> *entry in bookmarks) {
            NSView *row = [self bookmarkPopoverRowForEntry:entry];
            [stack addArrangedSubview:row];
            [row.widthAnchor constraintEqualToConstant:356.0].active = YES;
        }
    }

    NSButton *manage = [self popoverButtonWithTitle:@"Manage Bookmarks" action:@selector(openBookmarksSettings:)];
    [content addSubview:manage];

    [NSLayoutConstraint activateConstraints:@[
        [content.widthAnchor constraintEqualToConstant:390.0],
        [content.heightAnchor constraintEqualToConstant:340.0],
        [title.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:16.0],
        [title.topAnchor constraintEqualToAnchor:content.topAnchor constant:14.0],
        [status.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-16.0],
        [status.centerYAnchor constraintEqualToAnchor:title.centerYAnchor],
        [status.leadingAnchor constraintGreaterThanOrEqualToAnchor:title.trailingAnchor constant:12.0],
        [stack.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:16.0],
        [stack.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-16.0],
        [stack.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:12.0],
        [manage.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:16.0],
        [manage.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-16.0],
        [manage.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-12.0],
        [stack.bottomAnchor constraintLessThanOrEqualToAnchor:manage.topAnchor constant:-10.0]
    ]];

    return content;
}

- (void)showBookmarksPopover:(id)sender {
    (void)sender;
    if (self.bookmarksPopover.shown) {
        [self.bookmarksPopover close];
        return;
    }

    NSPopover *popover = [[NSPopover alloc] init];
    popover.behavior = NSPopoverBehaviorTransient;
    popover.animates = YES;
    NSViewController *controller = [[NSViewController alloc] init];
    controller.view = [self bookmarksPopoverContentView];
    popover.contentViewController = controller;
    self.bookmarksPopover = popover;
    NSView *anchor = [sender isKindOfClass:NSView.class] ? sender : self.bookmarksButton;
    [popover showRelativeToRect:anchor.bounds
                         ofView:anchor
                  preferredEdge:NSMinYEdge];
}

- (void)openBookmarkFromBar:(id)sender {
    NSString *urlString = [sender respondsToSelector:@selector(identifier)] ? [sender identifier] : @"";
    if (urlString.length == 0) return;
    [self loadURLString:urlString];
}

- (void)openBookmarkFromPopover:(id)sender {
    NSString *urlString = [sender respondsToSelector:@selector(identifier)] ? [sender identifier] : @"";
    if (urlString.length == 0) return;
    [self.bookmarksPopover close];
    [self loadURLString:urlString];
}

- (void)removeBookmarkFromPopover:(id)sender {
    NSString *urlString = [sender respondsToSelector:@selector(identifier)] ? [sender identifier] : @"";
    if (urlString.length == 0) return;
    [self removeBookmarkForURLString:urlString];
    [self.bookmarksPopover close];
}

- (void)openBookmarksSettings:(id)sender {
    (void)sender;
    [self.bookmarksPopover close];
    [self openSettings:nil];
}

- (void)setBookmarkBarVisible:(BOOL)visible persist:(BOOL)persist {
    BOOL hasBookmarks = [self bookmarkEntries].count > 0;
    BOOL effectiveVisible = visible && hasBookmarks;
    self.bookmarkBarVisible = effectiveVisible;
    if (persist) {
        [[NSUserDefaults standardUserDefaults] setBool:visible forKey:TBBookmarkBarVisibleKey];
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:TBBookmarkBarUserConfiguredKey];
    }
    self.bookmarkBar.hidden = !effectiveVisible;
    self.bookmarkBarHeightConstraint.constant = effectiveVisible ? 34.0 : 0.0;
    [self reloadBookmarkBarItems];
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = 0.18;
        context.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
        [self.window.contentView layoutSubtreeIfNeeded];
    } completionHandler:^{
        self.bookmarkBar.hidden = !self.bookmarkBarVisible;
        [self setStatusText:self.bookmarkBarVisible ? @"Bookmarks bar shown" : @"Bookmarks bar hidden"];
        if (!self.restoringSession) [self writeBrowserStateRunning:YES];
    }];
}

- (void)toggleBookmarkBar:(id)sender {
    (void)sender;
    [self setBookmarkBarVisible:!self.bookmarkBarVisible persist:YES];
}

- (void)updateDownloadsButton {
    BOOL active = self.activeDownloads.count > 0;
    self.downloadsButton.toolTip = active
        ? [NSString stringWithFormat:@"%lu download%@ active",
           (unsigned long)self.activeDownloads.count,
           self.activeDownloads.count == 1 ? @"" : @"s"]
        : @"Downloads";
    if ([self.downloadsButton isKindOfClass:TBFlatButton.class]) {
        ((TBFlatButton *)self.downloadsButton).active = active;
    }
    if (@available(macOS 11.0, *)) {
        NSString *symbol = active ? @"arrow.down.circle.fill" : @"arrow.down.circle";
        NSImage *image = [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:self.downloadsButton.toolTip];
        image.template = YES;
        self.downloadsButton.image = image;
    }
    if (@available(macOS 10.14, *)) {
        self.downloadsButton.contentTintColor = active ? TBAccent() : TBMuted();
    }
}

- (NSTextField *)popoverLabelWithString:(NSString *)string
                                   font:(NSFont *)font
                                  color:(NSColor *)color {
    NSTextField *label = [NSTextField labelWithString:string ?: @""];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.font = font;
    label.textColor = color;
    label.lineBreakMode = NSLineBreakByTruncatingTail;
    label.maximumNumberOfLines = 1;
    return label;
}

- (NSButton *)popoverButtonWithTitle:(NSString *)title action:(SEL)action {
    TBFlatButton *button = [[TBFlatButton alloc] initWithFrame:NSZeroRect];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    button.cornerRadius = 7.0;
    button.target = self;
    button.action = action;
    button.bordered = NO;
    button.attributedTitle = [[NSAttributedString alloc] initWithString:title attributes:@{
        NSFontAttributeName: [NSFont systemFontOfSize:12.0 weight:NSFontWeightSemibold],
        NSForegroundColorAttributeName: TBText()
    }];
    [button.heightAnchor constraintEqualToConstant:28.0].active = YES;
    return button;
}

- (NSView *)downloadPopoverRowForEntry:(NSDictionary<NSString *, id> *)entry {
    NSView *row = [[NSView alloc] initWithFrame:NSZeroRect];
    row.translatesAutoresizingMaskIntoConstraints = NO;

    NSString *downloadID = [entry[@"id"] isKindOfClass:NSString.class] ? entry[@"id"] : @"";
    NSString *filename = [entry[@"filename"] isKindOfClass:NSString.class] ? entry[@"filename"] : @"download";
    NSString *path = [entry[@"path"] isKindOfClass:NSString.class] ? entry[@"path"] : @"";
    NSString *status = [entry[@"status"] isKindOfClass:NSString.class] ? entry[@"status"] : @"";
    BOOL active = [entry[@"active"] respondsToSelector:@selector(boolValue)] && [entry[@"active"] boolValue];
    NSString *resumeDataPath = [entry[@"resumeDataPath"] isKindOfClass:NSString.class] ? entry[@"resumeDataPath"] : @"";
    BOOL canResume = downloadID.length > 0 && resumeDataPath.length > 0;
    NSString *detail = @"";
    if (active) {
        detail = [entry[@"progressText"] isKindOfClass:NSString.class] ? entry[@"progressText"] : @"Downloading";
    } else if ([status isEqualToString:@"failed"] || [status isEqualToString:@"canceled"]) {
        detail = [entry[@"error"] isKindOfClass:NSString.class] ? entry[@"error"] : ([status isEqualToString:@"canceled"] ? @"Canceled" : @"Download failed");
    } else {
        detail = path.length ? path.stringByAbbreviatingWithTildeInPath : status;
    }

    NSTextField *title = [self popoverLabelWithString:filename
                                                 font:[NSFont systemFontOfSize:12.5 weight:NSFontWeightMedium]
                                                color:TBText()];
    [row addSubview:title];

    NSTextField *subtitle = [self popoverLabelWithString:detail
                                                    font:[NSFont systemFontOfSize:11.0 weight:NSFontWeightRegular]
                                                   color:TBFaint()];
    [row addSubview:subtitle];

    NSStackView *actions = [[NSStackView alloc] initWithFrame:NSZeroRect];
    actions.translatesAutoresizingMaskIntoConstraints = NO;
    actions.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    actions.alignment = NSLayoutAttributeCenterY;
    actions.distribution = NSStackViewDistributionFill;
    actions.spacing = 6.0;
    [row addSubview:actions];

    if (active) {
        NSButton *cancel = [self popoverButtonWithTitle:@"Cancel" action:@selector(cancelDownloadFromPopover:)];
        cancel.identifier = downloadID;
        cancel.enabled = ![status isEqualToString:@"canceling"];
        [actions addArrangedSubview:cancel];
        [cancel.widthAnchor constraintEqualToConstant:68.0].active = YES;
    } else if (canResume) {
        NSButton *resume = [self popoverButtonWithTitle:@"Resume" action:@selector(resumeDownloadFromPopover:)];
        resume.identifier = downloadID;
        [actions addArrangedSubview:resume];
        [resume.widthAnchor constraintEqualToConstant:68.0].active = YES;
    } else {
        NSButton *reveal = [self popoverButtonWithTitle:@"Reveal" action:@selector(revealDownloadFromPopover:)];
        reveal.identifier = path;
        reveal.enabled = path.length > 0 && [status isEqualToString:@"complete"];
        [actions addArrangedSubview:reveal];
        [reveal.widthAnchor constraintEqualToConstant:64.0].active = YES;
    }

    NSProgressIndicator *progress = nil;
    if (active) {
        progress = [[NSProgressIndicator alloc] initWithFrame:NSZeroRect];
        progress.translatesAutoresizingMaskIntoConstraints = NO;
        progress.style = NSProgressIndicatorStyleBar;
        progress.controlSize = NSControlSizeSmall;
        progress.minValue = 0.0;
        progress.maxValue = 1.0;
        progress.indeterminate = [entry[@"progressIndeterminate"] respondsToSelector:@selector(boolValue)] &&
                                 [entry[@"progressIndeterminate"] boolValue];
        if (!progress.indeterminate && [entry[@"progress"] respondsToSelector:@selector(doubleValue)]) {
            progress.doubleValue = [entry[@"progress"] doubleValue];
        } else {
            [progress startAnimation:nil];
        }
        [row addSubview:progress];
    }

    NSMutableArray<NSLayoutConstraint *> *constraints = [@[
        [row.heightAnchor constraintEqualToConstant:active ? 62.0 : 50.0],
        [title.leadingAnchor constraintEqualToAnchor:row.leadingAnchor],
        [title.trailingAnchor constraintEqualToAnchor:actions.leadingAnchor constant:-10.0],
        [title.topAnchor constraintEqualToAnchor:row.topAnchor constant:7.0],
        [subtitle.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [subtitle.trailingAnchor constraintEqualToAnchor:title.trailingAnchor],
        [subtitle.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:2.0],
        [actions.trailingAnchor constraintEqualToAnchor:row.trailingAnchor],
        [actions.centerYAnchor constraintEqualToAnchor:row.centerYAnchor]
    ] mutableCopy];
    if (progress) {
        [constraints addObjectsFromArray:@[
            [progress.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
            [progress.trailingAnchor constraintEqualToAnchor:title.trailingAnchor],
            [progress.topAnchor constraintEqualToAnchor:subtitle.bottomAnchor constant:6.0],
            [progress.heightAnchor constraintEqualToConstant:3.0]
        ]];
    }
    [NSLayoutConstraint activateConstraints:constraints];

    return row;
}

- (NSView *)downloadsPopoverContentView {
    NSView *content = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 360, 320)];
    content.translatesAutoresizingMaskIntoConstraints = NO;
    content.wantsLayer = YES;
    content.layer.backgroundColor = TBSurface().CGColor;

    NSTextField *title = [self popoverLabelWithString:@"Downloads"
                                                 font:[NSFont systemFontOfSize:14.0 weight:NSFontWeightSemibold]
                                                color:TBText()];
    [content addSubview:title];

    NSString *activeText = self.activeDownloads.count > 0
        ? [NSString stringWithFormat:@"%lu active", (unsigned long)self.activeDownloads.count]
        : @"Recent files";
    NSTextField *status = [self popoverLabelWithString:activeText
                                                  font:[NSFont systemFontOfSize:11.0 weight:NSFontWeightMedium]
                                                 color:self.activeDownloads.count > 0 ? TBAccent() : TBFaint()];
    status.alignment = NSTextAlignmentRight;
    [content addSubview:status];

    NSStackView *stack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.distribution = NSStackViewDistributionFill;
    stack.spacing = 4.0;
    [content addSubview:stack];

    NSArray<NSDictionary<NSString *, id> *> *downloads = [self recentDownloadEntriesLimitedTo:5];
    if (downloads.count == 0) {
        NSTextField *empty = [self popoverLabelWithString:@"No downloads yet."
                                                     font:[NSFont systemFontOfSize:12.0 weight:NSFontWeightRegular]
                                                    color:TBFaint()];
        [stack addArrangedSubview:empty];
        [empty.widthAnchor constraintEqualToConstant:326.0].active = YES;
        [empty.heightAnchor constraintEqualToConstant:44.0].active = YES;
    } else {
        for (NSDictionary<NSString *, id> *entry in downloads) {
            NSView *row = [self downloadPopoverRowForEntry:entry];
            [stack addArrangedSubview:row];
            [row.widthAnchor constraintEqualToConstant:326.0].active = YES;
        }
    }

    NSButton *openSettings = [self popoverButtonWithTitle:@"Open Downloads" action:@selector(openDownloadsSettings:)];
    [content addSubview:openSettings];

    [NSLayoutConstraint activateConstraints:@[
        [content.widthAnchor constraintEqualToConstant:360.0],
        [content.heightAnchor constraintEqualToConstant:320.0],
        [title.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:16.0],
        [title.topAnchor constraintEqualToAnchor:content.topAnchor constant:14.0],
        [status.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-16.0],
        [status.centerYAnchor constraintEqualToAnchor:title.centerYAnchor],
        [status.leadingAnchor constraintGreaterThanOrEqualToAnchor:title.trailingAnchor constant:12.0],
        [stack.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:16.0],
        [stack.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-16.0],
        [stack.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:12.0],
        [openSettings.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:16.0],
        [openSettings.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-16.0],
        [openSettings.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-12.0],
        [stack.bottomAnchor constraintLessThanOrEqualToAnchor:openSettings.topAnchor constant:-10.0]
    ]];

    return content;
}

- (void)showDownloadsPopover:(id)sender {
    (void)sender;
    if (self.downloadsPopover.shown) {
        [self.downloadsPopover close];
        return;
    }

    NSPopover *popover = [[NSPopover alloc] init];
    popover.behavior = NSPopoverBehaviorTransient;
    popover.animates = YES;
    NSViewController *controller = [[NSViewController alloc] init];
    controller.view = [self downloadsPopoverContentView];
    popover.contentViewController = controller;
    self.downloadsPopover = popover;
    [popover showRelativeToRect:self.downloadsButton.bounds
                         ofView:self.downloadsButton
                  preferredEdge:NSMinYEdge];
}

- (void)revealDownloadFromPopover:(id)sender {
    NSString *path = [sender respondsToSelector:@selector(identifier)] ? [sender identifier] : @"";
    [self revealDownloadAtPath:path];
}

- (void)cancelDownloadFromPopover:(id)sender {
    NSString *downloadID = [sender respondsToSelector:@selector(identifier)] ? [sender identifier] : @"";
    [self cancelDownloadWithID:downloadID];
}

- (void)resumeDownloadFromPopover:(id)sender {
    NSString *downloadID = [sender respondsToSelector:@selector(identifier)] ? [sender identifier] : @"";
    [self resumeDownloadWithID:downloadID];
}

- (void)openDownloadsSettings:(id)sender {
    (void)sender;
    [self.downloadsPopover close];
    [self openSettings:nil];
}

- (void)updateBookmarkButton {
    NSString *urlString = [self bookmarkURLStringForCurrentPage];
    BOOL bookmarkable = urlString.length > 0;
    BOOL bookmarked = bookmarkable && [self isURLStringBookmarked:urlString];
    self.bookmarkButton.enabled = bookmarkable;
    self.bookmarkButton.toolTip = bookmarked ? @"Remove bookmark" : @"Bookmark this page";
    if ([self.bookmarkButton isKindOfClass:TBFlatButton.class]) {
        ((TBFlatButton *)self.bookmarkButton).active = NO;
    }
    if (@available(macOS 11.0, *)) {
        NSString *symbol = bookmarked ? @"star.fill" : @"star";
        NSImage *image = [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:self.bookmarkButton.toolTip];
        image.template = YES;
        self.bookmarkButton.image = image;
    }
    if (@available(macOS 10.14, *)) {
        self.bookmarkButton.contentTintColor = bookmarked ? TBAccent() : TBMuted();
    }
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
        if (!self.restoringSession) [self writeBrowserStateRunning:YES];
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

- (NSString *)safeFilenameFromString:(NSString *)string fallback:(NSString *)fallback extension:(NSString *)extension {
    NSString *name = [string stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (name.length == 0) name = fallback.length ? fallback : @"Page";
    NSCharacterSet *bad = [NSCharacterSet characterSetWithCharactersInString:@"/:\\?%*|\"<>"];
    name = [[name componentsSeparatedByCharactersInSet:bad] componentsJoinedByString:@"-"];
    name = [name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (name.length == 0) name = fallback.length ? fallback : @"Page";
    if (extension.length == 0) return name;
    return [[name stringByDeletingPathExtension] stringByAppendingPathExtension:extension];
}

- (void)openFile:(id)sender {
    (void)sender;
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseFiles = YES;
    panel.canChooseDirectories = NO;
    panel.allowsMultipleSelection = YES;
    panel.title = @"Open File";
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
        if (result != NSModalResponseOK) return;
        NSArray<NSURL *> *urls = panel.URLs;
        BOOL privateBrowsing = [self activeTab].privateBrowsing;
        for (NSUInteger i = 0; i < urls.count; i++) {
            if (privateBrowsing) {
                [self newPrivateTabWithURLString:urls[i].absoluteString select:(i == urls.count - 1)];
            } else {
                [self newTabWithURLString:urls[i].absoluteString select:(i == urls.count - 1)];
            }
        }
    }];
}

- (void)printPage:(id)sender {
    (void)sender;
    if (!self.webView) {
        NSBeep();
        return;
    }
    if (@available(macOS 11.0, *)) {
        NSPrintOperation *operation = [self.webView printOperationWithPrintInfo:NSPrintInfo.sharedPrintInfo];
        [operation runOperationModalForWindow:self.window
                                     delegate:nil
                               didRunSelector:nil
                                  contextInfo:NULL];
    } else {
        NSPrintOperation *operation = [NSPrintOperation printOperationWithView:self.webView
                                                                     printInfo:NSPrintInfo.sharedPrintInfo];
        [operation runOperationModalForWindow:self.window
                                     delegate:nil
                               didRunSelector:nil
                                  contextInfo:NULL];
    }
}

- (void)exportPageAsPDF:(id)sender {
    (void)sender;
    if (!self.webView) {
        NSBeep();
        return;
    }

    BrowserTab *tab = [self activeTab];
    NSString *filename = [self safeFilenameFromString:(tab.title ?: self.webView.title)
                                             fallback:@"TrailBrowser Page"
                                            extension:@"pdf"];
    NSSavePanel *panel = [NSSavePanel savePanel];
    panel.title = @"Save Page as PDF";
    panel.nameFieldStringValue = filename;
    if (@available(macOS 11.0, *)) panel.allowedContentTypes = @[ UTTypePDF ];
    panel.canCreateDirectories = YES;

    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
        if (result != NSModalResponseOK || !panel.URL) return;
        NSURL *destination = panel.URL;
        void (^writePDF)(NSData *) = ^(NSData *data) {
            NSError *error = nil;
            if (![data writeToURL:destination options:NSDataWritingAtomic error:&error]) {
                [self setStatusText:error.localizedDescription ?: @"Could not save PDF"];
                NSBeep();
                return;
            }
            [self setStatusText:@"Saved PDF"];
        };

        if (@available(macOS 11.0, *)) {
            [self.webView createPDFWithConfiguration:nil completionHandler:^(NSData *pdfDocumentData, NSError *error) {
                if (!pdfDocumentData || error) {
                    [self setStatusText:error.localizedDescription ?: @"Could not create PDF"];
                    NSBeep();
                    return;
                }
                writePDF(pdfDocumentData);
            }];
        } else {
            NSData *data = [self.webView dataWithPDFInsideRect:self.webView.bounds];
            writePDF(data ?: [NSData data]);
        }
    }];
}

- (NSString *)sourceViewerHTMLForURLString:(NSString *)urlString source:(NSString *)source {
    NSString *escapedURL = [self htmlEscaped:urlString ?: @""];
    NSString *escapedSource = [self htmlEscaped:source ?: @""];
    NSString *scheme = TBThemeIsDark() ? @"dark" : @"light";
    NSString *background = TBThemeIsDark() ? @"#0a0a0b" : @"#f7eef4";
    NSString *surface = TBThemeIsDark() ? @"#161618" : @"#fffafd";
    NSString *text = TBThemeIsDark() ? @"#f3f3f4" : @"#17141a";
    NSString *muted = TBThemeIsDark() ? @"#8a8a90" : @"#625d6a";
    NSString *border = TBThemeIsDark() ? @"rgba(255,255,255,.09)" : @"rgba(30,24,38,.1)";
    return [NSString stringWithFormat:
        @"<!doctype html><html><head><meta charset='utf-8'>"
         "<title>View Source</title><style>"
         ":root{color-scheme:%@}*{box-sizing:border-box}"
         "body{margin:0;background:%@;color:%@;"
         "font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;font-size:12px;line-height:1.55}"
         "header{position:sticky;top:0;padding:12px 18px;background:%@;border-bottom:1px solid %@}"
         "h1{margin:0 0 3px;font:600 13px -apple-system,BlinkMacSystemFont,'SF Pro Display',sans-serif}"
         "p{margin:0;color:%@;font:12px -apple-system,BlinkMacSystemFont,'SF Pro Display',sans-serif;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}"
         "pre{margin:0;padding:18px;white-space:pre-wrap;word-break:break-word}"
         "</style></head><body><header><h1>View Source</h1><p>%@</p></header><pre>%@</pre></body></html>",
        scheme, background, text, surface, border, muted, escapedURL, escapedSource];
}

- (void)viewSource:(id)sender {
    (void)sender;
    if (!self.webView) {
        NSBeep();
        return;
    }

    NSString *urlString = self.webView.URL.absoluteString ?: [self activeTab].urlString ?: @"";
    NSString *script = @"document.documentElement ? document.documentElement.outerHTML : ''";
    [self.webView evaluateJavaScript:script completionHandler:^(id result, NSError *error) {
        if (error) {
            [self setStatusText:error.localizedDescription ?: @"Could not read source"];
            NSBeep();
            return;
        }
        NSString *source = [result isKindOfClass:NSString.class] ? result : @"";
        BOOL privateBrowsing = [self activeTab].privateBrowsing;
        BrowserTab *tab = privateBrowsing
            ? [self newPrivateTabWithURLString:@"" select:YES]
            : [self newTabWithURLString:@"" select:YES];
        tab.title = @"View Source";
        tab.urlString = urlString.length ? [@"view-source:" stringByAppendingString:urlString] : @"view-source:";
        tab.favicon = nil;
        [tab.webView loadHTMLString:[self sourceViewerHTMLForURLString:urlString source:source] baseURL:nil];
        [self syncAddressBarWithWebView];
        [self reloadSidebarRowForTab:tab];
        [self writeBrowserStateRunning:YES];
    }];
}

- (CGFloat)currentPageZoom {
    if (!self.webView) return 1.0;
    if (@available(macOS 11.0, *)) {
        return self.webView.pageZoom > 0 ? self.webView.pageZoom : 1.0;
    }
    return self.webView.magnification > 0 ? self.webView.magnification : 1.0;
}

- (void)setPageZoom:(CGFloat)zoom {
    if (!self.webView) return;
    CGFloat bounded = MIN(MAX(zoom, 0.5), 3.0);
    if (@available(macOS 11.0, *)) {
        self.webView.pageZoom = bounded;
    } else {
        self.webView.allowsMagnification = YES;
        self.webView.magnification = bounded;
    }
    [self setStatusText:[NSString stringWithFormat:@"Zoom %.0f%%", bounded * 100.0]];
}

- (void)zoomIn:(id)sender {
    (void)sender;
    [self setPageZoom:[self currentPageZoom] + 0.1];
}

- (void)zoomOut:(id)sender {
    (void)sender;
    [self setPageZoom:[self currentPageZoom] - 0.1];
}

- (void)resetPageZoom:(id)sender {
    (void)sender;
    [self setPageZoom:1.0];
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
        [self updateAddressSuggestions];
    }
}

- (void)controlTextDidChange:(NSNotification *)notification {
    if (notification.object == self.addressField) {
        [self updateAddressSuggestions];
        return;
    }
    if (notification.object == self.findField) {
        [self runFindBackwards:NO];
    }
}

- (void)controlTextDidEndEditing:(NSNotification *)notification {
    if (notification.object == self.addressField) {
        self.userEditingAddress = NO;
        self.addressContainer.focused = NO;
        [self.addressContainer setNeedsDisplay:YES];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (![self isAddressFieldBeingEdited]) [self hideAddressSuggestionsPanel];
        });
    }
}

- (BOOL)control:(NSControl *)control
       textView:(NSTextView *)textView
doCommandBySelector:(SEL)commandSelector {
    (void)textView;
    if (control == self.findField) {
        if (commandSelector == @selector(cancelOperation:)) {
            [self closeFindBar:nil];
            return YES;
        }
        if (commandSelector == @selector(insertNewline:)) {
            [self findNext:nil];
            return YES;
        }
        return NO;
    }

    if (control != self.addressField) return NO;

    if (commandSelector == @selector(moveDown:)) {
        [self moveAddressSuggestionSelectionBy:1];
        return YES;
    }
    if (commandSelector == @selector(moveUp:)) {
        [self moveAddressSuggestionSelectionBy:-1];
        return YES;
    }
    if (commandSelector == @selector(cancelOperation:)) {
        [self hideAddressSuggestionsPanel];
        return YES;
    }
    if (commandSelector == @selector(insertNewline:)) {
        if (self.addressSuggestionIndex >= 0 &&
            self.addressSuggestionIndex < (NSInteger)self.addressSuggestions.count) {
            [self acceptAddressSuggestionAtIndex:self.addressSuggestionIndex];
            return YES;
        }
        [self hideAddressSuggestionsPanel];
        return NO;
    }

    return NO;
}

#pragma mark - Page assistant

- (void)assistantModeChanged:(id)sender {
    (void)sender;
    [self closeAssistantResult:nil];
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

#pragma mark - AI form autofill

- (void)updateAutofillButton {
    BOOL show = self.pageHasFillableForms && self.webView && [self isHTTPURL:self.webView.URL];
    self.autofillButton.hidden = !show;
    self.autofillButtonWidthConstraint.constant = show ? 72.0 : 0.0;
    self.autofillButton.enabled = show && !self.formAutofillInProgress;
    self.autofillButton.title = self.formAutofillInProgress ? @"Filling" : @"Fill AI";
    self.autofillButton.toolTip = show
        ? @"Autofill this form with AI"
        : @"AI autofill appears on pages with forms";
}

- (NSString *)fillableFormDetectionScript {
    return
        @"(() => {"
         "const blocked = /^(hidden|password|file|submit|button|reset|image)$/i;"
         "const visible = (el) => {"
         "const r = el.getBoundingClientRect();"
         "const s = getComputedStyle(el);"
         "return r.width > 0 && r.height > 0 && s.display !== 'none' && s.visibility !== 'hidden' && !el.disabled && !el.readOnly;"
         "};"
         "const hostedFormURL = () => {"
         "const patterns = [/airtable\\.com\\/embed\\/.*\\/form/i,/airtable\\.com\\/.*\\/form/i,/typeform\\.com\\//i,/tally\\.so\\//i,/forms\\.gle\\//i,/docs\\.google\\.com\\/forms\\//i,/form\\.jotform\\.com\\//i];"
         "for (const frame of Array.from(document.querySelectorAll('iframe[src]'))) {"
         "if (!visible(frame)) continue;"
         "let href = '';"
         "try { href = new URL(frame.getAttribute('src') || '', location.href).href; } catch (_) {}"
         "if (href && patterns.some((pattern) => pattern.test(href))) return href;"
         "}"
         "return '';"
         "};"
         "const hasDirectFields = Array.from(document.querySelectorAll('input,textarea,select,[contenteditable=\"true\"],[role=\"textbox\"]')).some((el) => {"
         "const type = (el.getAttribute('type') || el.tagName || '').toLowerCase();"
         "return !blocked.test(type) && visible(el);"
         "});"
         "return hasDirectFields || hostedFormURL().length > 0;"
         "})()";
}

- (NSString *)embeddedFormURLScript {
    return
        @"(() => {"
         "const visible = (el) => {"
         "const r = el.getBoundingClientRect();"
         "const s = getComputedStyle(el);"
         "return r.width > 0 && r.height > 0 && s.display !== 'none' && s.visibility !== 'hidden';"
         "};"
         "const patterns = [/airtable\\.com\\/embed\\/.*\\/form/i,/airtable\\.com\\/.*\\/form/i,/typeform\\.com\\//i,/tally\\.so\\//i,/forms\\.gle\\//i,/docs\\.google\\.com\\/forms\\//i,/form\\.jotform\\.com\\//i];"
         "for (const frame of Array.from(document.querySelectorAll('iframe[src]'))) {"
         "if (!visible(frame)) continue;"
         "let href = '';"
         "try { href = new URL(frame.getAttribute('src') || '', location.href).href; } catch (_) {}"
         "if (href && patterns.some((pattern) => pattern.test(href))) return href;"
         "}"
         "return '';"
         "})()";
}

- (void)embeddedFormURLWithCompletion:(void (^)(NSString *urlString))completion {
    if (!self.webView) {
        completion(@"");
        return;
    }

    [self.webView evaluateJavaScript:[self embeddedFormURLScript]
                   completionHandler:^(id result, NSError *error) {
        if (error || ![result isKindOfClass:NSString.class]) {
            completion(@"");
            return;
        }
        completion((NSString *)result);
    }];
}

- (BOOL)URLLooksLikeHostedForm:(NSURL *)url {
    NSString *value = url.absoluteString.lowercaseString ?: @"";
    if (value.length == 0) return NO;
    return ([value containsString:@"airtable.com/"] && [value containsString:@"/form"]) ||
           [value containsString:@"typeform.com/"] ||
           [value containsString:@"tally.so/"] ||
           [value containsString:@"forms.gle/"] ||
           [value containsString:@"docs.google.com/forms/"] ||
           [value containsString:@"form.jotform.com/"];
}

- (void)detectFillableFormsForWebView:(WKWebView *)webView {
    if (!webView || webView != self.webView || ![self isHTTPURL:webView.URL]) {
        self.pageHasFillableForms = NO;
        [self updateAutofillButton];
        return;
    }

    [webView evaluateJavaScript:[self fillableFormDetectionScript]
              completionHandler:^(id result, NSError *error) {
        if (webView != self.webView) return;
        BOOL hasForms = !error && [result respondsToSelector:@selector(boolValue)] && [result boolValue];
        self.pageHasFillableForms = hasForms;
        [self updateAutofillButton];
    }];
}

- (void)scheduleFormDetectionForWebView:(WKWebView *)webView {
    if (!webView || webView != self.webView) return;
    [self detectFillableFormsForWebView:webView];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self detectFillableFormsForWebView:webView];
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self detectFillableFormsForWebView:webView];
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self detectFillableFormsForWebView:webView];
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(7.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self detectFillableFormsForWebView:webView];
    });
}

- (nullable NSString *)promptForAutofillInstructions {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.alertStyle = NSAlertStyleInformational;
    alert.messageText = @"Autofill this form with AI";
    alert.informativeText =
        @"TrailBrowser will send form labels, placeholders, page context, and your instructions "
         "to the selected AI CLI. Existing field values, cookies, passwords, payment fields, "
         "and hidden fields are not sent.";
    [alert addButtonWithTitle:@"Autofill"];
    [alert addButtonWithTitle:@"Cancel"];

    NSTextField *field = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 420, 28)];
    field.placeholderString = @"What should AI use for this form?";
    field.stringValue = @"";
    alert.accessoryView = field;

    NSModalResponse response = [alert runModal];
    if (response != NSAlertFirstButtonReturn) return nil;
    return [field.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
}

- (void)setAutofillWorking:(BOOL)working {
    self.formAutofillInProgress = working;
    [self updateAutofillButton];
    [self setStatusText:working ? @"Autofilling form with AI" : @"Ready"];
}

- (void)formSnapshotWithCompletion:(void (^)(NSString *snapshot, NSError *error))completion {
    NSString *script =
        @"(() => {"
         "const clip = (value, limit) => String(value || '').replace(/\\s+/g, ' ').trim().slice(0, limit);"
         "const blocked = /^(hidden|password|file|submit|button|reset|image)$/i;"
         "const sensitive = /(password|passcode|otp|one.?time|2fa|mfa|credit|card|cvv|cvc|ssn|social security|bank|routing|account|passport|secret|token|api.?key|private.?key)/i;"
         "const visible = (el) => {"
         "const r = el.getBoundingClientRect();"
         "const s = getComputedStyle(el);"
         "return r.width > 0 && r.height > 0 && s.display !== 'none' && s.visibility !== 'hidden' && !el.disabled && !el.readOnly;"
         "};"
         "const labels = Array.from(document.querySelectorAll('label'));"
         "const labelFor = (el) => {"
         "const pieces = [];"
         "const ariaLabel = el.getAttribute('aria-label'); if (ariaLabel) pieces.push(ariaLabel);"
         "if (el.id) { const exact = labels.find((label) => label.htmlFor === el.id); if (exact) pieces.push(exact.innerText); }"
         "const parentLabel = el.closest('label'); if (parentLabel) pieces.push(parentLabel.innerText);"
         "const describedBy = (el.getAttribute('aria-describedby') || '').split(/\\s+/).filter(Boolean)"
         ".map((id) => document.getElementById(id)?.innerText).filter(Boolean).join(' ');"
         "if (describedBy) pieces.push(describedBy);"
         "return clip(pieces.filter(Boolean).join(' '), 180);"
         "};"
         "const contextFor = (el) => {"
         "const form = el.closest('form,fieldset,section,article,main') || el.parentElement;"
         "if (!form) return '';"
         "const clone = form.cloneNode(true);"
         "clone.querySelectorAll('script,style,noscript,iframe,svg,img,input,textarea,select,button,[contenteditable=\"true\"],[role=\"textbox\"]').forEach((node) => node.remove());"
         "return clip(clone.innerText, 600);"
         "};"
         "let seq = window.__trailbrowserAutofillSeq || 1;"
         "const fields = [];"
         "for (const el of Array.from(document.querySelectorAll('input,textarea,select,[contenteditable=\"true\"],[role=\"textbox\"]'))) {"
         "const tag = el.tagName.toLowerCase();"
         "const type = tag === 'input' ? (el.getAttribute('type') || 'text').toLowerCase() : (el.getAttribute('role') || (el.isContentEditable ? 'contenteditable' : tag)).toLowerCase();"
         "const label = labelFor(el);"
         "const identity = [label, el.getAttribute('aria-label'), el.name, el.id, el.getAttribute('placeholder'), el.autocomplete, type].join(' ');"
         "if (blocked.test(type) || sensitive.test(identity) || !visible(el)) continue;"
         "if (!el.dataset.trailbrowserAutofillId) el.dataset.trailbrowserAutofillId = String(seq++);"
         "const options = tag === 'select'"
         "? Array.from(el.options).slice(0, 80).map((option) => ({ value: option.value, text: clip(option.textContent, 120) }))"
         ": [];"
         "fields.push({"
         "id: el.dataset.trailbrowserAutofillId,"
         "tag, type,"
         "label,"
         "name: clip(el.getAttribute('name') || el.name, 120),"
         "domId: clip(el.id, 120),"
         "ariaLabel: clip(el.getAttribute('aria-label'), 160),"
         "placeholder: clip(el.getAttribute('placeholder') || el.placeholder, 160),"
         "autocomplete: clip(el.getAttribute('autocomplete') || el.autocomplete, 80),"
         "required: !!el.required,"
         "maxLength: Number(el.maxLength || 0),"
         "options,"
         "nearbyText: contextFor(el)"
         "});"
         "}"
         "window.__trailbrowserAutofillSeq = seq;"
         "return JSON.stringify({"
         "url: location.href,"
         "title: document.title,"
         "headings: clip(Array.from(document.querySelectorAll('h1,h2,h3')).map((node) => node.innerText).filter(Boolean).join('\\n'), 1800),"
         "fields"
         "});"
         "})()";

    [self.webView evaluateJavaScript:script completionHandler:^(id result, NSError *error) {
        if (error) {
            completion(nil, error);
            return;
        }
        if (![result isKindOfClass:NSString.class]) {
            completion(nil, [self assistantErrorWithMessage:@"Could not inspect this form."]);
            return;
        }
        completion(result, nil);
    }];
}

- (NSString *)autofillPromptForInstructions:(NSString *)instructions snapshot:(NSString *)snapshot {
    return [NSString stringWithFormat:
            @"You are TrailBrowser's AI form autofill assistant.\n"
             "Return strict JSON only. No markdown, no explanation.\n"
             "Schema: {\"fields\":[{\"id\":string,\"value\":string|boolean}],\"summary\":string|null}.\n"
             "Use only the supplied form metadata, page context, and user instructions.\n"
             "Do not submit the form, navigate, fetch URLs, or request cookies/storage.\n"
             "Do not invent private personal data. If the user did not provide a real name, email, phone, address, payment, account, or identifier, skip that field.\n"
             "Never fill passwords, OTPs, payment cards, banking, SSN, passport, secrets, API keys, hidden fields, or file uploads. Those fields should already be excluded; skip anything that still looks sensitive.\n"
             "For select/radio fields, use an exact option value from the field's options when possible.\n"
             "For checkboxes, return true only when the user instruction or page context clearly says it should be checked.\n"
             "Keep answers concise and valid for field maxlengths.\n\n"
             "User instructions:\n%@\n\n"
             "Form snapshot JSON:\n%@\n",
            instructions.length ? instructions : @"Use visible page context only. Skip personal fields unless the value is obvious from context.",
            snapshot ?: @"{}"];
}

- (NSArray<NSDictionary<NSString *, id> *> *)autofillFieldsFromAIOutput:(NSString *)output {
    id parsed = [self JSONObjectFromAIOutput:output ?: @""];
    NSArray *rawFields = nil;
    if ([parsed isKindOfClass:NSDictionary.class]) {
        id fields = ((NSDictionary *)parsed)[@"fields"];
        if ([fields isKindOfClass:NSArray.class]) rawFields = fields;
    } else if ([parsed isKindOfClass:NSArray.class]) {
        rawFields = parsed;
    }

    NSMutableArray<NSDictionary<NSString *, id> *> *fields = [NSMutableArray array];
    for (id item in rawFields ?: @[]) {
        if (![item isKindOfClass:NSDictionary.class]) continue;
        NSDictionary *field = item;
        NSString *fieldID = [field[@"id"] isKindOfClass:NSString.class] ? field[@"id"] : @"";
        id value = field[@"value"];
        if (fieldID.length == 0 || value == nil || value == [NSNull null]) continue;
        if (![value isKindOfClass:NSString.class] && ![value isKindOfClass:NSNumber.class]) continue;
        [fields addObject:@{ @"id": fieldID, @"value": value }];
    }
    return fields;
}

- (NSString *)scriptForApplyingAutofillFields:(NSArray<NSDictionary<NSString *, id> *> *)fields {
    NSData *data = [NSJSONSerialization dataWithJSONObject:fields ?: @[] options:0 error:nil];
    NSString *json = [[NSString alloc] initWithData:data ?: [NSData data] encoding:NSUTF8StringEncoding] ?: @"[]";
    NSString *literal = [self javaScriptStringLiteralForString:json];
    return [NSString stringWithFormat:
            @"(() => {"
             "const fields = JSON.parse(%@);"
             "const truthy = (value) => /^(1|true|yes|on|checked)$/i.test(String(value));"
             "const eventOptions = { bubbles: true };"
             "let filled = 0;"
             "for (const field of fields) {"
             "const id = String(field.id || '');"
             "const candidates = Array.from(document.querySelectorAll('[data-trailbrowser-autofill-id]'));"
             "const el = candidates.find((node) => node.dataset.trailbrowserAutofillId === id);"
             "if (!el || el.disabled || el.readOnly) continue;"
             "const tag = el.tagName.toLowerCase();"
             "const type = (el.getAttribute('type') || '').toLowerCase();"
             "const value = field.value;"
             "if (type === 'checkbox') {"
             "el.checked = truthy(value);"
             "} else if (type === 'radio') {"
             "if (truthy(value) || String(value) === String(el.value)) el.checked = true;"
             "} else if (tag === 'select') {"
             "const options = Array.from(el.options);"
             "const match = options.find((option) => String(option.value) === String(value)) ||"
             "options.find((option) => option.textContent.trim().toLowerCase() === String(value).trim().toLowerCase());"
             "if (!match) continue;"
             "el.value = match.value;"
             "} else if (el.isContentEditable || el.getAttribute('role') === 'textbox') {"
             "el.focus();"
             "el.textContent = String(value);"
             "} else {"
             "el.value = String(value);"
             "}"
             "el.dispatchEvent(new Event('input', eventOptions));"
             "el.dispatchEvent(new Event('change', eventOptions));"
             "el.style.transition = 'box-shadow 180ms ease, outline-color 180ms ease';"
             "el.style.outline = '2px solid rgba(236,107,91,.72)';"
             "el.style.boxShadow = '0 0 0 4px rgba(236,107,91,.16)';"
             "window.setTimeout(() => { el.style.outline = ''; el.style.boxShadow = ''; }, 1200);"
             "filled += 1;"
             "}"
             "return filled;"
             "})()",
            literal];
}

- (BOOL)requestLooksLikeFormAutofill:(NSString *)request {
    NSString *lower = request.lowercaseString ?: @"";
    BOOL mentionsFill = [lower containsString:@"autofill"] ||
                        [lower containsString:@"auto fill"] ||
                        [lower containsString:@"fill this"] ||
                        [lower containsString:@"fill the"] ||
                        [lower containsString:@"fill form"] ||
                        [lower isEqualToString:@"fill"];
    BOOL mentionsForm = [lower containsString:@"form"] ||
                        [lower containsString:@"field"] ||
                        [lower containsString:@"application"] ||
                        [lower containsString:@"apply"];
    return mentionsFill && mentionsForm;
}

- (void)autofillFormsWithInstructions:(NSString *)instructions promptIfEmpty:(BOOL)promptIfEmpty {
    [self autofillFormsWithInstructions:instructions promptIfEmpty:promptIfEmpty retryCount:0];
}

- (void)autofillFormsWithInstructions:(NSString *)instructions
                        promptIfEmpty:(BOOL)promptIfEmpty
                            retryCount:(NSInteger)retryCount {
    if (self.formAutofillInProgress && retryCount == 0) return;
    if (!self.webView || ![self isHTTPURL:self.webView.URL]) {
        NSBeep();
        return;
    }

    NSString *trimmedInstructions = [instructions stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
    if (promptIfEmpty || trimmedInstructions.length == 0) {
        trimmedInstructions = [self promptForAutofillInstructions];
        if (!trimmedInstructions) return;
    }

    [self setAutofillWorking:YES];
    [self formSnapshotWithCompletion:^(NSString *snapshot, NSError *snapshotError) {
        if (snapshotError) {
            [self setAutofillWorking:NO];
            [self showAssistantMessage:snapshotError.localizedDescription ?: @"Could not inspect this form."];
            return;
        }

        NSData *snapshotData = [snapshot dataUsingEncoding:NSUTF8StringEncoding];
        NSDictionary *snapshotObject = snapshotData
            ? [NSJSONSerialization JSONObjectWithData:snapshotData options:0 error:nil]
            : nil;
        NSArray *fields = [snapshotObject[@"fields"] isKindOfClass:NSArray.class] ? snapshotObject[@"fields"] : @[];
        if (fields.count == 0) {
            [self embeddedFormURLWithCompletion:^(NSString *embeddedURLString) {
                NSString *embedded = [embeddedURLString stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
                NSString *current = self.webView.URL.absoluteString ?: @"";
                if (embedded.length > 0 && ![embedded isEqualToString:current]) {
                    self.pendingAutofillInstructionsAfterNavigation = trimmedInstructions;
                    [self setAutofillWorking:NO];
                    [self setStatusText:@"Opening embedded form"];
                    [self loadURLString:embedded];
                    return;
                }

                if (retryCount < 2 && [self URLLooksLikeHostedForm:self.webView.URL]) {
                    [self setStatusText:@"Waiting for form fields"];
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                        if (!self.formAutofillInProgress) return;
                        [self autofillFormsWithInstructions:trimmedInstructions
                                              promptIfEmpty:NO
                                                  retryCount:retryCount + 1];
                    });
                    return;
                }

                self.pageHasFillableForms = NO;
                [self setAutofillWorking:NO];
                [self updateAutofillButton];
                [self showAssistantMessage:@"No safe fillable fields were found on this page."];
            }];
            return;
        }

        NSString *prompt = [self autofillPromptForInstructions:trimmedInstructions snapshot:snapshot];
        [self runAIWithPrompt:prompt enableSearch:NO effortOverride:@"low" completion:^(NSString *output, NSError *error) {
            if (error) {
                [self setAutofillWorking:NO];
                [self showAssistantMessage:error.localizedDescription ?: @"AI autofill failed."];
                return;
            }

            NSArray<NSDictionary<NSString *, id> *> *autofillFields = [self autofillFieldsFromAIOutput:output];
            if (autofillFields.count == 0) {
                [self setAutofillWorking:NO];
                [self showAssistantMessage:@"AI did not return any safe fields to fill."];
                return;
            }

            [self.webView evaluateJavaScript:[self scriptForApplyingAutofillFields:autofillFields]
                           completionHandler:^(id result, NSError *applyError) {
                [self setAutofillWorking:NO];
                if (applyError) {
                    [self showAssistantMessage:applyError.localizedDescription ?: @"Could not apply autofill values."];
                    return;
                }
                NSUInteger filled = [result respondsToSelector:@selector(unsignedIntegerValue)]
                    ? [result unsignedIntegerValue]
                    : autofillFields.count;
                [self setStatusText:[NSString stringWithFormat:@"AI autofilled %lu field%@",
                                     (unsigned long)filled,
                                     filled == 1 ? @"" : @"s"]];
            }];
        }];
    }];
}

- (void)autofillFormsWithAI:(id)sender {
    (void)sender;
    [self autofillFormsWithInstructions:@"" promptIfEmpty:YES];
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
    NSString *background = TBThemeIsDark() ? @"#0a0a0b" : @"linear-gradient(135deg,#f6d9e6 0%,#fbf7fb 48%,#edf0ff 100%)";
    NSString *text = TBThemeIsDark() ? @"#f3f3f4" : @"#17141a";
    NSString *muted = TBThemeIsDark() ? @"#8a8a90" : @"#625d6a";
    NSString *spinnerBorder = TBThemeIsDark() ? @"rgba(255,255,255,0.12)" : @"rgba(23,20,26,0.12)";
    return [NSString stringWithFormat:
        @"<!doctype html><html><head><meta charset='utf-8'><style>"
         "html,body{height:100%%;margin:0}"
         "body{display:grid;place-items:center;background:%@;color:%@;"
         "font-family:-apple-system,BlinkMacSystemFont,'SF Pro Display','Inter',sans-serif}"
         ".box{text-align:center;max-width:520px;padding:0 24px}"
         ".spin{width:34px;height:34px;margin:0 auto 22px;border-radius:50%%;"
         "border:3px solid %@;border-top-color:#ec6b5b;animation:s 0.8s linear infinite}"
         ".dot{width:14px;height:14px;margin:0 auto 22px;border-radius:50%%;background:#d94a5c}"
         "@keyframes s{to{transform:rotate(360deg)}}"
         "h1{font-size:20px;font-weight:500;margin:0 0 8px}"
         "p{color:%@;font-size:14px;line-height:1.5;margin:0}"
         ".q{color:#ec6b5b}"
         "</style></head><body><div class='box'>%@"
         "<h1>%@</h1><p class='q'>%@</p><p>%@</p></div></body></html>",
        background, text, spinnerBorder, muted, spinner, [self htmlEscaped:heading], q, [self htmlEscaped:note]];
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
    NSString *themeCSS = TBThemeIsDark()
        ? @":root{color-scheme:dark;--bg:#0a0a0b;--page-bg:#0a0a0b;--text:#f3f3f4;--body:#e7e7ea;--muted:#8a8a90;--line:rgba(255,255,255,0.09);--code-bg:#111113;--code-line:rgba(255,255,255,0.09);--strong:#fff}"
        : @":root{color-scheme:light;--bg:#f7eef4;--page-bg:linear-gradient(135deg,#f6d9e6 0%,#fbf7fb 48%,#edf0ff 100%);--text:#17141a;--body:#332d39;--muted:#625d6a;--line:rgba(30,24,38,0.1);--code-bg:rgba(255,255,255,0.84);--code-line:rgba(30,24,38,0.1);--strong:#17141a}";
    return [NSString stringWithFormat:
        @"<!doctype html><html lang='en'><head><meta charset='utf-8'>"
         "<meta name='viewport' content='width=device-width, initial-scale=1'>"
         "<title>%@</title><style>"
         "%@"
         "*{box-sizing:border-box}"
         "html,body{margin:0}"
         "body{background:var(--bg);color:var(--text);"
         "font-family:-apple-system,BlinkMacSystemFont,'SF Pro Display','Inter',sans-serif;"
         "line-height:1.7;font-size:16px;"
         "background-image:var(--page-bg)}"
         ".wrap{max-width:760px;margin:0 auto;padding:64px 28px 96px}"
         "header.page{border-bottom:1px solid var(--line);padding-bottom:22px;margin-bottom:34px}"
         ".eyebrow{display:inline-flex;align-items:center;gap:7px;color:#ec6b5b;font-size:12px;"
         "font-weight:600;letter-spacing:0;text-transform:uppercase;margin:0 0 12px}"
         ".eyebrow::before{content:'';width:7px;height:7px;border-radius:50%%;background:#ec6b5b}"
         "h1{font-size:30px;line-height:1.2;font-weight:500;letter-spacing:0;margin:0}"
         "article{animation:rise .4s cubic-bezier(.22,.61,.36,1) both}"
         "@keyframes rise{from{opacity:0;transform:translateY(10px)}to{opacity:1;transform:none}}"
         "h2{font-size:21px;font-weight:500;letter-spacing:0;margin:38px 0 12px}"
         "h3{font-size:17px;font-weight:500;margin:26px 0 8px}"
         "p{margin:0 0 16px;color:var(--body)}"
         "a{color:#de5a4b;text-decoration:none;border-bottom:1px solid rgba(222,90,75,0.35)}"
         "a:hover{border-bottom-color:#de5a4b}"
         "ul,ol{margin:0 0 18px;padding-left:22px}li{margin:6px 0;color:var(--body)}"
         "strong{color:var(--strong)}"
         "blockquote{margin:20px 0;padding:4px 18px;border-left:3px solid #ec6b5b;color:var(--muted)}"
         "code{background:var(--code-bg);border:1px solid var(--code-line);padding:2px 6px;border-radius:5px;font-size:0.92em}"
         "pre{background:var(--code-bg);border:1px solid var(--code-line);border-radius:10px;"
         "padding:16px;overflow:auto}pre code{background:none;padding:0}"
         "table{width:100%%;border-collapse:collapse;margin:18px 0;font-size:14.5px}"
         "th,td{text-align:left;padding:10px 12px;border-bottom:1px solid var(--line)}"
         "th{color:var(--muted);font-weight:500;text-transform:uppercase;letter-spacing:0;font-size:12px}"
         "hr{border:0;border-top:1px solid var(--line);margin:34px 0}"
         "img{max-width:100%%;border-radius:10px}"
         "svg{display:block;max-width:100%%;height:auto;margin:8px auto 4px}"
         "@media(prefers-reduced-motion:reduce){article{animation:none}}"
         "</style></head><body><div class='wrap'>"
         "<header class='page'><p class='eyebrow'>TrailBrowser AI</p><h1>%@</h1></header>"
         "<article>%@</article></div></body></html>",
        [self htmlEscaped:query], themeCSS, [self htmlEscaped:query], contentHTML];
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
    if (!self.webView) {
        NSBeep();
        return;
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
    if (!editMode && [self requestLooksLikeFormAutofill:request]) {
        [self clearAssistantPromptField];
        [self autofillFormsWithInstructions:request promptIfEmpty:NO];
        return;
    }

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
        if (effort.length == 0) effort = effortOverride.length > 0 ? effortOverride : @"low";
        if ([effort isEqualToString:@"minimal"]) effort = @"low";
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

- (NSMenuItem *)tabContextMenuItemWithTitle:(NSString *)title
                                     action:(SEL)action
                                        row:(NSInteger)row
                                    enabled:(BOOL)enabled {
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:action keyEquivalent:@""];
    item.target = self;
    item.tag = row;
    item.enabled = enabled;
    return item;
}

- (void)menuNeedsUpdate:(NSMenu *)menu {
    if (menu != self.tabContextMenu) return;

    [menu removeAllItems];

    NSInteger row = self.tabTable.clickedRow;
    BOOL hasTab = row >= 0 && row < (NSInteger)self.tabs.count;
    if (hasTab) {
        BrowserTab *tab = self.tabs[(NSUInteger)row];
        [menu addItem:[self tabContextMenuItemWithTitle:@"Reload Tab"
                                                 action:@selector(reloadTabFromMenu:)
                                                    row:row
                                                enabled:YES]];
        [menu addItem:[self tabContextMenuItemWithTitle:@"Duplicate Tab"
                                                 action:@selector(duplicateTabFromMenu:)
                                                    row:row
                                                enabled:YES]];
        [menu addItem:[self tabContextMenuItemWithTitle:(tab.pinned ? @"Unpin Tab" : @"Pin Tab")
                                                 action:@selector(toggleTabPinnedFromMenu:)
                                                    row:row
                                                enabled:YES]];
        [menu addItem:[NSMenuItem separatorItem]];
        [menu addItem:[self tabContextMenuItemWithTitle:@"Move Tab Up"
                                                 action:@selector(moveTabUpFromMenu:)
                                                    row:row
                                                enabled:row > 0]];
        [menu addItem:[self tabContextMenuItemWithTitle:@"Move Tab Down"
                                                 action:@selector(moveTabDownFromMenu:)
                                                    row:row
                                                enabled:row < (NSInteger)self.tabs.count - 1]];
        [menu addItem:[NSMenuItem separatorItem]];
        [menu addItem:[self tabContextMenuItemWithTitle:@"Close Tab"
                                                 action:@selector(closeTabFromMenu:)
                                                    row:row
                                                enabled:YES]];
        [menu addItem:[self tabContextMenuItemWithTitle:@"Close Other Tabs"
                                                 action:@selector(closeOtherTabsFromMenu:)
                                                    row:row
                                                enabled:self.tabs.count > 1]];
        [menu addItem:[self tabContextMenuItemWithTitle:@"Close Tabs to the Right"
                                                 action:@selector(closeTabsToRightFromMenu:)
                                                    row:row
                                                enabled:row < (NSInteger)self.tabs.count - 1]];
        [menu addItem:[NSMenuItem separatorItem]];
    }

    [menu addItem:[self tabContextMenuItemWithTitle:@"New Tab"
                                             action:@selector(newTab:)
                                                row:row
                                            enabled:YES]];
    [menu addItem:[self tabContextMenuItemWithTitle:@"Reopen Closed Tab"
                                             action:@selector(reopenClosedTab:)
                                                row:row
                                            enabled:self.recentlyClosedTabs.count > 0]];
}

- (void)reloadTabFromMenu:(id)sender {
    [self reloadTabAtIndex:[sender tag]];
}

- (void)duplicateTabFromMenu:(id)sender {
    [self duplicateTabAtIndex:[sender tag] select:YES];
}

- (void)toggleTabPinnedFromMenu:(id)sender {
    [self togglePinnedForTabAtIndex:[sender tag]];
}

- (void)moveTabUpFromMenu:(id)sender {
    NSInteger row = [sender tag];
    [self moveTabFromIndex:row toDropIndex:row - 1];
}

- (void)moveTabDownFromMenu:(id)sender {
    NSInteger row = [sender tag];
    [self moveTabFromIndex:row toDropIndex:row + 2];
}

- (void)closeTabFromMenu:(id)sender {
    [self closeTabAtIndex:[sender tag]];
}

- (void)closeOtherTabsFromMenu:(id)sender {
    [self closeTabsExceptIndex:[sender tag]];
}

- (void)closeTabsToRightFromMenu:(id)sender {
    [self closeTabsToRightOfIndex:[sender tag]];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    (void)tableView;
    return (NSInteger)self.tabs.count;
}

- (NSInteger)draggedTabIndexFromPasteboard:(NSPasteboard *)pasteboard {
    NSString *value = [pasteboard stringForType:TBTabDragPasteboardType];
    if (value.length == 0) return -1;
    return value.integerValue;
}

- (id<NSPasteboardWriting>)tableView:(NSTableView *)tableView pasteboardWriterForRow:(NSInteger)row {
    if (tableView != self.tabTable || row < 0 || row >= (NSInteger)self.tabs.count) return nil;

    NSPasteboardItem *item = [[NSPasteboardItem alloc] init];
    [item setString:[NSString stringWithFormat:@"%ld", (long)row] forType:TBTabDragPasteboardType];
    return item;
}

- (NSDragOperation)tableView:(NSTableView *)tableView
                validateDrop:(id<NSDraggingInfo>)info
                  proposedRow:(NSInteger)row
        proposedDropOperation:(NSTableViewDropOperation)dropOperation {
    if (tableView != self.tabTable || info.draggingSource != self.tabTable) return NSDragOperationNone;

    NSInteger sourceIndex = [self draggedTabIndexFromPasteboard:info.draggingPasteboard];
    if (sourceIndex < 0 || sourceIndex >= (NSInteger)self.tabs.count) return NSDragOperationNone;
    if (dropOperation != NSTableViewDropAbove) {
        [tableView setDropRow:row dropOperation:NSTableViewDropAbove];
    }

    NSInteger dropIndex = MIN(MAX(row, 0), (NSInteger)self.tabs.count);
    if (dropIndex == sourceIndex || dropIndex == sourceIndex + 1) return NSDragOperationNone;
    return NSDragOperationMove;
}

- (BOOL)tableView:(NSTableView *)tableView
       acceptDrop:(id<NSDraggingInfo>)info
              row:(NSInteger)row
    dropOperation:(NSTableViewDropOperation)dropOperation {
    (void)dropOperation;
    if (tableView != self.tabTable || info.draggingSource != self.tabTable) return NO;

    NSInteger sourceIndex = [self draggedTabIndexFromPasteboard:info.draggingPasteboard];
    return [self moveTabFromIndex:sourceIndex toDropIndex:row];
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
    NSString *subtitle = nil;
    if (url.host.length > 0) {
        subtitle = url.host;
    } else if (tab.urlString.length > 0) {
        subtitle = tab.urlString;
    } else {
        subtitle = @"New tab";
    }
    NSMutableArray<NSString *> *prefixes = [NSMutableArray array];
    if (tab.privateBrowsing) [prefixes addObject:@"Private"];
    if (tab.pinned) [prefixes addObject:@"Pinned"];
    if (prefixes.count == 0) return subtitle;
    return [NSString stringWithFormat:@"%@ - %@", [prefixes componentsJoinedByString:@" / "], subtitle];
}

- (void)reloadSidebarRowForTab:(BrowserTab *)tab {
    NSUInteger index = [self.tabs indexOfObject:tab];
    if (index == NSNotFound) return;

    [self.tabTable reloadDataForRowIndexes:[NSIndexSet indexSetWithIndex:index]
                             columnIndexes:[NSIndexSet indexSetWithIndex:0]];
    if (self.tabSwitcherVisible) [self refreshTabSwitcher];
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
        title.font = [NSFont systemFontOfSize:13.0 weight:NSFontWeightRegular];
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
            NSString *symbol = tab.privateBrowsing ? @"eye.slash" : @"globe";
            NSImage *image = [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:@"Website"];
            image.template = YES;
            cell.tabIconView.image = image;
        }
        if (@available(macOS 10.14, *)) {
            cell.tabIconView.contentTintColor = (selected || tab.privateBrowsing || tab.pinned) ? TBAccent() : TBFaint();
        }
    }
    return cell;
}

- (void)closeTabFromButton:(id)sender {
    NSInteger row = [self.tabTable rowForView:sender];
    if (row == -1) row = [sender tag];
    if (row < 0 || row >= (NSInteger)self.tabs.count) return;
    [self closeTabAtIndex:row];
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    if (notification.object != self.tabTable) return;
    if (self.suppressTabSelectionChange) return;
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

    WKHTTPCookieStore *store = [WKWebsiteDataStore defaultDataStore].httpCookieStore;
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

        NSMutableString *message = [NSMutableString stringWithFormat:
                                    @"Imported %lu cookie%@ from \"%@\".",
                                    (unsigned long)result.imported,
                                    result.imported == 1 ? @"" : @"s",
                                    profile.displayName];
        NSUInteger staleSkipped = result.skipped;
        if (result.partitionedSkipped <= staleSkipped) {
            staleSkipped -= result.partitionedSkipped;
        } else {
            staleSkipped = 0;
        }
        if (staleSkipped > 0) {
            [message appendFormat:@" Skipped %lu stale or unreadable cookie%@.",
             (unsigned long)staleSkipped,
             staleSkipped == 1 ? @"" : @"s"];
        }
        if (result.partitionedSkipped > 0) {
            [message appendFormat:@" Skipped %lu partitioned Chrome cookie%@ that WebKit cannot import through its public cookie API.",
             (unsigned long)result.partitionedSkipped,
             result.partitionedSkipped == 1 ? @"" : @"s"];
        }
        if (result.decryptionFailures > 0) {
            [message appendFormat:@" %lu encrypted cookie%@ could not be decrypted by the Chrome Safe Storage key.",
             (unsigned long)result.decryptionFailures,
             result.decryptionFailures == 1 ? @"" : @"s"];
        }
        [message appendString:@"\n\nReload the current page to use them."];
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
    [self updateBookmarkButton];
    [self updateSiteInfoButton];
    [self updateDownloadsButton];
    [self updateAutofillButton];
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
        if (observedWebView == self.webView) {
            [self syncAddressBarWithWebView];
            [self updateBookmarkButton];
            [self updateSiteInfoButton];
        }
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
    self.pageHasFillableForms = NO;
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
        [self scheduleFormDetectionForWebView:webView];
        NSString *pendingAutofill = self.pendingAutofillInstructionsAfterNavigation;
        if (pendingAutofill.length > 0) {
            self.pendingAutofillInstructionsAfterNavigation = nil;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                if (webView != self.webView || ![self isHTTPURL:webView.URL]) return;
                [self autofillFormsWithInstructions:pendingAutofill promptIfEmpty:NO];
            });
        }
    }
    [self recordHistoryEntryForWebView:webView];
    [self writeBrowserStateRunning:YES];
    if (webView == self.webView) [self updateControls];
}

- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    (void)navigation;
    [self preloadFinishedForWebView:webView];
    if (webView != self.webView) return;
    self.pageHasFillableForms = NO;
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

    if (navigationAction.navigationType == WKNavigationTypeLinkActivated && [self isHTTPURL:url]) {
        NSEventModifierFlags flags = navigationAction.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask;
        BOOL commandClick = (flags & NSEventModifierFlagCommand) != 0;
        BOOL middleClick = navigationAction.buttonNumber == 2;
        if (commandClick || middleClick) {
            BOOL selectNewTab = (flags & NSEventModifierFlagShift) != 0;
            BrowserTab *sourceTab = [self tabForWebView:webView];
            if (sourceTab.privateBrowsing) {
                [self newPrivateTabWithURLString:url.absoluteString select:selectNewTab];
            } else {
                [self newTabWithURLString:url.absoluteString select:selectNewTab];
            }
            decisionHandler(WKNavigationActionPolicyCancel);
            return;
        }
    }

    decisionHandler(WKNavigationActionPolicyAllow);
}

- (void)webView:(WKWebView *)webView
decidePolicyForNavigationResponse:(WKNavigationResponse *)navigationResponse
decisionHandler:(void (^)(WKNavigationResponsePolicy))decisionHandler {
    (void)webView;
    if (@available(macOS 11.3, *)) {
        if (!navigationResponse.canShowMIMEType) {
            decisionHandler(WKNavigationResponsePolicyDownload);
            return;
        }
    }
    decisionHandler(WKNavigationResponsePolicyAllow);
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
        BrowserTab *sourceTab = [self tabForWebView:webView];
        NSEventModifierFlags flags = navigationAction.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask;
        BOOL commandClick = (flags & NSEventModifierFlagCommand) != 0;
        BOOL selectNewTab = !commandClick || (flags & NSEventModifierFlagShift);
        if (sourceTab.privateBrowsing) {
            configuration.websiteDataStore = [WKWebsiteDataStore nonPersistentDataStore];
        }
        BrowserTab *tab = [self newTabWithConfiguration:configuration
                                              URLString:navigationAction.request.URL.absoluteString
                                                 select:selectNewTab
                                        privateBrowsing:sourceTab.privateBrowsing];
        return tab.webView;
    }
    return nil;
}

- (void)webView:(WKWebView *)webView
requestMediaCapturePermissionForOrigin:(WKSecurityOrigin *)origin
initiatedByFrame:(WKFrameInfo *)frame
           type:(WKMediaCaptureType)type
decisionHandler:(void (^)(WKPermissionDecision decision))decisionHandler {
    NSString *originString = [self originStringForSecurityOrigin:origin] ?:
                             [self originStringForSecurityOrigin:frame.securityOrigin] ?:
                             [self originStringForURL:frame.request.URL];
    NSString *displayOrigin = originString.length ? originString : @"This site";
    NSArray<NSString *> *kinds = [self sitePermissionKindsForMediaCaptureType:type];
    BrowserTab *tab = [self tabForWebView:webView];
    BOOL privateBrowsing = tab.privateBrowsing;

    if (!privateBrowsing && originString.length > 0) {
        if ([self anySitePermissionKindDenied:kinds originString:originString]) {
            decisionHandler(WKPermissionDecisionDeny);
            return;
        }
        if ([self allSitePermissionKindsAllowed:kinds originString:originString]) {
            decisionHandler(WKPermissionDecisionGrant);
            return;
        }
    }

    NSString *captureLabel = [self mediaCaptureLabelForType:type];
    NSAlert *alert = [[NSAlert alloc] init];
    alert.alertStyle = NSAlertStyleInformational;
    alert.messageText = [NSString stringWithFormat:@"Allow %@ access?", [captureLabel capitalizedString]];
    alert.informativeText = privateBrowsing
        ? [NSString stringWithFormat:@"%@ wants to use your %@. Private tabs do not save site permission choices.",
           displayOrigin, captureLabel]
        : [NSString stringWithFormat:@"%@ wants to use your %@.", displayOrigin, captureLabel];
    [alert addButtonWithTitle:@"Allow"];
    [alert addButtonWithTitle:@"Block"];

    BOOL canRemember = !privateBrowsing && originString.length > 0;
    if (canRemember) {
        alert.showsSuppressionButton = YES;
        alert.suppressionButton.title = @"Remember for this site";
    }

    void (^finish)(NSModalResponse) = ^(NSModalResponse response) {
        WKPermissionDecision decision = response == NSAlertFirstButtonReturn
            ? WKPermissionDecisionGrant
            : WKPermissionDecisionDeny;
        BOOL remember = canRemember && alert.suppressionButton.state == NSControlStateValueOn;
        if (remember) {
            NSString *value = decision == WKPermissionDecisionGrant ? TBSitePermissionAllow : TBSitePermissionDeny;
            for (NSString *kind in kinds) {
                [self setSitePermissionValue:value forOriginString:originString kind:kind];
            }
        }
        decisionHandler(decision);
    };

    if (self.window) {
        [alert beginSheetModalForWindow:self.window completionHandler:finish];
    } else {
        finish([alert runModal]);
    }
}

#pragma mark - Downloads

- (void)trackDownload:(WKDownload *)download {
    if (!download) return;
    if (!self.activeDownloads) self.activeDownloads = [NSMutableSet set];
    if (!self.downloadMetadata) self.downloadMetadata = [NSMapTable strongToStrongObjectsMapTable];
    download.delegate = self;
    [self.activeDownloads addObject:download];
    if (![self.downloadMetadata objectForKey:download]) {
        NSMutableDictionary<NSString *, id> *metadata = [@{
            @"timestamp": [[self historyDateFormatter] stringFromDate:[NSDate date]],
            @"status": @"started"
        } mutableCopy];
        [self.downloadMetadata setObject:metadata forKey:download];
    }
    [self downloadIDForMetadata:[self.downloadMetadata objectForKey:download]];
    [self setStatusText:@"Downloading"];
    [self updateDownloadsButton];
    [self startDownloadRefreshTimerIfNeeded];
    [self refreshDownloadsPopoverIfOpen];
}

- (NSURL *)uniqueDownloadURLForSuggestedFilename:(NSString *)suggestedFilename {
    NSString *filename = suggestedFilename.lastPathComponent;
    if (filename.length == 0) filename = @"download";
    NSCharacterSet *badChars = [NSCharacterSet characterSetWithCharactersInString:@"/:"];
    filename = [[filename componentsSeparatedByCharactersInSet:badChars] componentsJoinedByString:@"-"];
    if (filename.length == 0) filename = @"download";

    NSURL *downloadsURL = [[NSFileManager defaultManager] URLsForDirectory:NSDownloadsDirectory
                                                                 inDomains:NSUserDomainMask].firstObject;
    if (!downloadsURL) downloadsURL = [NSURL fileURLWithPath:[NSHomeDirectory() stringByAppendingPathComponent:@"Downloads"]
                                                 isDirectory:YES];
    [[NSFileManager defaultManager] createDirectoryAtURL:downloadsURL
                             withIntermediateDirectories:YES
                                              attributes:nil
                                                   error:nil];

    NSString *extension = filename.pathExtension;
    NSString *stem = filename.stringByDeletingPathExtension;
    if (stem.length == 0) stem = @"download";
    NSURL *candidate = [downloadsURL URLByAppendingPathComponent:filename isDirectory:NO];
    NSInteger suffix = 2;
    while ([[NSFileManager defaultManager] fileExistsAtPath:candidate.path]) {
        NSString *copyName = extension.length
            ? [NSString stringWithFormat:@"%@ %ld.%@", stem, (long)suffix, extension]
            : [NSString stringWithFormat:@"%@ %ld", stem, (long)suffix];
        candidate = [downloadsURL URLByAppendingPathComponent:copyName isDirectory:NO];
        suffix += 1;
    }
    return candidate;
}

- (void)webView:(WKWebView *)webView
navigationAction:(WKNavigationAction *)navigationAction
didBecomeDownload:(WKDownload *)download {
    (void)webView;
    (void)navigationAction;
    [self trackDownload:download];
}

- (void)webView:(WKWebView *)webView
navigationResponse:(WKNavigationResponse *)navigationResponse
didBecomeDownload:(WKDownload *)download {
    (void)webView;
    (void)navigationResponse;
    [self trackDownload:download];
}

- (void)download:(WKDownload *)download
decideDestinationUsingResponse:(NSURLResponse *)response
suggestedFilename:(NSString *)suggestedFilename
completionHandler:(void (^)(NSURL *destination))completionHandler {
    (void)response;
    NSURL *destination = [self uniqueDownloadURLForSuggestedFilename:suggestedFilename];
    if (!self.downloadMetadata) self.downloadMetadata = [NSMapTable strongToStrongObjectsMapTable];
    NSMutableDictionary<NSString *, id> *metadata = [self.downloadMetadata objectForKey:download];
    if (!metadata) {
        metadata = [@{ @"timestamp": [[self historyDateFormatter] stringFromDate:[NSDate date]] } mutableCopy];
        [self.downloadMetadata setObject:metadata forKey:download];
    }
    metadata[@"filename"] = destination.lastPathComponent ?: suggestedFilename ?: @"download";
    metadata[@"path"] = destination.path ?: @"";
    metadata[@"status"] = @"started";
    completionHandler(destination);
    [self refreshDownloadsPopoverIfOpen];
}

- (void)downloadDidFinish:(WKDownload *)download {
    NSMutableDictionary<NSString *, id> *metadata = [[self.downloadMetadata objectForKey:download] mutableCopy] ?: [NSMutableDictionary dictionary];
    metadata[@"timestamp"] = metadata[@"timestamp"] ?: [[self historyDateFormatter] stringFromDate:[NSDate date]];
    metadata[@"status"] = @"complete";
    NSString *resumeDataPath = [metadata[@"resumeDataPath"] isKindOfClass:NSString.class] ? metadata[@"resumeDataPath"] : @"";
    [self removeDownloadResumeDataAtPath:resumeDataPath];
    [metadata removeObjectForKey:@"resumeDataPath"];
    [metadata removeObjectForKey:@"error"];
    if (![metadata[@"filename"] isKindOfClass:NSString.class]) metadata[@"filename"] = @"download";
    [self downloadIDForMetadata:metadata];
    [self recordDownloadEntry:metadata];
    [self.downloadMetadata removeObjectForKey:download];
    [self.activeDownloads removeObject:download];
    [self setStatusText:self.activeDownloads.count > 0 ? @"Downloading" : @"Download complete"];
    [self updateDownloadsButton];
    [self stopDownloadRefreshTimerIfIdle];
    [self refreshDownloadsPopoverIfOpen];
    [self reloadSettingsIfVisible];
}

- (void)download:(WKDownload *)download didFailWithError:(NSError *)error resumeData:(NSData *)resumeData {
    NSMutableDictionary<NSString *, id> *metadata = [[self.downloadMetadata objectForKey:download] mutableCopy] ?: [NSMutableDictionary dictionary];
    NSString *downloadID = [self downloadIDForMetadata:metadata];
    metadata[@"timestamp"] = metadata[@"timestamp"] ?: [[self historyDateFormatter] stringFromDate:[NSDate date]];
    metadata[@"status"] = @"failed";
    metadata[@"error"] = error.localizedDescription ?: @"Download failed";
    if (![metadata[@"filename"] isKindOfClass:NSString.class]) metadata[@"filename"] = @"download";
    [metadata removeObjectForKey:@"resumeDataPath"];
    NSString *resumePath = [self storeResumeData:resumeData forDownloadID:downloadID];
    if (resumePath.length > 0) metadata[@"resumeDataPath"] = resumePath;
    [self recordDownloadEntry:metadata];
    [self.downloadMetadata removeObjectForKey:download];
    [self.activeDownloads removeObject:download];
    [self setStatusText:error.localizedDescription ?: @"Download failed"];
    [self updateDownloadsButton];
    [self stopDownloadRefreshTimerIfIdle];
    [self refreshDownloadsPopoverIfOpen];
    [self reloadSettingsIfVisible];
}

@end

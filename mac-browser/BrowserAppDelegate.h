#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>

#import "BrowserTab.h"
#import "TBControls.h"

NS_ASSUME_NONNULL_BEGIN

@interface BrowserAppDelegate : NSObject <NSApplicationDelegate, NSTextFieldDelegate, WKNavigationDelegate, WKUIDelegate, NSTableViewDataSource, NSTableViewDelegate>
@property (nonatomic, strong) NSWindow *window;
@property (nonatomic, strong, nullable) WKWebView *webView;
@property (nonatomic, strong) NSView *webContainer;
@property (nonatomic, strong) NSView *toolbar;
@property (nonatomic, strong) NSView *sidebar;
@property (nonatomic, strong) NSView *sidebarSeparator;
@property (nonatomic, strong) NSTableView *tabTable;
@property (nonatomic, strong) NSMutableArray<BrowserTab *> *tabs;
@property (nonatomic, strong) NSTextField *addressField;
@property (nonatomic, strong) TBFieldContainer *addressContainer;
@property (nonatomic, strong) NSTextField *tabCountLabel;
@property (nonatomic, strong) NSButton *backButton;
@property (nonatomic, strong) NSButton *forwardButton;
@property (nonatomic, strong) NSButton *sidebarToggleButton;
@property (nonatomic, strong) NSButton *reloadButton;
@property (nonatomic, strong) NSButton *plusButton;
@property (nonatomic, strong) NSButton *addTabButton;
@property (nonatomic, strong) NSButton *closeTabButton;
@property (nonatomic, strong) TBPillButton *askButton;
@property (nonatomic, strong) NSButton *settingsButton;
@property (nonatomic, strong) TBProgressBar *progressBar;
@property (nonatomic, strong) NSView *statusDot;
@property (nonatomic, strong) NSVisualEffectView *assistantBar;
@property (nonatomic, strong) NSSegmentedControl *assistantModeControl;
@property (nonatomic, strong) NSTextField *assistantPromptField;
@property (nonatomic, strong) NSButton *assistantRunButton;
@property (nonatomic, strong) NSProgressIndicator *assistantSpinner;
@property (nonatomic, strong) NSVisualEffectView *assistantResultPanel;
@property (nonatomic, strong) NSTextView *assistantResultTextView;
@property (nonatomic, strong) NSButton *assistantResultCloseButton;
@property (nonatomic, strong) NSButton *assistantCollapseButton;
@property (nonatomic, strong) NSLayoutConstraint *sidebarWidthConstraint;
@property (nonatomic, copy) NSString *lastRecordedURL;
@property (nonatomic, assign) NSInteger activeTabIndex;
@property (nonatomic, assign) BOOL renderingInternalPage;
@property (nonatomic, assign) BOOL userEditingAddress;
@property (nonatomic, assign) BOOL sidebarVisible;
@end

NS_ASSUME_NONNULL_END

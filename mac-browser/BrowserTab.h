// BrowserTab.h - Model for a single browser tab.
//
// Inactive tabs release their WKWebView to save memory but keep URL/title/
// favicon metadata so they can be restored on demand (low-memory tab sleeping).

#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface BrowserTab : NSObject
@property (nonatomic, strong, nullable) WKWebView *webView;
@property (nonatomic, copy, nullable) NSString *title;
@property (nonatomic, copy, nullable) NSString *urlString;
@property (nonatomic, copy, nullable) NSString *lastRecordedURL;
@property (nonatomic, strong, nullable) NSImage *favicon;
@property (nonatomic, copy, nullable) NSString *faviconURLString;
@property (nonatomic, copy, nullable) NSString *pendingFaviconURLString;
@end

NS_ASSUME_NONNULL_END

// BrowserTabViews.h - Sidebar tab list row and cell views.

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

// Row view that draws the selected-tab card (elevated fill + accent bar) and a
// faint hover background. Selection highlight style is disabled on the table.
@interface BrowserTabRowView : NSTableRowView
@property (nonatomic, assign) BOOL hovering;
@end

// Cell view holding the favicon, title, host subtitle, and a hover-revealed
// close button. The controller lays out and populates these subviews.
@interface BrowserTabCellView : NSTableCellView
@property (nonatomic, strong, nullable) NSImageView *tabIconView;
@property (nonatomic, strong, nullable) NSTextField *titleLabel;
@property (nonatomic, strong, nullable) NSTextField *subtitleLabel;
@property (nonatomic, strong, nullable) NSButton *closeButton;
@property (nonatomic, assign) BOOL hovering;
@end

NS_ASSUME_NONNULL_END

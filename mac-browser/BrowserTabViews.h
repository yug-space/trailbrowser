#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface BrowserTabRowView : NSTableRowView
@property (nonatomic, assign) BOOL hovering;
@property (nonatomic, assign) BOOL activeTab;
@end

@interface BrowserTabCellView : NSTableCellView
@property (nonatomic, strong, nullable) NSImageView *tabIconView;
@property (nonatomic, strong, nullable) NSTextField *titleLabel;
@property (nonatomic, strong, nullable) NSTextField *subtitleLabel;
@property (nonatomic, strong, nullable) NSButton *closeButton;
@property (nonatomic, assign) BOOL hovering;
@end

NS_ASSUME_NONNULL_END

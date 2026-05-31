// TBControls.h - Reusable themed AppKit controls for TrailBrowser.

#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>

NS_ASSUME_NONNULL_BEGIN

// Borderless symbol button with an animated rounded hover/press background and
// a tinted template image. Reused for every toolbar and sidebar icon control.
@interface TBFlatButton : NSButton
@property (nonatomic, assign) CGFloat cornerRadius;
@property (nonatomic, assign) BOOL hovering;
@end

typedef NS_ENUM(NSInteger, TBPillStyle) {
    TBPillStyleAccent,
    TBPillStyleSecondary
};

// Rounded text button (animated fill) used for primary ("Ask") and secondary actions.
@interface TBPillButton : NSButton
@property (nonatomic, assign) TBPillStyle pillStyle;
@property (nonatomic, assign) BOOL hovering;
@end

// A thin accent fill (e.g. 2px) replacing NSProgressIndicator so it can be
// colored precisely; pinned along the toolbar's bottom edge.
@interface TBProgressBar : NSView
@property (nonatomic, assign) double progress;
@property (nonatomic, strong) CALayer *fillLayer;
@end

// Rounded container giving the address field an elevated fill, a hairline
// border, and an animated accent focus ring. Holds a leading glyph + field.
@interface TBFieldContainer : NSView
@property (nonatomic, assign) BOOL focused;
@end

NS_ASSUME_NONNULL_END

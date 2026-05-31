#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>

NS_ASSUME_NONNULL_BEGIN

@interface TBFlatButton : NSButton
@property (nonatomic, assign) CGFloat cornerRadius;
@property (nonatomic, assign) BOOL hovering;
@property (nonatomic, assign) BOOL active;
@end

typedef NS_ENUM(NSInteger, TBPillStyle) {
    TBPillStyleAccent,
    TBPillStyleSecondary
};

@interface TBPillButton : NSButton
@property (nonatomic, assign) TBPillStyle pillStyle;
@property (nonatomic, assign) BOOL hovering;
@end

@interface TBProgressBar : NSView
@property (nonatomic, assign) double progress;
@property (nonatomic, strong) CALayer *fillLayer;
@end

@interface TBFieldContainer : NSView
@property (nonatomic, assign) BOOL focused;
@end

@interface TBSegmentedControl : NSControl
@property (nonatomic, copy) NSArray<NSString *> *titles;
@property (nonatomic, assign) NSInteger selectedIndex;
@end

NS_ASSUME_NONNULL_END

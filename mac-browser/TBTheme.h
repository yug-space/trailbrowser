#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>

NS_ASSUME_NONNULL_BEGIN

NSColor *TBBg(void);
NSColor *TBSurface(void);
NSColor *TBElevated(void);
NSColor *TBBorder(void);
NSColor *TBText(void);
NSColor *TBMuted(void);
NSColor *TBFaint(void);
NSColor *TBAccent(void);
NSColor *TBAccentHover(void);
NSColor *TBOk(void);
NSColor *TBError(void);

void TBAnimateBackground(CALayer *layer, NSColor *color, CGFloat duration);

NS_ASSUME_NONNULL_END

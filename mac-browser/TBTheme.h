// TBTheme.h - TrailBrowser's shared color palette and animation helpers.
//
// A single near-black + warm-orange palette, defined once and reused across the
// whole window so the look does not depend on the user's system accent or mode.

#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>

NS_ASSUME_NONNULL_BEGIN

NSColor *TBBg(void);          // window / web gutter
NSColor *TBSurface(void);     // toolbar, sidebar
NSColor *TBElevated(void);    // hover / selected row, fields
NSColor *TBBorder(void);      // hairlines, field borders
NSColor *TBText(void);        // primary text
NSColor *TBMuted(void);       // subtitles, section headers
NSColor *TBFaint(void);       // idle glyphs, disabled
NSColor *TBAccent(void);      // primary action, active tab, progress, focus ring
NSColor *TBAccentHover(void); // accent hover state
NSColor *TBOk(void);          // "Ready" status
NSColor *TBError(void);       // failed loads, error status

// Smoothly transition a layer's backgroundColor (used for hover/press states).
void TBAnimateBackground(CALayer *layer, NSColor *color, CGFloat duration);

NS_ASSUME_NONNULL_END

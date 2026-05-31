#import "TBTheme.h"

static NSColor *TBHex(uint32_t rgb, CGFloat alpha) {
    return [NSColor colorWithSRGBRed:((rgb >> 16) & 0xFF) / 255.0
                               green:((rgb >> 8) & 0xFF) / 255.0
                                blue:(rgb & 0xFF) / 255.0
                               alpha:alpha];
}

NSColor *TBBg(void)          { return TBHex(0x0A0A0B, 1.0); }
NSColor *TBSurface(void)     { return TBHex(0x111113, 1.0); }
NSColor *TBElevated(void)    { return TBHex(0x1B1B1F, 1.0); }
NSColor *TBBorder(void)      { return [NSColor colorWithWhite:1.0 alpha:0.08]; }
NSColor *TBText(void)        { return TBHex(0xF3F3F4, 1.0); }
NSColor *TBMuted(void)       { return TBHex(0x8A8A90, 1.0); }
NSColor *TBFaint(void)       { return TBHex(0x56565C, 1.0); }
NSColor *TBAccent(void)      { return TBHex(0xF76B1C, 1.0); }
NSColor *TBAccentHover(void) { return TBHex(0xFF8330, 1.0); }
NSColor *TBOk(void)          { return TBHex(0x2FD06A, 1.0); }
NSColor *TBError(void)       { return TBHex(0xFF4D4D, 1.0); }

void TBAnimateBackground(CALayer *layer, NSColor *color, CGFloat duration) {
    if (!layer) return;
    CGColorRef target = color.CGColor;
    CABasicAnimation *animation = [CABasicAnimation animationWithKeyPath:@"backgroundColor"];
    animation.fromValue = (__bridge id)(layer.backgroundColor ?: NSColor.clearColor.CGColor);
    animation.toValue = (__bridge id)target;
    animation.duration = duration;
    animation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
    [layer addAnimation:animation forKey:@"tbBackground"];
    layer.backgroundColor = target;
}

#import "TBTheme.h"

static NSColor *TBHex(uint32_t rgb, CGFloat alpha) {
    return [NSColor colorWithSRGBRed:((rgb >> 16) & 0xFF) / 255.0
                               green:((rgb >> 8) & 0xFF) / 255.0
                                blue:(rgb & 0xFF) / 255.0
                               alpha:alpha];
}

static TBThemeMode TBCurrentThemeMode = TBThemeModeLight;

void TBThemeSetMode(TBThemeMode mode) {
    TBCurrentThemeMode = mode;
}

TBThemeMode TBThemeCurrentMode(void) {
    return TBCurrentThemeMode;
}

TBThemeMode TBThemeModeFromString(NSString *name) {
    NSString *normalized = (name ?: @"light").lowercaseString;
    return [normalized isEqualToString:@"dark"] ? TBThemeModeDark : TBThemeModeLight;
}

NSString *TBThemeModeName(TBThemeMode mode) {
    return mode == TBThemeModeDark ? @"dark" : @"light";
}

BOOL TBThemeIsDark(void) {
    return TBCurrentThemeMode == TBThemeModeDark;
}

NSColor *TBBg(void)          { return TBThemeIsDark() ? TBHex(0x0A0A0B, 1.0) : TBHex(0xF7EEF4, 1.0); }
NSColor *TBSurface(void)     { return TBThemeIsDark() ? TBHex(0x161618, 1.0) : TBHex(0xFBF7FB, 1.0); }
NSColor *TBElevated(void)    { return TBThemeIsDark() ? TBHex(0x1F1F23, 1.0) : TBHex(0xFFFFFF, 1.0); }
NSColor *TBBorder(void)      { return [NSColor colorWithWhite:TBThemeIsDark() ? 1.0 : 0.0 alpha:0.09]; }
NSColor *TBText(void)        { return TBThemeIsDark() ? TBHex(0xF3F3F4, 1.0) : TBHex(0x17141A, 1.0); }
NSColor *TBMuted(void)       { return TBThemeIsDark() ? TBHex(0x8A8A90, 1.0) : TBHex(0x625D6A, 1.0); }
NSColor *TBFaint(void)       { return TBThemeIsDark() ? TBHex(0x56565C, 1.0) : TBHex(0xA9A2AE, 1.0); }
NSColor *TBAccent(void)      { return TBHex(0xEC6B5B, 1.0); }
NSColor *TBAccentHover(void) { return TBHex(0xDE5A4B, 1.0); }
NSColor *TBOk(void)          { return TBHex(0x42B883, 1.0); }
NSColor *TBError(void)       { return TBThemeIsDark() ? TBHex(0xFF9A8A, 1.0) : TBHex(0xD94A5C, 1.0); }

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

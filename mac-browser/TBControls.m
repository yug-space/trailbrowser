#import "TBControls.h"
#import "TBTheme.h"

#pragma mark - Flat icon button

@implementation TBFlatButton

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        self.bordered = NO;
        self.wantsLayer = YES;
        self.cornerRadius = 7.0;
        self.layer.backgroundColor = NSColor.clearColor.CGColor;
        [self setButtonType:NSButtonTypeMomentaryChange];
    }
    return self;
}

- (void)setCornerRadius:(CGFloat)cornerRadius {
    _cornerRadius = cornerRadius;
    self.layer.cornerRadius = cornerRadius;
}

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    for (NSTrackingArea *area in [self.trackingAreas copy]) {
        [self removeTrackingArea:area];
    }
    NSTrackingArea *area = [[NSTrackingArea alloc]
        initWithRect:self.bounds
             options:NSTrackingMouseEnteredAndExited | NSTrackingActiveInActiveApp | NSTrackingInVisibleRect
               owner:self
            userInfo:nil];
    [self addTrackingArea:area];
}

- (void)mouseEntered:(NSEvent *)event { (void)event; self.hovering = YES; [self refreshBackground]; }
- (void)mouseExited:(NSEvent *)event { (void)event; self.hovering = NO; [self refreshBackground]; }
- (void)setHighlighted:(BOOL)highlighted { [super setHighlighted:highlighted]; [self refreshBackground]; }
- (void)setEnabled:(BOOL)enabled { [super setEnabled:enabled]; [self refreshBackground]; }
- (void)setActive:(BOOL)active { _active = active; [self refreshBackground]; }

- (void)refreshBackground {
    NSColor *color = NSColor.clearColor;
    if (self.isEnabled && (self.hovering || self.isHighlighted)) {
        color = [NSColor colorWithWhite:1.0 alpha:(self.isHighlighted ? 0.16 : 0.08)];
    } else if (self.active) {
        color = [NSColor colorWithWhite:1.0 alpha:0.10];
    }
    TBAnimateBackground(self.layer, color, 0.16);
}

@end

#pragma mark - Pill button

@implementation TBPillButton

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        self.bordered = NO;
        self.wantsLayer = YES;
        self.pillStyle = TBPillStyleSecondary;
        [self setButtonType:NSButtonTypeMomentaryChange];
    }
    return self;
}

- (void)setPillStyle:(TBPillStyle)pillStyle {
    _pillStyle = pillStyle;
    [self refreshBackground];
    [self setNeedsDisplay:YES];
}

- (void)layout {
    [super layout];
    self.layer.cornerRadius = NSHeight(self.bounds) / 2.0;
    [self refreshBackground];
}

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    for (NSTrackingArea *area in [self.trackingAreas copy]) {
        [self removeTrackingArea:area];
    }
    NSTrackingArea *area = [[NSTrackingArea alloc]
        initWithRect:self.bounds
             options:NSTrackingMouseEnteredAndExited | NSTrackingActiveInActiveApp | NSTrackingInVisibleRect
               owner:self
            userInfo:nil];
    [self addTrackingArea:area];
}

- (void)mouseEntered:(NSEvent *)event { (void)event; self.hovering = YES; [self refreshBackground]; [self setNeedsDisplay:YES]; }
- (void)mouseExited:(NSEvent *)event { (void)event; self.hovering = NO; [self refreshBackground]; [self setNeedsDisplay:YES]; }

- (void)refreshBackground {
    NSColor *fill;
    if (self.pillStyle == TBPillStyleAccent) {
        fill = self.hovering ? TBAccentHover() : TBAccent();
        self.layer.borderWidth = 0.0;
    } else {
        fill = self.hovering ? TBElevated() : [NSColor colorWithWhite:1.0 alpha:0.05];
        self.layer.borderWidth = 1.0;
        self.layer.borderColor = TBBorder().CGColor;
    }
    TBAnimateBackground(self.layer, fill, 0.14);
}

- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    NSColor *textColor;
    if (self.pillStyle == TBPillStyleAccent) {
        textColor = NSColor.whiteColor;
    } else {
        textColor = self.hovering ? TBText() : TBMuted();
    }

    NSMutableParagraphStyle *paragraph = [[NSMutableParagraphStyle alloc] init];
    paragraph.alignment = NSTextAlignmentCenter;
    NSDictionary<NSAttributedStringKey, id> *attributes = @{
        NSFontAttributeName: [NSFont systemFontOfSize:12.5 weight:NSFontWeightSemibold],
        NSForegroundColorAttributeName: textColor,
        NSParagraphStyleAttributeName: paragraph
    };
    NSAttributedString *title = [[NSAttributedString alloc] initWithString:self.title attributes:attributes];
    NSSize size = title.size;
    NSRect rect = NSMakeRect(NSMinX(self.bounds),
                             NSMidY(self.bounds) - size.height / 2.0,
                             NSWidth(self.bounds),
                             size.height);
    [title drawInRect:rect];
}

@end

#pragma mark - Thin progress bar

@implementation TBProgressBar

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        self.wantsLayer = YES;
        self.layer.backgroundColor = NSColor.clearColor.CGColor;
        self.fillLayer = [CALayer layer];
        self.fillLayer.backgroundColor = TBAccent().CGColor;
        [self.layer addSublayer:self.fillLayer];
    }
    return self;
}

- (void)setProgress:(double)progress {
    _progress = progress;
    [self layoutFill];
}

- (void)layout {
    [super layout];
    [self layoutFill];
}

- (void)layoutFill {
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.fillLayer.frame = NSMakeRect(0, 0, NSWidth(self.bounds) * MAX(0.0, MIN(1.0, _progress)), NSHeight(self.bounds));
    [CATransaction commit];
}

@end

#pragma mark - Address field pill

@implementation TBFieldContainer

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        self.wantsLayer = YES;
        self.layer.cornerRadius = 9.0;
        self.layer.backgroundColor = TBElevated().CGColor;
        self.layer.borderWidth = 1.0;
        self.layer.borderColor = TBBorder().CGColor;
    }
    return self;
}

- (void)setFocused:(BOOL)focused {
    if (_focused == focused) return;
    _focused = focused;

    CGColorRef target = focused ? [TBAccent() colorWithAlphaComponent:0.9].CGColor : TBBorder().CGColor;
    CGFloat targetWidth = focused ? 1.6 : 1.0;

    CABasicAnimation *colorAnim = [CABasicAnimation animationWithKeyPath:@"borderColor"];
    colorAnim.fromValue = (__bridge id)(self.layer.borderColor);
    colorAnim.toValue = (__bridge id)target;
    colorAnim.duration = 0.16;
    CABasicAnimation *widthAnim = [CABasicAnimation animationWithKeyPath:@"borderWidth"];
    widthAnim.fromValue = @(self.layer.borderWidth);
    widthAnim.toValue = @(targetWidth);
    widthAnim.duration = 0.16;
    [self.layer addAnimation:colorAnim forKey:@"borderColor"];
    [self.layer addAnimation:widthAnim forKey:@"borderWidth"];
    self.layer.borderColor = target;
    self.layer.borderWidth = targetWidth;
}

@end

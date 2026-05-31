// BrowserTabViews.m - Implementation of the sidebar tab row and cell views.

#import "BrowserTabViews.h"
#import "TBTheme.h"

@implementation BrowserTabRowView

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

- (void)mouseEntered:(NSEvent *)event { (void)event; self.hovering = YES; [self setNeedsDisplay:YES]; }
- (void)mouseExited:(NSEvent *)event { (void)event; self.hovering = NO; [self setNeedsDisplay:YES]; }

- (void)drawBackgroundInRect:(NSRect)dirtyRect {
    [super drawBackgroundInRect:dirtyRect];

    NSRect fillRect = NSInsetRect(self.bounds, 6.0, 3.0);
    NSBezierPath *fillPath = [NSBezierPath bezierPathWithRoundedRect:fillRect xRadius:8.0 yRadius:8.0];

    if (self.selected) {
        [TBElevated() setFill];
        [fillPath fill];

        // A short accent bar hugging the card's left edge marks the active tab.
        NSRect accentRect = NSMakeRect(NSMinX(fillRect) + 5.0,
                                       NSMidY(fillRect) - 8.0,
                                       3.0,
                                       16.0);
        NSBezierPath *accentPath = [NSBezierPath bezierPathWithRoundedRect:accentRect xRadius:1.5 yRadius:1.5];
        [TBAccent() setFill];
        [accentPath fill];
    } else if (self.hovering) {
        [[NSColor colorWithWhite:1.0 alpha:0.05] setFill];
        [fillPath fill];
    }
}

- (void)drawSelectionInRect:(NSRect)dirtyRect {
    (void)dirtyRect;
}

@end

@implementation BrowserTabCellView

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

- (void)mouseEntered:(NSEvent *)event { (void)event; self.hovering = YES; self.closeButton.hidden = NO; }
- (void)mouseExited:(NSEvent *)event { (void)event; self.hovering = NO; self.closeButton.hidden = YES; }

@end

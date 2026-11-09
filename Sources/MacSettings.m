#import "MacSettings.h"
#import "MacModel.h"
#import "MacAuth.h"
#include <sys/sysctl.h>

/* Every page is Wyrm Android's own (the same rows, wording and engine
   settings, written through the same natives), set in Wyrm Desktop's
   two-pane workspace. Phone-only pages (touch layouts, on-screen buttons,
   joystick) are not here: on a computer the mouse and keys steer. */

NSInteger WSettingsOpenPage = 0;

static CGFloat measure(NSTextField* t, CGFloat w) {
  return ceil([t.cell cellSizeForBounds:NSMakeRect(0, 0, MAX(1, w), 100000)].height);
}
static CGFloat lineH(NSTextField* t) { [t sizeToFit]; return t.frame.size.height; }

/* The page rebuilds after a change that can show or hide rows. */
static void (^rebuildPage)(void);
static void changed(WSetting* s, NSArray* values, BOOL rebuild) {
  [WEngine write:s values:values];
  if (rebuild && rebuildPage) rebuildPage();
}

#pragma mark - Blocks

@interface WBlock : WFlipped
@property CGFloat top, bottom, side;
@property BOOL first;
- (CGFloat)heightFor:(CGFloat)width;
@end
@implementation WBlock
- (CGFloat)heightFor:(CGFloat)width { return self.frame.size.height; }
@end

@interface WStack : WFlipped
@property(strong) NSMutableArray<WBlock*>* blocks;
- (CGFloat)heightFor:(CGFloat)width;
- (void)add:(WBlock*)b;
@end
@implementation WStack
- (instancetype)init { if ((self = [super initWithFrame:NSZeroRect])) _blocks = [NSMutableArray new]; return self; }
- (void)add:(WBlock*)b { if (!b) return; [self.blocks addObject:b]; [self addSubview:b]; }
- (CGFloat)heightFor:(CGFloat)width {
  CGFloat y = 0;
  for (WBlock* b in self.blocks) if (!b.hidden) y += b.top + [b heightFor:width - 2 * b.side] + b.bottom;
  return y;
}
- (void)layout {
  [super layout];
  CGFloat y = 0, w = self.bounds.size.width;
  for (WBlock* b in self.blocks) {
    if (b.hidden) continue;
    y += b.top;
    CGFloat h = [b heightFor:w - 2 * b.side];
    b.frame = NSMakeRect(b.side, y, w - 2 * b.side, h);
    y += h + b.bottom;
  }
}
@end

/* SettingsSectionLabel: 11.5 semibold caps, tracked, quiet. */
static WBlock* sectionLabel(NSString* text, CGFloat top) {
  WBlock* b = [WBlock new];
  NSTextField* t = label(text.uppercaseString, 11.5, 600, QUIET);
  track(t, 0.92);
  [b addSubview:t];
  [t sizeToFit];
  b.frame = NSMakeRect(0, 0, 10, t.frame.size.height);
  t.frame = NSMakeRect(0, 0, 600, t.frame.size.height);
  t.autoresizingMask = NSViewWidthSizable;
  b.side = 20;
  b.top = top;
  b.bottom = 8;
  return b;
}
@interface WCaption : WBlock
@property(strong) NSTextField* text;
@end
@implementation WCaption
- (CGFloat)heightFor:(CGFloat)w { return measure(self.text, w); }
- (void)layout { [super layout]; self.text.frame = self.bounds; }
@end
static WCaption* caption(NSString* text) {
  WCaption* c = [WCaption new];
  c.text = wrapLabel(text, 12.5, 400, QUIET);
  lineHeight(c.text, 18, NSTextAlignmentLeft);
  [c addSubview:c.text];
  c.side = 20;
  c.top = 14;
  c.bottom = 8;
  return c;
}

/* SettingsCard: 14 continuous corners, card, rule; rows stacked with hairlines. */
@interface WCardBlock : WBlock
@property(strong) NSMutableArray<WBlock*>* rows;
- (void)add:(WBlock*)row;
@end
@implementation WCardBlock
- (instancetype)init {
  if ((self = [super initWithFrame:NSZeroRect])) {
    _rows = [NSMutableArray new];
    self.wantsLayer = YES;
    self.layer.backgroundColor = CARD.CGColor;
    self.layer.cornerRadius = 14;
    self.layer.cornerCurve = kCACornerCurveContinuous;
    self.layer.borderWidth = 1;
    self.layer.borderColor = RULE.CGColor;
    self.layer.masksToBounds = YES;
    self.side = 16;
  }
  return self;
}
- (void)add:(WBlock*)row {
  if (!row) return;
  row.first = self.rows.count == 0;
  [self.rows addObject:row];
  [self addSubview:row];
}
- (CGFloat)heightFor:(CGFloat)w {
  CGFloat h = 0;
  for (WBlock* r in self.rows) if (!r.hidden) h += [r heightFor:w];
  return h;
}
- (void)layout {
  [super layout];
  CGFloat y = 0, w = self.bounds.size.width;
  for (WBlock* r in self.rows) {
    if (r.hidden) continue;
    CGFloat h = [r heightFor:w];
    r.frame = NSMakeRect(0, y, w, h);
    y += h;
  }
}
@end
static WCardBlock* card(NSArray<WBlock*>* rows) {
  WCardBlock* c = [WCardBlock new];
  for (WBlock* r in rows) [c add:r];
  return c;
}

/* A row inside a card: draws its hairline unless it is the first. */
@interface WRow : WBlock
@property(strong) NSView* hairline;
@property(copy) void (^onClick)(void);
@property BOOL hovered, pressed;
@end
@implementation WRow
- (void)layout {
  [super layout];
  if (!self.first) {
    if (!self.hairline) { self.hairline = rule(); [self addSubview:self.hairline]; }
    place(self.hairline, 0, 0, self.bounds.size.width, 1);
  }
}
- (void)updateTrackingAreas {
  for (NSTrackingArea* a in self.trackingAreas) [self removeTrackingArea:a];
  if (self.onClick)
    [self addTrackingArea:[[NSTrackingArea alloc] initWithRect:NSZeroRect
        options:NSTrackingMouseEnteredAndExited | NSTrackingActiveInKeyWindow | NSTrackingInVisibleRect owner:self userInfo:nil]];
  [super updateTrackingAreas];
}
- (void)paintHover {
  self.wantsLayer = YES;
  self.layer.backgroundColor = (self.onClick && (self.hovered || self.pressed) ? [INK colorWithAlphaComponent:self.pressed ? 0.06 : 0.035] : NSColor.clearColor).CGColor;
}
- (void)mouseEntered:(NSEvent*)e { self.hovered = YES; [self paintHover]; }
- (void)mouseExited:(NSEvent*)e { self.hovered = NO; self.pressed = NO; [self paintHover]; }
- (void)resetCursorRects { if (self.onClick) [self addCursorRect:self.bounds cursor:NSCursor.pointingHandCursor]; }
- (void)mouseDown:(NSEvent*)e { if (self.onClick) { self.pressed = YES; [self paintHover]; } }
- (void)mouseUp:(NSEvent*)e {
  BOOL hit = NSPointInRect([self convertPoint:e.locationInWindow fromView:nil], self.bounds);
  BOOL fire = self.pressed && hit;
  self.pressed = NO;
  [self paintHover];
  if (fire && self.onClick) self.onClick();
}
- (BOOL)acceptsFirstMouse:(NSEvent*)e { return YES; }
@end

/* SettingsBoolRow: title, detail, the green switch; a click anywhere toggles. */
@interface WBoolRow : WRow
@property(strong) NSTextField *title, *detail;
@property(strong) WSwitch* toggle;
@end
@implementation WBoolRow
- (CGFloat)textWidth:(CGFloat)w { return w - 14 - 12 - 63 - 14; }
- (CGFloat)heightFor:(CGFloat)w {
  CGFloat tw = [self textWidth:w], h = measure(self.title, tw);
  if (self.detail.stringValue.length) h += 1 + measure(self.detail, tw);
  return MAX(58, 20 + h);
}
- (void)layout {
  [super layout];
  NSSize s = self.bounds.size;
  CGFloat tw = [self textWidth:s.width], th = measure(self.title, tw), dh = self.detail.stringValue.length ? 1 + measure(self.detail, tw) : 0;
  CGFloat y = (s.height - th - dh) / 2;
  place(self.title, 14, y, tw, th);
  place(self.detail, 14, y + th + 1, tw, dh - 1);
  place(self.toggle, s.width - 14 - 63, (s.height - 28) / 2, 63, 28);
}
@end
static WBoolRow* boolRow(NSString* title, NSString* detail, BOOL on, void (^toggle)(BOOL)) {
  WBoolRow* r = [WBoolRow new];
  r.title = wrapLabel(title, 15.5, 400, INK);
  r.detail = wrapLabel(detail ?: @"", 12.5, 400, QUIET);
  r.toggle = [WSwitch new];
  r.toggle.on = on;
  r.toggle.onToggle = toggle;
  __weak WBoolRow* weak = r;
  r.onClick = ^{ [weak.toggle click]; };
  for (NSView* v in @[r.title, r.detail, r.toggle]) [r addSubview:v];
  return r;
}

/* SettingsSliderRow: title and value, the detail, the liquid slider. */
@interface WSliderRow : WRow
@property(strong) NSTextField *title, *value, *detail;
@property(strong) WSlider* slider;
@end
@implementation WSliderRow
- (CGFloat)heightFor:(CGFloat)w {
  CGFloat h = 14 + lineH(self.title);
  if (self.detail.stringValue.length) h += 2 + measure(self.detail, w - 28);
  return h + 4 + 34 + 14;
}
- (void)layout {
  [super layout];
  CGFloat w = self.bounds.size.width, y = 14;
  [self.value sizeToFit];
  CGFloat vw = self.value.frame.size.width;
  CGFloat th = lineH(self.title);
  place(self.title, 14, y, w - 28 - vw - 8, th);
  place(self.value, w - 14 - vw, y + (th - self.value.frame.size.height), vw, self.value.frame.size.height);
  y += th;
  if (self.detail.stringValue.length) { CGFloat dh = measure(self.detail, w - 28); place(self.detail, 14, y + 2, w - 28, dh); y += 2 + dh; }
  place(self.slider, 14, y + 4, w - 28, 34);
}
@end
static WSliderRow* sliderRow(NSString* title, NSString* valueText, NSString* detail, CGFloat value, CGFloat min, CGFloat max,
                             int steps, void (^change)(CGFloat, WSliderRow*)) {
  WSliderRow* r = [WSliderRow new];
  r.title = label(title, 15.5, 400, INK);
  r.value = label(valueText, 14, 400, MUTE);
  r.value.font = [NSFont monospacedDigitSystemFontOfSize:14 weight:NSFontWeightRegular];
  r.value.font = body(14, 400);
  r.detail = wrapLabel(detail ?: @"", 12.5, 400, QUIET);
  r.slider = [[WSlider alloc] initWithFrame:NSZeroRect];
  r.slider.minimum = min;
  r.slider.maximum = max;
  r.slider.value = MAX(min, MIN(max, value));
  r.slider.steps = steps;
  __weak WSliderRow* weak = r;
  r.slider.onChange = ^(CGFloat v) { if (change) change(v, weak); [weak setNeedsLayout:YES]; };
  for (NSView* v in @[r.title, r.value, r.detail, r.slider]) [r addSubview:v];
  return r;
}

/* SettingsEnumBlock: title, detail, then the segmented choice. */
@interface WEnumRow : WRow
@property(strong) NSTextField *title, *detail;
@property(strong) WSegmented* segments;
@end
@implementation WEnumRow
- (CGFloat)heightFor:(CGFloat)w {
  CGFloat h = 14 + lineH(self.title);
  if (self.detail.stringValue.length) h += 2 + measure(self.detail, w - 28);
  return h + 11 + 34 + 14;
}
- (void)layout {
  [super layout];
  CGFloat w = self.bounds.size.width, y = 14, th = lineH(self.title);
  place(self.title, 14, y, w - 28, th);
  y += th;
  if (self.detail.stringValue.length) { CGFloat dh = measure(self.detail, w - 28); place(self.detail, 14, y + 2, w - 28, dh); y += 2 + dh; }
  place(self.segments, 14, y + 11, w - 28, 34);
}
@end
static WEnumRow* enumRow(NSString* title, NSString* detail, NSArray* options, NSInteger selected, void (^pick)(NSInteger)) {
  WEnumRow* r = [WEnumRow new];
  r.title = label(title, 15.5, 400, INK);
  r.detail = wrapLabel(detail ?: @"", 12.5, 400, QUIET);
  r.segments = [[WSegmented alloc] initWithOptions:options];
  r.segments.selected = MAX(0, MIN((NSInteger)options.count - 1, selected));
  r.segments.onSelect = pick;
  for (NSView* v in @[r.title, r.detail, r.segments]) [r addSubview:v];
  return r;
}

/* SettingsValueRow: title, value, a chevron when it opens something. */
@interface WValueRow : WRow
@property(strong) NSTextField *title, *value;
@property(strong) NSTextField* chevron;
@property(strong) NSView* badge;
@end
@implementation WValueRow
- (CGFloat)heightFor:(CGFloat)w { return 54; }
- (void)layout {
  [super layout];
  NSSize s = self.bounds.size;
  CGFloat right = s.width - 14;
  if (!self.chevron.hidden) { [self.chevron sizeToFit]; place(self.chevron, right - self.chevron.frame.size.width, (s.height - self.chevron.frame.size.height) / 2, self.chevron.frame.size.width, self.chevron.frame.size.height); right -= self.chevron.frame.size.width + 6; }
  [self.value sizeToFit];
  CGFloat vw = MIN(self.value.frame.size.width, s.width * 0.55);
  place(self.value, right - vw, (s.height - self.value.frame.size.height) / 2, vw, self.value.frame.size.height);
  CGFloat th = lineH(self.title);
  place(self.title, 14, (s.height - th) / 2, right - vw - 14 - 10, th);
}
@end
static WValueRow* valueRow(NSString* title, NSString* value, void (^open)(void)) {
  WValueRow* r = [WValueRow new];
  r.title = label(title, 15.5, 400, INK);
  r.value = label(value ?: @"", 14, 400, QUIET);
  r.chevron = label(@"›", 17, 400, FAINT);
  r.chevron.hidden = open == nil;
  r.onClick = open;
  for (NSView* v in @[r.title, r.value, r.chevron]) [r addSubview:v];
  return r;
}
/* SettingsActionRow: one line that acts; red when it destroys. */
static WRow* actionRow(NSString* title, BOOL danger, void (^act)(void)) {
  WValueRow* r = valueRow(title, @"", nil);
  r.title.textColor = danger ? BADGE : INK;
  r.onClick = act;
  r.frame = NSMakeRect(0, 0, 10, 52);
  return r;
}
static WRow* linkRow(NSString* title, NSString* value, void (^act)(void)) {
  WValueRow* r = valueRow(title, value, nil);
  r.title.textColor = LINK;
  r.onClick = act;
  return r;
}

/* An intro card's text: a semibold title and a quiet line. */
@interface WIntroRow : WRow
@property(strong) NSTextField *title, *detail;
@end
@implementation WIntroRow
- (CGFloat)heightFor:(CGFloat)w { return 15 + lineH(self.title) + 2 + measure(self.detail, w - 28) + 15; }
- (void)layout {
  [super layout];
  CGFloat w = self.bounds.size.width, th = lineH(self.title);
  place(self.title, 14, 15, w - 28, th);
  place(self.detail, 14, 15 + th + 2, w - 28, measure(self.detail, w - 28));
}
@end
static WIntroRow* introRow(NSString* title, NSString* detail) {
  WIntroRow* r = [WIntroRow new];
  r.title = label(title, 16, 600, INK);
  r.detail = wrapLabel(detail, 12.5, 400, QUIET);
  [r addSubview:r.title];
  [r addSubview:r.detail];
  return r;
}

/* A row that holds any view at a fixed height. */
@interface WHoldRow : WRow
@property(strong) NSView* content;
@property CGFloat height;
@property NSEdgeInsets insets;
@end
@implementation WHoldRow
- (CGFloat)heightFor:(CGFloat)w { return self.height + self.insets.top + self.insets.bottom; }
- (void)layout {
  [super layout];
  place(self.content, self.insets.left, self.insets.top, self.bounds.size.width - self.insets.left - self.insets.right, self.height);
}
@end
static WHoldRow* holdRow(NSView* content, CGFloat height, NSEdgeInsets insets) {
  WHoldRow* r = [WHoldRow new];
  r.content = content;
  r.height = height;
  r.insets = insets;
  [r addSubview:content];
  return r;
}
static WBlock* holdBlock(NSView* content, CGFloat height, CGFloat side) {
  WHoldRow* r = holdRow(content, height, NSEdgeInsetsMake(0, 0, 0, 0));
  r.first = YES;
  r.side = side;
  return r;
}

/* AdvancedFold: a capsule card with HIDE / SHOW and a turning chevron. */
@interface WFold : WRow
@property(strong) NSTextField *title, *state;
@property(strong) NSView* box;
@property(strong) NSImageView* chevron;
@end
@implementation WFold
- (CGFloat)heightFor:(CGFloat)w { return 52; }
- (void)layout {
  [super layout];
  NSSize s = self.bounds.size;
  place(self.box, s.width - 11 - 30, 11, 30, 30);
  place(self.chevron, 6, 6, 18, 18);
  [self.state sizeToFit];
  place(self.state, s.width - 11 - 30 - 9 - self.state.frame.size.width, (52 - self.state.frame.size.height) / 2, self.state.frame.size.width, self.state.frame.size.height);
  CGFloat th = lineH(self.title);
  place(self.title, 15, (52 - th) / 2, s.width - 120, th);
}
@end
static WFold* fold(NSString* title, BOOL open, void (^toggle)(void)) {
  WFold* f = [WFold new];
  f.first = YES;
  f.wantsLayer = YES;
  f.layer.backgroundColor = CARD.CGColor;
  f.layer.cornerRadius = 13;
  f.layer.cornerCurve = kCACornerCurveContinuous;
  f.layer.borderWidth = 1;
  f.layer.borderColor = (open ? FAINT : ROW_RULE).CGColor;
  f.title = label(title.uppercaseString, 11, 600, INK);
  track(f.title, 0.78);
  f.state = label(open ? @"HIDE" : @"SHOW", 9, 600, QUIET);
  track(f.state, 0.7);
  f.box = [WFlipped new];
  f.box.wantsLayer = YES;
  f.box.layer.cornerRadius = 9;
  f.box.layer.backgroundColor = (open ? INK : [INK colorWithAlphaComponent:0.05]).CGColor;
  f.chevron = glyph(open ? @"chevron.up" : @"chevron.down", 13, open ? PAPER : INK);
  [f.box addSubview:f.chevron];
  for (NSView* v in @[f.title, f.state, f.box]) [f addSubview:v];
  f.onClick = toggle;
  f.side = 16;
  f.top = 18;
  f.bottom = 8;
  return f;
}

#pragma mark - Colour row (hue, strength, brightness, opacity)

static NSColor* hsv(CGFloat h, CGFloat s, CGFloat v) { return [NSColor colorWithHue:h / 360.0 saturation:s brightness:v alpha:1]; }

/* WSGradientTrack: a 22 pt gradient capsule and a 20 pt ink knob ringed in card. */
@interface WGradientTrack : NSView
@property(strong) NSArray<NSColor*>* colours;
@property CGFloat fraction;
@property(copy) void (^onPick)(CGFloat);
@end
@implementation WGradientTrack
- (BOOL)isFlipped { return YES; }
- (void)drawRect:(NSRect)r {
  NSRect b = NSInsetRect(self.bounds, 0.5, 0.5);
  NSBezierPath* capsule = [NSBezierPath bezierPathWithRoundedRect:b xRadius:b.size.height / 2 yRadius:b.size.height / 2];
  if (self.colours.count == 2 && self.colours[0].alphaComponent < 0.01) {
    [NSGraphicsContext saveGraphicsState];
    [capsule addClip];
    for (int i = 0; i * 6 < b.size.width; i++) for (int j = 0; j < 4; j++) {
      [((i + j) % 2 ? NSColor.whiteColor : [NSColor colorWithWhite:0.86 alpha:1]) setFill];
      NSRectFill(NSMakeRect(i * 6, j * 6, 6, 6));
    }
    [NSGraphicsContext restoreGraphicsState];
  }
  [[[NSGradient alloc] initWithColors:self.colours] drawInBezierPath:capsule angle:0];
  [RULE setStroke];
  [capsule stroke];
  CGFloat run = self.bounds.size.width - 20, x = run * MAX(0, MIN(1, self.fraction));
  NSRect knob = NSMakeRect(x, 1, 20, 20);
  NSShadow* sh = [NSShadow new];
  sh.shadowColor = [NSColor colorWithWhite:0 alpha:0.18];
  sh.shadowBlurRadius = 2;
  sh.shadowOffset = NSMakeSize(0, -1);
  [NSGraphicsContext saveGraphicsState];
  [sh set];
  [INK setFill];
  [[NSBezierPath bezierPathWithOvalInRect:knob] fill];
  [NSGraphicsContext restoreGraphicsState];
  NSBezierPath* ring = [NSBezierPath bezierPathWithOvalInRect:NSInsetRect(knob, 1, 1)];
  ring.lineWidth = 2;
  [CARD setStroke];
  [ring stroke];
}
- (void)pick:(NSEvent*)e {
  CGFloat x = [self convertPoint:e.locationInWindow fromView:nil].x;
  self.fraction = MAX(0, MIN(1, (x - 10) / MAX(1, self.bounds.size.width - 20)));
  [self setNeedsDisplay:YES];
  if (self.onPick) self.onPick(self.fraction);
}
- (void)mouseDown:(NSEvent*)e { [self pick:e]; }
- (void)mouseDragged:(NSEvent*)e { [self pick:e]; }
- (BOOL)acceptsFirstMouse:(NSEvent*)e { return YES; }
@end

@interface WColourRow : WRow
@property(strong) WSetting* setting;
@property(strong) NSTextField *title, *hint, *chevron;
@property(strong) NSView* swatch;
@property(strong) NSMutableArray* tracks;  // [label?, track]
@property BOOL open;
@property CGFloat h, s, v;
@end
@implementation WColourRow
- (CGFloat)headerHeight:(CGFloat)w {
  CGFloat tw = w - 14 - 26 - 8 - 12 - 14 - 10, h = lineH(self.title);
  if (self.hint.stringValue.length) h += 1 + measure(self.hint, tw);
  return MAX(54, h + 18);
}
- (CGFloat)heightFor:(CGFloat)w {
  CGFloat h = [self headerHeight:w];
  if (self.open) h += 22 + ([self.setting.type isEqualToString:@"color4"] ? 3 : 2) * (10 + 15 + 6 + 22) + 14;
  return h;
}
- (void)sync {
  NSArray* c = self.setting.channels;
  NSColor* rgb = [NSColor colorWithSRGBRed:[c[0] floatValue] green:[c[1] floatValue] blue:[c[2] floatValue] alpha:1];
  CGFloat hh, ss, vv, aa;
  [[rgb colorUsingColorSpace:NSColorSpace.genericRGBColorSpace] getHue:&hh saturation:&ss brightness:&vv alpha:&aa];
  if (ss > 0.001 && vv > 0.001) self.h = hh * 360;
  self.s = ss;
  self.v = vv;
  self.swatch.layer.backgroundColor = rgb.CGColor;
  if (!self.tracks.count) return;
  WGradientTrack* hue = self.tracks[0];
  hue.fraction = self.h / 360;
  NSMutableArray* rainbow = [NSMutableArray new];
  for (int i = 0; i <= 6; i++) [rainbow addObject:hsv(i * 60, 1, 1)];
  hue.colours = rainbow;
  WGradientTrack* strength = self.tracks[2];
  strength.colours = @[hsv(self.h, 0, self.v), hsv(self.h, 1, self.v)];
  strength.fraction = self.s;
  WGradientTrack* bright = self.tracks[4];
  bright.colours = @[NSColor.blackColor, hsv(self.h, self.s, 1)];
  bright.fraction = self.v;
  if (self.tracks.count > 6) {
    WGradientTrack* opacity = self.tracks[6];
    opacity.colours = @[NSColor.clearColor, rgb];
    opacity.fraction = [c[3] floatValue];
  }
  for (NSView* t in self.tracks) [t setNeedsDisplay:YES];
}
- (void)emit {
  NSColor* c = [hsv(self.h, self.s, self.v) colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
  NSMutableArray* values = [@[@(c.redComponent), @(c.greenComponent), @(c.blueComponent)] mutableCopy];
  if ([self.setting.type isEqualToString:@"color4"]) [values addObject:self.setting.channels[3]];
  changed(self.setting, values, NO);
  [self sync];
}
- (void)toggleOpen {
  self.open = !self.open;
  if (self.open && !self.tracks.count) {
    self.tracks = [NSMutableArray new];
    __weak WColourRow* weak = self;
    WGradientTrack* hue = [WGradientTrack new];
    hue.onPick = ^(CGFloat f) { weak.h = f * 360; [weak emit]; };
    [self.tracks addObject:hue];
    NSArray* names = [self.setting.type isEqualToString:@"color4"] ? @[@"Strength", @"Brightness", @"Opacity"] : @[@"Strength", @"Brightness"];
    for (NSUInteger i = 0; i < names.count; i++) {
      NSTextField* l = label(names[i], 11.5, 600, QUIET);
      track(l, 0.6);
      WGradientTrack* t = [WGradientTrack new];
      if (i == 0) t.onPick = ^(CGFloat f) { weak.s = f; [weak emit]; };
      if (i == 1) t.onPick = ^(CGFloat f) { weak.v = f; [weak emit]; };
      if (i == 2) t.onPick = ^(CGFloat f) {
        NSMutableArray* c = [weak.setting.channels mutableCopy];
        c[3] = @(f);
        changed(weak.setting, c, NO);
        [weak sync];
      };
      [self.tracks addObject:l];
      [self.tracks addObject:t];
    }
    for (NSView* v in self.tracks) [self addSubview:v];
    [self sync];
  }
  for (NSView* v in self.tracks) v.hidden = !self.open;
  self.chevron.stringValue = self.open ? @"⌄" : @"›";
  NSView* settings = self.superview;
  while (settings && ![settings respondsToSelector:@selector(layoutPage)]) settings = settings.superview;
  [settings performSelector:@selector(layoutPage)];
}
- (void)layout {
  [super layout];
  CGFloat w = self.bounds.size.width, hh = [self headerHeight:w];
  CGFloat tw = w - 14 - 26 - 8 - 12 - 14 - 10, th = lineH(self.title), dh = self.hint.stringValue.length ? 1 + measure(self.hint, tw) : 0;
  place(self.title, 14, (hh - th - dh) / 2, tw, th);
  place(self.hint, 14, (hh - th - dh) / 2 + th + 1, tw, MAX(0, dh - 1));
  [self.chevron sizeToFit];
  place(self.chevron, w - 14 - 10, (hh - self.chevron.frame.size.height) / 2, 12, self.chevron.frame.size.height);
  place(self.swatch, w - 14 - 12 - 8 - 26, (hh - 26) / 2, 26, 26);
  if (!self.open) return;
  CGFloat y = hh;
  place(self.tracks[0], 14, y, w - 28, 22);
  y += 22;
  for (NSUInteger i = 1; i + 1 < self.tracks.count; i += 2) {
    y += 10;
    [(NSTextField*)self.tracks[i] sizeToFit];
    place(self.tracks[i], 14, y, w - 28, 15);
    y += 15 + 6;
    place(self.tracks[i + 1], 14, y, w - 28, 22);
    y += 22;
  }
}
@end
static WColourRow* colourRow(WSetting* s) {
  WColourRow* r = [WColourRow new];
  r.setting = s;
  r.title = label(s.label, 15.5, 400, INK);
  r.hint = wrapLabel(s.hint, 12.5, 400, QUIET);
  r.chevron = label(@"›", 17, 400, FAINT);
  r.swatch = [NSView new];
  r.swatch.wantsLayer = YES;
  r.swatch.layer.cornerRadius = 8;
  r.swatch.layer.cornerCurve = kCACornerCurveContinuous;
  r.swatch.layer.borderWidth = 1;
  r.swatch.layer.borderColor = RULE.CGColor;
  for (NSView* v in @[r.title, r.hint, r.chevron, r.swatch]) [r addSubview:v];
  __weak WColourRow* weak = r;
  r.onClick = ^{ [weak toggleOpen]; };
  [r sync];
  return r;
}

/* SettingTypedRow: whatever the engine's row is, as Android draws it. */
static WBlock* typedRow(WSetting* s) {
  if (!s) return nil;
  if ([s.type isEqualToString:@"bool"])
    return boolRow(s.label, s.hint, s.enabled, ^(BOOL on) { changed(s, @[@(on ? 1 : 0)], YES); });
  if ([s.type isEqualToString:@"enum"])
    return enumRow(s.label, s.hint, s.options, s.index, ^(NSInteger i) { changed(s, @[@(i)], YES); });
  if (s.isColour) return colourRow(s);
  BOOL intLike = [s.type isEqualToString:@"int"];
  CGFloat span = s.maximum - s.minimum;
  int steps = intLike && span >= 1 ? (int)lround(span) - 1 : 0;
  return sliderRow(s.label, [WEngine formatted:s], s.hint, s.number, s.minimum, s.maximum, MAX(0, steps), ^(CGFloat v, WSliderRow* row) {
    CGFloat written = intLike ? round(v) : v;
    changed(s, @[@(written)], NO);
    row.value.stringValue = [WEngine formatted:s];
  });
}
static NSString* local(WSetting* s) {
  NSRange dot = [s.ident rangeOfString:@"."];
  return dot.location == NSNotFound ? s.ident : [s.ident substringFromIndex:dot.location + 1];
}

#pragma mark - Pages

typedef NS_ENUM(NSInteger, WPage) {
  PDisplay, PControls, PModes, PBot, PFood, PProfile, PNotifications, PPrivacy, PThemes, PVersion, PHelp, PAbout, PCount
};
static NSString* const PageGroup[] = {@"Arena", @"Arena", @"Playing help", @"Playing help", @"Food", @"Account", @"Account",
                                      @"Account", @"Accessibility", @"This computer", @"Help", @"About"};
static NSString* const PageTitle[] = {@"Display", @"Controls", @"Modes", @"Bot", @"Food style", @"Profile", @"Notifications",
                                      @"Privacy", @"Themes", @"Version", @"Help & feedback", @"About Wyrm"};
static NSString* const PageSub[] = {@"Scores, names, minimap, text sizes", @"Mouse and your keys",
                                    @"Normal, Assist, helper lines and arena colours", @"When it circles, how wide it swings",
                                    @"Original, rings and geometric shapes", @"Name, username, scores",
                                    @"Which alerts reach you as Mac notifications", @"Your activity, and what is stored",
                                    @"Paper, dark and colour appearances", @"Wyrm for Mac and its settings format",
                                    @"Report a problem, ideas, your reports", @"The story, the maker, and how to support"};
static NSString* const PageSymbol[] = {@"display", @"computermouse", @"scope", @"cpu", @"circle.grid.3x3.fill", @"person.crop.circle",
                                       @"bell", @"shield", @"paintpalette", @"info.circle", @"questionmark.circle", @"heart"};

/* State the pages keep while Settings is open. */
static BOOL displayAdvanced, modesAdvanced = YES, themesAdvanced;
static NSInteger modesMode = 1, foodMode = 0;
static NSString* revealId;

static void addTyped(WCardBlock* c, NSArray<WSetting*>* rows) { for (WSetting* s in rows) [c add:typedRow(s)]; }
static NSArray<WSetting*>* named(NSArray<NSString*>* ids) {
  NSMutableArray* out = [NSMutableArray new];
  for (NSString* i in ids) { WSetting* s = [WEngine named:i]; if (s) [out addObject:s]; }
  return out;
}

/* Settings › Display (spec page 09): Basic, Camera, then Advanced. */
static void displayPage(WStack* p) {
  NSArray* basicIds = @[@"general.snake_scores", @"general.show_own_name", @"general.minimap_size", @"general.ui_font"];
  [p add:sectionLabel(@"Basic", 18)];
  WCardBlock* basic = [WCardBlock new];
  addTyped(basic, named(basicIds));
  [p add:basic];
  [p add:sectionLabel(@"Camera", 22)];
  [p add:card(@[boolRow(@"Look ahead", @"Like slither: the view moves ahead of your snake, toward where it is going, and a little further while boosting.",
                        [WStore lookAhead], ^(BOOL on) { [WStore setLookAhead:on]; })])];
  NSMutableArray* advanced = [NSMutableArray new];
  for (WSetting* s in [WEngine settings]) {
    BOOL general = [s.group isEqualToString:@"general"] || [s.group hasPrefix:@"general."];
    if (general && ![s.group isEqualToString:@"general.bot"] && ![basicIds containsObject:s.ident] &&
        ![s.ident isEqualToString:@"general.vsync"] && s.label.length) [advanced addObject:s];
  }
  if ([advanced indexOfObjectPassingTest:^BOOL(WSetting* s, NSUInteger i, BOOL* stop) { return [s.ident isEqualToString:revealId]; }] != NSNotFound)
    displayAdvanced = YES;
  if (advanced.count) {
    [p add:fold(@"Advanced", displayAdvanced, ^{ displayAdvanced = !displayAdvanced; rebuildPage(); })];
    if (displayAdvanced) {
      WCardBlock* c = [WCardBlock new];
      addTyped(c, advanced);
      [p add:c];
      [p add:caption(@"Zoom step, cursor size and after-death delay live here — the things nobody touches twice. Vsync is always on and the display runs at its fastest.")];
    }
  }
}

/* Settings › Bot (spec page 13). */
static void botPage(WStack* p) {
  [p add:holdBlock([NSView new], 18, 0)];
  [p add:card(@[introRow(@"Let the bot play", @"Turn it on with the Bot key in a match. It eats, dodges snakes, breaks away with boost when it is surrounded, and coils round itself once it is big.")])];
  [p add:sectionLabel(@"Basic · behaviour", 22)];
  WCardBlock* c = [WCardBlock new];
  addTyped(c, named(@[@"general.bot_circle", @"general.bot_radius"]));
  [p add:c];
  [p add:caption(@"Laser and helper drawing moved to Assist, where you can actually see them.")];
}

#pragma mark Modes (with the snake preview)

@interface WSnakePreview : NSView
@property NSInteger mode;
@property BOOL spine, castShadow;
@property CGFloat spineWidth;
@end
@implementation WSnakePreview
- (BOOL)isFlipped { return YES; }
- (void)drawRect:(NSRect)r {
  NSRect box = NSInsetRect(self.bounds, 0.5, 0.5);
  NSBezierPath* frame = [NSBezierPath bezierPathWithRoundedRect:box xRadius:12 yRadius:12];
  [WELL setFill];
  [frame fill];
  [RULE setStroke];
  [frame stroke];
  int total = 160;
  CGFloat W = self.bounds.size.width, H = self.bounds.size.height;
  CGFloat span = 1 + (total - 1) * (8.0 / 48.0) + 0.7, scale = MIN(H * 0.34, (W - 28) / span);
  CGFloat step = 8 * (scale / 48), left = (W - span * scale) / 2, amp = H * 0.16;
  NSPoint (^at)(int) = ^NSPoint(int i) {
    CGFloat along = i / (total - 1.0);
    return NSMakePoint(left + scale * 0.5 + i * step, H * 0.5 + amp * sin(along * 6.2831855 * 1.15));
  };
  NSColor* bead = rgba(0xFF5FB98B), *dark = rgba(0xFF3E8A63);
  if (self.castShadow && self.mode != 3)
    for (int i = 0; i < total; i++) {
      NSPoint c = at(i);
      [[NSColor colorWithWhite:0 alpha:0.35] setFill];
      [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(c.x - scale * 0.57, c.y - scale * 0.57 + scale * 0.07, scale * 1.14, scale * 1.14)] fill];
    }
  if (self.mode == 3) {
    NSBezierPath* path = [NSBezierPath bezierPath];
    [path moveToPoint:at(0)];
    for (int i = 1; i < total; i++) [path lineToPoint:at(i)];
    path.lineWidth = scale;
    path.lineCapStyle = NSLineCapStyleRound;
    path.lineJoinStyle = NSLineJoinStyleRound;
    [[bead colorWithAlphaComponent:0.8] setStroke];
    [path stroke];
  } else {
    for (int i = 0; i < total; i++) {
      NSPoint c = at(i);
      NSRect o = NSMakeRect(c.x - scale / 2, c.y - scale / 2, scale, scale);
      NSColor* colour = self.mode == 1 ? ((total - 1 - i) % 6 < 3 ? bead : dark) : bead;
      if (self.mode == 0) {
        NSGradient* g = [[NSGradient alloc] initWithStartingColor:WMix(bead, NSColor.whiteColor, 0.35) endingColor:dark];
        [g drawInBezierPath:[NSBezierPath bezierPathWithOvalInRect:o] relativeCenterPosition:NSMakePoint(-0.3, 0.35)];
      } else {
        [colour setFill];
        [[NSBezierPath bezierPathWithOvalInRect:o] fill];
      }
    }
  }
  if (self.spine && self.spineWidth > 0) {
    NSBezierPath* path = [NSBezierPath bezierPath];
    [path moveToPoint:at(0)];
    for (int i = 1; i < total; i++) [path lineToPoint:at(i)];
    path.lineCapStyle = NSLineCapStyleRound;
    path.lineJoinStyle = NSLineJoinStyleRound;
    CGFloat over = scale * MAX(0, MIN(1, self.spineWidth));
    path.lineWidth = over + MIN(over, 1.7);
    [[NSColor colorWithWhite:0 alpha:0.35] setStroke];
    [path stroke];
    path.lineWidth = over;
    [[NSColor colorWithWhite:1 alpha:0.8] setStroke];
    [path stroke];
  }
  /* The head: eyes forward, as the arena draws them last. */
  NSPoint head = at(total - 1), prev = at(total - 3);
  CGFloat ang = atan2(head.y - prev.y, head.x - prev.x);
  for (int side = -1; side <= 1; side += 2) {
    CGFloat ex = head.x + cos(ang) * scale * 0.2 - sin(ang) * side * scale * 0.22, ey = head.y + sin(ang) * scale * 0.2 + cos(ang) * side * scale * 0.22;
    [NSColor.whiteColor setFill];
    [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(ex - scale * 0.2, ey - scale * 0.2, scale * 0.4, scale * 0.4)] fill];
    [NSColor.blackColor setFill];
    [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(ex - scale * 0.11 + cos(ang) * scale * 0.06, ey - scale * 0.11 + sin(ang) * scale * 0.06, scale * 0.22, scale * 0.22)] fill];
  }
}
@end

static NSString* spineWidthLabel(CGFloat v) {
  if (v <= 0.005) return @"Hidden";
  if (v >= 0.995) return @"Snake width";
  return [NSString stringWithFormat:@"%ld%%", lround(v * 100)];
}

/* Settings › Modes (spec page 12), the computer's version (no joystick sections). */
static void modesPage(WStack* p) {
  [p add:holdBlock([NSView new], 18, 0)];
  [p add:card(@[introRow(@"Arena modes", @"Tune the normal arena and the helper view independently.")])];
  [p add:sectionLabel(@"Choose mode", 22)];
  WSegmented* seg = [[WSegmented alloc] initWithOptions:@[@"Assist mode", @"Normal mode"]];
  seg.selected = modesMode == 1 ? 0 : 1;
  seg.onSelect = ^(NSInteger i) { modesMode = i == 0 ? 1 : 0; rebuildPage(); };
  WHoldRow* segRow = holdRow(seg, 34, NSEdgeInsetsMake(12, 12, 8, 12));
  [p add:card(@[segRow])];

  NSString* group = modesMode == 1 ? @"assist" : @"normal";
  NSSet* foodIds = [NSSet setWithArray:@[@"food_type", @"food_scale", @"food_float", @"food_flicker", @"const_food_scale", @"uniform_food_color", @"food_color"]];
  NSSet* dotIds = [NSSet setWithArray:@[@"show_crosshair", @"head_dot_size", @"head_dot_color"]];
  NSSet* snakeIds = [NSSet setWithArray:@[@"render_mode", @"spine", @"spine_mine", @"spine_width", @"snake_shadow", @"hide_cosmetics"]];
  NSSet* boostIds = [NSSet setWithArray:@[@"show_boost", @"boost_type", @"boost_own"]];
  NSMutableArray *mode = [NSMutableArray new], *colours = [NSMutableArray new], *rest = [NSMutableArray new];
  for (WSetting* s in [WEngine settings]) if ([s.group isEqualToString:group] && s.label.length) [mode addObject:s];
  WSetting* (^find)(NSString*) = ^WSetting*(NSString* name) { return [WEngine named:[NSString stringWithFormat:@"%@.%@", group, name]]; };
  for (WSetting* s in mode) {
    NSString* l = local(s);
    if (![foodIds containsObject:l] && ![dotIds containsObject:l] && s.isColour) [colours addObject:s];
  }
  for (WSetting* s in mode) {
    NSString* l = local(s);
    if (![colours containsObject:s] && ![foodIds containsObject:l] && ![dotIds containsObject:l] && ![snakeIds containsObject:l] &&
        ![boostIds containsObject:l] && ![l isEqualToString:@"bg_scale"]) [rest addObject:s];
  }

  /* Snake look (OM, 2026-10-05): follows the visible mode tab. */
  [p add:sectionLabel(@"Snake", 22)];
  WCardBlock* snake = [WCardBlock new];
  WSetting *render = find(@"render_mode"), *spine = find(@"spine"), *width = find(@"spine_width"), *shadow = find(@"snake_shadow");
  WSnakePreview* preview = [WSnakePreview new];
  preview.mode = render ? render.index : 0;
  preview.spine = spine.enabled;
  preview.spineWidth = width ? width.number : 0.1;
  preview.castShadow = shadow.enabled;
  WFlipped* previewBox = [WFlipped new];
  NSTextField* previewLabel = label(@"Preview", 12.5, 400, QUIET);
  [previewBox addSubview:previewLabel];
  [previewBox addSubview:preview];
  placeLabel(previewLabel, 0, 0, 300);
  preview.frame = NSMakeRect(0, 24, 10, 88);
  preview.autoresizingMask = NSViewWidthSizable;
  [snake add:holdRow(previewBox, 112, NSEdgeInsetsMake(12, 14, 12, 14))];
  if (render) [snake add:typedRow(render)];
  if (spine) [snake add:typedRow(spine)];
  WSetting* mine = find(@"spine_mine");
  if (mine && spine.enabled)
    [snake add:enumRow(@"Show spine on", @"Mine shows it on your snake only", @[@"Mine", @"Everyone"], mine.enabled ? 0 : 1,
                       ^(NSInteger i) { changed(mine, @[@(i == 0 ? 1 : 0)], YES); })];
  if (width && spine.enabled)
    [snake add:sliderRow(@"Spine width", spineWidthLabel(width.number), @"0 hides it; full is as wide as the snake", width.number, 0, 1, 0,
                         ^(CGFloat v, WSliderRow* row) {
                           changed(width, @[@(v)], NO);
                           row.value.stringValue = spineWidthLabel(v);
                           preview.spineWidth = v;
                           [preview setNeedsDisplay:YES];
                         })];
  if (shadow) [snake add:typedRow(shadow)];
  if (modesMode == 1 && find(@"hide_cosmetics")) [snake add:typedRow(find(@"hide_cosmetics"))];
  [p add:snake];
  [p add:caption(@"Skinless keeps the plain snake's width and length. Only the skin turns see-through. Spine is a white line down every snake; its width goes from hidden to the snake's own. Snake shadow is the original app's shadow under every snake.")];

  /* Boost (OM, 2026-10-18): on/off, its style, and whose boost shows. */
  WSetting *boostOn = find(@"show_boost"), *boostType = find(@"boost_type"), *boostOwn = find(@"boost_own");
  if (boostOn) {
    [p add:sectionLabel(@"Boost", 22)];
    WCardBlock* boost = [WCardBlock new];
    [boost add:typedRow(boostOn)];
    if (boostOn.enabled) {
      if (boostType) [boost add:typedRow(boostType)];
      if (boostOwn)
        [boost add:enumRow(@"Show boost on", @"Mine shows only your own boost", @[@"Mine", @"Everyone"], boostOwn.enabled ? 0 : 1,
                           ^(NSInteger i) { changed(boostOwn, @[@(i == 0 ? 1 : 0)], YES); })];
    }
    [p add:boost];
  }
  if (colours.count) {
    [p add:sectionLabel(@"Arena colours", 22)];
    WCardBlock* c = [WCardBlock new];
    for (WSetting* s in colours) [c add:colourRow(s)];
    [p add:c];
  }
  /* Arena background size: Desktop's editor is a slider here, the same engine value. */
  WSetting* bg = find(@"bg_scale");
  if (bg) {
    [p add:sectionLabel(@"Arena background", 22)];
    CGFloat base = 599.0 / 4096.0;
    [p add:card(@[sliderRow(@"Arena background size", [NSString stringWithFormat:@"%ld%%", lround(bg.number / base * 100)], @"",
                            bg.number, bg.minimum, bg.maximum, 0, ^(CGFloat v, WSliderRow* row) {
                              changed(bg, @[@(v)], NO);
                              row.value.stringValue = [NSString stringWithFormat:@"%ld%%", lround(v / base * 100)];
                            })])];
  }
  [p add:fold(@"Advanced · helper lines", modesAdvanced, ^{ modesAdvanced = !modesAdvanced; rebuildPage(); })];
  if (modesAdvanced) {
    WCardBlock* c = [WCardBlock new];
    addTyped(c, named(@[@"general.laser_thickness", @"general.laser_color"]));
    addTyped(c, rest);
    [p add:c];
  }
}

#pragma mark Food

static const uint32_t FOOD_HUES[] = {0xFFC080FF, 0xFF9099FF, 0xFF80D0D0, 0xFF80FF80, 0xFFEEEE70, 0xFFFFA060, 0xFFFF9090, 0xFFFF4040, 0xFFE030E0};
static NSInteger shapeOf(NSInteger style) { return style <= 1 ? style : style - 1; }

static void polygon(NSPoint c, CGFloat r, int points, CGFloat (^radius)(int)) {
  NSBezierPath* p = [NSBezierPath bezierPath];
  for (int i = 0; i < points; i++) {
    CGFloat a = -M_PI / 2 + i * 2 * M_PI / points, rr = r * (radius ? radius(i) : 1);
    NSPoint q = NSMakePoint(c.x + cos(a) * rr, c.y + sin(a) * rr);
    if (i == 0) [p moveToPoint:q]; else [p lineToPoint:q];
  }
  [p closePath];
  [p fill];
}
/* Food as the arena draws it: a soft halo, the body, a small bright highlight. */
static void glowingFood(NSInteger shape, NSPoint c, CGFloat r, NSColor* colour, CGFloat glow) {
  NSGradient* halo = [[NSGradient alloc] initWithStartingColor:[colour colorWithAlphaComponent:0.55 * glow] endingColor:[colour colorWithAlphaComponent:0]];
  [halo drawFromCenter:c radius:0 toCenter:c radius:r * 2.8 options:0];
  [[colour colorWithAlphaComponent:0.55 + 0.45 * glow] set];
  switch (shape) {
    case 0: [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(c.x - r, c.y - r, 2 * r, 2 * r)] fill]; break;
    case 1: {
      NSBezierPath* ring = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(c.x - r * 0.88, c.y - r * 0.88, r * 1.76, r * 1.76)];
      ring.lineWidth = r * 0.34;
      [ring stroke];
      break;
    }
    case 2: polygon(c, r, 10, ^CGFloat(int i) { return i % 2 == 0 ? 1 : 0.45; }); break;
    case 3: polygon(c, r, 3, nil); break;
    case 4: polygon(c, r, 4, nil); break;
    case 5: polygon(c, r, 6, nil); break;
    case 6: NSRectFill(NSMakeRect(c.x - r * 0.85, c.y - r * 0.85, r * 1.7, r * 1.7)); break;
    default: polygon(c, r, 24, ^CGFloat(int i) { return 0.82 + 0.18 * cos(i * 6.0 * 2.0 * M_PI / 24.0); });
  }
  if (shape != 1) {
    [[NSColor colorWithWhite:1 alpha:0.38 * glow] setFill];
    [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(c.x - r * 0.3 - r * 0.28, c.y - r * 0.32 - r * 0.28, r * 0.56, r * 0.56)] fill];
  }
}

@interface WFoodPreview : NSView
@property NSInteger style;
@property CGFloat scale;
@property BOOL uniform, drift, flicker;
@property(strong) NSColor* uniformColour;
@property(strong) NSTimer* timer;
@property CGFloat time;
@end
@implementation WFoodPreview
- (BOOL)isFlipped { return YES; }
- (void)viewDidMoveToWindow {
  [self.timer invalidate];
  self.timer = nil;
  if (!self.window || !(self.drift || self.flicker)) return;
  __weak WFoodPreview* weak = self;
  self.timer = [NSTimer scheduledTimerWithTimeInterval:1.0 / 30 repeats:YES block:^(NSTimer* t) {
    weak.time = fmod(weak.time + 1.0 / 30 / 6.0, 1);
    [weak setNeedsDisplay:YES];
  }];
}
- (void)drawRect:(NSRect)dirty {
  NSBezierPath* frame = [NSBezierPath bezierPathWithRoundedRect:self.bounds xRadius:22 yRadius:22];
  [NSGraphicsContext saveGraphicsState];
  [frame addClip];
  [rgba(0xFF161B22) setFill];
  NSRectFill(self.bounds);
  CGFloat step = 22, w = self.bounds.size.width, h = self.bounds.size.height;
  int row = 0;
  [[NSColor colorWithWhite:1 alpha:0.035] setFill];
  for (CGFloat y = step / 2; y < h; y += step * 0.86, row++)
    for (CGFloat x = row % 2 ? step : step / 2; x < w; x += step)
      [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(x - 1.4, y - 1.4, 2.8, 2.8)] fill];
  srand48(0x5715);
  CGFloat base = 5.5 * MAX(0.25, MIN(3, self.scale)), phase = self.time * 6.283;
  for (int i = 0; i < 34; i++) {
    CGFloat mx = drand48(), my = drand48(), ms = drand48(), mp = drand48() * 6.283;
    int hue = (int)(drand48() * 9), shape = (int)(drand48() * 8);
    CGFloat wobble = self.drift ? 4 : 0;
    NSPoint c = NSMakePoint(mx * w + cos(phase + mp) * wobble, my * h + sin(phase * 1.3 + mp) * wobble);
    CGFloat glow = self.flicker ? 0.55 + 0.45 * ((sin(phase * 3 + mp * 2) + 1) / 2) : 1;
    NSColor* colour = self.uniform ? self.uniformColour : rgba(FOOD_HUES[hue]);
    glowingFood(self.style == 2 ? shape : shapeOf(self.style), c, base * (0.65 + ms * 0.7), colour, glow);
  }
  [NSGraphicsContext restoreGraphicsState];
  [RULE setStroke];
  [frame stroke];
  NSDictionary* attrs = @{NSFontAttributeName: body(9.5, 700), NSForegroundColorAttributeName: [NSColor colorWithWhite:1 alpha:0.72], NSKernAttributeName: @1.2};
  NSSize ts = [@"LIVE PREVIEW" sizeWithAttributes:attrs];
  NSRect pill = NSMakeRect(12, 12, ts.width + 18, ts.height + 8);
  [[NSColor colorWithWhite:1 alpha:0.08] setFill];
  [[NSBezierPath bezierPathWithRoundedRect:pill xRadius:pill.size.height / 2 yRadius:pill.size.height / 2] fill];
  [@"LIVE PREVIEW" drawAtPoint:NSMakePoint(21, 16) withAttributes:attrs];
}
@end

@interface WFoodTile : WTap
@property NSInteger style;
@property BOOL selected;
@property(strong) NSTextField* name;
@end
@implementation WFoodTile
- (void)drawRect:(NSRect)dirty {
  NSRect floor = NSMakeRect(8, 8, self.bounds.size.width - 16, (self.bounds.size.width - 16) / 1.25);
  NSBezierPath* clip = [NSBezierPath bezierPathWithRoundedRect:floor xRadius:12 yRadius:12];
  [NSGraphicsContext saveGraphicsState];
  [clip addClip];
  [rgba(0xFF161B22) setFill];
  NSRectFill(floor);
  CGFloat r = MIN(floor.size.width, floor.size.height) * 0.17;
  if (self.style == 2) {
    int shapes[] = {0, 2, 3, 5};
    for (int spot = 0; spot < 4; spot++) {
      CGFloat x = floor.origin.x + floor.size.width * (spot % 2 == 0 ? 0.33 : 0.67), y = floor.origin.y + floor.size.height * (spot < 2 ? 0.33 : 0.67);
      glowingFood(shapes[spot], NSMakePoint(x, y), r * 0.62, rgba(FOOD_HUES[(spot * 2 + 1) % 9]), 1);
    }
  } else glowingFood(shapeOf(self.style), NSMakePoint(NSMidX(floor), NSMidY(floor)), r, rgba(FOOD_HUES[self.style % 9]), 1);
  [NSGraphicsContext restoreGraphicsState];
  if (self.selected) {
    NSRect dot = NSMakeRect(NSMaxX(floor) - 26, floor.origin.y + 6, 20, 20);
    [INK setFill];
    [[NSBezierPath bezierPathWithOvalInRect:dot] fill];
    NSImage* check = symbol(@"checkmark", 9, NSFontWeightHeavy);
    [check lockFocus];
    [ON_INK set];
    NSRectFillUsingOperation(NSMakeRect(0, 0, check.size.width, check.size.height), NSCompositingOperationSourceAtop);
    [check unlockFocus];
    [check drawInRect:NSMakeRect(NSMidX(dot) - check.size.width / 2, NSMidY(dot) - check.size.height / 2, check.size.width, check.size.height)];
  }
}
- (void)layout {
  [super layout];
  CGFloat w = self.bounds.size.width;
  [self.name sizeToFit];
  place(self.name, 4, 8 + (w - 16) / 1.25 + 7, w - 8, self.name.frame.size.height);
}
@end

@interface WFoodGrid : WBlock
@property(strong) NSMutableArray<WFoodTile*>* tiles;
@end
@implementation WFoodGrid
- (CGFloat)tileW:(CGFloat)w { return (w - 20) / 3; }
- (CGFloat)tileH:(CGFloat)w { CGFloat t = [self tileW:w]; return 8 + (t - 16) / 1.25 + 7 + 17 + 2 + 8; }
- (CGFloat)heightFor:(CGFloat)w {
  NSInteger rows = (self.tiles.count + 2) / 3;
  return rows * [self tileH:w] + MAX(0, rows - 1) * 10;
}
- (void)layout {
  [super layout];
  CGFloat w = self.bounds.size.width, tw = [self tileW:w], th = [self tileH:w];
  for (NSUInteger i = 0; i < self.tiles.count; i++)
    place(self.tiles[i], (i % 3) * (tw + 10), (i / 3) * (th + 10), tw, th);
}
@end

static BOOL isFood(WSetting* s) {
  NSString* l = local(s);
  return [l hasPrefix:@"food_"] || [l isEqualToString:@"const_food_scale"] || [l isEqualToString:@"uniform_food_color"];
}
static void foodPage(WStack* p) {
  NSString* group = foodMode == 0 ? @"normal" : @"assist";
  NSMutableArray* food = [NSMutableArray new];
  for (WSetting* s in [WEngine settings]) if ([s.group isEqualToString:group] && isFood(s)) [food addObject:s];
  WSetting* (^find)(NSString*) = ^WSetting*(NSString* name) { return [WEngine named:[NSString stringWithFormat:@"%@.%@", group, name]]; };
  WSetting *style = find(@"food_type"), *scale = find(@"food_scale"), *uniform = find(@"uniform_food_color"), *colour = find(@"food_color");
  WSetting *drift = find(@"food_float"), *flicker = find(@"food_flicker"), *constant = find(@"const_food_scale");
  [p add:holdBlock([NSView new], 18, 0)];
  WFoodPreview* preview = [WFoodPreview new];
  preview.style = style ? style.index : 0;
  preview.scale = scale ? scale.number : 1;
  preview.uniform = uniform.enabled;
  NSArray* c = colour.channels;
  preview.uniformColour = colour ? [NSColor colorWithSRGBRed:[c[0] floatValue] green:[c[1] floatValue] blue:[c[2] floatValue] alpha:1] : rgba(FOOD_HUES[3]);
  preview.drift = drift.enabled;
  preview.flicker = flicker.enabled;
  [p add:holdBlock(preview, 176, 16)];
  WSegmented* seg = [[WSegmented alloc] initWithOptions:@[@"Normal mode", @"With assist"]];
  seg.selected = foodMode;
  seg.onSelect = ^(NSInteger i) { foodMode = i; rebuildPage(); };
  WBlock* segBlock = holdBlock(seg, 34, 16);
  segBlock.top = 12;
  [p add:segBlock];
  [p add:sectionLabel(@"Shape", 22)];
  if (style) {
    WFoodGrid* grid = [WFoodGrid new];
    grid.side = 16;
    grid.tiles = [NSMutableArray new];
    for (NSUInteger i = 0; i < style.options.count; i++) {
      WFoodTile* t = [WFoodTile new];
      t.style = i;
      t.selected = style.index == (NSInteger)i;
      t.pressScale = YES;
      t.fill = CARD;
      t.hover = CARD;
      t.layer.cornerRadius = 18;
      t.layer.borderWidth = t.selected ? 2 : 1;
      t.layer.borderColor = (t.selected ? INK : RULE).CGColor;
      t.name = label(style.options[i], 12.5, t.selected ? 700 : 600, t.selected ? INK : MUTE);
      t.name.alignment = NSTextAlignmentCenter;
      [t addSubview:t.name];
      t.onClick = ^{ changed(style, @[@(i)], YES); };
      [grid.tiles addObject:t];
      [grid addSubview:t];
    }
    [p add:grid];
  }
  [p add:caption(@"Mixed uses every shape and keeps each morsel the same shape for its whole life.")];
  [p add:sectionLabel(@"Look", 22)];
  WCardBlock* look = [WCardBlock new];
  NSMutableArray* shown = [NSMutableArray new];
  for (WSetting* s in @[scale ?: NSNull.null, constant ?: NSNull.null, uniform ?: NSNull.null,
                        (uniform.enabled && colour) ? colour : NSNull.null, drift ?: NSNull.null, flicker ?: NSNull.null])
    if (![s isEqual:NSNull.null]) [shown addObject:s];
  for (WSetting* s in food) if (s != style && s != colour && ![shown containsObject:s]) [shown addObject:s];
  for (WSetting* s in shown) {
    WBlock* row = typedRow(s);
    if (s == scale) {
      WSliderRow* r = (WSliderRow*)row;
      void (^old)(CGFloat) = r.slider.onChange;
      r.slider.onChange = ^(CGFloat v) { old(v); preview.scale = v; [preview setNeedsDisplay:YES]; };
    }
    [look add:row];
  }
  [p add:look];
  [p add:caption(@"Only how food looks changes. Where it lies, what it is worth and eating it stay the arena's own.")];
}

#pragma mark Controls (keys)

static NSArray* keyGroups(void) {
  return @[@[@"Moving", @[@[@10, @"Boost"], @[@11, @"Turn left"], @[@12, @"Turn right"], @[@8, @"Zoom in"], @[@9, @"Zoom out"]]],
           @[@"In a match", @[@[@15, @"Eyes back"], @[@14, @"Auto restart"], @[@6, @"Restart"], @[@7, @"Quit to the lobby"], @[@4, @"Bot"], @[@3, @"Assist"]]],
           @[@"What you see", @[@[@0, @"HUD"], @[@1, @"Show names"], @[@2, @"Big food"], @[@5, @"Hotkey menu"]]]];
}
static NSString* keyLabel(WHotkey* row) {
  if (!row || row.key < 0) return @"Not set";
  NSString* name = row.keyName.length ? row.keyName : [WEngine nameOfKey:row.key];
  NSDictionary* nice = @{@"SPACE": @"Space", @"LEFT": @"Left arrow", @"RIGHT": @"Right arrow", @"UP": @"Up arrow", @"DOWN": @"Down arrow",
                         @"TAB": @"Tab", @"SHIFT": @"Shift", @"CTRL": @"Control", @"RIGHT CLICK": @"Right click",
                         @"MIDDLE CLICK": @"Middle click", @"MOUSE 4": @"Mouse 4", @"MOUSE 5": @"Mouse 5"};
  if (!name.length || [name isEqualToString:@"KEY"]) return [NSString stringWithFormat:@"Key %d", row.key];
  return nice[name] ?: name;
}
static NSString* titleOfAction(int action) {
  for (NSArray* g in keyGroups()) for (NSArray* a in g[1]) if ([a[0] intValue] == action) return a[1];
  return @"Another action";
}
static int listeningAction = -1;
static NSString* keyNote;

static WTap* chip(NSString* text, BOOL strong) {
  WTap* c = [WTap new];
  c.layer.cornerRadius = 10;
  c.fill = strong ? INK : WELL;
  c.hover = strong ? INK : WMix(WELL, INK, 0.05);
  c.layer.borderWidth = 1;
  c.layer.borderColor = (strong ? INK : RULE).CGColor;
  NSTextField* t = label(text, 13.5, 400, strong ? ON_INK : INK);
  t.alignment = NSTextAlignmentCenter;
  t.identifier = @"text";
  [c addSubview:t];
  [t sizeToFit];
  c.frame = NSMakeRect(0, 0, MAX(112, t.frame.size.width + 24), t.frame.size.height + 14);
  t.frame = NSMakeRect(0, 7, c.frame.size.width, t.frame.size.height);
  t.autoresizingMask = NSViewWidthSizable;
  return c;
}

@interface WKeyRow : WRow
@property(strong) NSTextField *title, *modeLabel;
@property(strong) WSwitch* mode;
@property(strong) WTap* key;
@end
@implementation WKeyRow
- (CGFloat)heightFor:(CGFloat)w { return 54; }
- (void)layout {
  [super layout];
  NSSize s = self.bounds.size;
  CGFloat x = s.width - 14 - self.key.frame.size.width;
  place(self.key, x, (s.height - self.key.frame.size.height) / 2, self.key.frame.size.width, self.key.frame.size.height);
  if (self.mode) {
    /* "Hold" and its switch: on, the helper works while the key is down; off, a press turns it on and off. */
    x -= 12 + 51;
    place(self.mode, x, (s.height - 28) / 2, 51, 28);
    [self.modeLabel sizeToFit];
    CGFloat lw = self.modeLabel.frame.size.width;
    x -= 8 + lw;
    place(self.modeLabel, x, (s.height - self.modeLabel.frame.size.height) / 2, lw, self.modeLabel.frame.size.height);
  }
  CGFloat th = lineH(self.title);
  place(self.title, 14, (s.height - th) / 2, x - 14 - 8, th);
}
@end

static void controlsPage(WStack* p) {
  [WEngine refreshKeys];
  [p add:sectionLabel(@"Mouse", 14)];
  [p add:card(@[valueRow(@"Steer", @"Mouse", nil), valueRow(@"Boost", @"Left click", nil), valueRow(@"Zoom", @"Mouse wheel", nil),
                valueRow(@"Leave the match", @"Esc", nil), valueRow(@"Full screen", @"F11", nil)])];
  [p add:caption(@"Your snake heads for the pointer, measured from the middle of the arena.")];
  NSMutableDictionary* rows = [NSMutableDictionary new];
  for (WHotkey* k in [WEngine hotkeys]) rows[@(k.action)] = k;
  if (!rows.count) { [p add:caption(@"Your keys appear here once the arena has started.")]; return; }
  for (NSArray* g in keyGroups()) {
    [p add:sectionLabel(g[0], 22)];
    WCardBlock* c = [WCardBlock new];
    for (NSArray* a in g[1]) {
      int action = [a[0] intValue];
      WHotkey* row = rows[@(action)];
      if (!row) continue;
      WKeyRow* r = [WKeyRow new];
      r.title = label(a[1], 15.5, 400, INK);
      [r addSubview:r.title];
      if (!row.fixedMode) {
        r.modeLabel = label(@"Hold", 13.5, 400, MUTE);
        r.mode = [WSwitch new];
        r.mode.on = row.mode == 1;
        r.mode.onToggle = ^(BOOL hold) { [WEngine setMode:hold ? 1 : 0 forAction:action]; row.mode = hold ? 1 : 0; };
        [r addSubview:r.modeLabel];
        [r addSubview:r.mode];
      }
      BOOL listening = listeningAction == action;
      r.key = chip(listening ? @"Press a key…" : keyLabel(row), listening);
      r.key.onClick = ^{ keyNote = nil; listeningAction = listening ? -1 : action; rebuildPage(); };
      [r addSubview:r.key];
      [c add:r];
    }
    [p add:c];
    if ([g[0] isEqualToString:@"Moving"]) [p add:caption(@"W and the Up arrow boost too, while no other action uses them.")];
  }
  if (keyNote.length) {
    WCaption* note = caption(keyNote);
    note.text.textColor = INK;
    note.text.font = body(13, 400);
    [p add:note];
  }
  [p add:caption(@"Click a key, then press the new one or a mouse button (right, middle, side). Esc cancels, Delete leaves the action without a key. With Hold on, a helper works only while its key is down; with Hold off, a press turns it on and the next turns it off.")];
  [p add:sectionLabel(@"Defaults", 22)];
  [p add:card(@[actionRow(@"Reset keys to defaults", NO, ^{
    listeningAction = -1;
    keyNote = @"Keys are back to their defaults.";
    [WEngine resetKeys];
    rebuildPage();
  })])];
}
/* What a pressed key binds to (GLFW's codes, as the engine keeps them); 0 for a key that cannot. */
static int engineKey(NSEvent* e) {
  switch (e.keyCode) {
    case 49: return 32;
    case 124: return 262;
    case 123: return 263;
    case 125: return 264;
    case 126: return 265;
    case 122: return 290; case 120: return 291; case 99: return 292; case 118: return 293; case 96: return 294;
    case 97: return 295; case 98: return 296; case 100: return 297; case 101: return 298; case 109: return 299;
    case 111: return 301;
    case 56: case 60: return 340;
    case 59: case 62: return 341;
  }
  NSString* c = e.charactersIgnoringModifiers.uppercaseString;
  if (c.length == 1) {
    unichar u = [c characterAtIndex:0];
    if ((u >= 'A' && u <= 'Z') || (u >= '0' && u <= '9')) return u;
  }
  return 0;
}
static NSString* reservedKey(NSEvent* e) {
  if (e.keyCode == 48) return @"Tab switches the arena chat tab.";
  if (e.keyCode == 103) return @"F11 is full screen.";
  if (e.keyCode == 36 || e.keyCode == 76) return @"Enter is kept for chat.";
  if (e.modifierFlags & NSEventModifierFlagCommand) return @"That key belongs to macOS.";
  return nil;
}
static BOOL bindListening(int key) {
  if (listeningAction < 0) return NO;
  int action = listeningAction;
  listeningAction = -1;
  WHotkey* before = nil;
  for (WHotkey* k in [WEngine hotkeys]) if (k.action == action) before = k;
  NSString* oldLabel = keyLabel(before);
  WHotkey* swapped = [WEngine bindKey:key toAction:action];
  if (swapped) {
    WHotkey* probe = [WHotkey new];
    probe.key = key;
    keyNote = [NSString stringWithFormat:@"%@ was %@'s key, so %@ now has %@.", keyLabel(probe), titleOfAction(swapped.action),
               titleOfAction(swapped.action), oldLabel];
  } else keyNote = key < 0 ? [NSString stringWithFormat:@"%@ has no key now.", titleOfAction(action)] : nil;
  if (rebuildPage) rebuildPage();
  return YES;
}

#pragma mark Themes

@interface WThemeRow : WRow
@property int theme;
@property BOOL selected;
@property(strong) NSTextField *name, *detail;
@end
/* The intensity while its slider is held (-1 when not): swatches follow it live. */
static double themeLive = -1;
@implementation WThemeRow
- (CGFloat)heightFor:(CGFloat)w { return 68; }
- (void)drawRect:(NSRect)dirty {
  WPalette p = WThemePalette(self.theme, themeLive >= 0 ? themeLive : [WStore themeIntensity]);
  NSRect sw = NSMakeRect(14, (68 - 42) / 2, 58, 42);
  NSBezierPath* outer = [NSBezierPath bezierPathWithRoundedRect:sw xRadius:10 yRadius:10];
  [p.paper setFill]; [outer fill]; [p.rule setStroke]; [outer stroke];
  NSBezierPath* inner = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(sw.origin.x + 10, sw.origin.y + 9.5, 38, 23) xRadius:6 yRadius:6];
  [p.card setFill]; [inner fill]; [p.rule setStroke]; [inner stroke];
  NSArray* dots = @[p.ink, p.live, p.link];
  for (int i = 0; i < 3; i++) {
    [dots[i] setFill];
    [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(sw.origin.x + 29 - 9.5 + i * 8 - 2.5 + 2.5, NSMaxY(sw) - 6 - 5, 5, 5)] fill];
  }
  NSRect radio = NSMakeRect(self.bounds.size.width - 14 - 22, 23, 22, 22);
  NSBezierPath* ring = [NSBezierPath bezierPathWithOvalInRect:NSInsetRect(radio, 0.75, 0.75)];
  ring.lineWidth = 1.5;
  [(self.selected ? INK : FAINT) setStroke];
  [ring stroke];
  if (self.selected) { [INK setFill]; [[NSBezierPath bezierPathWithOvalInRect:NSInsetRect(radio, 5, 5)] fill]; }
}
- (void)layout {
  [super layout];
  CGFloat w = self.bounds.size.width, tw = w - 14 - 58 - 24 - 22 - 14;
  CGFloat nh = lineH(self.name), dh = lineH(self.detail);
  place(self.name, 14 + 58 + 12, (68 - nh - dh - 1) / 2, tw, nh);
  place(self.detail, 14 + 58 + 12, (68 - nh - dh - 1) / 2 + nh + 1, tw, dh);
}
@end

static void themesPage(WStack* p) {
  [p add:sectionLabel(@"Themes", 18)];
  WCardBlock* c = [WCardBlock new];
  int selected = [WStore theme];
  for (int i = 0; i < WTHEME_COUNT; i++) {
    WThemeRow* r = [WThemeRow new];
    r.theme = i;
    r.selected = i == selected;
    r.name = label(WThemeName[i], 15.5, r.selected ? 600 : 400, INK);
    r.detail = label(WThemeDetail[i], 12.5, 400, QUIET);
    [r addSubview:r.name];
    [r addSubview:r.detail];
    r.onClick = ^{ if (i != [WStore theme]) [WStore setTheme:i]; };
    [c add:r];
  }
  [p add:c];
  WCaption* note = caption(@"Themes colour the app and arena interface only. Skins, arena background and gameplay stay untouched.");
  note.side = 16;
  note.top = 12;
  [p add:note];
  [p add:fold(@"Advanced settings", themesAdvanced, ^{ themesAdvanced = !themesAdvanced; rebuildPage(); })];
  if (themesAdvanced) {
    double intensity = [WStore themeIntensity];
    WSliderRow* slider = sliderRow(@"Theme intensity", [NSString stringWithFormat:@"%ld%%", lround(intensity * 100)],
                                   @"50% is the original theme look. Lower moves towards Paper; higher is richer.", intensity, 0, 1, 0,
                                   ^(CGFloat v, WSliderRow* row) {
      row.value.stringValue = [NSString stringWithFormat:@"%ld%%", lround(v * 100)];
      /* The whole app follows the knob while it moves (OM). */
      themeLive = v;
      WThemeLive(row.window, [WStore theme], v);
    });
    __weak WSliderRow* weakSlider = slider;
    slider.slider.onEnd = ^{ themeLive = -1; [WStore setThemeIntensity:weakSlider.slider.value]; };
    WButton* reset = [WButton well:nil text:@"Reset"];
    reset.fill = NSColor.clearColor;
    reset.layer.cornerRadius = 12;
    reset.layer.borderWidth = 1;
    reset.layer.borderColor = RULE.CGColor;
    reset.title.textColor = MUTE;
    reset.title.font = body(15, 400);
    reset.enabled = fabs(intensity - 0.5) >= 0.001;
    reset.onClick = ^{ [WStore setThemeIntensity:0.5]; };
    [p add:card(@[slider, holdRow(reset, 46, NSEdgeInsetsMake(14, 14, 14, 14))])];
  }
}

#pragma mark Account pages

/* The privacy document, laid out again whenever its width changes. */
@interface WDocBlock : WBlock
@property(strong) NSView* doc;
@property CGFloat builtWidth, builtHeight;
@end
@implementation WDocBlock
- (CGFloat)heightFor:(CGFloat)w {
  if (fabs(w - self.builtWidth) > 0.5) {
    [self.doc removeFromSuperview];
    CGFloat h;
    self.doc = WPrivacyDocument(w, &h);
    [self addSubview:self.doc];
    self.builtWidth = w;
    self.builtHeight = h;
  }
  return self.builtHeight;
}
@end

static void privacyPage(WStack* p) {
  WAccount* a = [WAccount shared];
  if (a.hasSession) {
    [p add:sectionLabel(@"Activity", 18)];
    [p add:card(@[boolRow(@"Show my activity to friends",
                          @"Friends who follow you back see when you are on Wyrm and which arena you play in. Off, you don't see theirs either.",
                          a.shareActivity, ^(BOOL on) { [a setActivitySharing:on]; })])];
  }
  [p add:sectionLabel(@"What Wyrm keeps", 18)];
  [p add:card(@[valueRow(@"Stored on this Mac", @"Team ID, auth key, all settings", nil),
                valueRow(@"Stored on the server", @"Name, username, photo, bio, scores, when you play", nil),
                valueRow(@"Chat retention", @"Global 24 hours · direct until deleted", nil),
                valueRow(@"Analytics", @"Crash reports, when you play", nil)])];
  [p add:sectionLabel(@"The policy", 22)];
  WDocBlock* doc = [WDocBlock new];
  doc.side = 20;
  [p add:doc];
}

static NSArray* notificationGroups(void) {
  return @[@[@"People", @[@[@"invite", @"Arena invites", @"Someone sends you a server and key."],
                          @[@"dm", @"Direct messages", @"New thread or reply."],
                          @[@"follow", @"New followers", @"When another player starts following you."]]],
           @[@"Trails", @[@[@"trail_like", @"Beads on your trails", @"When someone gives a trail you posted a bead."],
                          @[@"trail_reply", @"Replies to your trails", @"When someone replies to a trail you posted."]]],
           @[@"Wyrm", @[@[@"notice", @"Notices", @"Maintenance, downtime and important alerts."],
                        @[@"broadcast", @"Broadcasts", @"General announcements sent to everyone."],
                        @[@"event", @"Battledome events", @"Scheduled events, start times and arena addresses."],
                        @[@"update", @"Updates", @"New versions and their changelogs."],
                        @[@"feature", @"New features", @"What has been added or changed inside Wyrm."],
                        @[@"support", @"Replies from Wyrm", @"Answers to your reports, ideas and questions."]]],
           @[@"You", @[@[@"achievement", @"Achievements", @"Personal bests and milestones after a run."],
                       @[@"rank", @"Rank changes", @"Leaderboard movement after a finished run."]]]];
}
static void notificationsPage(WStack* p) {
  [p add:sectionLabel(@"Mac", 14)];
  WBoolRow* master = boolRow(@"Mac notifications", @"Wyrm for Mac does not show notifications yet. The choices below are kept with your account.", NO, nil);
  master.toggle.alphaValue = 0.45;
  master.onClick = nil;
  __weak WSwitch* masterToggle = master.toggle;
  master.toggle.onToggle = ^(BOOL on) { [masterToggle setOn:NO animated:YES]; };
  [p add:card(@[master])];
  for (NSArray* g in notificationGroups()) {
    [p add:sectionLabel(g[0], 22)];
    WCardBlock* c = [WCardBlock new];
    for (NSArray* k in g[1]) [c add:boolRow(k[1], k[2], [WStore notifyKind:k[0]], ^(BOOL on) { [WStore setNotifyKind:k[0] on:on]; })];
    [p add:c];
  }
  [p add:caption(@"Nothing here shows while you are in an arena, or while Wyrm's window is in front: the badges say it there.")];
}

static void versionPage(WStack* p) {
  NSString* v = [WEngine version];
  [p add:sectionLabel(@"Wyrm for Mac", 14)];
  [p add:card(@[valueRow(@"Version", @"0.1.0 (1)", nil), valueRow(@"Settings format", v.length ? [@"v" stringByAppendingString:v] : @"", nil),
                valueRow(@"Engine", @"Wyrm Desktop engine", nil)])];
  [p add:caption(@"This Mac's settings are saved to your account when Wyrm loses focus, when it quits and when you log out.")];
}

#pragma mark Profile (and Edit profile)

static BOOL profileEditing;
static NSDictionary* profileBadges;
static NSArray* profileTrails;
static BOOL profileTrailsLoaded;
static NSString* profileError = @"";
static NSString* profileToast;

@interface WGridTile : WTap
@property(strong) NSImageView* image;
@end
@implementation WGridTile
@end

static void loadProfileExtras(NSString* playerId) {
  if (!playerId.length) return;
  WApi(@"GET", [NSString stringWithFormat:@"/v1/players/%@/badges", playerId], nil, YES, ^(id json, NSInteger s, NSString* e) {
    if (!e) { profileBadges = json; if (rebuildPage) rebuildPage(); }
  });
  WApi(@"GET", [NSString stringWithFormat:@"/v1/trails?limit=20&author=%@", playerId], nil, YES, ^(id json, NSInteger s, NSString* e) {
    profileTrailsLoaded = YES;
    profileTrails = e ? @[] : ([json[@"trails"] isKindOfClass:NSArray.class] ? json[@"trails"] : @[]);
    if (rebuildPage) rebuildPage();
  });
}

static NSString* compact(long v) {
  if (v >= 1000000) return [[NSString stringWithFormat:@"%.1fM", v / 1e6] stringByReplacingOccurrencesOfString:@".0M" withString:@"M"];
  if (v >= 10000) return [NSString stringWithFormat:@"%ldK", v / 1000];
  if (v >= 1000) return [[NSString stringWithFormat:@"%.1fK", v / 1e3] stringByReplacingOccurrencesOfString:@".0K" withString:@"K"];
  return [NSString stringWithFormat:@"%ld", v];
}

@interface WProfileHeader : WBlock
@property(strong) WAvatar* avatar;
@property(strong) NSArray<NSTextField*>* stats;  // value, label pairs
@property(strong) NSTextField *name, *bio;
@property(strong) WButton *edit, *share;
@end
@implementation WProfileHeader
- (CGFloat)heightFor:(CGFloat)w {
  CGFloat h = 18 + 86 + 14 + lineH(self.name);
  if (self.bio.stringValue.length) h += 4 + measure(self.bio, w - 36);
  return h + 14 + 38;
}
- (void)layout {
  [super layout];
  CGFloat w = self.bounds.size.width, x = 18, y = 18;
  place(self.avatar, x, y, 86, 86);
  CGFloat sx = x + 86 + 16, sw = (w - sx - 18) / 3;
  for (int i = 0; i < 3; i++) {
    NSTextField *v = self.stats[i * 2], *l = self.stats[i * 2 + 1];
    CGFloat vh = lineH(v), lh = lineH(l), top = y + (86 - vh - lh - 2) / 2;
    place(v, sx + sw * i, top, sw, vh);
    place(l, sx + sw * i, top + vh + 2, sw, lh);
  }
  y += 86 + 14;
  CGFloat nh = lineH(self.name);
  place(self.name, x, y, w - 36, nh);
  y += nh;
  if (self.bio.stringValue.length) { CGFloat bh = measure(self.bio, w - 36); place(self.bio, x, y + 4, w - 36, bh); y += 4 + bh; }
  y += 14;
  CGFloat bw = (w - 36 - 8) / 2;
  place(self.edit, x, y, bw, 38);
  place(self.share, x + bw + 8, y, bw, 38);
}
@end

static void editProfilePage(WStack* p);

/* The profile's trails: square tiles, three across, 2 pt apart. */
@interface WTrailGrid : WBlock
@end
@implementation WTrailGrid
- (CGFloat)heightFor:(CGFloat)w {
  NSUInteger rows = (self.subviews.count + 2) / 3;
  CGFloat side = (w - 4) / 3;
  return rows * side + (rows ? rows - 1 : 0) * 2 + 2;
}
- (void)layout {
  [super layout];
  CGFloat side = (self.bounds.size.width - 4) / 3;
  NSUInteger i = 0;
  for (NSView* v in self.subviews) {
    place(v, (i % 3) * (side + 2), 2 + (i / 3) * (side + 2), side, side);
    for (NSView* c in v.subviews) if ([c isKindOfClass:NSTextField.class]) place(c, 8, 8, side - 16, side - 16);
    i++;
  }
}
@end


static void profilePage(WStack* p) {
  if (profileEditing) { editProfilePage(p); return; }
  WAccount* a = [WAccount shared];
  if (!a.hasSession) { [p add:caption(@"Log in to see your profile.")]; return; }
  WProfileHeader* h = [WProfileHeader new];
  h.side = 0;
  h.avatar = [[WAvatar alloc] initWithFrame:NSZeroRect];
  h.avatar.corner = 26;
  [h.avatar setURL:a.avatarURL initials:WInitials(a.displayName)];
  NSString* trails = profileBadges ? [NSString stringWithFormat:@"%@", profileBadges[@"trailCount"] ?: @0]
                   : profileTrailsLoaded ? [NSString stringWithFormat:@"%lu", (unsigned long)profileTrails.count] : @"–";
  NSMutableArray* stats = [NSMutableArray new];
  NSArray* pairs = @[@[trails, @"Trails"], @[compact([a.player[@"followerCount"] longValue]), @"Followers"],
                     @[compact([a.player[@"followingCount"] longValue]), @"Following"]];
  for (NSArray* pair in pairs) {
    NSTextField* v = label(pair[0], 18, 700, INK);
    v.alignment = NSTextAlignmentCenter;
    NSTextField* l = label(pair[1], 11.5, 400, QUIET);
    l.alignment = NSTextAlignmentCenter;
    [stats addObject:v];
    [stats addObject:l];
  }
  h.stats = stats;
  h.name = label(a.displayName, 18, 700, INK);
  NSString* bio = [a.player[@"bio"] isKindOfClass:NSString.class] ? a.player[@"bio"] : @"";
  h.bio = wrapLabel(bio.length ? bio : @"Add a line about how you play", 13.5, bio.length ? 400 : 600, bio.length ? MUTE : LINK);
  lineHeight(h.bio, 19, NSTextAlignmentLeft);
  h.edit = [WButton well:nil text:@"Edit profile"];
  h.share = [WButton well:nil text:@"Share profile"];
  h.edit.onClick = ^{ profileEditing = YES; profileError = @""; rebuildPage(); };
  h.share.onClick = ^{
    NSString* name = a.handle.length ? a.handle : a.displayName;
    WCopy([@"Find me on Wyrm: " stringByAppendingString:name]);
    profileToast = [@"Copied: Find me on Wyrm: " stringByAppendingString:name];
    rebuildPage();
    WAfter(2.2, ^{ profileToast = nil; if (rebuildPage) rebuildPage(); });
  };
  for (NSView* v in [@[h.avatar, h.name, h.bio, h.edit, h.share] arrayByAddingObjectsFromArray:stats]) [h addSubview:v];
  [p add:h];
  if (profileToast) { WCaption* t = caption(profileToast); t.text.textColor = LIVE; [p add:t]; }
  /* The trails grid. */
  WFlipped* tabs = [WFlipped new];
  NSImageView* gridIcon = glyph(@"square.grid.3x3", 12, INK);
  NSTextField* tabTitle = label(@"Trails", 13.5, 600, INK);
  NSView* underline = [NSView new];
  underline.wantsLayer = YES;
  underline.layer.backgroundColor = INK.CGColor;
  NSView* line = rule();
  for (NSView* v in @[gridIcon, tabTitle, underline, line]) [tabs addSubview:v];
  WBlock* tabBlock = holdBlock(tabs, 45, 0);
  tabBlock.top = 20;
  tabBlock.frame = NSMakeRect(0, 0, 600, 45);
  [tabTitle sizeToFit];
  CGFloat cx = 300, tw = 14 + 7 + tabTitle.frame.size.width;
  place(gridIcon, cx - tw / 2, 14, 14, 16);
  place(tabTitle, cx - tw / 2 + 21, 13, tabTitle.frame.size.width, tabTitle.frame.size.height);
  place(underline, cx - 45, 42, 90, 2);
  place(line, 0, 44, 600, 1);
  for (NSView* v in @[gridIcon, tabTitle, underline]) v.autoresizingMask = NSViewMinXMargin | NSViewMaxXMargin;
  line.autoresizingMask = NSViewWidthSizable;
  [p add:tabBlock];
  if (!profileTrailsLoaded) { [p add:caption(@"Loading trails…")]; return; }
  if (!profileTrails.count) {
    WCaption* empty = caption(@"Share your first trail\nA photo, a run, a few words. It shows up here and in Trails.");
    empty.text.alignment = NSTextAlignmentCenter;
    empty.top = 40;
    [p add:empty];
    return;
  }
  WTrailGrid* grid = [WTrailGrid new];
  for (NSDictionary* t in profileTrails) {
    NSString* url = WAbsolute([t[@"thumbUrl"] isKindOfClass:NSString.class] ? t[@"thumbUrl"] :
                              [t[@"photo"] isKindOfClass:NSDictionary.class] ? t[@"photo"][@"url"] : @"");
    WAvatar* img = [[WAvatar alloc] initWithFrame:NSZeroRect];
    img.corner = 0;
    img.layer.backgroundColor = WELL.CGColor;
    [img setURL:url initials:@""];
    NSString* words = [t[@"caption"] isKindOfClass:NSString.class] ? t[@"caption"] : @"";
    if (!url.length && words.length) {
      NSTextField* c = wrapLabel(words, 12, 600, INK);
      c.alignment = NSTextAlignmentCenter;
      c.maximumNumberOfLines = 4;
      [img addSubview:c];
    }
    [grid addSubview:img];
  }
  [p add:grid];
}

static NSTextField* editField(NSString* value, BOOL multi) {
  NSTextField* f = WField(@"", 15, 400, NO);
  f.stringValue = value ?: @"";
  if (multi) { f.cell.wraps = YES; f.cell.scrollable = NO; f.cell.usesSingleLineMode = NO; }
  return f;
}

@interface WEditField : WRow <NSTextFieldDelegate>
@property(strong) NSTextField *caption_, *limit, *prefix, *hint, *field;
@property(strong) NSView* box;
@property BOOL multi;
@property NSInteger maxLength;
@property BOOL usernameOnly;
@property(copy) void (^onChange)(NSString*);
@end
@implementation WEditField
- (CGFloat)heightFor:(CGFloat)w {
  CGFloat h = 11 + lineH(self.caption_) + 7 + (self.multi ? 74 : 42);
  if (self.hint.stringValue.length) h += 8 + measure(self.hint, w - 28);
  return h + 11;
}
- (void)layout {
  [super layout];
  CGFloat w = self.bounds.size.width, y = 11, ch = lineH(self.caption_);
  [self.limit sizeToFit];
  place(self.caption_, 14, y, w - 28 - self.limit.frame.size.width, ch);
  place(self.limit, w - 14 - self.limit.frame.size.width, y, self.limit.frame.size.width, self.limit.frame.size.height);
  y += ch + 7;
  CGFloat bh = self.multi ? 74 : 42;
  place(self.box, 14, y, w - 28, bh);
  CGFloat px = 12;
  if (self.prefix.stringValue.length) { [self.prefix sizeToFit]; place(self.prefix, 12, (bh - self.prefix.frame.size.height) / 2, self.prefix.frame.size.width, self.prefix.frame.size.height); px += self.prefix.frame.size.width + 1; }
  CGFloat fh = self.multi ? bh - 22 : 20;
  place(self.field, px, self.multi ? 11 : (bh - fh) / 2, w - 28 - px - 12, fh);
  y += bh;
  if (self.hint.stringValue.length) place(self.hint, 14, y + 8, w - 28, measure(self.hint, w - 28));
}
- (void)controlTextDidChange:(NSNotification*)n {
  NSString* v = self.field.stringValue;
  if (self.usernameOnly) {
    NSMutableString* clean = [NSMutableString new];
    for (NSUInteger i = 0; i < v.length; i++) { unichar c = [v characterAtIndex:i]; if (isalnum(c) || c == '_') [clean appendFormat:@"%C", c]; }
    v = clean;
  }
  if ((NSInteger)v.length > self.maxLength) v = [v substringToIndex:self.maxLength];
  if (![v isEqualToString:self.field.stringValue]) self.field.stringValue = v;
  if (self.onChange) self.onChange(v);
}
@end
static WEditField* editRow(NSString* caption, NSString* limit, NSString* value, NSString* prefix, NSString* hint, BOOL multi, NSInteger max) {
  WEditField* r = [WEditField new];
  r.caption_ = label(caption, 12.5, 400, QUIET);
  r.limit = label(limit, 12, 400, QUIET);
  r.prefix = label(prefix ?: @"", 15, 400, QUIET);
  r.hint = wrapLabel(hint ?: @"", 12.5, 400, QUIET);
  r.box = [WFlipped new];
  r.box.wantsLayer = YES;
  r.box.layer.cornerRadius = 10;
  r.box.layer.cornerCurve = kCACornerCurveContinuous;
  r.box.layer.borderWidth = 1;
  r.box.layer.borderColor = RULE.CGColor;
  r.field = editField(value, multi);
  r.field.delegate = r;
  r.multi = multi;
  r.maxLength = max;
  [r.box addSubview:r.prefix];
  [r.box addSubview:r.field];
  for (NSView* v in @[r.caption_, r.limit, r.box, r.hint]) [r addSubview:v];
  return r;
}
static NSString* allowanceLine(id left) {
  if (![left isKindOfClass:NSNumber.class]) return @"Twice a month";
  return [left intValue] == 1 ? @"1 change left this month" : [NSString stringWithFormat:@"%d changes left this month", [left intValue]];
}

static NSDictionary* renameAllowance;
static NSMutableDictionary* profileDraft;
static BOOL profileBusy;

static NSData* avatarJPEG(NSImage* image) {
  NSBitmapImageRep* source = [[NSBitmapImageRep alloc] initWithData:image.TIFFRepresentation];
  CGFloat w = source.pixelsWide, h = source.pixelsHigh, side = MIN(w, h);
  NSBitmapImageRep* out = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:512 pixelsHigh:512 bitsPerSample:8
                                                             samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
  [NSGraphicsContext saveGraphicsState];
  NSGraphicsContext.currentContext = [NSGraphicsContext graphicsContextWithBitmapImageRep:out];
  [source drawInRect:NSMakeRect(0, 0, 512, 512) fromRect:NSMakeRect((w - side) / 2, (h - side) / 2, side, side)
           operation:NSCompositingOperationCopy fraction:1 respectFlipped:YES hints:nil];
  [NSGraphicsContext restoreGraphicsState];
  return [out representationUsingType:NSBitmapImageFileTypeJPEG properties:@{NSImageCompressionFactor: @0.86}];
}

static void editProfilePage(WStack* p) {
  WAccount* a = [WAccount shared];
  NSDictionary* me = a.player ?: @{};
  if (!profileDraft) {
    profileDraft = [@{@"displayName": a.displayName, @"username": [me[@"username"] isKindOfClass:NSString.class] ? me[@"username"] : @"",
                      @"bio": [me[@"bio"] isKindOfClass:NSString.class] ? me[@"bio"] : @""} mutableCopy];
    WApi(@"GET", @"/v1/me/renames", nil, YES, ^(id json, NSInteger s, NSString* e) { if (!e) { renameAllowance = json; if (rebuildPage) rebuildPage(); } });
  }
  NSString *name = profileDraft[@"displayName"], *user = profileDraft[@"username"], *bio = profileDraft[@"bio"];
  NSString* oldUser = [me[@"username"] isKindOfClass:NSString.class] ? me[@"username"] : @"";
  NSString* oldBio = [me[@"bio"] isKindOfClass:NSString.class] ? me[@"bio"] : @"";
  NSString* oldName = a.displayName;
  /* What would be sent, and whether Save may go (Android's canSave). */
  NSDictionary* (^changes)(void) = ^NSDictionary* {
    NSString* n = [profileDraft[@"displayName"] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    NSString* u = profileDraft[@"username"];
    NSString* b = [profileDraft[@"bio"] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    NSMutableDictionary* body = [NSMutableDictionary new];
    if (![n isEqualToString:oldName]) body[@"displayName"] = n;
    if (![u isEqualToString:oldUser]) body[@"username"] = u;
    if (![b isEqualToString:oldBio]) body[@"bio"] = b;
    return body;
  };
  BOOL (^canSave)(void) = ^BOOL {
    NSDictionary* body = changes();
    NSString* n = [profileDraft[@"displayName"] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    NSString* u = profileDraft[@"username"];
    BOOL nameAllowed = !body[@"displayName"] || !renameAllowance || [renameAllowance[@"displayName"] intValue] > 0;
    BOOL userAllowed = !body[@"username"] || !renameAllowance || [renameAllowance[@"username"] intValue] > 0;
    return body.count && u.length >= 3 && u.length <= 20 && n.length >= 2 && nameAllowed && userAllowed && !profileBusy;
  };
  /* Header: Cancel · Edit profile · Save. */
  WFlipped* bar = [WFlipped new];
  WButton* cancel = [WButton well:nil text:@"Cancel"];
  cancel.fill = NSColor.clearColor;
  cancel.title.textColor = LINK;
  cancel.onClick = ^{ profileEditing = NO; profileDraft = nil; rebuildPage(); };
  NSTextField* title = label(@"Edit profile", 16, 600, INK);
  title.alignment = NSTextAlignmentCenter;
  WButton* save = [WButton well:nil text:profileBusy ? @"Saving…" : @"Save"];
  save.fill = NSColor.clearColor;
  save.title.font = body(15.5, 600);
  __weak WButton* weakSave = save;
  void (^refreshSave)(void) = ^{
    BOOL ok = canSave();
    weakSave.enabled = ok;
    weakSave.alphaValue = 1;
    weakSave.title.textColor = ok ? LINK : WP.tabIdle;
  };
  refreshSave();
  save.onClick = ^{
    NSDictionary* body = changes();
    profileBusy = YES;
    rebuildPage();
    WApi(@"PATCH", @"/v1/me", body, YES, ^(id json, NSInteger s, NSString* e) {
      profileBusy = NO;
      if (e) { profileError = [a friendlyError:e status:s]; rebuildPage(); return; }
      [a refreshPlayer:nil];
      profileEditing = NO;
      profileDraft = nil;
      profileError = @"";
      rebuildPage();
    });
  };
  for (NSView* v in @[cancel, title, save]) [bar addSubview:v];
  place(cancel, 0, 0, 80, 40);
  place(save, 520, 0, 80, 40);
  placeLabel(title, 0, 10, 600);
  save.autoresizingMask = NSViewMinXMargin;
  title.autoresizingMask = NSViewWidthSizable;
  bar.frame = NSMakeRect(0, 0, 600, 40);
  WBlock* barBlock = holdBlock(bar, 40, 14);
  [p add:barBlock];
  [p add:holdBlock(rule(), 1, 0)];
  /* The photo. */
  WFlipped* photo = [WFlipped new];
  WAvatar* avatar = [[WAvatar alloc] initWithFrame:NSMakeRect(0, 0, 60, 60)];
  avatar.corner = 17;
  [avatar setURL:a.avatarURL initials:WInitials(name.length ? name : a.displayName)];
  WButton* change = [WButton well:nil text:a.avatarURL.length ? @"Change photo" : @"Choose photo"];
  change.fill = NSColor.clearColor;
  change.layer.cornerRadius = 12;
  change.layer.borderWidth = 1;
  change.layer.borderColor = RULE.CGColor;
  change.title.textColor = MUTE;
  change.title.font = body(15, 400);
  change.onClick = ^{
    NSOpenPanel* panel = [NSOpenPanel openPanel];
    panel.allowedFileTypes = @[@"png", @"jpg", @"jpeg", @"heic"];
    if ([panel runModal] != NSModalResponseOK) return;
    NSImage* img = [[NSImage alloc] initWithContentsOfURL:panel.URL];
    if (!img) return;
    profileBusy = YES;
    rebuildPage();
    WApiBinary(@"PUT", @"/v1/me/avatar", @"image/jpeg", avatarJPEG(img), ^(id json, NSInteger s, NSString* e) {
      profileBusy = NO;
      if (e) profileError = [a friendlyError:e status:s]; else [a refreshPlayer:nil];
      if (rebuildPage) rebuildPage();
    });
  };
  [photo addSubview:avatar];
  [photo addSubview:change];
  CGFloat photoH = 60;
  place(change, 74, a.avatarURL.length ? 0 : 7, 300, 46);
  change.autoresizingMask = NSViewWidthSizable;
  if (a.avatarURL.length) {
    WButton* remove = [WButton tinted:@"Remove" fill:[BADGE colorWithAlphaComponent:0.08] ink:BADGE symbol:nil];
    remove.layer.cornerRadius = 10;
    remove.onClick = ^{
      WApi(@"DELETE", @"/v1/me/avatar", nil, YES, ^(id json, NSInteger s, NSString* e) { [a refreshPlayer:nil]; if (rebuildPage) rebuildPage(); });
    };
    place(remove, 74, 54, 120, 32);
    [photo addSubview:remove];
    photoH = 86;
  }
  [p add:card(@[holdRow(photo, photoH, NSEdgeInsetsMake(14, 14, 14, 14))])];
  [p add:caption(@"PNG or JPG. Shown on your profile and the leaderboard.")];
  [p add:sectionLabel(@"Identity", 22)];
  WEditField* nameRow = editRow(@"Display name", allowanceLine(renameAllowance[@"displayName"]), name, nil, nil, NO, 40);
  nameRow.onChange = ^(NSString* v) { profileDraft[@"displayName"] = v; refreshSave(); };
  WEditField* userRow = editRow(@"Username", allowanceLine(renameAllowance[@"username"]), user, @"@", @"Your in-game name lives on Play and changes freely.", NO, 20);
  userRow.usernameOnly = YES;
  userRow.onChange = ^(NSString* v) { profileDraft[@"username"] = v; refreshSave(); };
  WEditField* bioRow = editRow(@"Bio", [NSString stringWithFormat:@"%lu / 150", (unsigned long)bio.length], bio, nil, nil, YES, 150);
  __weak WEditField* weakBio = bioRow;
  bioRow.onChange = ^(NSString* v) {
    profileDraft[@"bio"] = v;
    weakBio.limit.stringValue = [NSString stringWithFormat:@"%lu / 150", (unsigned long)v.length];
    [weakBio setNeedsLayout:YES];
    refreshSave();
  };
  [p add:card(@[nameRow, userRow, bioRow])];
  if (profileError.length) { WCaption* e = caption(profileError); e.text.textColor = BADGE; e.text.font = body(13, 400); [p add:e]; }
  [p add:caption(@"Save stays disabled until something actually changes.")];
  [p add:sectionLabel(@"Account", 22)];
  [p add:card(@[actionRow(@"Delete account", YES, ^{
    NSAlert* alert = [NSAlert new];
    alert.messageText = @"Delete your Wyrm account?";
    alert.informativeText = @"Your profile, trails and messages are removed from Wyrm's server. This cannot be undone.";
    [alert addButtonWithTitle:@"Delete account"];
    [alert addButtonWithTitle:@"Cancel"];
    alert.buttons[0].hasDestructiveAction = YES;
    if ([alert runModal] != NSAlertFirstButtonReturn) return;
    WApi(@"DELETE", @"/v1/me", nil, YES, ^(id json, NSInteger s, NSString* e) {
      if (e) { profileError = [a friendlyError:e status:s]; if (rebuildPage) rebuildPage(); return; }
      profileEditing = NO;
      [a logOut:YES];
    });
  })])];
}

#pragma mark Help & feedback

typedef NS_ENUM(NSInteger, WHelp) { HelpMain, HelpCompose, HelpReports };
static WHelp helpPage = HelpMain;
static NSInteger helpKind = 0;
static NSArray* helpReports;
static BOOL helpSent, helpSending, helpAttach = YES;
static NSString* helpMessage = @"";
static NSString* helpError = @"";
static NSInteger faqOpen = -1;

static NSArray* kinds(void) {
  return @[@[@"bug", @"Problem", @"Report a problem", @"What went wrong?", @"What you did, what you expected, and what happened instead.", @"ladybug"],
           @[@"suggestion", @"Idea", @"Suggest an idea", @"What would make Wyrm better?", @"A feature, a skin, a mode, a small thing that bugs you. Every idea is read.", @"lightbulb"],
           @[@"help", @"Help", @"Ask for help", @"What do you need help with?", @"Ask anything about Wyrm: your account, skins, arenas, backups.", @"questionmark.circle"],
           @[@"other", @"Other", @"Something else", @"What's on your mind?", @"Tell us anything.", @"bubble.left"]];
}
static NSArray* faqs(void) {
  return @[@[@"My snake spawned and then dropped out of the arena",
             @"Another slither app on the same Wi-Fi (on a PC or another phone) can make the arena drop you. Close it, or try once on another network, then pick the arena again. Joining the same arena many times a minute also gets a short timeout; wait a minute and try once."],
           @[@"How do I change my username or photo?", @"Open Settings › Profile and click Edit profile. You can rename twice a month."],
           @[@"My skin or beads look different in the arena",
             @"Other players see the arena's own colours, not Wyrm beads; your Wyrm beads and looks are drawn on your own snake."],
           @[@"How do I keep my settings when I reinstall?", @"Your settings and keys are saved to your Wyrm account. Log in on the new install and they come back."],
           @[@"I'm not getting notifications", @"Wyrm for Mac does not show notifications yet. Anything you miss waits in Alerts on your phone."],
           @[@"How do I delete my account?", @"Settings › Profile › Edit profile › Delete account. Your profile, trails and messages are removed from Wyrm's server."]];
}
static void loadReports(void) {
  if (![WAccount shared].hasSession) return;
  WApi(@"GET", @"/v1/me/support", nil, YES, ^(id json, NSInteger s, NSString* e) {
    if (!e) { helpReports = [json[@"reports"] isKindOfClass:NSArray.class] ? json[@"reports"] : @[]; if (rebuildPage) rebuildPage(); }
  });
}
static NSString* tailOfLog(void) {
  NSString* path = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Logs/Wyrm/engine.log"];
  NSString* log = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil] ?: @"";
  return log.length > 120000 ? [log substringFromIndex:log.length - 120000] : log;
}
static NSDictionary* deviceContext(void) {
  char model[128] = "";
  size_t size = sizeof(model);
  sysctlbyname("hw.model", model, &size, NULL, 0);
  NSOperatingSystemVersion v = NSProcessInfo.processInfo.operatingSystemVersion;
  return @{@"platform": @"macos", @"appVersion": @"0.1.0", @"model": @(model),
           @"os": [NSString stringWithFormat:@"macOS %ld.%ld.%ld", (long)v.majorVersion, (long)v.minorVersion, (long)v.patchVersion],
           @"screen": @"Settings"};
}

@interface WTextArea : WRow <NSTextViewDelegate>
@property(strong) NSScrollView* scroll;
@property(strong) NSTextView* text;
@property(strong) NSTextField* placeholder;
@end
@implementation WTextArea
- (CGFloat)heightFor:(CGFloat)w { return 180; }
- (void)layout {
  [super layout];
  place(self.scroll, 14, 12, self.bounds.size.width - 28, 156);
  [self.placeholder sizeToFit];
  place(self.placeholder, 19, 14, self.bounds.size.width - 38, measure(self.placeholder, self.bounds.size.width - 38));
}
- (void)textDidChange:(NSNotification*)n {
  NSString* v = self.text.string;
  if (v.length > 4000) { v = [v substringToIndex:4000]; self.text.string = v; }
  helpMessage = v;
  self.placeholder.hidden = v.length > 0;
}
@end

/* Three equal tiles side by side, 10 apart. */
@interface WRowOfThree : WFlipped
@end
@implementation WRowOfThree
- (void)layout {
  [super layout];
  CGFloat w = (self.bounds.size.width - 20) / 3;
  NSUInteger i = 0;
  for (NSView* v in self.subviews) place(v, (i++) * (w + 10), 0, w, self.bounds.size.height);
}
@end

static void helpMainPage(WStack* p) {
  WFlipped* head = [WFlipped new];
  NSTextField* t = label(@"How can we help?", 26, 700, INK);
  NSTextField* s = label(@"Wyrm is made by one person, and every report is read.", 13, 400, QUIET);
  placeLabel(t, 0, 0, 600);
  placeLabel(s, 0, t.frame.size.height + 2, 600);
  [head addSubview:t];
  [head addSubview:s];
  WBlock* hb = holdBlock(head, t.frame.size.height + 2 + s.frame.size.height, 20);
  hb.top = 16;
  [p add:hb];
  WRowOfThree* tiles = [WRowOfThree new];
  for (int i = 0; i < 3; i++) {
    WTap* tile = [WTap new];
    tile.pressScale = YES;
    tile.fill = CARD;
    tile.hover = WMix(CARD, INK, 0.03);
    tile.layer.cornerRadius = 16;
    tile.layer.borderWidth = 1;
    tile.layer.borderColor = RULE.CGColor;
    NSImageView* icon = glyph(kinds()[i][5], 18, INK);
    NSTextField* name = label(kinds()[i][2], 13, 600, INK);
    [tile addSubview:icon];
    [tile addSubview:name];
    place(icon, 14, 16, 24, 22);
    placeLabel(name, 14, 50, 0);
    name.autoresizingMask = NSViewWidthSizable;
    tile.onClick = ^{ helpKind = i; helpPage = HelpCompose; helpSent = NO; helpError = @""; helpMessage = @""; helpAttach = i == 0 || i == 2; rebuildPage(); };
    tile.identifier = [NSString stringWithFormat:@"%d", i];
    [tiles addSubview:tile];
  }
  WHoldRow* tileRow = (WHoldRow*)holdBlock(tiles, 84, 16);
  tileRow.top = 16;
  [p add:tileRow];
  [p add:sectionLabel(@"Your reports", 22)];
  NSString* summary = !helpReports ? @"" : helpReports.count ? [NSString stringWithFormat:@"%lu", (unsigned long)helpReports.count] : @"None yet";
  [p add:card(@[valueRow(@"Your reports", summary, ^{ helpPage = HelpReports; loadReports(); rebuildPage(); })])];
  [p add:sectionLabel(@"Common questions", 22)];
  WCardBlock* questions = [WCardBlock new];
  NSArray* list = faqs();
  for (NSUInteger i = 0; i < list.count; i++) {
    BOOL open = faqOpen == (NSInteger)i;
    WIntroRow* r = introRow(list[i][0], open ? list[i][1] : @"");
    r.title.font = body(14.5, 600);
    r.title.maximumNumberOfLines = 2;
    if (!open) r.detail.stringValue = @"";
    r.onClick = ^{ faqOpen = faqOpen == (NSInteger)i ? -1 : (NSInteger)i; rebuildPage(); };
    [questions add:r];
  }
  [p add:questions];
  [p add:sectionLabel(@"Something else", 22)];
  [p add:card(@[valueRow(@"Write to Wyrm", @"", ^{ helpKind = 3; helpPage = HelpCompose; helpSent = NO; helpError = @""; helpMessage = @""; helpAttach = NO; rebuildPage(); })])];
  [p add:caption(@"Replies from Wyrm arrive in Alerts and under Your reports.")];
}

static void helpBar(WStack* p, NSString* title, NSString* trailing, BOOL trailingEnabled, void (^onTrailing)(void)) {
  WFlipped* bar = [WFlipped new];
  WButton* back = [WButton well:nil text:@"‹ Help"];
  back.fill = NSColor.clearColor;
  back.title.textColor = LINK;
  back.title.font = body(16, 400);
  back.onClick = ^{ helpPage = HelpMain; rebuildPage(); };
  NSTextField* t = label(title, 16, 600, INK);
  t.alignment = NSTextAlignmentCenter;
  [bar addSubview:back];
  [bar addSubview:t];
  place(back, 0, 0, 90, 40);
  placeLabel(t, 0, 10, 600);
  t.autoresizingMask = NSViewWidthSizable;
  if (trailing) {
    WButton* go = [WButton well:nil text:trailing];
    go.fill = NSColor.clearColor;
    go.title.textColor = trailingEnabled ? LINK : WP.tabIdle;
    go.title.font = body(15.5, 600);
    go.enabled = trailingEnabled;
    go.alphaValue = 1;
    go.onClick = onTrailing;
    place(go, 520, 0, 80, 40);
    go.autoresizingMask = NSViewMinXMargin;
    [bar addSubview:go];
  }
  bar.frame = NSMakeRect(0, 0, 600, 40);
  [p add:holdBlock(bar, 40, 14)];
  [p add:holdBlock(rule(), 1, 0)];
}

static void helpComposePage(WStack* p) {
  NSArray* kind = kinds()[helpKind];
  WAccount* a = [WAccount shared];
  if (helpSent) {
    helpBar(p, @"Sent", nil, NO, nil);
    WFlipped* done = [WFlipped new];
    NSTextField* t = label(@"Thank you", 26, 700, INK);
    NSTextField* s = wrapLabel(helpKind == 1 ? @"Your idea is with the developer. The best ones end up in Wyrm."
                                             : @"Your report is with the developer. If we reply, it arrives in Alerts and under Your reports.", 14, 400, MUTE);
    placeLabel(t, 0, 0, 560);
    CGFloat sh = placeWrap(s, 0, t.frame.size.height + 8, 560);
    WButton* ok = [WButton primary:@"Done"];
    ok.onClick = ^{ helpPage = HelpMain; helpSent = NO; rebuildPage(); };
    place(ok, 0, t.frame.size.height + 8 + sh + 20, 560, 46);
    WButton* see = [WButton well:nil text:@"See your reports"];
    see.fill = NSColor.clearColor;
    see.title.textColor = LINK;
    see.onClick = ^{ helpPage = HelpReports; loadReports(); rebuildPage(); };
    place(see, 0, NSMaxY(ok.frame) + 8, 560, 36);
    for (NSView* v in @[t, s, ok, see]) [done addSubview:v];
    WBlock* b = holdBlock(done, NSMaxY(see.frame), 20);
    b.top = 30;
    [p add:b];
    return;
  }
  BOOL canSend = [helpMessage stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length > 0 && !helpSending;
  helpBar(p, kind[2], helpSending ? @"Sending…" : @"Send", canSend, ^{
    helpSending = YES;
    helpError = @"";
    rebuildPage();
    NSMutableDictionary* body = [@{@"kind": kind[0], @"message": helpMessage, @"context": deviceContext()} mutableCopy];
    if (helpAttach) body[@"logs"] = tailOfLog();
    WApi(@"POST", @"/v1/support/reports", body, YES, ^(id json, NSInteger s, NSString* e) {
      helpSending = NO;
      if (e) helpError = s == 0 ? @"Couldn't send it. Check your connection and try again." : [a friendlyError:e status:s];
      else { helpSent = YES; helpMessage = @""; loadReports(); }
      if (rebuildPage) rebuildPage();
    });
  });
  WSegmented* seg = [[WSegmented alloc] initWithOptions:@[@"Problem", @"Idea", @"Help", @"Other"]];
  seg.selected = helpKind;
  seg.onSelect = ^(NSInteger i) { helpKind = i; rebuildPage(); };
  WBlock* segBlock = holdBlock(seg, 34, 16);
  segBlock.top = 16;
  [p add:segBlock];
  WFlipped* q = [WFlipped new];
  NSTextField* question = label(kind[3], 20, 700, INK);
  placeLabel(question, 0, 0, 600);
  question.autoresizingMask = NSViewWidthSizable;
  [q addSubview:question];
  WBlock* qb = holdBlock(q, question.frame.size.height, 20);
  qb.top = 18;
  qb.bottom = 10;
  [p add:qb];
  WTextArea* area = [WTextArea new];
  area.scroll = [NSScrollView new];
  area.scroll.drawsBackground = NO;
  area.scroll.hasVerticalScroller = NO;
  area.scroll.autohidesScrollers = YES;
  area.text = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 500, 156)];
  area.text.font = body(15, 400);
  area.text.textColor = INK;
  area.text.drawsBackground = NO;
  area.text.insertionPointColor = INK;
  area.text.string = helpMessage;
  area.text.delegate = area;
  area.text.autoresizingMask = NSViewWidthSizable;
  area.text.textContainer.widthTracksTextView = YES;
  area.scroll.documentView = area.text;
  area.placeholder = wrapLabel(kind[4], 15, 400, WP.tabIdle);
  area.placeholder.hidden = helpMessage.length > 0;
  [area addSubview:area.scroll];
  [area addSubview:area.placeholder];
  [p add:card(@[area])];
  WCaption* count = caption(helpError.length ? helpError : [NSString stringWithFormat:@"%lu/4000", (unsigned long)helpMessage.length]);
  if (helpError.length) count.text.textColor = BADGE;
  count.top = 8;
  [p add:count];
  [p add:sectionLabel(@"Include", 22)];
  [p add:card(@[boolRow(@"Device info and recent log", @"Mac model, macOS and Wyrm version, the last few minutes of Wyrm's log. Makes problems much easier to fix.",
                        helpAttach, ^(BOOL on) { helpAttach = on; })])];
  [p add:caption(a.hasSession ? [NSString stringWithFormat:@"Sent as %@. If we reply, you'll find it in Alerts and under Your reports. Never your password, keys or messages.", a.handle.length ? a.handle : @"you"]
                              : @"You're not signed in, so we can't reply in the app.")];
}

static void helpReportsPage(WStack* p) {
  helpBar(p, @"Your reports", nil, NO, nil);
  if (!helpReports) { [p add:caption(@"Loading…")]; return; }
  if (!helpReports.count) { [p add:caption(@"Nothing sent yet. Reports, ideas and questions you send show up here with any reply from Wyrm.")]; return; }
  for (NSDictionary* r in helpReports) {
    NSString* kindTitle = @"Report";
    for (NSArray* k in kinds()) if ([k[0] isEqualToString:r[@"kind"]]) kindTitle = k[1];
    if ([r[@"kind"] isEqualToString:@"crash"]) kindTitle = @"Crash";
    if ([r[@"kind"] isEqualToString:@"drop"]) kindTitle = @"Arena drop";
    NSString* status = [r[@"status"] isKindOfClass:NSString.class] ? [r[@"status"] capitalizedString] : @"";
    NSString* message = [r[@"message"] isKindOfClass:NSString.class] ? r[@"message"] : @"";
    NSString* reply = [r[@"reply"] isKindOfClass:NSString.class] && ![r[@"reply"] isEqualToString:@"null"] ? r[@"reply"] : @"";
    WIntroRow* row = introRow([NSString stringWithFormat:@"%@ · %@", kindTitle, status],
                              reply.length ? [NSString stringWithFormat:@"%@\n\nWyrm: %@", message, reply] : message);
    row.title.font = body(14.5, 600);
    [p add:sectionLabel([r[@"createdAt"] isKindOfClass:NSString.class] ? [r[@"createdAt"] substringToIndex:MIN(10, [r[@"createdAt"] length])] : @"", 14)];
    [p add:card(@[row])];
  }
}
static void helpPages(WStack* p) {
  if (!helpReports) loadReports();
  if (helpPage == HelpCompose) helpComposePage(p);
  else if (helpPage == HelpReports) helpReportsPage(p);
  else helpMainPage(p);
}

#pragma mark About

static void aboutPage(WStack* p) {
  WFlipped* page = [WFlipped new];
  __block CGFloat y = 14, W = 600;
  void (^addLabel)(NSTextField*, CGFloat, CGFloat) = ^(NSTextField* t, CGFloat x, CGFloat after) {
    if (t.cell.wraps) y += placeWrap(t, x, y, W - x) + after; else { placeLabel(t, x, y, W - x); y += t.frame.size.height + after; }
    [page addSubview:t];
  };
  NSTextField* kicker = label(@"THE STORY OF", 11, 700, QUIET);
  track(kicker, 1.4);
  addLabel(kicker, 0, 0);
  NSTextField* big = label(@"Wyrm", 58, 400, INK);
  big.font = display(58, 400);
  addLabel(big, 0, 0);
  NSTextField* tagline = wrapLabel(@"One developer. One snake game.\nA whole ecosystem.", 17, 400, MUTE);
  lineHeight(tagline, 24, NSTextAlignmentLeft);
  addLabel(tagline, 0, 26);
  void (^chapter)(NSString*, NSString*, NSString*) = ^(NSString* numeral, NSString* title, NSString* text) {
    NSView* disc = [NSView new];
    disc.wantsLayer = YES;
    disc.layer.backgroundColor = INK.CGColor;
    disc.layer.cornerRadius = 18;
    place(disc, 0, y, 36, 36);
    NSTextField* n = label(numeral, 15, 400, ON_INK);
    n.font = display(15, 500);
    n.alignment = NSTextAlignmentCenter;
    placeLabel(n, 0, 9, 36);
    [disc addSubview:n];
    [page addSubview:disc];
    NSTextField* k = label([@"CHAPTER " stringByAppendingString:numeral], 10, 700, QUIET);
    track(k, 1.2);
    addLabel(k, 52, 0);
    NSTextField* t = wrapLabel(title, 27, 400, INK);
    t.font = display(27, 400);
    addLabel(t, 52, 0);
    NSTextField* body_ = wrapLabel(text, 15, 400, MUTE);
    lineHeight(body_, 23, NSTextAlignmentLeft);
    addLabel(body_, 52, 18);
  };
  chapter(@"I", @"It began as a mod", @"Wyrm started as a simple slither.io mod for Android. A few tweaks for my own games, nothing more.");
  chapter(@"II", @"Then it grew a name", @"I kept building, one feature after another, until the mod was no longer a mod. It became Wyrm: my own brand, a small one, inside the slither community.");
  chapter(@"III", @"Then it became an ecosystem", @"Wyrm now runs on phones and computers, lives inside the browser, and even the original slither apps on Android and iOS were modded into it.");
  NSArray* eco = @[@[@"Wyrm Android", @"Where it all started"], @[@"Wyrm iOS", @"The same Wyrm on iPhone"], @[@"Wyrm Desktop", @"For the big screen"],
                   @[@"Wyrm for Mac", @"Native on macOS"], @[@"Wyrm Windows", @"Native on Windows"], @[@"Wyrm Linux", @"Native on Linux"],
                   @[@"NTL VANCED", @"Browser extension, powered by Wyrm"], @[@"Slither for Android", @"The original app, modded into Wyrm"],
                   @[@"Slither for iOS", @"The original app, modded into Wyrm"]];
  CGFloat cw = (W - 52 - 10) / 2;
  for (NSUInteger i = 0; i < eco.count; i += 2) {
    CGFloat rowH = 0;
    for (NSUInteger j = i; j < MIN(i + 2, eco.count); j++) {
      WCard* c = [[WCard alloc] initWithRadius:14];
      c.layer.shadowOpacity = 0;
      NSTextField* n = label(eco[j][0], 14, 700, INK);
      NSTextField* d = wrapLabel(eco[j][1], 11.5, 400, QUIET);
      placeLabel(n, 14, 14, cw - 28);
      CGFloat dh = placeWrap(d, 14, 14 + n.frame.size.height, cw - 28);
      [c addSubview:n];
      [c addSubview:d];
      rowH = MAX(rowH, 14 + n.frame.size.height + dh + 14);
      place(c, 52 + (j - i) * (cw + 10), y, cw, 14 + n.frame.size.height + dh + 14);
      [page addSubview:c];
    }
    y += rowH + 10;
  }
  y += 16;
  chapter(@"IV", @"Built by one person", @"I'm OM Rajput, and Wyrm is a one-person project. The backend, the apps, the engine work, the design and every release: I build and run all of it myself.");
  y -= 12;
  CGFloat cx = 52;
  for (NSString* chipText in @[@"Backend", @"Apps", @"Engine", @"Design", @"Releases", @"Support"]) {
    NSTextField* t = label(chipText, 11, 700, INK);
    [t sizeToFit];
    WFlipped* c = [WFlipped new];
    c.wantsLayer = YES;
    c.layer.backgroundColor = WELL.CGColor;
    c.layer.cornerRadius = (t.frame.size.height + 10) / 2;
    place(c, cx, y, t.frame.size.width + 20, t.frame.size.height + 10);
    place(t, 10, 5, t.frame.size.width, t.frame.size.height);
    [c addSubview:t];
    [page addSubview:c];
    cx += t.frame.size.width + 28;
  }
  y += 30;
  addLabel(label(@"From the first line of the server to the last pixel of this page.", 12.5, 400, QUIET), 52, 0);
  void (^kickerAt)(NSString*) = ^(NSString* text) {
    y += 30;
    NSTextField* k = label(text, 10.5, 700, QUIET);
    track(k, 1.4);
    addLabel(k, 0, 6);
  };
  void (^heading)(NSString*) = ^(NSString* text) {
    NSTextField* h = label(text, 28, 400, INK);
    h.font = display(28, 400);
    addLabel(h, 0, 0);
  };
  WButton* (^pill)(NSString*, BOOL) = ^WButton*(NSString* text, BOOL filled) {
    WButton* b = [WButton capsule:text filled:filled];
    b.title.font = body(14, 700);
    if (!filled) { b.fill = WELL; b.layer.borderWidth = 1; b.layer.borderColor = RULE.CGColor; }
    b.layer.shadowOpacity = 0;
    [b.title sizeToFit];
    b.frame = NSMakeRect(0, 0, b.title.frame.size.width + 40, 42);
    return b;
  };
  kickerAt(@"THE COMMUNITY");
  heading(@"Play with the people who play Wyrm");
  addLabel(label(@"Updates first, ideas heard, games together.", 14, 400, MUTE), 0, 12);
  WButton* discord = pill(@"Join the Wyrm Discord", YES);
  discord.onClick = ^{ WOpenURL(@"https://discord.gg/efqjEmQdeq"); };
  [discord setFrameOrigin:NSMakePoint(0, y)];
  [page addSubview:discord];
  y += 42;
  kickerAt(@"BUY ME A COFFEE");
  heading(@"Keep the servers warm");
  NSTextField* coffee = wrapLabel(@"Wyrm is free. If it made your games better, a coffee keeps it going. Scan with any UPI app.", 14, 400, MUTE);
  lineHeight(coffee, 20, NSTextAlignmentLeft);
  addLabel(coffee, 0, 12);
  WFlipped* qr = [WFlipped new];
  qr.wantsLayer = YES;
  qr.layer.backgroundColor = NSColor.whiteColor.CGColor;
  qr.layer.cornerRadius = 18;
  qr.layer.borderWidth = 1;
  qr.layer.borderColor = RULE.CGColor;
  NSImageView* code = [NSImageView imageViewWithImage:[[NSImage alloc] initWithContentsOfFile:[NSBundle.mainBundle pathForResource:@"about_upi_qr" ofType:@"png"]] ?: [NSImage new]];
  code.imageScaling = NSImageScaleProportionallyUpOrDown;
  place(code, 12, 12, 156, 156);
  [qr addSubview:code];
  place(qr, 0, y, 180, 180);
  [page addSubview:qr];
  NSTextField* upiK = label(@"UPI ID", 10, 700, QUIET);
  track(upiK, 1.2);
  placeLabel(upiK, 198, y + 54, 0);
  NSTextField* upi = label(@"ommanav@fam", 16, 700, INK);
  placeLabel(upi, 198, y + 54 + upiK.frame.size.height + 8, 0);
  WButton* copy = pill(@"Copy UPI ID", NO);
  NSTextField* toast = label(@"", 13, 600, LIVE);
  copy.onClick = ^{ WCopy(@"ommanav@fam"); toast.stringValue = @"UPI ID copied"; WAfter(2.2, ^{ toast.stringValue = @""; }); };
  [copy setFrameOrigin:NSMakePoint(198, NSMaxY(upi.frame) + 8)];
  for (NSView* v in @[upiK, upi, copy]) [page addSubview:v];
  y += 180;
  kickerAt(@"SAY HELLO");
  heading(@"Write to me");
  y += 10;
  NSArray* contacts = @[@[@"EMAIL", @"ommanav.mail@gmail.com", @"mailto:ommanav.mail@gmail.com"], @[@"WEBSITE", @"omrajput.in", @"https://www.omrajput.in"]];
  for (NSUInteger i = 0; i < contacts.count; i++) {
    WTap* c = [WTap new];
    c.fill = CARD;
    c.hover = WMix(CARD, INK, 0.03);
    c.layer.cornerRadius = 14;
    c.layer.borderWidth = 1;
    c.layer.borderColor = RULE.CGColor;
    NSTextField* k = label(contacts[i][0], 10, 700, QUIET);
    track(k, 1.2);
    NSTextField* v = label(contacts[i][1], 15, 600, INK);
    placeLabel(k, 14, 14, 0);
    placeLabel(v, 14, 14 + k.frame.size.height, 0);
    [c addSubview:k];
    [c addSubview:v];
    NSString* url = contacts[i][2];
    c.onClick = ^{ WOpenURL(url); };
    place(c, i * 250, y, 240, 14 + k.frame.size.height + v.frame.size.height + 14);
    [page addSubview:c];
  }
  y += 70 + 28;
  addLabel(label(@"Made with care by OM Rajput", 12.5, 600, MUTE), 0, 0);
  addLabel(label(@"Wyrm for Mac 0.1.0", 11, 400, QUIET), 0, 10);
  placeLabel(toast, 0, y, 300);
  [page addSubview:toast];
  y += 24;
  WBlock* b = holdBlock(page, y, 20);
  [p add:b];
}

#pragma mark - The two panes

@interface WNavRow : WTap
@property(strong) NSView* iconBox;
@property(strong) NSImageView* icon;
@property(strong) NSTextField *title, *value;
@end
@implementation WNavRow
- (void)layout {
  [super layout];
  NSSize s = self.bounds.size;
  place(self.iconBox, 18, 9, 30, 30);
  place(self.icon, 6, 6, 18, 18);
  [self.value sizeToFit];
  CGFloat vw = self.value.stringValue.length ? MIN(110, self.value.frame.size.width) : 0;
  place(self.value, s.width - 12 - vw, (48 - self.value.frame.size.height) / 2, vw, self.value.frame.size.height);
  CGFloat th = lineH(self.title);
  place(self.title, 18 + 30 + 12, (48 - th) / 2, s.width - 60 - 12 - vw - 8, th);
}
@end

@interface WSettingsView () <NSTextFieldDelegate>
@property(strong) NSTextField* heading;
@property(strong) WFlipped* search;
@property(strong) NSTextField* searchField;
@property(strong) NSScrollView* navScroll;
@property(strong) WFlipped* nav;
@property(strong) NSView *pill, *bead, *divider;
@property(strong) NSMutableArray<WNavRow*>* rows;
@property(strong) NSView* pageHost;
@property(strong) NSTextField *pageGroup, *pageTitle, *pageSub;
@property(strong) WButton* headerAction;
@property(strong) NSScrollView* pageScroll;
@property(strong) WStack* stack;
@property BOOL pillPlaced;
@property(strong) id observers;
@end

@implementation WSettingsView

- (instancetype)initWithFrame:(NSRect)frame {
  if (!(self = [super initWithFrame:frame])) return nil;
  _heading = label(@"Settings", 30, 700, INK);
  track(_heading, -0.5);
  _search = [WFlipped new];
  _search.wantsLayer = YES;
  _search.layer.backgroundColor = CARD.CGColor;
  _search.layer.cornerRadius = 13;
  _search.layer.cornerCurve = kCACornerCurveContinuous;
  _search.layer.borderWidth = 1;
  _search.layer.borderColor = RULE.CGColor;
  NSImageView* magnifier = glyph(@"magnifyingglass", 14, QUIET);
  magnifier.identifier = @"magnifier";
  _searchField = WField(@"Search settings", 15, 400, NO);
  _searchField.delegate = self;
  [_search addSubview:magnifier];
  [_search addSubview:_searchField];
  _navScroll = [NSScrollView new];
  _navScroll.drawsBackground = NO;
  _navScroll.hasVerticalScroller = NO;
  _navScroll.autohidesScrollers = YES;
  _nav = [WFlipped new];
  _navScroll.documentView = _nav;
  _divider = [NSView new];
  _divider.wantsLayer = YES;
  _divider.layer.backgroundColor = RULE.CGColor;
  _pageGroup = label(@"", 11.5, 600, QUIET);
  _pageTitle = label(@"", 28, 700, INK);
  _pageSub = label(@"", 14, 400, MUTE);
  _pageScroll = [NSScrollView new];
  _pageScroll.drawsBackground = NO;
  _pageScroll.hasVerticalScroller = NO;
  _pageScroll.autohidesScrollers = YES;
  _pageHost = [WFlipped new];
  for (NSView* v in @[_pageGroup, _pageTitle, _pageSub, _pageScroll]) [_pageHost addSubview:v];
  for (NSView* v in @[_heading, _search, _navScroll, _divider, _pageHost]) [self addSubview:v];
  __weak WSettingsView* weak = self;
  rebuildPage = ^{ [weak buildPage:NO]; };
  [self buildNav];
  [self buildPage:NO];
  NSNotificationCenter* nc = NSNotificationCenter.defaultCenter;
  _observers = @[[nc addObserverForName:WSettingsChanged object:nil queue:nil usingBlock:^(NSNotification* n) { [weak reload]; }],
                 [nc addObserverForName:WAccountChanged object:nil queue:nil usingBlock:^(NSNotification* n) { [weak reload]; }]];
  return self;
}
- (void)dealloc {
  for (id o in self.observers) [NSNotificationCenter.defaultCenter removeObserver:o];
  if (rebuildPage) rebuildPage = nil;
}
- (BOOL)acceptsFirstResponder { return YES; }
- (CGFloat)pageOffset { return self.pageScroll.contentView.bounds.origin.y; }
- (void)setPageOffset:(CGFloat)y {
  [self layoutSubtreeIfNeeded];
  NSClipView* clip = self.pageScroll.contentView;
  CGFloat most = MAX(0, self.pageScroll.documentView.frame.size.height - clip.bounds.size.height);
  [clip scrollToPoint:NSMakePoint(0, MAX(0, MIN(most, y)))];
  [self.pageScroll reflectScrolledClipView:clip];
}
- (void)reload {
  [WEngine refresh];
  [self buildNav];
  [self buildPage:NO];
}

/* Key capture for Settings › Controls. */
- (void)keyDown:(NSEvent*)e {
  if (listeningAction < 0) { [super keyDown:e]; return; }
  if (e.keyCode == 53) { listeningAction = -1; rebuildPage(); return; }
  if (e.keyCode == 51 || e.keyCode == 117) { bindListening(-1); return; }
  NSString* reason = reservedKey(e);
  if (reason) { keyNote = reason; rebuildPage(); return; }
  int key = engineKey(e);
  if (key) bindListening(key);
}
- (void)flagsChanged:(NSEvent*)e {
  if (listeningAction < 0) return;
  if (e.modifierFlags & (NSEventModifierFlagShift | NSEventModifierFlagControl)) bindListening(engineKey(e));
}
- (void)rightMouseDown:(NSEvent*)e { if (!(listeningAction >= 0 && bindListening(401))) [super rightMouseDown:e]; }
- (void)otherMouseDown:(NSEvent*)e {
  if (listeningAction < 0) { [super otherMouseDown:e]; return; }
  int key = e.buttonNumber == 2 ? 402 : e.buttonNumber == 3 ? 403 : e.buttonNumber == 4 ? 404 : 0;
  if (key) bindListening(key);
}

- (void)controlTextDidChange:(NSNotification*)n { [self buildNav]; }

- (NSString*)valueFor:(NSInteger)page {
  if (page == PThemes) return WThemeName[[WStore theme]];
  if (page == PFood) { WSetting* f = [WEngine named:@"normal.food_type"]; return f && f.index < (NSInteger)f.options.count ? f.options[f.index] : @""; }
  if (page == PProfile) return [WAccount shared].handle;
  return @"";
}
- (WNavRow*)navRow:(NSInteger)page title:(NSString*)title value:(NSString*)value chosen:(BOOL)chosen {
  WNavRow* r = [WNavRow new];
  r.fill = NSColor.clearColor;
  r.hover = chosen ? NSColor.clearColor : [INK colorWithAlphaComponent:0.04];
  r.pressScale = YES;
  r.layer.cornerRadius = 14;
  r.iconBox = [WFlipped new];
  r.iconBox.wantsLayer = YES;
  r.iconBox.layer.cornerRadius = 9;
  r.iconBox.layer.cornerCurve = kCACornerCurveContinuous;
  r.iconBox.layer.backgroundColor = (chosen ? INK : WELL).CGColor;
  r.icon = glyph(PageSymbol[page], 13, chosen ? ON_INK : INK);
  [r.iconBox addSubview:r.icon];
  r.title = label(title, 15, chosen ? 700 : 600, chosen ? INK : MUTE);
  r.value = label(value ?: @"", 13, 400, QUIET);
  for (NSView* v in @[r.iconBox, r.title, r.value]) [r addSubview:v];
  return r;
}
- (void)open:(NSInteger)page {
  if (page == PHelp && WSettingsOpenPage != PHelp) helpPage = HelpMain;
  if (page != WSettingsOpenPage) { profileEditing = NO; profileDraft = nil; listeningAction = -1; keyNote = nil; }
  BOOL down = page > WSettingsOpenPage;
  BOOL same = page == WSettingsOpenPage;
  WSettingsOpenPage = page;
  if (page == PProfile) { profileTrailsLoaded = NO; [[WAccount shared] refreshPlayer:nil]; loadProfileExtras([WAccount shared].player[@"id"]); }
  if (self.searchField.stringValue.length) [self buildNav]; else [self updateChosen:YES];
  if (!same) [self buildPage:YES down:down];
}
/* The open section: its row's look, and the card glides to it (no rebuild, no bounce). */
- (void)updateChosen:(BOOL)animated {
  for (NSUInteger i = 0; i < self.rows.count; i++) {
    WNavRow* r = self.rows[i];
    BOOL chosen = (NSInteger)i == WSettingsOpenPage;
    r.iconBox.layer.backgroundColor = (chosen ? INK : WELL).CGColor;
    r.icon.contentTintColor = chosen ? ON_INK : INK;
    r.title.font = body(15, chosen ? 700 : 600);
    r.title.textColor = chosen ? INK : MUTE;
    r.hover = chosen ? NSColor.clearColor : [INK colorWithAlphaComponent:0.04];
    r.value.stringValue = [self valueFor:i];
    [r setNeedsLayout:YES];
    if (chosen) {
      NSRect to = r.frame;
      if (animated) WGlide(self.pill, to); else self.pill.frame = to;
    }
  }
}
- (void)buildNav {
  for (NSView* v in self.nav.subviews.copy) [v removeFromSuperview];
  self.rows = [NSMutableArray new];
  NSString* q = [self.searchField.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet].lowercaseString;
  CGFloat y = 0, w = 296;
  __weak WSettingsView* weak = self;
  if (q.length) {
    y += 8;
    BOOL any = NO;
    for (NSInteger i = 0; i < PCount; i++) {
      if (![PageTitle[i].lowercaseString containsString:q] && ![PageSub[i].lowercaseString containsString:q]) continue;
      any = YES;
      WNavRow* r = [self navRow:i title:PageTitle[i] value:@"" chosen:NO];
      r.onClick = ^{ weak.searchField.stringValue = @""; [weak open:i]; };
      place(r, 0, y, w, 48);
      [self.nav addSubview:r];
      y += 48;
    }
    NSMutableSet* seen = [NSMutableSet new];
    int hits = 0;
    for (WSetting* s in [WEngine settings]) {
      if (!s.label.length || ![s.label.lowercaseString containsString:q] || hits >= 24) continue;
      NSInteger page = [s.ident containsString:@"food"] ? PFood : [s.group isEqualToString:@"general.bot"] ? PBot
                     : ([s.group isEqualToString:@"general"] || [s.group hasPrefix:@"general."]) ? ([s.ident isEqualToString:@"general.vsync"] ? -1 : PDisplay)
                     : ([s.group hasPrefix:@"normal"] || [s.group hasPrefix:@"assist"]) ? PModes : -1;
      NSString* key = [NSString stringWithFormat:@"%@|%ld", s.label, (long)page];
      if (page < 0 || [seen containsObject:key]) continue;
      [seen addObject:key];
      hits++;
      any = YES;
      WTap* hit = [self searchHit:s.label where:PageTitle[page]];
      NSString* ident = s.ident;
      hit.onClick = ^{ weak.searchField.stringValue = @""; revealId = ident; if ([ident hasPrefix:@"assist."]) modesMode = 1, foodMode = 1; else if ([ident hasPrefix:@"normal."]) modesMode = 0, foodMode = 0; [weak open:page]; [weak buildPage:NO]; };
      place(hit, 0, y, w, 48);
      [self.nav addSubview:hit];
      y += 48;
    }
    for (NSArray* g in keyGroups()) for (NSArray* a in g[1]) {
      if (![[a[1] lowercaseString] containsString:q]) continue;
      any = YES;
      WTap* hit = [self searchHit:[a[1] stringByAppendingString:@" key"] where:@"Controls"];
      hit.onClick = ^{ weak.searchField.stringValue = @""; [weak open:PControls]; };
      place(hit, 0, y, w, 48);
      [self.nav addSubview:hit];
      y += 48;
    }
    if (!any) {
      NSTextField* none = label([NSString stringWithFormat:@"No results for “%@”", self.searchField.stringValue], 14, 400, QUIET);
      placeLabel(none, 12, y + 10, w - 12);
      [self.nav addSubview:none];
      y += 40;
    }
  } else {
    /* The sections in Android's groups; the open one wears a bead that glides to it. */
    if (!self.pill) {
      self.pill = [NSView new];
      self.pill.wantsLayer = YES;
      self.pill.layer.cornerRadius = 14;
      self.pill.layer.cornerCurve = kCACornerCurveContinuous;
      self.bead = [NSView new];
      self.bead.wantsLayer = YES;
      self.bead.layer.cornerRadius = 2;
      [self.pill addSubview:self.bead];
    }
    self.pill.layer.backgroundColor = CARD.CGColor;
    self.pill.layer.borderWidth = 1;
    self.pill.layer.borderColor = RULE.CGColor;
    self.bead.layer.backgroundColor = INK.CGColor;
    [self.nav addSubview:self.pill];
    NSString* last = @"";
    CGFloat chosenY = 0;
    for (NSInteger i = 0; i < PCount; i++) {
      if (![PageGroup[i] isEqualToString:last]) {
        last = PageGroup[i];
        NSTextField* g = label(last.uppercaseString, 11, 600, QUIET);
        track(g, 0.9);
        placeLabel(g, 12, y + 16, w - 12);
        [self.nav addSubview:g];
        y += 16 + g.frame.size.height + 6;
      }
      BOOL chosen = i == WSettingsOpenPage;
      if (chosen) chosenY = y;
      WNavRow* r = [self navRow:i title:PageTitle[i] value:[self valueFor:i] chosen:chosen];
      r.onClick = ^{ [weak open:i]; };
      place(r, 0, y, w, 48);
      [self.nav addSubview:r];
      [self.rows addObject:r];
      y += 48;
    }
    place(self.bead, 6, 15, 4, 18);
    self.pill.frame = NSMakeRect(0, chosenY, w, 48);
  }
  /* Reset everything and Log out: both ask twice, as Android's Settings does. */
  y += 18;
  WTap* reset = [self dangerCard:@"Reset everything to defaults"];
  reset.onClick = ^{ [weak confirmReset]; };
  place(reset, 0, y, w, 52);
  [self.nav addSubview:reset];
  y += 52;
  if ([WAccount shared].hasSession) {
    y += 12;
    WTap* out = [self dangerCard:@"Log out"];
    out.onClick = ^{ if (weak.onLogOut) weak.onLogOut(); };
    place(out, 0, y, w, 52);
    [self.nav addSubview:out];
    y += 52;
  }
  NSString* v = [WEngine version];
  NSTextField* foot = label(v.length ? [NSString stringWithFormat:@"Wyrm · settings format v%@", v] : @"Wyrm", 12, 400, QUIET);
  foot.alignment = NSTextAlignmentCenter;
  placeLabel(foot, 0, y + 14, w);
  [self.nav addSubview:foot];
  y += 14 + foot.frame.size.height + 18;
  self.nav.frame = NSMakeRect(0, 0, w, y);
}
- (WTap*)searchHit:(NSString*)title where:(NSString*)where {
  WTap* hit = [WTap new];
  hit.fill = NSColor.clearColor;
  hit.hover = [INK colorWithAlphaComponent:0.045];
  hit.layer.cornerRadius = 12;
  NSTextField* t = label(title, 14.5, 600, INK);
  NSTextField* s = label(where, 12.5, 400, QUIET);
  placeLabel(t, 14, 7, 270);
  placeLabel(s, 14, 7 + t.frame.size.height, 270);
  [hit addSubview:t];
  [hit addSubview:s];
  return hit;
}
- (WTap*)dangerCard:(NSString*)title {
  WTap* c = [WTap new];
  c.fill = CARD;
  c.hover = WMix(CARD, BADGE, 0.06);
  c.pressScale = YES;
  c.layer.cornerRadius = 14;
  c.layer.borderWidth = 1;
  c.layer.borderColor = RULE.CGColor;
  NSTextField* t = label(title, 15.5, 400, BADGE);
  placeLabel(t, 14, 0, 260);
  t.frame = NSMakeRect(14, (52 - t.frame.size.height) / 2, 260, t.frame.size.height);
  [c addSubview:t];
  return c;
}
- (void)confirmReset {
  WFlipped* cardView = [WFlipped new];
  cardView.wantsLayer = YES;
  cardView.layer.backgroundColor = CARD.CGColor;
  cardView.layer.cornerRadius = 24;
  NSTextField* title = label(@"Reset all settings?", 17, 600, INK);
  title.alignment = NSTextAlignmentCenter;
  placeLabel(title, 20, 22, 320);
  WButton* go = [WButton tinted:@"Reset settings" fill:WELL ink:RED symbol:nil];
  WButton* cancel = [WButton tinted:@"Cancel" fill:WELL ink:INK symbol:nil];
  place(go, 20, 62, 320, 48);
  place(cancel, 20, 118, 320, 48);
  for (NSView* v in @[title, go, cancel]) [cardView addSubview:v];
  cardView.frame = NSMakeRect(0, 0, 360, 186);
  WDialogHost* host = [[WDialogHost alloc] initWithCard:cardView];
  __weak WDialogHost* weakHost = host;
  host.onCancel = ^{ [weakHost dismiss]; };
  cancel.onClick = host.onCancel;
  go.onClick = ^{ [WEngine resetAll]; [weakHost dismiss]; };
  host.onConfirm = go.onClick;
  NSView* root = self.window.contentView.subviews.lastObject ?: self;
  host.frame = root.bounds;
  host.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  [root addSubview:host];
  [host present];
}

- (void)buildPage:(BOOL)animated { [self buildPage:animated down:YES]; }
- (void)buildPage:(BOOL)animated down:(BOOL)down {
  NSInteger page = WSettingsOpenPage;
  self.pageGroup.stringValue = PageGroup[page].uppercaseString;
  track(self.pageGroup, 1);
  self.pageTitle.stringValue = PageTitle[page];
  track(self.pageTitle, -0.5);
  self.pageSub.stringValue = PageSub[page];
  [self.headerAction removeFromSuperview];
  self.headerAction = nil;
  if (page == PDisplay) {
    WButton* arrange = [WButton primary:@"Arrange arena UI"];
    arrange.icon = glyph(@"arrow.up.and.down.and.arrow.left.and.right", 13, ON_INK);
    [arrange addSubview:arrange.icon];
    arrange.title.font = body(13.5, 700);
    arrange.layer.cornerRadius = 19;
    arrange.pressScale = YES;
    arrange.onClick = ^{ [NSNotificationCenter.defaultCenter postNotificationName:@"WyrmOpenHudEditor" object:nil]; };
    self.headerAction = arrange;
    [self.pageHost addSubview:arrange];
  }
  CGFloat keep = self.pageScroll.contentView.bounds.origin.y;
  WStack* stack = [WStack new];
  switch (page) {
    case PDisplay: displayPage(stack); break;
    case PControls: controlsPage(stack); break;
    case PModes: modesPage(stack); break;
    case PBot: botPage(stack); break;
    case PFood: foodPage(stack); break;
    case PProfile: profilePage(stack); break;
    case PNotifications: notificationsPage(stack); break;
    case PPrivacy: privacyPage(stack); break;
    case PThemes: themesPage(stack); break;
    case PVersion: versionPage(stack); break;
    case PHelp: helpPages(stack); break;
    case PAbout: aboutPage(stack); break;
  }
  [stack add:holdBlock([NSView new], 32, 0)];
  self.stack = stack;
  WFlipped* holder = [WFlipped new];
  [holder addSubview:stack];
  self.pageScroll.documentView = holder;
  [self layoutPage];
  if (!animated) [self.pageScroll.contentView scrollToPoint:NSMakePoint(0, MIN(keep, MAX(0, stack.frame.size.height - self.pageScroll.contentSize.height)))];
  else {
    [self.pageScroll.contentView scrollToPoint:NSZeroPoint];
    /* Pages rise in from the side they sit on. */
    NSView* host = self.pageHost;
    host.wantsLayer = YES;
    /* Only the page's own column moves: the header and the sidebar stay still. */
    NSView* column = self.pageScroll;
    CGFloat d = MIN(40, column.bounds.size.height / 14) * (down ? 1 : -1);
    CABasicAnimation* slide = [CABasicAnimation animationWithKeyPath:@"transform.translation.y"];
    slide.fromValue = @(d);
    slide.toValue = @0;
    CABasicAnimation* fade = [CABasicAnimation animationWithKeyPath:@"opacity"];
    fade.fromValue = @0;
    fade.toValue = @1;
    CAAnimationGroup* rise = [CAAnimationGroup animation];
    rise.animations = @[slide, fade];
    rise.duration = 0.34;
    rise.timingFunction = [CAMediaTimingFunction functionWithControlPoints:0.22 :0.8 :0.24 :1];
    column.wantsLayer = YES;
    [column.layer addAnimation:rise forKey:@"rise"];
    (void)host;
  }
  if (revealId) {
    NSString* target = revealId;
    revealId = nil;
    (void)target;
  }
  if (listeningAction >= 0) [self.window makeFirstResponder:self];
}
- (void)layoutPage {
  NSSize s = self.pageHost.bounds.size;
  CGFloat w = MIN(780, s.width), x = (s.width - w) / 2 + 28, inner = w - 56;
  placeLabel(self.pageGroup, x + 16, 18, inner);
  placeLabel(self.pageTitle, x + 16, 18 + self.pageGroup.frame.size.height + 2, inner);
  placeLabel(self.pageSub, x + 16, NSMaxY(self.pageTitle.frame) + 4, inner - (self.headerAction ? 200 : 0));
  if (self.headerAction) {
    [self.headerAction.title sizeToFit];
    CGFloat bw = self.headerAction.title.frame.size.width + 18 + 8 + 32;
    place(self.headerAction, x + inner - 4 - bw, NSMidY(self.pageSub.frame) - 19, bw, 38);
  }
  CGFloat top = NSMaxY(self.pageSub.frame) + 6;
  place(self.pageScroll, 0, top, s.width, s.height - top);
  /* The page is a column (max 780, 28 aside) inside a holder as wide as the pane. */
  CGFloat h = [self.stack heightFor:inner];
  NSView* holder = self.pageScroll.documentView;
  holder.frame = NSMakeRect(0, 0, s.width, h);
  self.stack.frame = NSMakeRect(x, 0, inner, h);
  [self.stack setNeedsLayout:YES];
  [self.stack layoutSubtreeIfNeeded];
}
- (void)layout {
  [super layout];
  NSSize s = self.bounds.size;
  CGFloat top = 92 - 8, navW = 330;
  placeLabel(self.heading, 20 + 6, top + 14, navW - 40);
  CGFloat sy = NSMaxY(self.heading.frame) + 12;
  place(self.search, 20, sy, navW - 34, 44);
  for (NSView* v in self.search.subviews) {
    if ([v.identifier isEqualToString:@"magnifier"]) place(v, 14, 13, 18, 18);
    else place(v, 14 + 18 + 8, 12, navW - 34 - 14 - 26 - 14, 20);
  }
  place(self.navScroll, 20, sy + 44 + 6, navW - 34, s.height - (sy + 50));
  self.nav.frame = NSMakeRect(0, 0, navW - 34, self.nav.frame.size.height);
  place(self.divider, navW, top + 18, 1, s.height - top - 36);
  place(self.pageHost, navW + 1, top, s.width - navW - 1, s.height - top);
  [self layoutPage];
}
- (void)viewDidEndLiveResize { [super viewDidEndLiveResize]; [self layoutPage]; }
@end

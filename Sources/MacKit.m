#import "MacKit.h"
#import <objc/runtime.h>
#import <CoreText/CoreText.h>
#import <CoreImage/CoreImage.h>

#pragma mark - Palettes (Android WyrmThemeId, same order and values)

WPalette WP;
NSString* const WThemeStored[WTHEME_COUNT] = {@"paper", @"graphite", @"blush", @"sun", @"slate", @"lilac", @"forest", @"midnight"};
NSString* const WThemeName[WTHEME_COUNT] = {@"Paper", @"Graphite", @"Blush", @"Sun", @"Slate", @"Lilac", @"Forest", @"Midnight"};
NSString* const WThemeDetail[WTHEME_COUNT] = {
  @"The original warm Wyrm canvas", @"Charcoal paper, warm readable type", @"Soft rose paper with berry ink",
  @"Cream and ochre without harsh glare", @"Cool grey field with crisp graphite", @"Pale violet paper with aubergine ink",
  @"Muted sage with deep evergreen ink", @"Blue-black paper with cool moonlit type"};

typedef struct { CGFloat r, g, b, a; } WRGBA;
typedef struct { WRGBA c[17]; BOOL dark; } WRaw;
static WRGBA hex(uint32_t argb) {
  return (WRGBA){((argb >> 16) & 255) / 255.0, ((argb >> 8) & 255) / 255.0, (argb & 255) / 255.0, (argb >> 24) / 255.0};
}
static const uint32_t THEMES[WTHEME_COUNT][17] = {
  {0xFFF7F6F3, 0xFFFFFFFF, 0xFF37352F, 0xFFFFFFFF, 0xFF787774, 0xFF6B6660, 0x1437352F, 0x1237352F, 0xFF448361,
   0xFF2F6FDE, 0xFF7C776F, 0xF0FCFBFA, 0xFFC6C1B8, 0xFFC4554D, 0xFFF0EEE9, 0xFFEFEDE8, 0xFFFAF9F7},
  {0xFF171816, 0xFF222321, 0xFFF2EFE8, 0xFF171816, 0xFFB9B5AD, 0xFFD1CDC4, 0x24F2EFE8, 0x1CF2EFE8, 0xFF72B68F,
   0xFF8CB4FF, 0xFFA7A39B, 0xF01D1E1C, 0xFF77746E, 0xFFE17B72, 0xFF2B2C29, 0xFF30312E, 0xFF282926},
  {0xFFFFF4F5, 0xFFFFFBFB, 0xFF4C3036, 0xFFFFFBFB, 0xFF88676D, 0xFF73555B, 0x184C3036, 0x124C3036, 0xFF3F8062,
   0xFF9D4561, 0xFF8A7074, 0xF0FFF9FA, 0xFFCDB7BA, 0xFFC44F5F, 0xFFF7E7E9, 0xFFF3E1E4, 0xFFFFF8F8},
  {0xFFFFF8DE, 0xFFFFFCF0, 0xFF463B22, 0xFFFFFCF0, 0xFF7D6F51, 0xFF695C40, 0x18463B22, 0x12463B22, 0xFF487A59,
   0xFF9A681D, 0xFF82765E, 0xF0FFFAE9, 0xFFC9BB96, 0xFFB94F47, 0xFFF4EAC8, 0xFFF1E5BD, 0xFFFFFBEA},
  {0xFFF0F2F3, 0xFFF9FAFA, 0xFF30383C, 0xFFF9FAFA, 0xFF646E74, 0xFF566168, 0x1830383C, 0x1230383C, 0xFF3F7D61,
   0xFF356C8E, 0xFF727C81, 0xF0F5F7F7, 0xFFB8C0C3, 0xFFB65252, 0xFFE5E9EA, 0xFFE2E7E8, 0xFFF5F7F7},
  {0xFFF7F2FC, 0xFFFCFAFF, 0xFF403348, 0xFFFCFAFF, 0xFF796B81, 0xFF65566E, 0x18403348, 0x12403348, 0xFF487D61,
   0xFF7655A3, 0xFF7C7182, 0xF0FAF7FD, 0xFFC3B7CA, 0xFFC15362, 0xFFEDE4F2, 0xFFE9E0EF, 0xFFFAF7FD},
  {0xFFF1F5ED, 0xFFFAFCF8, 0xFF2F3F34, 0xFFFAFCF8, 0xFF647168, 0xFF536158, 0x182F3F34, 0x122F3F34, 0xFF3D7B56,
   0xFF356F5C, 0xFF707C73, 0xF0F7FAF5, 0xFFB6C2B7, 0xFFB95450, 0xFFE4EBDD, 0xFFE1E9DA, 0xFFF7FAF5},
  {0xFF101820, 0xFF19242D, 0xFFEAF1F4, 0xFF101820, 0xFFAAB8C0, 0xFFC5D0D5, 0x24EAF1F4, 0x1CEAF1F4, 0xFF6DB68F,
   0xFF83B8E8, 0xFF9DABB3, 0xF0141E27, 0xFF6B7B85, 0xFFE07972, 0xFF22303A, 0xFF283741, 0xFF1E2A34},
};
static const BOOL THEME_DARK[WTHEME_COUNT] = {NO, YES, NO, NO, NO, NO, NO, YES};
enum { P_PAPER, P_CARD, P_INK, P_ONINK, P_QUIET, P_MUTE, P_RULE, P_ROWRULE, P_LIVE, P_LINK, P_TABIDLE, P_TABBAR,
       P_CHEVRON, P_BADGE, P_WELL, P_TRACK, P_HOVER };

static WRaw rawTheme(int t) {
  WRaw raw;
  for (int i = 0; i < 17; i++) raw.c[i] = hex(THEMES[t][i]);
  raw.dark = THEME_DARK[t];
  return raw;
}
static CGFloat channel(CGFloat c) { return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4); }
static CGFloat luminance(WRGBA c) { return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b); }
static CGFloat contrast(WRGBA a, WRGBA b) {
  CGFloat x = luminance(a), y = luminance(b);
  return (MAX(x, y) + 0.05) / (MIN(x, y) + 0.05);
}
static WRGBA mix(WRGBA a, WRGBA b, CGFloat t) {
  t = MAX(0, MIN(1, t));
  return (WRGBA){a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, a.a + (b.a - a.a) * t};
}
static BOOL same(WRGBA a, WRGBA b) { return a.r == b.r && a.g == b.g && a.b == b.b && a.a == b.a; }
static WRGBA readable(WRGBA bg, WRGBA fg) {
  if (contrast(bg, fg) >= 4.5) return bg;
  WRGBA target = luminance(fg) < 0.5 ? hex(0xFFFFFFFF) : hex(0xFF111111);
  CGFloat low = 0, high = 1;
  for (int i = 0; i < 12; i++) {
    CGFloat m = (low + high) / 2;
    if (contrast(mix(bg, target, m), fg) >= 4.5) high = m; else low = m;
  }
  return mix(bg, target, high);
}
static WRGBA chroma(WRGBA c, CGFloat intensity) {
  CGFloat k = intensity * 2, l = c.r * 0.2126 + c.g * 0.7152 + c.b * 0.0722;
  return (WRGBA){MAX(0, MIN(1, l + (c.r - l) * k)), MAX(0, MIN(1, l + (c.g - l) * k)), MAX(0, MIN(1, l + (c.b - l) * k)), c.a};
}
/* WyrmPalette.withIntensity, line for line. */
static WRaw withIntensity(WRaw p, CGFloat intensity) {
  intensity = MAX(0, MIN(1, intensity));
  if (fabs(intensity - 0.5) < 0.0001) return p;
  if (intensity >= 0.5) {
    for (int i = 0; i < 17; i++) p.c[i] = chroma(p.c[i], intensity);
    return p;
  }
  WRaw base = rawTheme(0);
  if (intensity < 0.0001) return base;
  CGFloat amount = intensity * 2;
  WRGBA paper = mix(base.c[P_PAPER], p.c[P_PAPER], amount), card = mix(base.c[P_CARD], p.c[P_CARD], amount),
        wellc = mix(base.c[P_WELL], p.c[P_WELL], amount);
  WRGBA surfaces[3] = {paper, card, wellc};
  CGFloat baseScore = 99, themeScore = 99, blackScore = 99, whiteScore = 99;
  for (int i = 0; i < 3; i++) {
    baseScore = MIN(baseScore, contrast(surfaces[i], base.c[P_INK]));
    themeScore = MIN(themeScore, contrast(surfaces[i], p.c[P_INK]));
    blackScore = MIN(blackScore, contrast(surfaces[i], hex(0xFF111111)));
    whiteScore = MIN(whiteScore, contrast(surfaces[i], hex(0xFFFFFFFF)));
  }
  WRGBA fallback = blackScore >= whiteScore ? hex(0xFF111111) : hex(0xFFFFFFFF);
  WRGBA ink = baseScore >= 4.5 && baseScore >= themeScore ? base.c[P_INK] : themeScore >= 4.5 ? p.c[P_INK] : fallback;
  BOOL themeText = same(ink, p.c[P_INK]) || luminance(ink) > 0.5;
  WRGBA onInk = same(ink, base.c[P_INK]) ? base.c[P_ONINK] : same(ink, p.c[P_INK]) ? p.c[P_ONINK]
              : luminance(ink) > 0.5 ? hex(0xFF111111) : hex(0xFFFFFFFF);
  WRaw out = p;
  out.c[P_PAPER] = readable(paper, ink);
  out.c[P_CARD] = readable(card, ink);
  out.c[P_WELL] = readable(wellc, ink);
  out.c[P_INK] = ink;
  out.c[P_ONINK] = onInk;
  int textRoles[] = {P_QUIET, P_MUTE, P_TABIDLE, P_CHEVRON};
  for (int i = 0; i < 4; i++) out.c[textRoles[i]] = themeText ? p.c[textRoles[i]] : base.c[textRoles[i]];
  int mixRoles[] = {P_RULE, P_ROWRULE, P_LIVE, P_LINK, P_TABBAR, P_BADGE, P_TRACK, P_HOVER};
  for (int i = 0; i < 8; i++) out.c[mixRoles[i]] = mix(base.c[mixRoles[i]], p.c[mixRoles[i]], amount);
  out.dark = luminance(out.c[P_PAPER]) < 0.45;
  return out;
}
static NSColor* colourOf(WRGBA c) { return [NSColor colorWithSRGBRed:c.r green:c.g blue:c.b alpha:c.a]; }
WPalette WThemePalette(int theme, CGFloat intensity) {
  WRaw raw = withIntensity(rawTheme(MAX(0, MIN(WTHEME_COUNT - 1, theme))), intensity);
  WPalette p;
  NSColor* __strong* slots[17] = {&p.paper, &p.card, &p.ink, &p.onInk, &p.quiet, &p.mute, &p.rule, &p.rowRule, &p.live,
                                  &p.link, &p.tabIdle, &p.tabBar, &p.chevron, &p.badge, &p.well, &p.track, &p.hover};
  for (int i = 0; i < 17; i++) *slots[i] = colourOf(raw.c[i]);
  p.dark = raw.dark;
  return p;
}
void WThemeApply(int theme, CGFloat intensity) { WP = WThemePalette(theme, intensity); }
int WThemeIndex(NSString* stored) {
  for (int i = 0; i < WTHEME_COUNT; i++) if ([WThemeStored[i] isEqualToString:stored]) return i;
  return 0;
}
static int argbOf(NSColor* c) {
  NSColor* s = [c colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
  int a = (int)lround(s.alphaComponent * 255), r = (int)lround(s.redComponent * 255);
  int g = (int)lround(s.greenComponent * 255), b = (int)lround(s.blueComponent * 255);
  return (int)(((uint32_t)a << 24) | ((uint32_t)r << 16) | ((uint32_t)g << 8) | (uint32_t)b);
}
void WThemePublishToEngine(void) {
  int roles[12] = {argbOf(WP.paper), argbOf(WP.card), argbOf(WP.ink), argbOf(WP.onInk), argbOf(WP.quiet),
                   argbOf(WP.mute), argbOf(WP.rule), argbOf(WP.live), argbOf(WP.link), argbOf(WP.well),
                   argbOf(WP.track), argbOf(WP.badge)};
  wyrm_mac_set_arena_theme(roles, 12, WP.dark);
}

NSColor* rgba(uint32_t argb) { return colourOf(hex(argb)); }
NSColor* WMix(NSColor* a, NSColor* b, CGFloat t) {
  NSColor *x = [a colorUsingColorSpace:NSColorSpace.sRGBColorSpace], *y = [b colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
  return colourOf(mix((WRGBA){x.redComponent, x.greenComponent, x.blueComponent, x.alphaComponent},
                      (WRGBA){y.redComponent, y.greenComponent, y.blueComponent, y.alphaComponent}, t));
}

#pragma mark - Fonts

static CTFontDescriptorRef fontFile(NSString* name) {
  NSURL* url = [NSURL fileURLWithPath:[@"app/res/fonts" stringByAppendingPathComponent:name]];
  CFArrayRef all = CTFontManagerCreateFontDescriptorsFromURL((__bridge CFURLRef)url);
  CTFontDescriptorRef d = all && CFArrayGetCount(all) ? CFRetain(CFArrayGetValueAtIndex(all, 0)) : NULL;
  if (all) CFRelease(all);
  return d;
}
static NSFont* weighted(CTFontDescriptorRef base, CGFloat size, int weight) {
  NSDictionary* axes = @{@0x77676874: @(weight)};
  CTFontDescriptorRef d = CTFontDescriptorCreateCopyWithAttributes(base,
      (__bridge CFDictionaryRef)@{(__bridge id)kCTFontVariationAttribute: axes});
  NSFont* font = (__bridge_transfer NSFont*)CTFontCreateWithFontDescriptor(d, size, NULL);
  CFRelease(d);
  return font;
}
/* Manrope is variable; like Android, each weight is set ~50 heavier than its name. */
NSFont* body(CGFloat size, int weight) {
  static CTFontDescriptorRef manrope;
  static NSCache* cache;
  if (!manrope) { manrope = fontFile(@"wyrm_body.ttf"); cache = [NSCache new]; }
  if (!manrope) return [NSFont systemFontOfSize:size weight:weight >= 700 ? NSFontWeightBold :
                        weight >= 600 ? NSFontWeightSemibold : NSFontWeightRegular];
  NSString* key = [NSString stringWithFormat:@"%.2f/%d", size, weight];
  NSFont* font = [cache objectForKey:key];
  if (!font) { font = weighted(manrope, size, MIN(800, weight + 50)); [cache setObject:font forKey:key]; }
  return font;
}
/* Wyrm.Display: Bodoni Moda. */
NSFont* display(CGFloat size, int weight) {
  static CTFontDescriptorRef bodoni;
  if (!bodoni) bodoni = fontFile(@"wyrm_display.ttf");
  if (!bodoni) return [NSFont fontWithName:@"Didot" size:size] ?: [NSFont systemFontOfSize:size];
  return weighted(bodoni, size, weight);
}

#pragma mark - Small helpers

/* Static text never takes a click: a button under a title (Back under a
   page's title) still gets it. Editable or selectable text does. */
@interface WLabel : NSTextField
@end
@implementation WLabel
- (NSView*)hitTest:(NSPoint)p { return self.isEditable || self.isSelectable ? [super hitTest:p] : nil; }
@end

NSTextField* label(NSString* text, CGFloat size, int weight, NSColor* colour) {
  NSTextField* t = [WLabel labelWithString:text ?: @""];
  t.font = body(size, weight);
  t.textColor = colour;
  t.lineBreakMode = NSLineBreakByTruncatingTail;
  t.maximumNumberOfLines = 1;
  return t;
}
NSTextField* wrapLabel(NSString* text, CGFloat size, int weight, NSColor* colour) {
  NSTextField* t = [WLabel wrappingLabelWithString:text ?: @""];
  t.font = body(size, weight);
  t.textColor = colour;
  t.selectable = NO;
  return t;
}
void lineHeight(NSTextField* t, CGFloat height, NSTextAlignment align) {
  NSMutableParagraphStyle* p = [NSMutableParagraphStyle new];
  p.minimumLineHeight = p.maximumLineHeight = height;
  p.alignment = align;
  p.lineBreakMode = NSLineBreakByWordWrapping;
  t.attributedStringValue = [[NSAttributedString alloc] initWithString:t.stringValue
      attributes:@{NSFontAttributeName: t.font, NSForegroundColorAttributeName: t.textColor, NSParagraphStyleAttributeName: p}];
}
CGFloat placeWrap(NSTextField* t, CGFloat x, CGFloat y, CGFloat w) {
  t.preferredMaxLayoutWidth = w;
  NSSize s = [t.cell cellSizeForBounds:NSMakeRect(0, 0, w, 10000)];
  t.frame = NSMakeRect(x, y, w, ceil(s.height));
  return ceil(s.height);
}
void track(NSTextField* t, CGFloat kern) {
  NSMutableParagraphStyle* p = [NSMutableParagraphStyle new];
  p.alignment = t.alignment;
  p.lineBreakMode = t.lineBreakMode;
  t.attributedStringValue = [[NSAttributedString alloc] initWithString:t.stringValue
      attributes:@{NSFontAttributeName: t.font, NSForegroundColorAttributeName: t.textColor, NSKernAttributeName: @(kern),
                   NSParagraphStyleAttributeName: p}];
}
NSImage* symbol(NSString* name, CGFloat size, NSFontWeight weight) {
  NSImage* image = [NSImage imageWithSystemSymbolName:name accessibilityDescription:nil];
  return [image imageWithSymbolConfiguration:[NSImageSymbolConfiguration configurationWithPointSize:size weight:weight]];
}
NSImageView* glyph(NSString* name, CGFloat size, NSColor* tint) {
  NSImageView* v = [NSImageView imageViewWithImage:symbol(name, size, NSFontWeightSemibold) ?: [NSImage new]];
  v.contentTintColor = tint;
  return v;
}
void place(NSView* v, CGFloat x, CGFloat y, CGFloat w, CGFloat h) { v.frame = NSMakeRect(x, y, w, h); }
void placeLabel(NSTextField* t, CGFloat x, CGFloat y, CGFloat w) {
  [t sizeToFit];
  t.frame = NSMakeRect(x, y, w > 0 ? w : t.frame.size.width, t.frame.size.height);
}
NSString* grouped(long value) {
  return [NSNumberFormatter localizedStringFromNumber:@(value) numberStyle:NSNumberFormatterDecimalStyle];
}
NSView* rule(void) {
  NSView* v = [NSView new];
  v.wantsLayer = YES;
  v.layer.backgroundColor = ROW_RULE.CGColor;
  return v;
}
NSView* well(NSString* symbolName) {
  WFlipped* w = [WFlipped new];
  w.wantsLayer = YES;
  w.layer.backgroundColor = WELL.CGColor;
  w.layer.cornerRadius = 8;
  w.layer.cornerCurve = kCACornerCurveContinuous;
  NSImageView* i = glyph(symbolName, 13, MUTE);
  place(i, 4, 4, 18, 18);
  [w addSubview:i];
  return w;
}
NSTextField* section(NSString* text) {
  NSTextField* t = label(text.uppercaseString, 10.5, 600, QUIET);
  track(t, 0.9);
  return t;
}
void WCopy(NSString* text) {
  [NSPasteboard.generalPasteboard clearContents];
  [NSPasteboard.generalPasteboard setString:text forType:NSPasteboardTypeString];
}
void WOpenURL(NSString* url) { [NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:url]]; }
void WAfter(double seconds, void (^block)(void)) {
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(seconds * NSEC_PER_SEC)), dispatch_get_main_queue(), block);
}

#pragma mark - Motion

CASpringAnimation* WSpring(NSString* keyPath, id from, id to, CGFloat response, CGFloat damping) {
  CASpringAnimation* a = [CASpringAnimation animationWithKeyPath:keyPath];
  CGFloat omega = 2 * M_PI / response;
  a.mass = 1;
  a.stiffness = omega * omega;
  a.damping = 2 * damping * omega;
  a.fromValue = from;
  a.toValue = to;
  a.duration = a.settlingDuration;
  a.fillMode = kCAFillModeBoth;
  return a;
}
CAMediaTimingFunction* WFastOutSlowIn(void) { return [CAMediaTimingFunction functionWithControlPoints:0.4 :0 :0.2 :1]; }
CATransform3D WScaleAbout(NSView* v, CGFloat scale) {
  CGFloat w = v.bounds.size.width / 2, h = v.bounds.size.height / 2;
  CATransform3D t = CATransform3DMakeTranslation(w, h, 0);
  t = CATransform3DScale(t, scale, scale, 1);
  return CATransform3DTranslate(t, -w, -h, 0);
}
void WMaterialise(NSView* v, BOOL appear, CGFloat blur, CGFloat response, CGFloat damping, void (^done)(void)) {
  v.wantsLayer = YES;
  v.layerUsesCoreImageFilters = YES;
  CIFilter* filter = [CIFilter filterWithName:@"CIGaussianBlur"];
  filter.name = @"blur";
  [filter setValue:@(appear ? 0 : blur) forKey:kCIInputRadiusKey];
  v.layer.filters = @[filter];
  CALayer* l = v.layer;
  [CATransaction begin];
  [CATransaction setCompletionBlock:^{
    if (appear) l.filters = nil;
    if (done) done();
  }];
  CASpringAnimation* fade = WSpring(@"opacity", @(appear ? 0 : 1), @(appear ? 1 : 0), response, damping);
  CASpringAnimation* scale = WSpring(@"transform", [NSValue valueWithCATransform3D:appear ? WScaleAbout(v, 0.985) : CATransform3DIdentity],
                                     [NSValue valueWithCATransform3D:appear ? CATransform3DIdentity : WScaleAbout(v, 0.985)], response, damping);
  CASpringAnimation* blurring = WSpring(@"filters.blur.inputRadius", @(appear ? blur : 0), @(appear ? 0 : blur), response, damping);
  fade.removedOnCompletion = scale.removedOnCompletion = blurring.removedOnCompletion = appear;
  l.opacity = appear ? 1 : 0;
  [l addAnimation:fade forKey:@"wfade"];
  [l addAnimation:scale forKey:@"wscale"];
  [l addAnimation:blurring forKey:@"wblur"];
  [CATransaction commit];
}

#pragma mark - Views

@implementation WFlipped
- (BOOL)isFlipped { return YES; }
@end

@implementation WCard
- (instancetype)initWithRadius:(CGFloat)radius {
  if ((self = [super initWithFrame:NSZeroRect])) {
    self.wantsLayer = YES;
    self.layer.backgroundColor = [CARD colorWithAlphaComponent:0.92 * CARD.alphaComponent].CGColor;
    self.layer.cornerRadius = radius;
    self.layer.cornerCurve = kCACornerCurveContinuous;
    self.layer.borderWidth = 1;
    self.layer.borderColor = RULE.CGColor;
    self.layer.shadowColor = INK.CGColor;
    self.layer.shadowOpacity = 0.07;
    self.layer.shadowRadius = 14;
    self.layer.shadowOffset = CGSizeMake(0, -4);
  }
  return self;
}
- (instancetype)init { return [self initWithRadius:17]; }
@end

@implementation WTap
- (instancetype)init {
  if ((self = [super initWithFrame:NSZeroRect])) {
    self.wantsLayer = YES;
    self.layer.cornerCurve = kCACornerCurveContinuous;
    _enabled = YES;
  }
  return self;
}
- (void)refresh {
  NSColor* c = self.inside && self.enabled && self.hover ? self.hover : self.fill;
  self.layer.backgroundColor = c.CGColor;
  self.alphaValue = !self.enabled ? 0.38 : self.down ? 0.78 : 1;
  if (self.pressScale) self.layer.transform = self.down ? WScaleAbout(self, 0.975) : CATransform3DIdentity;
}
- (void)setFill:(NSColor*)fill { _fill = fill; [self refresh]; }
- (void)setHover:(NSColor*)hover { _hover = hover; [self refresh]; }
- (void)setEnabled:(BOOL)enabled { _enabled = enabled; [self refresh]; [self.window invalidateCursorRectsForView:self]; }
- (void)updateTrackingAreas {
  for (NSTrackingArea* a in self.trackingAreas) [self removeTrackingArea:a];
  [self addTrackingArea:[[NSTrackingArea alloc] initWithRect:NSZeroRect
      options:NSTrackingMouseEnteredAndExited | NSTrackingActiveInKeyWindow | NSTrackingInVisibleRect owner:self userInfo:nil]];
  [super updateTrackingAreas];
}
- (void)resetCursorRects { if (self.enabled) [self addCursorRect:self.bounds cursor:NSCursor.pointingHandCursor]; }
- (void)mouseEntered:(NSEvent*)e { self.inside = YES; [self refresh]; }
- (void)mouseExited:(NSEvent*)e { self.inside = NO; self.down = NO; [self refresh]; }
- (void)mouseDown:(NSEvent*)e { if (self.enabled) { self.down = YES; [self refresh]; } }
- (void)mouseUp:(NSEvent*)e {
  BOOL hit = NSPointInRect([self convertPoint:e.locationInWindow fromView:nil], self.bounds);
  BOOL fire = self.down && hit && self.enabled;
  self.down = NO;
  [self refresh];
  if (fire && self.onClick) self.onClick();
}
- (void)rightMouseDown:(NSEvent*)e { if (self.onRightClick) self.onRightClick(e); else [super rightMouseDown:e]; }
- (void)otherMouseDown:(NSEvent*)e { if (self.onRightClick) self.onRightClick(e); else [super otherMouseDown:e]; }
- (BOOL)acceptsFirstMouse:(NSEvent*)e { return YES; }
@end

@implementation WButton
+ (instancetype)primary:(NSString*)text {
  WButton* b = [WButton new];
  b.layer.cornerRadius = 11;
  b.fill = INK;
  b.hover = [INK colorWithAlphaComponent:0.86];
  b.title = label(text, 15, 700, ON_INK);
  [b addSubview:b.title];
  return b;
}
+ (instancetype)well:(NSString*)symbolName text:(NSString*)text {
  WButton* b = [WButton new];
  b.layer.cornerRadius = 11;
  b.fill = WELL;
  b.hover = WMix(WELL, INK, 0.06);
  if (text) { b.title = label(text, 14, 600, INK); [b addSubview:b.title]; }
  if (symbolName) { b.icon = glyph(symbolName, 15, INK); [b addSubview:b.icon]; }
  return b;
}
/* WelcomeCapsule: a solid ink capsule, or a ghost one with a hairline. */
+ (instancetype)capsule:(NSString*)text filled:(BOOL)filled {
  WButton* b = [WButton new];
  b.pressScale = YES;
  b.fill = filled ? INK : NSColor.clearColor;
  b.hover = filled ? [INK colorWithAlphaComponent:0.9] : [INK colorWithAlphaComponent:0.04];
  if (!filled) { b.layer.borderWidth = 1.5; b.layer.borderColor = [INK colorWithAlphaComponent:0.22].CGColor; }
  else {
    b.layer.shadowColor = INK.CGColor;
    b.layer.shadowOpacity = 0.16;
    b.layer.shadowRadius = 14;
    b.layer.shadowOffset = CGSizeMake(0, -6);
  }
  b.title = label(text, 16, filled ? 700 : 600, filled ? ON_INK : INK);
  [b addSubview:b.title];
  return b;
}
+ (instancetype)tinted:(NSString*)text fill:(NSColor*)fill ink:(NSColor*)ink symbol:(NSString*)symbolName {
  WButton* b = [WButton new];
  b.pressScale = YES;
  b.layer.cornerRadius = 15;
  b.fill = fill;
  b.hover = fill.alphaComponent > 0 ? WMix(fill, ink, 0.08) : [INK colorWithAlphaComponent:0.04];
  b.title = label(text, 15, 600, ink);
  [b addSubview:b.title];
  if (symbolName) { b.icon = glyph(symbolName, 15, ink); [b addSubview:b.icon]; }
  return b;
}
- (void)layout {
  [super layout];
  NSSize s = self.bounds.size;
  if (self.layer.borderWidth == 1.5 || self.pressScale) self.layer.cornerRadius = MIN(self.layer.cornerRadius ?: s.height / 2, s.height / 2);
  [self.title sizeToFit];
  CGFloat iw = self.icon ? 18 : 0, gap = self.icon && self.title ? 8 : 0;
  CGFloat tw = self.title ? MIN(self.title.frame.size.width, s.width - iw - gap - 16) : 0;
  CGFloat total = iw + gap + tw, x = (s.width - total) / 2;
  CGFloat ix = self.iconTrailing ? x + tw + gap : x, tx = self.iconTrailing ? x : x + iw + gap;
  if (self.icon) place(self.icon, ix, (s.height - 18) / 2, 18, 18);
  if (self.title) place(self.title, tx, (s.height - self.title.frame.size.height) / 2, tw, self.title.frame.size.height);
}
@end

@implementation WMetric
+ (instancetype)metric:(NSString*)name {
  WMetric* m = [WMetric new];
  m.name = label(name, 9.5, 700, QUIET);
  track(m.name, 0.8);
  m.value = label(@"—", 17, 700, INK);
  [m addSubview:m.name];
  [m addSubview:m.value];
  return m;
}
- (void)setNumber:(NSString*)text { self.value.stringValue = text; }
- (void)layout {
  [super layout];
  CGFloat w = self.bounds.size.width - 36;
  placeLabel(self.name, 18, 12, w);
  placeLabel(self.value, 18, 12 + self.name.frame.size.height + 2, w);
}
@end

#pragma mark - Liquid Glass controls

/* The switch and slider are AppKit's own: on macOS 26 they are Liquid Glass.
   Their tint is the app's accent, which WInstallAccent makes Wyrm's live green. */
static IMP systemAccent;
static NSColor* wyrmAccent(id self, SEL cmd) { return WP.live ?: ((NSColor* (*)(id, SEL))systemAccent)(self, cmd); }
void WInstallAccent(void) {
  /* The app's own domain wins over the system accent for this app only. */
  [NSUserDefaults.standardUserDefaults setInteger:3 forKey:@"AppleAccentColor"];
  Method m = class_getClassMethod(NSColor.class, @selector(controlAccentColor));
  if (m && !systemAccent) systemAccent = method_setImplementation(m, (IMP)wyrmAccent);
}

@interface WSwitch ()
@property(strong) NSSwitch* control;
@end
@implementation WSwitch
- (instancetype)initWithFrame:(NSRect)frame {
  if ((self = [super initWithFrame:frame])) {
    _control = [NSSwitch new];
    _control.target = self;
    _control.action = @selector(toggled:);
    [self addSubview:_control];
  }
  return self;
}
- (BOOL)isFlipped { return YES; }
- (void)toggled:(NSSwitch*)sender {
  _on = sender.state == NSControlStateValueOn;
  if (self.onToggle) self.onToggle(_on);
}
- (void)setOn:(BOOL)on { [self setOn:on animated:NO]; }
- (void)setOn:(BOOL)on animated:(BOOL)animated {
  _on = on;
  NSControlStateValue state = on ? NSControlStateValueOn : NSControlStateValueOff;
  if (animated) [self.control.animator setState:state]; else self.control.state = state;
}
/* A click on the row: the switch's own animation, as if clicked. */
- (void)click { [self.control performClick:nil]; }
- (void)layout {
  [super layout];
  NSSize s = self.control.intrinsicContentSize, b = self.bounds.size;
  self.control.frame = NSMakeRect(b.width - s.width, (b.height - s.height) / 2, s.width, s.height);
}
@end

/* NSSlider follows a drag in a modal loop of its own, and the engine runs on
   this same thread: the arena stood still under a slider and a change showed
   only on release. This one follows the mouse through the window's ordinary
   events, so every value reaches the arena while it is dragged. No tick marks
   (OM): a stepped slider snaps without them. */
@interface WTrackSlider : NSSlider
@property(copy) void (^onDrag)(double value, BOOL ended);
@property CGFloat startX, spanX, grab;
@property BOOL tracking;
@end
@implementation WTrackSlider
- (BOOL)acceptsFirstMouse:(NSEvent*)e { return YES; }
- (BOOL)mouseDownCanMoveWindow { return NO; }
- (NSRect)knob { return [(NSSliderCell*)self.cell knobRectFlipped:self.isFlipped]; }
/* Where the knob's centre sits at the two ends, measured from the cell itself. */
- (void)measure {
  double was = self.doubleValue;
  self.doubleValue = self.minValue;
  CGFloat a = NSMidX(self.knob);
  self.doubleValue = self.maxValue;
  CGFloat b = NSMidX(self.knob);
  self.doubleValue = was;
  self.startX = a;
  self.spanX = MAX(1, b - a);
}
- (void)moveTo:(CGFloat)x ended:(BOOL)ended {
  double t = MAX(0, MIN(1, (x - self.grab - self.startX) / self.spanX));
  if (self.onDrag) self.onDrag(self.minValue + (self.maxValue - self.minValue) * t, ended);
}
- (void)mouseDown:(NSEvent*)e {
  if (!self.enabled) return;
  [self measure];
  CGFloat x = [self convertPoint:e.locationInWindow fromView:nil].x;
  NSRect k = self.knob;
  /* Held by the knob: it keeps its grip; elsewhere on the track it jumps there. */
  self.grab = x >= NSMinX(k) - 2 && x <= NSMaxX(k) + 2 ? x - NSMidX(k) : 0;
  self.tracking = YES;
  [self.cell setHighlighted:YES];
  [self moveTo:x ended:NO];
}
- (void)mouseDragged:(NSEvent*)e {
  if (self.tracking) [self moveTo:[self convertPoint:e.locationInWindow fromView:nil].x ended:NO];
}
- (void)mouseUp:(NSEvent*)e {
  if (!self.tracking) return;
  self.tracking = NO;
  [self.cell setHighlighted:NO];
  [self moveTo:[self convertPoint:e.locationInWindow fromView:nil].x ended:YES];
  [self setNeedsDisplay:YES];
}
/* The page scrolls under a slider; the wheel never moves it. */
- (void)scrollWheel:(NSEvent*)e { [self.nextResponder scrollWheel:e]; }
@end

@interface WSlider ()
@property(strong) WTrackSlider* control;
@end
@implementation WSlider
- (instancetype)initWithFrame:(NSRect)frame {
  if ((self = [super initWithFrame:frame])) {
    _maximum = 1;
    _control = [WTrackSlider sliderWithValue:0 minValue:0 maxValue:1 target:nil action:nil];
    _control.trackFillColor = INK;
    __weak WSlider* weak = self;
    _control.onDrag = ^(double v, BOOL ended) { [weak dragged:v ended:ended]; };
    [self addSubview:_control];
  }
  return self;
}
- (BOOL)isFlipped { return YES; }
- (void)setMinimum:(CGFloat)minimum { _minimum = minimum; self.control.minValue = minimum; }
- (void)setMaximum:(CGFloat)maximum { _maximum = maximum; self.control.maxValue = maximum; }
- (void)setValue:(CGFloat)value { _value = value; self.control.doubleValue = value; }
- (void)setSteps:(int)steps { _steps = steps; }
/* `steps` stops between the two ends, as the tick marks were. */
- (CGFloat)stepped:(CGFloat)v {
  if (self.steps <= 0 || self.maximum <= self.minimum) return v;
  CGFloat step = (self.maximum - self.minimum) / (self.steps + 1);
  return self.minimum + round((v - self.minimum) / step) * step;
}
- (void)dragged:(double)raw ended:(BOOL)ended {
  CGFloat v = [self stepped:raw];
  self.control.doubleValue = v;
  BOOL changed = fabs(v - _value) > 1e-9;
  _value = v;
  if (changed && self.onChange) self.onChange(v);
  if (ended && self.onEnd) self.onEnd();
}
- (void)layout {
  [super layout];
  NSSize b = self.bounds.size;
  CGFloat h = self.control.intrinsicContentSize.height;
  self.control.frame = NSMakeRect(0, (b.height - h) / 2, b.width, h);
}
@end

/* A view that never takes the mouse (the owner handles it). */
@interface WPassView : NSView
@end
@implementation WPassView
- (BOOL)isFlipped { return YES; }
- (NSView*)hitTest:(NSPoint)p { return nil; }
@end

/* The chosen-option thumb as iOS 26 draws it: at rest a plain pill under the
   labels ([rest]); held, a lens of real Liquid Glass (NSGlassEffectView,
   clear, untinted) rises above them a size larger and bends what it passes
   over; let go, it settles back into the pill. */
@implementation WGlassThumb {
  NSView* _glass;
  WPassView* _rest;
}
- (instancetype)initWithFrame:(NSRect)frame {
  if ((self = [super initWithFrame:frame])) {
    self.wantsLayer = YES;
    _rest = [WPassView new];
    _rest.wantsLayer = YES;
    _rest.layer.cornerCurve = kCACornerCurveContinuous;
    if (@available(macOS 26.0, *)) {
      NSGlassEffectView* g = [NSGlassEffectView new];
      g.style = NSGlassEffectViewStyleClear;
      _glass = g;
    } else {
      _glass = [NSView new];
      _glass.wantsLayer = YES;
      _glass.layer.backgroundColor = (WP.dark ? rgba(0xFF3A3B38) : NSColor.whiteColor).CGColor;
      _glass.layer.shadowColor = NSColor.blackColor.CGColor;
      _glass.layer.shadowOpacity = 0.16;
      _glass.layer.shadowRadius = 6;
    }
    [self addSubview:_glass];
    self.alphaValue = 0;
    self.restFill = [INK colorWithAlphaComponent:WP.dark ? 0.14 : 0.08];
  }
  return self;
}
- (BOOL)isFlipped { return YES; }
- (NSView*)hitTest:(NSPoint)p { return nil; }
- (NSView*)rest { return _rest; }
- (void)setRestFill:(NSColor*)fill {
  _restFill = fill;
  _rest.layer.backgroundColor = fill.CGColor;
}
- (void)placeAt:(NSRect)f {
  self.frame = f;
  _rest.frame = f;
  _rest.layer.cornerRadius = f.size.height / 2;
}
- (void)glideTo:(NSRect)f {
  _rest.layer.cornerRadius = f.size.height / 2;
  WGlide(self, f);
  WGlide(_rest, f);
}
- (void)setLifted:(BOOL)lifted {
  if (lifted == _lifted) return;
  _lifted = lifted;
  [self layoutSubtreeIfNeeded];
  CATransform3D to = lifted ? WScaleAbout(self, 1.18) : CATransform3DIdentity;
  CATransform3D from = self.layer.presentationLayer ? ((CALayer*)self.layer.presentationLayer).transform : self.layer.transform;
  self.layer.transform = to;
  [self.layer addAnimation:WSpring(@"transform", [NSValue valueWithCATransform3D:from], [NSValue valueWithCATransform3D:to],
                                   lifted ? 0.3 : 0.42, lifted ? 0.62 : 0.86) forKey:@"lift"];
  [NSAnimationContext runAnimationGroup:^(NSAnimationContext* ctx) {
    ctx.duration = lifted ? 0.14 : 0.26;
    self.animator.alphaValue = lifted ? 1 : 0;
    self->_rest.animator.alphaValue = lifted ? 0 : 1;
  }];
}
- (void)layout {
  [super layout];
  NSSize s = self.bounds.size;
  _glass.frame = self.bounds;
  if (@available(macOS 26.0, *)) ((NSGlassEffectView*)_glass).cornerRadius = s.height / 2;
  else _glass.layer.cornerRadius = s.height / 2;
  if (self.lifted) self.layer.transform = WScaleAbout(self, 1.18);
}
@end

void WGlide(NSView* v, NSRect to) {
  [NSAnimationContext runAnimationGroup:^(NSAnimationContext* ctx) {
    ctx.duration = 0.34;
    ctx.timingFunction = [CAMediaTimingFunction functionWithControlPoints:0.22 :0.8 :0.24 :1];
    ctx.allowsImplicitAnimation = YES;
    v.animator.frame = to;
  }];
}

/* LiquidSegmented: a capsule track; its thumb can be clicked to or dragged
   along, lifting into a glass lens while held, and settles on a choice. */
@interface WSegmented ()
@property(strong) WGlassThumb* thumb;
@property(strong) NSMutableArray<NSTextField*>* labels;
@property BOOL dragging, moved;
@property CGFloat grab, downX;
@end

@implementation WSegmented
- (instancetype)initWithOptions:(NSArray<NSString*>*)options {
  if ((self = [super initWithFrame:NSZeroRect])) {
    self.wantsLayer = YES;
    self.layer.backgroundColor = (WP.dark ? rgba(0x3D767680) : rgba(0x1F767680)).CGColor;
    self.layer.cornerCurve = kCACornerCurveContinuous;
    _options = options;
    _thumb = [WGlassThumb new];
    _thumb.restFill = WP.dark ? [NSColor colorWithWhite:1 alpha:0.16] : CARD;
    _thumb.rest.layer.shadowColor = NSColor.blackColor.CGColor;
    _thumb.rest.layer.shadowOpacity = WP.dark ? 0 : 0.1;
    _thumb.rest.layer.shadowRadius = 3;
    _thumb.rest.layer.shadowOffset = CGSizeMake(0, -1);
    [self addSubview:_thumb.rest];
    _labels = [NSMutableArray new];
    for (NSString* o in options) {
      NSTextField* t = label(o, 13.5, 600, INK);
      t.alignment = NSTextAlignmentCenter;
      [self addSubview:t];
      [_labels addObject:t];
    }
    [self addSubview:_thumb];
  }
  return self;
}
- (BOOL)isFlipped { return YES; }
- (CGFloat)segment { return (self.bounds.size.width - 4) / MAX(1, self.options.count); }
- (NSRect)thumbFrameAt:(NSInteger)i { return NSMakeRect(2 + self.segment * i, 2, self.segment, self.bounds.size.height - 4); }
- (void)setSelected:(NSInteger)selected {
  NSInteger was = _selected;
  _selected = selected;
  [self paintLabels];
  if (self.window && was != selected && !self.dragging) [self.thumb glideTo:[self thumbFrameAt:selected]];
  else [self setNeedsLayout:YES];
}
- (void)paintLabels {
  for (NSUInteger i = 0; i < self.labels.count; i++) {
    NSTextField* t = self.labels[i];
    t.font = body(13.5, (NSInteger)i == self.selected ? 700 : 600);
    t.textColor = (NSInteger)i == self.selected ? INK : MUTE;
  }
}
- (void)layout {
  [super layout];
  NSSize s = self.bounds.size;
  self.layer.cornerRadius = s.height / 2;
  if (!self.dragging) [self.thumb placeAt:[self thumbFrameAt:self.selected]];
  CGFloat seg = self.segment;
  [self paintLabels];
  for (NSUInteger i = 0; i < self.labels.count; i++) {
    NSTextField* t = self.labels[i];
    [t sizeToFit];
    place(t, 2 + seg * i + 4, (s.height - t.frame.size.height) / 2, seg - 8, t.frame.size.height);
  }
}
- (BOOL)acceptsFirstMouse:(NSEvent*)e { return YES; }
- (BOOL)mouseDownCanMoveWindow { return NO; }
- (void)resetCursorRects { [self addCursorRect:self.bounds cursor:NSCursor.pointingHandCursor]; }
- (NSInteger)indexAt:(CGFloat)x { return MAX(0, MIN((NSInteger)self.options.count - 1, (NSInteger)((x - 2) / self.segment))); }
- (void)mouseDown:(NSEvent*)e {
  CGFloat x = [self convertPoint:e.locationInWindow fromView:nil].x;
  self.downX = x;
  self.moved = NO;
  NSRect f = [self thumbFrameAt:self.selected];
  self.dragging = x >= NSMinX(f) - 4 && x <= NSMaxX(f) + 4;
  self.grab = x - f.origin.x;
  if (self.dragging) self.thumb.lifted = YES;
}
- (void)mouseDragged:(NSEvent*)e {
  if (!self.dragging) return;
  CGFloat x = [self convertPoint:e.locationInWindow fromView:nil].x;
  if (fabs(x - self.downX) > 2) self.moved = YES;
  NSRect f = self.thumb.frame;
  f.origin.x = MAX(2, MIN(self.bounds.size.width - 2 - f.size.width, x - self.grab));
  [self.thumb placeAt:f];
  /* The label under the lens reads as chosen while it passes. */
  NSInteger under = [self indexAt:NSMidX(f)];
  for (NSUInteger i = 0; i < self.labels.count; i++) self.labels[i].textColor = (NSInteger)i == under ? INK : MUTE;
}
- (void)mouseUp:(NSEvent*)e {
  CGFloat x = [self convertPoint:e.locationInWindow fromView:nil].x;
  NSInteger target = self.dragging && self.moved ? [self indexAt:NSMidX(self.thumb.frame)] : [self indexAt:x];
  BOOL wasDragging = self.dragging;
  self.dragging = NO;
  self.thumb.lifted = NO;
  if (target != self.selected) {
    self.selected = target;
    if (self.onSelect) self.onSelect(target);
  } else if (wasDragging) [self.thumb glideTo:[self thumbFrameAt:target]];
  [self paintLabels];
}
@end

#pragma mark - Spinner, mark, shimmer

@implementation WSpinner
- (instancetype)initWithFrame:(NSRect)frame {
  if ((self = [super initWithFrame:frame])) { self.wantsLayer = YES; _colour = QUIET; }
  return self;
}
- (void)viewDidMoveToWindow {
  [self.layer removeAllAnimations];
  self.layer.sublayers = nil;
  if (!self.window) return;
  CGFloat s = MIN(self.bounds.size.width, self.bounds.size.height);
  CAShapeLayer* arc = [CAShapeLayer layer];
  arc.frame = CGRectMake(0, 0, s, s);
  CGPathRef path = CGPathCreateWithEllipseInRect(CGRectInset(arc.frame, 1.5, 1.5), NULL);
  arc.path = path;
  CGPathRelease(path);
  arc.fillColor = NSColor.clearColor.CGColor;
  arc.strokeColor = self.colour.CGColor;
  arc.lineWidth = 2.2;
  arc.lineCap = kCALineCapRound;
  arc.strokeEnd = 0.72;
  [self.layer addSublayer:arc];
  self.layer.sublayerTransform = CATransform3DIdentity;
  CABasicAnimation* spin = [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
  spin.fromValue = @0;
  spin.toValue = @(-2 * M_PI);
  spin.duration = 0.9;
  spin.repeatCount = HUGE_VALF;
  arc.anchorPoint = CGPointMake(0.5, 0.5);
  arc.position = CGPointMake(s / 2, s / 2);
  [arc addAnimation:spin forKey:@"spin"];
}
@end

@implementation WMark
- (BOOL)isFlipped { return YES; }
/* The three curves of WyrmMark, each its own subpath so the round caps draw the peaks. */
- (void)drawRect:(NSRect)dirty {
  CGFloat w = self.markSize, h = w * 0.78;
  CGFloat left = self.bounds.size.width / 2 - w / 2, top = self.bounds.size.height / 2 - h / 2;
  NSBezierPath* p = [NSBezierPath bezierPath];
#define PT(x, y) NSMakePoint(left + w * (x), top + h * (y))
  [p moveToPoint:PT(0.06, 0.10)];
  [p curveToPoint:PT(0.36, 0.38) controlPoint1:PT(0.13, 0.92) controlPoint2:PT(0.30, 0.96)];
  [p moveToPoint:PT(0.36, 0.38)];
  [p curveToPoint:PT(0.64, 0.38) controlPoint1:PT(0.42, 0.94) controlPoint2:PT(0.58, 0.94)];
  [p moveToPoint:PT(0.64, 0.38)];
  [p curveToPoint:PT(0.94, 0.10) controlPoint1:PT(0.70, 0.96) controlPoint2:PT(0.87, 0.92)];
#undef PT
  p.lineWidth = w * 0.16;
  p.lineCapStyle = NSLineCapStyleRound;
  p.lineJoinStyle = NSLineJoinStyleRound;
  CGContextRef ctx = NSGraphicsContext.currentContext.CGContext;
  CGContextSaveGState(ctx);
  CGContextAddPath(ctx, p.CGPath);
  CGContextSetLineWidth(ctx, p.lineWidth);
  CGContextSetLineCap(ctx, kCGLineCapRound);
  CGContextSetLineJoin(ctx, kCGLineJoinRound);
  CGContextReplacePathWithStrokedPath(ctx);
  CGContextClip(ctx);
  NSGradient* g = [[NSGradient alloc] initWithStartingColor:[INK colorWithAlphaComponent:0.76] endingColor:INK];
  [g drawFromPoint:NSMakePoint(left, top) toPoint:NSMakePoint(left + w, top + h) options:NSGradientDrawsBeforeStartingLocation | NSGradientDrawsAfterEndingLocation];
  CGContextRestoreGState(ctx);
}
@end

@interface WShimmer ()
@property(strong) NSTextField* bright;
@property(strong) CAGradientLayer* band;
@end

@implementation WShimmer
- (instancetype)initWithFrame:(NSRect)frame {
  if ((self = [super initWithFrame:frame])) {
    _text = label(@"", 13, 700, [QUIET colorWithAlphaComponent:0.58]);
    _bright = label(@"", 13, 700, [INK colorWithAlphaComponent:0.96]);
    _text.alignment = _bright.alignment = NSTextAlignmentCenter;
    [self addSubview:_text];
    [self addSubview:_bright];
    _bright.wantsLayer = YES;
    _band = [CAGradientLayer layer];
    _band.startPoint = CGPointMake(0, 0.5);
    _band.endPoint = CGPointMake(1, 0.5);
    _band.colors = @[(id)NSColor.clearColor.CGColor, (id)NSColor.blackColor.CGColor, (id)NSColor.clearColor.CGColor];
  }
  return self;
}
- (BOOL)isFlipped { return YES; }
- (void)setTitle:(NSString*)title {
  self.text.stringValue = self.bright.stringValue = title;
  track(self.text, 0.55);
  track(self.bright, 0.55);
  [self setNeedsLayout:YES];
}
- (void)layout {
  [super layout];
  place(self.text, 0, 0, self.bounds.size.width, self.bounds.size.height);
  place(self.bright, 0, 0, self.bounds.size.width, self.bounds.size.height);
  [self.text sizeToFit];
  CGFloat tw = self.text.frame.size.width, w = self.bounds.size.width;
  place(self.text, 0, 0, w, self.bounds.size.height);
  CGFloat bandW = MAX(72, tw * 0.58), textLeft = (w - tw) / 2;
  self.band.frame = CGRectMake(0, 0, bandW, self.bounds.size.height);
  self.bright.layer.mask = self.band;
  [self.band removeAllAnimations];
  CABasicAnimation* sweep = [CABasicAnimation animationWithKeyPath:@"position.x"];
  sweep.fromValue = @(textLeft - 1.4 * tw + bandW / 2);
  sweep.toValue = @(textLeft + 1.5 * tw + bandW / 2);
  sweep.duration = 1.35;
  sweep.repeatCount = HUGE_VALF;
  [self.band addAnimation:sweep forKey:@"sweep"];
}
@end

/* A field's text and placeholder stand in the middle of its height, while
   typing too (the field editor takes the same rect). */
static NSRect centredLine(NSRect r, NSFont* font) {
  static NSLayoutManager* lm;
  if (!lm) lm = [NSLayoutManager new];
  CGFloat h = ceil([lm defaultLineHeightForFont:font ?: body(14, 400)]);
  if (r.size.height > h) { r.origin.y += floor((r.size.height - h) / 2); r.size.height = h; }
  return r;
}
@interface WFieldCell : NSTextFieldCell
@end
@implementation WFieldCell
- (NSRect)drawingRectForBounds:(NSRect)rect { return centredLine([super drawingRectForBounds:rect], self.font); }
@end
@interface WSecureFieldCell : NSSecureTextFieldCell
@end
@implementation WSecureFieldCell
- (NSRect)drawingRectForBounds:(NSRect)rect { return centredLine([super drawingRectForBounds:rect], self.font); }
@end

NSTextField* WField(NSString* placeholder, CGFloat size, int weight, BOOL secure) {
  NSTextField* f = secure ? [NSSecureTextField new] : [NSTextField new];
  NSTextFieldCell* cell = secure ? [[WSecureFieldCell alloc] initTextCell:@""] : [[WFieldCell alloc] initTextCell:@""];
  cell.editable = YES;
  cell.selectable = YES;
  f.cell = cell;
  f.bezeled = NO;
  f.bordered = NO;
  f.drawsBackground = NO;
  f.focusRingType = NSFocusRingTypeNone;
  f.font = body(size, weight);
  f.textColor = INK;
  f.cell.scrollable = YES;
  f.cell.wraps = NO;
  /* Never usesSingleLineMode: with Manrope it draws the text 18 pt above the field. */
  f.placeholderAttributedString = [[NSAttributedString alloc] initWithString:placeholder ?: @""
      attributes:@{NSFontAttributeName: body(size, weight), NSForegroundColorAttributeName: [QUIET colorWithAlphaComponent:0.55]}];
  return f;
}

#pragma mark - Avatar

NSString* WInitials(NSString* name) {
  NSMutableString* out = [NSMutableString new];
  for (NSString* word in [name componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceCharacterSet]) {
    if (!word.length) continue;
    [out appendString:[word substringToIndex:[word rangeOfComposedCharacterSequenceAtIndex:0].length]];
    if (out.length >= 2) break;
  }
  return out.length ? out.uppercaseString : @"W";
}

@interface WAvatar ()
@property(strong) NSImageView* image;
@property(strong) NSTextField* letters;
@property(copy) NSString* url;
@end

@implementation WAvatar
static NSCache* avatarCache;
- (instancetype)initWithFrame:(NSRect)frame {
  if ((self = [super initWithFrame:frame])) {
    self.wantsLayer = YES;
    self.layer.backgroundColor = INK.CGColor;
    self.layer.cornerCurve = kCACornerCurveContinuous;
    self.layer.masksToBounds = YES;
    _corner = -1;
    _letters = label(@"W", 13, 700, ON_INK);
    _letters.alignment = NSTextAlignmentCenter;
    _image = [NSImageView new];
    _image.imageScaling = NSImageScaleAxesIndependently;
    [self addSubview:_letters];
    [self addSubview:_image];
  }
  return self;
}
- (BOOL)isFlipped { return YES; }
- (void)setURL:(NSString*)url initials:(NSString*)initials {
  self.letters.stringValue = initials ?: @"W";
  if ([url isEqualToString:self.url]) return;
  self.url = url;
  self.image.image = nil;
  if (!url.length) return;
  if (!avatarCache) avatarCache = [NSCache new];
  NSImage* cached = [avatarCache objectForKey:url];
  if (cached) { self.image.image = cached; return; }
  __weak WAvatar* weak = self;
  [[NSURLSession.sharedSession dataTaskWithURL:[NSURL URLWithString:url] completionHandler:^(NSData* d, NSURLResponse* r, NSError* e) {
    NSImage* img = d ? [[NSImage alloc] initWithData:d] : nil;
    dispatch_async(dispatch_get_main_queue(), ^{
      if (!img) return;
      [avatarCache setObject:img forKey:url];
      if ([weak.url isEqualToString:url]) weak.image.image = img;
    });
  }] resume];
}
- (void)layout {
  [super layout];
  NSSize s = self.bounds.size;
  self.layer.cornerRadius = self.corner >= 0 ? self.corner : s.width * 0.3;
  self.letters.font = body(MAX(11, s.width * 0.36), 700);
  [self.letters sizeToFit];
  place(self.letters, 0, (s.height - self.letters.frame.size.height) / 2, s.width, self.letters.frame.size.height);
  place(self.image, 0, 0, s.width, s.height);
}
@end

#pragma mark - Live theme (a slider's drag recolours what is on screen)

/* Theme intensity changes as it is dragged (OM): every colour on screen that is
   one of the palette's seventeen roles (or one of them at another alpha) takes
   the new palette's role; drawn views draw again from WP. Release builds the
   shell again from the stored value, so anything mixed from two roles is exact
   by then. */
typedef struct { CGFloat r, g, b, a; } WComp;
static WComp liveFrom[17], liveTo[17];
static NSColor* __strong liveToColour[17];
static BOOL compsOf(NSColor* c, WComp* out) {
  NSColor* s = [c colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
  if (!s) return NO;
  *out = (WComp){s.redComponent, s.greenComponent, s.blueComponent, s.alphaComponent};
  return YES;
}
static NSArray<NSColor*>* roleList(WPalette p) {
  return @[p.paper, p.card, p.ink, p.onInk, p.quiet, p.mute, p.rule, p.rowRule, p.live, p.link, p.tabIdle, p.tabBar,
           p.chevron, p.badge, p.well, p.track, p.hover];
}
static NSColor* remap(NSColor* c) {
  if (!c) return nil;
  WComp x;
  if (!compsOf(c, &x)) return c;
  int rgbMatch = -1;
  for (int i = 0; i < 17; i++) {
    WComp f = liveFrom[i];
    if (fabs(f.r - x.r) < 0.003 && fabs(f.g - x.g) < 0.003 && fabs(f.b - x.b) < 0.003) {
      if (fabs(f.a - x.a) < 0.003) return liveToColour[i];
      if (rgbMatch < 0) rgbMatch = i;
    }
  }
  if (rgbMatch < 0) return c;
  WComp f = liveFrom[rgbMatch], t = liveTo[rgbMatch];
  return [liveToColour[rgbMatch] colorWithAlphaComponent:f.a > 0.001 ? MIN(1, x.a * t.a / f.a) : x.a];
}
static CGColorRef remapCG(CGColorRef c) {
  if (!c) return c;
  NSColor* from = [NSColor colorWithCGColor:c];
  NSColor* to = remap(from);
  return to == from ? c : to.CGColor;
}
static NSAttributedString* remapText(NSAttributedString* s) {
  if (!s.length) return s;
  NSMutableAttributedString* m = [s mutableCopy];
  __block BOOL changed = NO;
  [s enumerateAttribute:NSForegroundColorAttributeName inRange:NSMakeRange(0, s.length) options:0
             usingBlock:^(NSColor* c, NSRange r, BOOL* stop) {
    NSColor* to = remap(c);
    if (c && to != c) { [m addAttribute:NSForegroundColorAttributeName value:to range:r]; changed = YES; }
  }];
  return changed ? m : s;
}
static void recolourLayer(CALayer* l, NSMutableSet* seen) {
  if (!l) return;
  NSValue* key = [NSValue valueWithPointer:(__bridge void*)l];
  if ([seen containsObject:key]) return;
  [seen addObject:key];
  if (l.backgroundColor) l.backgroundColor = remapCG(l.backgroundColor);
  if (l.borderColor) l.borderColor = remapCG(l.borderColor);
  if (l.shadowColor) l.shadowColor = remapCG(l.shadowColor);
  if ([l isKindOfClass:CAShapeLayer.class]) {
    CAShapeLayer* s = (CAShapeLayer*)l;
    if (s.fillColor) s.fillColor = remapCG(s.fillColor);
    if (s.strokeColor) s.strokeColor = remapCG(s.strokeColor);
  }
  for (CALayer* sub in l.sublayers.copy) recolourLayer(sub, seen);
}
static void recolourView(NSView* v) {
  if ([v isKindOfClass:NSTextField.class]) {
    NSTextField* t = (NSTextField*)v;
    if (!t.currentEditor) {
      NSAttributedString* a = t.attributedStringValue;
      t.textColor = remap(t.textColor);
      NSAttributedString* b = remapText(a);
      if (b != a) t.attributedStringValue = b;
    }
    if (t.placeholderAttributedString) t.placeholderAttributedString = remapText(t.placeholderAttributedString);
    if (t.drawsBackground) t.backgroundColor = remap(t.backgroundColor);
  } else if ([v isKindOfClass:NSImageView.class]) {
    NSImageView* i = (NSImageView*)v;
    if (i.contentTintColor) i.contentTintColor = remap(i.contentTintColor);
  } else if ([v isKindOfClass:NSSlider.class]) {
    NSSlider* s = (NSSlider*)v;
    if (s.trackFillColor) s.trackFillColor = remap(s.trackFillColor);
  } else if ([v isKindOfClass:NSTextView.class]) {
    NSTextView* t = (NSTextView*)v;
    t.textColor = remap(t.textColor);
    t.insertionPointColor = remap(t.insertionPointColor);
    if (t.drawsBackground) t.backgroundColor = remap(t.backgroundColor);
  } else if ([v isKindOfClass:WTap.class]) {
    WTap* t = (WTap*)v;
    t.hover = remap(t.hover);
    t.fill = remap(t.fill);
  }
  if (@available(macOS 26.0, *)) {
    if ([v isKindOfClass:NSGlassEffectView.class]) {
      NSGlassEffectView* g = (NSGlassEffectView*)v;
      if (g.tintColor) g.tintColor = remap(g.tintColor);
    }
  }
  [v setNeedsDisplay:YES];
  for (NSView* sub in v.subviews.copy) recolourView(sub);
}
void WRecolour(NSWindow* window, WPalette fromPalette) {
  if (!window.contentView) return;
  NSArray* from = roleList(fromPalette);
  NSArray* to = roleList(WP);
  for (int i = 0; i < 17; i++) {
    if (!compsOf(from[i], &liveFrom[i])) liveFrom[i] = (WComp){-1, -1, -1, -1};
    compsOf(to[i], &liveTo[i]);
    liveToColour[i] = to[i];
  }
  /* Layers first, once each, then the views' own colours (a tap's fill writes its layer). */
  recolourLayer(window.contentView.layer, [NSMutableSet new]);
  recolourView(window.contentView);
  window.backgroundColor = PAPER;
  window.appearance = [NSAppearance appearanceNamed:WP.dark ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua];
}
static void applyLive(NSWindow* window, int theme, CGFloat intensity) {
  WPalette from = WP;
  WThemeApply(theme, intensity);
  WRecolour(window, from);
}
void WThemeLive(NSWindow* window, int theme, CGFloat intensity) {
  static BOOL scheduled;
  static __weak NSWindow* pendingWindow;
  static int pendingTheme;
  static CGFloat pendingIntensity;
  pendingWindow = window;
  pendingTheme = theme;
  pendingIntensity = intensity;
  if (scheduled) return;
  scheduled = YES;
  /* At most ~40 passes a second, always ending on the newest value. */
  WAfter(0.025, ^{
    scheduled = NO;
    applyLive(pendingWindow, pendingTheme, pendingIntensity);
  });
}

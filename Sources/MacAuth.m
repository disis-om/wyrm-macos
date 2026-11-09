#import "MacAuth.h"
#import "MacModel.h"

/* Wyrm Desktop's sign-in (DesktopAuth.kt) on the Mac: the desktop's opening,
   then the phones' cinematic flow exactly — the same stages, checks,
   wording, timings and springs (response 0.58, damping 0.86 unless noted).

   Opening: a blank page; the W materialises out of a blur in the middle,
   rises a little as "The arena and people in it." materialises under it,
   then both settle higher while the two capsules materialise below. */

typedef NS_ENUM(NSInteger, WStage) {
  WStageLanding, WStageCreateUsername, WStageCreatePassword, WStageCreateConfirmation,
  WStageLoginUsername, WStageLoginPassword, WStageCreating, WStageSigningIn, WStageSuccess, WStageWorking
};
typedef NS_ENUM(NSInteger, WOpening) { WOpeningBlank, WOpeningMark, WOpeningLine, WOpeningActions };
enum { AV_IDLE, AV_CHECKING, AV_AVAILABLE, AV_TAKEN, AV_UNAVAILABLE };
enum { CF_IDLE, CF_CHECKING, CF_MATCHED, CF_MISMATCHED };

static BOOL usernameOK(NSString* u) {
  static NSRegularExpression* re;
  if (!re) re = [NSRegularExpression regularExpressionWithPattern:@"^[A-Za-z0-9_]{3,20}$" options:0 error:nil];
  return [re numberOfMatchesInString:u options:0 range:NSMakeRange(0, u.length)] == 1;
}

/* Frame changes on a spring-like ease (the views are AppKit's; the W is pure Core Animation). */
static void glide(NSView* v, NSRect to, CGFloat response) {
  [NSAnimationContext runAnimationGroup:^(NSAnimationContext* ctx) {
    ctx.duration = response * 1.25;
    ctx.timingFunction = [CAMediaTimingFunction functionWithControlPoints:0.22 :0.9 :0.24 :1];
    ctx.allowsImplicitAnimation = YES;
    v.animator.frame = to;
  }];
}

#pragma mark - The W as a layer

/* WyrmBrandMark on a layer-hosting view that never takes the mouse. */
@interface WMarkLayerHost : NSView
@property(strong) CALayer* mark;
@property(strong) CAShapeLayer* stroke;
@property(strong) CAGradientLayer* gradient;
@property CGFloat drawn;
@end

@implementation WMarkLayerHost
- (instancetype)initWithFrame:(NSRect)frame {
  if ((self = [super initWithFrame:frame])) {
    self.layer = [CALayer layer];
    self.wantsLayer = YES;
    self.layerUsesCoreImageFilters = YES;
    _drawn = 132;
    _mark = [CALayer layer];
    _gradient = [CAGradientLayer layer];
    _stroke = [CAShapeLayer layer];
    CGFloat box = _drawn * 1.6;
    _mark.bounds = _gradient.frame = _stroke.frame = CGRectMake(0, 0, box, box);
    _gradient.colors = @[(id)[INK colorWithAlphaComponent:0.76].CGColor, (id)INK.CGColor];
    CGFloat w = _drawn, h = w * 0.78, left = box / 2 - w / 2, top = box / 2 - h / 2;
    _gradient.startPoint = CGPointMake(left / box, top / box);
    _gradient.endPoint = CGPointMake((left + w) / box, (top + h) / box);
    CGMutablePathRef p = CGPathCreateMutable();
#define PT(x, y) left + w * (x), top + h * (y)
    CGPathMoveToPoint(p, NULL, PT(0.06, 0.10));
    CGPathAddCurveToPoint(p, NULL, PT(0.13, 0.92), PT(0.30, 0.96), PT(0.36, 0.38));
    CGPathMoveToPoint(p, NULL, PT(0.36, 0.38));
    CGPathAddCurveToPoint(p, NULL, PT(0.42, 0.94), PT(0.58, 0.94), PT(0.64, 0.38));
    CGPathMoveToPoint(p, NULL, PT(0.64, 0.38));
    CGPathAddCurveToPoint(p, NULL, PT(0.70, 0.96), PT(0.87, 0.92), PT(0.94, 0.10));
#undef PT
    _stroke.path = p;
    CGPathRelease(p);
    _stroke.fillColor = NSColor.clearColor.CGColor;
    _stroke.strokeColor = NSColor.blackColor.CGColor;
    _stroke.lineWidth = w * 0.16;
    _stroke.lineCap = kCALineCapRound;
    _stroke.lineJoin = kCALineJoinRound;
    _gradient.mask = _stroke;
    [_mark addSublayer:_gradient];
    CIFilter* blur = [CIFilter filterWithName:@"CIGaussianBlur"];
    blur.name = @"blur";
    [blur setValue:@0 forKey:kCIInputRadiusKey];
    _mark.filters = @[blur];
    _mark.opacity = 0;
    [self.layer addSublayer:_mark];
  }
  return self;
}
- (BOOL)isFlipped { return YES; }
- (NSView*)hitTest:(NSPoint)p { return nil; }
/* The mark's size on screen, its centre (flipped, from the top), scale, alpha and blur. */
- (void)size:(CGFloat)size centreY:(CGFloat)y scale:(CGFloat)scale alpha:(CGFloat)alpha blur:(CGFloat)blur
    response:(CGFloat)response damping:(CGFloat)damping animated:(BOOL)animated {
  CALayer* m = self.mark;
  CALayer* now = m.presentationLayer ?: m;
  CGPoint to = CGPointMake(self.bounds.size.width / 2, y);
  CATransform3D t = CATransform3DMakeScale(size / self.drawn * scale, size / self.drawn * scale, 1);
  NSValue* fromPos = [NSValue valueWithPoint:now.position];
  NSValue* fromT = [NSValue valueWithCATransform3D:now.transform];
  NSNumber* fromA = @(now.opacity);
  NSNumber* fromB = [now valueForKeyPath:@"filters.blur.inputRadius"] ?: @0;
  [CATransaction begin];
  [CATransaction setDisableActions:YES];
  m.position = to;
  m.transform = t;
  m.opacity = alpha;
  [m setValue:@(blur) forKeyPath:@"filters.blur.inputRadius"];
  [CATransaction commit];
  if (!animated) return;
  [m addAnimation:WSpring(@"position", fromPos, [NSValue valueWithPoint:to], response, damping) forKey:@"pos"];
  [m addAnimation:WSpring(@"transform", fromT, [NSValue valueWithCATransform3D:t], 0.58, 0.86) forKey:@"size"];
}
/* A timed change of alpha / blur / scale (the first arrival and the dissolve). */
- (void)fadeAlpha:(CGFloat)a0 to:(CGFloat)a1 blur:(CGFloat)b0 to:(CGFloat)b1 scaleFrom:(CGFloat)s0 to:(CGFloat)s1 duration:(CGFloat)d {
  CALayer* m = self.mark;
  CATransform3D base = m.transform;
  CAAnimationGroup* g = [CAAnimationGroup animation];
  CABasicAnimation* fa = [CABasicAnimation animationWithKeyPath:@"opacity"];
  fa.fromValue = @(a0); fa.toValue = @(a1);
  CABasicAnimation* fb = [CABasicAnimation animationWithKeyPath:@"filters.blur.inputRadius"];
  fb.fromValue = @(b0); fb.toValue = @(b1);
  CABasicAnimation* fs = [CABasicAnimation animationWithKeyPath:@"transform"];
  fs.fromValue = [NSValue valueWithCATransform3D:CATransform3DScale(base, s0, s0, 1)];
  fs.toValue = [NSValue valueWithCATransform3D:CATransform3DScale(base, s1, s1, 1)];
  g.animations = @[fa, fb, fs];
  g.duration = d;
  g.timingFunction = WFastOutSlowIn();
  [CATransaction begin];
  [CATransaction setDisableActions:YES];
  m.opacity = a1;
  [m setValue:@(b1) forKeyPath:@"filters.blur.inputRadius"];
  m.transform = CATransform3DScale(base, s1, s1, 1);
  [CATransaction commit];
  [m addAnimation:g forKey:@"timed"];
}
@end

#pragma mark - Pieces

/* The white composer every credential sits in: 60 tall, 17 continuous corners. */
static WFlipped* composer(void) {
  WFlipped* c = [WFlipped new];
  c.wantsLayer = YES;
  c.layer.backgroundColor = [CARD colorWithAlphaComponent:0.94].CGColor;
  c.layer.cornerRadius = 17;
  c.layer.cornerCurve = kCACornerCurveContinuous;
  c.layer.borderWidth = 1;
  c.layer.borderColor = RULE.CGColor;
  c.layer.shadowColor = INK.CGColor;
  c.layer.shadowOpacity = 0.045;
  c.layer.shadowRadius = 22;
  c.layer.shadowOffset = CGSizeMake(0, -9);
  return c;
}
static NSView* circleMark(NSString* symbolName, NSColor* fill, CGFloat size, CGFloat glyphSize) {
  WFlipped* v = [WFlipped new];
  v.wantsLayer = YES;
  v.layer.backgroundColor = fill.CGColor;
  v.layer.cornerRadius = size / 2;
  v.frame = NSMakeRect(0, 0, size, size);
  NSImageView* i = glyph(symbolName, glyphSize, NSColor.whiteColor);
  i.image = symbol(symbolName, glyphSize, NSFontWeightHeavy);
  place(i, (size - glyphSize - 4) / 2, (size - glyphSize - 4) / 2, glyphSize + 4, glyphSize + 4);
  [v addSubview:i];
  return v;
}

/* `WyrmAuthKeyboardAction`: a compact pill, ink when it can go, a quiet well while it cannot. */
@interface WActionPill : WTap
@property(strong) NSTextField* text;
@property(strong) NSImageView* arrow;
- (void)setTitle:(NSString*)title enabled:(BOOL)enabled;
@end
@implementation WActionPill
- (instancetype)init {
  if ((self = [super init])) {
    self.pressScale = YES;
    self.layer.cornerRadius = 23;
    _text = label(@"", 15, 600, ON_INK);
    _arrow = glyph(@"arrow.right", 14, ON_INK);
    [self addSubview:_text];
    [self addSubview:_arrow];
  }
  return self;
}
- (void)setTitle:(NSString*)title enabled:(BOOL)enabled {
  self.text.stringValue = title;
  self.enabled = YES;
  self.fill = enabled ? INK : WELL;
  self.hover = enabled ? [INK colorWithAlphaComponent:0.9] : WELL;
  self.text.textColor = enabled ? ON_INK : QUIET;
  self.arrow.contentTintColor = enabled ? ON_INK : QUIET;
  self.layer.shadowColor = INK.CGColor;
  self.layer.shadowOpacity = enabled ? 0.14 : 0;
  self.layer.shadowRadius = 12;
  self.layer.shadowOffset = CGSizeMake(0, -5);
  self.alphaValue = 1;
  [self.text sizeToFit];
}
- (CGFloat)width { [self.text sizeToFit]; return 20 + self.text.frame.size.width + 8 + 15 + 16; }
- (void)refresh { [super refresh]; self.alphaValue = self.down ? 0.85 : 1; }
- (void)layout {
  [super layout];
  [self.text sizeToFit];
  place(self.text, 20, (46 - self.text.frame.size.height) / 2, self.text.frame.size.width, self.text.frame.size.height);
  place(self.arrow, 20 + self.text.frame.size.width + 8, 14, 17, 18);
}
@end

#pragma mark - Privacy policy (Android's PrivacyScreen document)

NSView* WPrivacyDocument(CGFloat width, CGFloat* height) {
  WFlipped* doc = [WFlipped new];
  NSString* source = [NSString stringWithContentsOfFile:[NSBundle.mainBundle pathForResource:@"PRIVACY" ofType:@"md"]
                                               encoding:NSUTF8StringEncoding error:nil] ?: @"The privacy policy could not be opened on this computer.";
  NSRegularExpression* link = [NSRegularExpression regularExpressionWithPattern:@"\\[([^\\]]+)\\]\\(([^)]+)\\)" options:0 error:nil];
  __block CGFloat y = 0;
  NSMutableString* paragraph = [NSMutableString new];
  NSAttributedString* (^inline_)(NSString*, CGFloat, NSColor*) = ^NSAttributedString*(NSString* s, CGFloat size, NSColor* colour) {
    s = [link stringByReplacingMatchesInString:s options:0 range:NSMakeRange(0, s.length) withTemplate:@"$1"];
    NSMutableAttributedString* out = [NSMutableAttributedString new];
    NSArray* parts = [s componentsSeparatedByString:@"**"];
    NSMutableParagraphStyle* p = [NSMutableParagraphStyle new];
    p.minimumLineHeight = p.maximumLineHeight = size * 1.57;
    for (NSUInteger i = 0; i < parts.count; i++)
      [out appendAttributedString:[[NSAttributedString alloc] initWithString:parts[i] attributes:@{
        NSFontAttributeName: body(size, i % 2 ? 700 : 400), NSForegroundColorAttributeName: i % 2 ? INK : colour,
        NSParagraphStyleAttributeName: p}]];
    return out;
  };
  void (^add)(NSAttributedString*, CGFloat, CGFloat, CGFloat) = ^(NSAttributedString* text, CGFloat x, CGFloat before, CGFloat after) {
    NSTextField* t = [NSTextField wrappingLabelWithString:@""];
    t.attributedStringValue = text;
    t.selectable = NO;
    y += before;
    y += placeWrap(t, x, y, width - x) + after;
    [doc addSubview:t];
  };
  void (^flush)(void) = ^{
    if (!paragraph.length) return;
    add(inline_([paragraph stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet], 14, MUTE), 0, 0, 12);
    [paragraph setString:@""];
  };
  for (NSString* raw in [source componentsSeparatedByString:@"\n"]) {
    NSString* line = [raw stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    if (!line.length) { flush(); continue; }
    if ([line hasPrefix:@"# "]) {
      flush();
      add([[NSAttributedString alloc] initWithString:[line substringFromIndex:2] attributes:@{NSFontAttributeName: body(22, 700), NSForegroundColorAttributeName: INK}], 0, 20, 6);
    } else if ([line hasPrefix:@"## "] || [line hasPrefix:@"### "]) {
      flush();
      BOOL two = [line hasPrefix:@"## "];
      add([[NSAttributedString alloc] initWithString:[line substringFromIndex:two ? 3 : 4] attributes:@{
        NSFontAttributeName: body(two ? 17 : 14, 700), NSForegroundColorAttributeName: two ? INK : QUIET, NSKernAttributeName: @(two ? 0 : 1.2)}], 0, 26, 8);
    } else if ([line hasPrefix:@"---"]) {
      flush();
      NSView* r = rule();
      place(r, 0, y + 12, width, 1);
      [doc addSubview:r];
      y += 19;
    } else if ([line hasPrefix:@"|"]) {
      flush();
      NSMutableArray* cells = [NSMutableArray new];
      for (NSString* c in [line componentsSeparatedByString:@"|"]) {
        NSString* t = [c stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if (t.length) [cells addObject:t];
      }
      BOOL separator = [[line stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"|- :"]] length] == 0;
      if (separator || cells.count < 2) continue;
      add(inline_([NSString stringWithFormat:@"**%@**", cells[0]], 13, INK), 0, 0, 2);
      add(inline_(cells[1], 13, MUTE), 0, 0, 12);
    } else if ([line hasPrefix:@"- "] || [line hasPrefix:@"* "]) {
      flush();
      NSTextField* dash = label(@"—", 14, 400, QUIET);
      placeLabel(dash, 0, y + 1, 0);
      [doc addSubview:dash];
      add(inline_([line substringFromIndex:2], 14, MUTE), 24, 0, 10);
    } else {
      if (paragraph.length) [paragraph appendString:@" "];
      [paragraph appendString:line];
    }
  }
  flush();
  doc.frame = NSMakeRect(0, 0, width, y);
  if (height) *height = y;
  return doc;
}

@interface WPrivacyPage : WFlipped
@property(strong) NSScrollView* scroll;
@property(strong) WButton* back;
@property(strong) NSTextField* title;
@property(copy) void (^onClose)(void);
@end
@implementation WPrivacyPage
- (instancetype)init {
  if ((self = [super initWithFrame:NSZeroRect])) {
    self.wantsLayer = YES;
    self.layer.backgroundColor = PAPER.CGColor;
    _back = [WButton well:@"chevron.left" text:@"Back"];
    __weak WPrivacyPage* weak = self;
    _back.onClick = ^{ if (weak.onClose) weak.onClose(); };
    _title = label(@"Privacy", 16, 600, INK);
    _title.alignment = NSTextAlignmentCenter;
    _scroll = [NSScrollView new];
    _scroll.drawsBackground = NO;
    _scroll.hasVerticalScroller = NO;
    _scroll.autohidesScrollers = YES;
    for (NSView* v in @[_scroll, _back, _title]) [self addSubview:v];
  }
  return self;
}
- (BOOL)acceptsFirstResponder { return YES; }
- (void)cancelOperation:(id)sender { if (self.onClose) self.onClose(); }
- (void)keyDown:(NSEvent*)e { if (e.keyCode == 53 && self.onClose) self.onClose(); }
- (void)layout {
  [super layout];
  NSSize s = self.bounds.size;
  CGFloat w = MIN(760, s.width), x = (s.width - w) / 2;
  place(self.back, x + 16, 16, 86, 34);
  placeLabel(self.title, x, 24, w);
  place(self.scroll, x, 64, w, s.height - 64);
  CGFloat h;
  NSView* doc = WPrivacyDocument(w - 40, &h);
  WFlipped* holder = [WFlipped new];
  holder.frame = NSMakeRect(0, 0, w, h + 40);
  doc.frame = NSMakeRect(20, 0, w - 40, h);
  [holder addSubview:doc];
  self.scroll.documentView = holder;
}
@end

#pragma mark - Sign-in

@interface WDotField : NSView
@end
@implementation WDotField
- (BOOL)isFlipped { return YES; }
- (void)drawRect:(NSRect)r {
  [[INK colorWithAlphaComponent:0.10] setFill];
  for (CGFloat y = 9.5; y < self.bounds.size.height; y += 19)
    for (CGFloat x = 9.5; x < self.bounds.size.width; x += 19)
      [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(x - 1.2, y - 1.2, 2.4, 2.4)] fill];
}
@end

@interface WAuthView () <NSTextFieldDelegate>
@property WStage stage;
@property WOpening opening;
@property(strong) WMarkLayerHost* mark;
@property(strong) WDotField* dots;
@property(strong) NSView* content;  // the shown stage
@property(strong) WButton* back;
@property(strong) WActionPill* action;
@property BOOL backShown, actionShown, dissolved, materialised;
@property(copy) NSString *username, *password, *confirmation, *error;
@property NSInteger availability, confirmState, checkToken;
@property(strong) NSTextField* field;
@property(strong) NSTextField *message;
@property(strong) NSView* indicator;
@property(strong) NSView* match;
@property(strong) WPrivacyPage* privacy;
@property BOOL busy;
@property(nonatomic, copy) NSString* workingTitle;
@end

@implementation WAuthView

- (instancetype)initWithFrame:(NSRect)frame { return [self initWithFrame:frame working:nil]; }
- (instancetype)initWithFrame:(NSRect)frame working:(NSString*)title {
  if (!(self = [super initWithFrame:frame])) return nil;
  self.wantsLayer = YES;
  self.layer.backgroundColor = PAPER.CGColor;
  _username = _password = _confirmation = _error = @"";
  _back = [WButton well:@"chevron.left" text:nil];
  _back.fill = [CARD colorWithAlphaComponent:0.88];
  _back.layer.cornerRadius = 23;
  _back.layer.borderWidth = 1;
  _back.layer.borderColor = RULE.CGColor;
  __weak WAuthView* weak = self;
  _back.onClick = ^{ [weak goBack]; };
  _back.hidden = YES;
  _action = [WActionPill new];
  _action.onClick = ^{ [weak advance]; };
  _action.hidden = YES;
  _mark = [[WMarkLayerHost alloc] initWithFrame:frame];
  [self addSubview:_back];
  [self addSubview:_action];
  [self addSubview:_mark];
  if (title) {
    /* Launch with a session, or a log out: the W comes up in the middle and stays. */
    _workingTitle = [title copy];
    _stage = WStageWorking;
    _opening = WOpeningActions;
    [self showStage:NO];
    [self arrive];
    return self;
  }
  [self showStage:NO];
  /* 260 ms blank, the W (900), the line (1050), then the actions. */
  WAfter(0.26, ^{ [weak setOpeningTo:WOpeningMark]; });
  WAfter(0.26 + 0.9, ^{ [weak setOpeningTo:WOpeningLine]; });
  WAfter(0.26 + 0.9 + 1.05, ^{ [weak setOpeningTo:WOpeningActions]; });
  return self;
}
- (BOOL)acceptsFirstResponder { return YES; }

/* The first arrival: out of a blur, a touch small, into place (900 ms). */
- (void)arrive {
  if (self.materialised) return;
  self.materialised = YES;
  [self layoutSubtreeIfNeeded];
  [self placeMark:NO];
  [self.mark fadeAlpha:0 to:1 blur:18 to:0 scaleFrom:0.9 to:1 duration:0.9];
}
- (void)setWorkingTitle:(NSString*)title {
  _workingTitle = [title copy];
  if (self.stage == WStageWorking && [self.content isKindOfClass:WShimmer.class]) [(WShimmer*)self.content setTitle:title];
}
- (void)showWorking:(NSString*)title {
  self.workingTitle = title;
  if (self.stage == WStageWorking) return;
  [self.window makeFirstResponder:self];
  self.stage = WStageWorking;
  [self showStage:YES];
  [self arrive];
}
/* The account is in: the same W swells once and dissolves into Play. */
- (void)completeIntoApp {
  self.stage = WStageSuccess;
  [self showStage:YES];
  __weak WAuthView* weak = self;
  WAfter(0.7, ^{
    weak.dissolved = YES;
    [weak.mark fadeAlpha:1 to:0 blur:0 to:18 scaleFrom:1 to:1 duration:0.52];
    WAfter(0.52, ^{ if (weak.onComplete) weak.onComplete(); });
  });
}
/* Signed out, or the saved session was refused: the same W rises to the landing. */
- (void)showLanding {
  self.username = self.password = self.confirmation = self.error = @"";
  self.busy = NO;
  self.dissolved = NO;
  self.opening = WOpeningActions;
  self.stage = WStageLanding;
  [self showStage:YES];
  [self arrive];
  [self.window makeFirstResponder:self];
}

#pragma mark State

- (CGFloat)landingMarkY {
  CGFloat h = self.bounds.size.height;
  switch (self.opening) {
    case WOpeningBlank: case WOpeningMark: return h * 0.5;
    case WOpeningLine: return h * 0.5 - 38;
    case WOpeningActions: return h * 0.34;
  }
}
- (BOOL)credential { return self.stage >= WStageCreateUsername && self.stage <= WStageLoginPassword; }
- (BOOL)passwordOK { return self.password.length >= 8 && self.password.length <= 200; }
- (BOOL)actionEnabled {
  switch (self.stage) {
    case WStageCreateUsername: return usernameOK(self.username) && self.availability == AV_AVAILABLE;
    case WStageLoginUsername: return self.username.length > 0;
    case WStageCreatePassword: return self.passwordOK;
    case WStageLoginPassword: return self.password.length > 0 && self.password.length <= 200;
    case WStageCreateConfirmation: return self.passwordOK && self.confirmState == CF_MATCHED;
    default: return NO;
  }
}
- (BOOL)showsAction {
  switch (self.stage) {
    case WStageCreateUsername: return usernameOK(self.username);
    case WStageLoginUsername: return self.username.length > 0;
    case WStageCreatePassword: case WStageLoginPassword: return self.password.length > 0;
    case WStageCreateConfirmation: return self.confirmState == CF_MATCHED;
    default: return NO;
  }
}
- (NSString*)actionTitle {
  switch (self.stage) {
    case WStageCreatePassword: return @"Next";
    case WStageLoginPassword: return @"Log in";
    case WStageCreateConfirmation: return @"Create account";
    default: return @"Continue";
  }
}

- (void)setOpeningTo:(WOpening)opening {
  self.opening = opening;
  if (self.stage != WStageLanding) return;
  if (!self.materialised && opening >= WOpeningMark) {
    self.materialised = YES;
    [self placeMark:NO];
    /* The first arrival: out of a blur, a touch small, into place (900 ms). */
    [self.mark fadeAlpha:0 to:1 blur:18 to:0 scaleFrom:0.9 to:1 duration:0.9];
  } else [self placeMark:YES];
  [self layoutLanding:(WFlipped*)self.content animated:YES];
}
- (CGFloat)markSize {
  switch (self.stage) {
    case WStageLanding: return 116;
    case WStageCreating: case WStageSigningIn: case WStageWorking: return 118;
    case WStageSuccess: return 132;
    default: return 74;
  }
}
- (CGFloat)markY {
  CGFloat h = self.bounds.size.height;
  switch (self.stage) {
    case WStageLanding: return self.landingMarkY;
    case WStageCreating: case WStageSigningIn: case WStageSuccess: case WStageWorking: return h * 0.45;
    default: return 96;
  }
}
- (void)placeMark:(BOOL)animated {
  if (!self.materialised) return;
  [self.mark size:self.markSize centreY:self.markY scale:self.stage == WStageSuccess ? 1.08 : 1
            alpha:self.dissolved ? 0 : 1 blur:self.dissolved ? 18 : 0 response:0.72 damping:0.9 animated:animated];
}

- (void)enter:(WStage)next {
  self.error = @"";
  [self.window makeFirstResponder:self];
  self.stage = next;
  [self showStage:YES];
  if (self.credential) {
    NSTextField* field = self.field;
    WStage at = next;
    __weak WAuthView* weak = self;
    WAfter(0.34, ^{ if (weak.stage == at && field.superview) [weak.window makeFirstResponder:field]; });
  }
}

- (void)advance {
  if (!self.actionEnabled) return;
  switch (self.stage) {
    case WStageCreateUsername: [self enter:WStageCreatePassword]; break;
    case WStageLoginUsername: [self enter:WStageLoginPassword]; break;
    case WStageCreatePassword: [self enter:WStageCreateConfirmation]; break;
    case WStageLoginPassword: [self authenticate:NO]; break;
    case WStageCreateConfirmation: [self authenticate:YES]; break;
    default: break;
  }
}
- (void)goBack {
  switch (self.stage) {
    case WStageCreateUsername: case WStageLoginUsername: [self enter:WStageLanding]; break;
    case WStageCreatePassword: [self enter:WStageCreateUsername]; break;
    case WStageCreateConfirmation: [self enter:WStageCreatePassword]; break;
    case WStageLoginPassword: [self enter:WStageLoginUsername]; break;
    default: break;
  }
}
- (void)authenticate:(BOOL)create {
  if (self.busy) return;
  self.busy = YES;
  self.error = @"";
  [self.window makeFirstResponder:self];
  self.stage = create ? WStageCreating : WStageSigningIn;
  [self showStage:YES];
  __weak WAuthView* weak = self;
  void (^answer)(NSString*) = ^(NSString* failure) {
    WAuthView* me = weak;
    if (!me) return;
    if (failure) {
      me.busy = NO;
      BOOL usernameFailure = create && [failure.lowercaseString containsString:@"username"];
      [me enter:usernameFailure ? WStageCreateUsername : create ? WStageCreateConfirmation : WStageLoginPassword];
      me.error = failure;
      [me refreshMessage];
      return;
    }
    /* The W stays until the account's surfaces are fetched, so Play never draws an empty account. */
    if (me.onAccountIn) me.onAccountIn();
    [[WAccount shared] bootstrap:^{ [me completeIntoApp]; }];
  };
  if (create) [[WAccount shared] signUp:self.username password:self.password done:answer];
  else [[WAccount shared] logIn:self.username password:self.password done:answer];
}

#pragma mark Checks (the phones' timings, to the millisecond)

- (void)usernameChanged {
  NSInteger token = ++self.checkToken;
  if (self.stage != WStageCreateUsername || !usernameOK(self.username)) { self.availability = AV_IDLE; [self refreshChrome]; return; }
  self.availability = AV_CHECKING;
  [self refreshChrome];
  NSString* name = self.username;
  __weak WAuthView* weak = self;
  WAfter(0.42, ^{
    if (weak.checkToken != token) return;
    [[WAccount shared] checkUsername:name done:^(NSInteger availability) {
      if (weak.checkToken != token || ![weak.username isEqualToString:name]) return;
      weak.availability = availability;
      [weak refreshChrome];
    }];
  });
}
- (void)confirmationChanged {
  NSInteger token = ++self.checkToken;
  if (self.stage != WStageCreateConfirmation || !self.password.length || self.confirmation.length < self.password.length) {
    self.confirmState = CF_IDLE;
    [self refreshChrome];
    return;
  }
  self.confirmState = CF_CHECKING;
  [self refreshChrome];
  __weak WAuthView* weak = self;
  WAfter(0.28, ^{
    if (weak.checkToken != token) return;
    weak.confirmState = [weak.confirmation isEqualToString:weak.password] ? CF_MATCHED : CF_MISMATCHED;
    [weak refreshChrome];
  });
}
- (void)controlTextDidChange:(NSNotification*)note {
  NSTextField* f = note.object;
  if (self.stage == WStageCreateUsername || self.stage == WStageLoginUsername) {
    NSMutableString* clean = [NSMutableString new];
    [f.stringValue enumerateSubstringsInRange:NSMakeRange(0, f.stringValue.length) options:NSStringEnumerationByComposedCharacterSequences
                                   usingBlock:^(NSString* s, NSRange r, NSRange e, BOOL* stop) {
      unichar c = [s characterAtIndex:0];
      if (s.length == 1 && (isalnum(c) || c == '_')) [clean appendString:s];
    }];
    if (clean.length > 20) [clean deleteCharactersInRange:NSMakeRange(20, clean.length - 20)];
    if (![clean isEqualToString:f.stringValue]) f.stringValue = clean;
    self.username = clean;
    self.error = @"";
    [self usernameChanged];
  } else if (self.stage == WStageCreateConfirmation) {
    self.confirmation = f.stringValue;
    [self confirmationChanged];
  } else {
    self.password = f.stringValue;
    [self refreshChrome];
  }
  [self refreshMessage];
}
- (BOOL)control:(NSControl*)control textView:(NSTextView*)textView doCommandBySelector:(SEL)command {
  if (command == @selector(insertNewline:)) { [self advance]; return YES; }
  if (command == @selector(cancelOperation:)) { [self goBack]; return YES; }
  return NO;
}
- (void)keyDown:(NSEvent*)e {
  if (self.privacy) return;
  if (e.keyCode == 36 || e.keyCode == 76) [self advance];
  else if (e.keyCode == 53) [self goBack];
}

#pragma mark Building the stage

- (NSView*)buildLanding {
  WFlipped* v = [WFlipped new];
  NSTextField* line = label(@"The arena and people in it.", 30, 700, INK);
  line.alignment = NSTextAlignmentCenter;
  track(line, -0.6);
  line.identifier = @"line";
  WButton* create = [WButton capsule:@"Create Wyrm account" filled:YES];
  WButton* login = [WButton capsule:@"Log in" filled:NO];
  __weak WAuthView* weak = self;
  create.onClick = ^{ [weak enter:WStageCreateUsername]; };
  login.onClick = ^{ [weak enter:WStageLoginUsername]; };
  WTap* privacy = [WTap new];
  privacy.fill = NSColor.clearColor;
  NSMutableAttributedString* text = [[NSMutableAttributedString alloc] initWithString:@"By continuing, you agree to Wyrm's "
      attributes:@{NSFontAttributeName: body(12, 400), NSForegroundColorAttributeName: QUIET}];
  [text appendAttributedString:[[NSAttributedString alloc] initWithString:@"Privacy Policy" attributes:@{
    NSFontAttributeName: body(12, 400), NSForegroundColorAttributeName: LINK, NSUnderlineStyleAttributeName: @(NSUnderlineStyleSingle)}]];
  NSTextField* words = [NSTextField labelWithAttributedString:text];
  words.alignment = NSTextAlignmentCenter;
  [privacy addSubview:words];
  privacy.onClick = ^{ [weak openPrivacy]; };
  WFlipped* actions = [WFlipped new];
  actions.identifier = @"actions";
  [actions addSubview:create];
  [actions addSubview:login];
  [actions addSubview:privacy];
  place(create, 0, 0, 340, 52);
  place(login, 0, 62, 340, 52);
  [words sizeToFit];
  place(privacy, 0, 130, 340, words.frame.size.height);
  place(words, 0, 0, 340, words.frame.size.height);
  actions.frame = NSMakeRect(0, 0, 340, 130 + words.frame.size.height);
  line.hidden = self.opening < WOpeningLine;
  actions.hidden = self.opening < WOpeningActions;
  [v addSubview:line];
  [v addSubview:actions];
  return v;
}
- (void)layoutLanding:(WFlipped*)v animated:(BOOL)animated {
  if (self.stage != WStageLanding || !v) return;
  NSTextField* line = nil;
  NSView* actions = nil;
  for (NSView* s in v.subviews) {
    if ([s.identifier isEqualToString:@"line"]) line = (NSTextField*)s;
    if ([s.identifier isEqualToString:@"actions"]) actions = s;
  }
  CGFloat w = self.bounds.size.width, top = self.landingMarkY + 82;
  [line sizeToFit];
  NSRect lineFrame = NSMakeRect(0, top, w, line.frame.size.height);
  NSRect actionsFrame = NSMakeRect((w - 340) / 2, top + line.frame.size.height + 42, 340, actions.frame.size.height);
  BOOL lineShown = !line.hidden && !NSIsEmptyRect(line.frame), actionsShown = !actions.hidden && !NSIsEmptyRect(actions.frame);
  if (animated && lineShown) glide(line, lineFrame, 0.72); else line.frame = lineFrame;
  if (animated && actionsShown) glide(actions, actionsFrame, 0.72); else actions.frame = actionsFrame;
  if (line.hidden && self.opening >= WOpeningLine) {
    line.hidden = NO;
    line.frame = lineFrame;
    WMaterialise(line, YES, 15, 0.7, 0.9, nil);
  }
  if (actions.hidden && self.opening >= WOpeningActions) {
    actions.hidden = NO;
    actions.frame = actionsFrame;
    WMaterialise(actions, YES, 15, 0.7, 0.9, nil);
  }
}
- (NSString*)kicker {
  switch (self.stage) {
    case WStageCreateUsername: return @"YOUR WYRM ID";
    case WStageLoginUsername: return @"WELCOME BACK";
    case WStageCreatePassword: return @"SECURE YOUR ACCOUNT";
    case WStageLoginPassword: return @"YOUR PASSWORD";
    case WStageCreateConfirmation: return @"ONE MORE TIME";
    default: return @"";
  }
}
- (NSString*)instruction {
  switch (self.stage) {
    case WStageCreateUsername: return @"Choose a username for your Wyrm account. It links your global leaderboard data, follows, follow-backs and messages.";
    case WStageLoginUsername: return @"Enter the username connected to your Wyrm profile.";
    case WStageCreatePassword: return @"Use at least 8 characters. This account has no email recovery, so keep the password somewhere safe.";
    case WStageLoginPassword: return [NSString stringWithFormat:@"Enter the password for @%@.", self.username];
    case WStageCreateConfirmation: return @"Re-enter your password to make sure it is correct.";
    default: return @"";
  }
}
- (NSString*)validation {
  if (self.stage == WStageCreateUsername && self.username.length && !usernameOK(self.username)) return @"3–20 letters, numbers or underscores";
  if (self.stage == WStageCreateUsername && self.availability == AV_TAKEN) return @"That username is already taken";
  if (self.stage == WStageCreateUsername && self.availability == AV_UNAVAILABLE) return @"Could not check availability. Edit the username to retry.";
  if (self.stage == WStageCreatePassword && self.password.length && !self.passwordOK) {
    NSInteger left = MAX(0, 8 - (NSInteger)self.password.length);
    return [NSString stringWithFormat:@"%ld more character%@", (long)left, self.password.length == 7 ? @"" : @"s"];
  }
  return nil;
}
- (NSView*)buildCredential {
  WFlipped* v = [WFlipped new];
  NSTextField* kicker = label(self.kicker, 10.5, 700, QUIET);
  kicker.alignment = NSTextAlignmentCenter;
  track(kicker, 1.35);
  kicker.identifier = @"kicker";
  WFlipped* box = composer();
  box.identifier = @"composer";
  BOOL user = self.stage == WStageCreateUsername || self.stage == WStageLoginUsername;
  BOOL confirm = self.stage == WStageCreateConfirmation;
  NSTextField* field = WField(user ? @"username" : confirm ? @"Password again" : @"Password", user ? 21 : 19, 600, !user);
  field.stringValue = user ? self.username : confirm ? self.confirmation : self.password;
  field.delegate = self;
  self.field = field;
  if (user) {
    NSTextField* at = label(@"@", 22, 600, QUIET);
    at.identifier = @"at";
    [box addSubview:at];
  }
  [box addSubview:field];
  self.indicator = [WFlipped new];
  [box addSubview:self.indicator];
  NSTextField* instruction = wrapLabel(self.instruction, 12.5, 400, MUTE);
  instruction.alignment = NSTextAlignmentCenter;
  lineHeight(instruction, 21, NSTextAlignmentCenter);
  instruction.identifier = @"instruction";
  self.message = label(@"", 11.5, 600, QUIET);
  self.message.alignment = NSTextAlignmentCenter;
  self.match = [WFlipped new];
  self.match.hidden = !confirm;
  for (NSView* s in @[kicker, box, self.match, instruction, self.message]) [v addSubview:s];
  return v;
}
- (void)layoutCredential:(WFlipped*)v {
  CGFloat W = self.bounds.size.width, H = self.bounds.size.height, w = MIN(460, W) - 48, x = (W - w) / 2;
  NSView *kicker = nil, *box = nil, *instruction = nil;
  for (NSView* s in v.subviews) {
    if ([s.identifier isEqualToString:@"kicker"]) kicker = s;
    if ([s.identifier isEqualToString:@"composer"]) box = s;
    if ([s.identifier isEqualToString:@"instruction"]) instruction = s;
  }
  BOOL confirm = self.stage == WStageCreateConfirmation;
  [(NSTextField*)kicker sizeToFit];
  CGFloat iw = MIN(330, w);
  NSSize instructionSize = [((NSTextField*)instruction).cell cellSizeForBounds:NSMakeRect(0, 0, iw, 400)];
  [self.message sizeToFit];
  CGFloat group = kicker.frame.size.height + 16 + 60 + (confirm ? 9 + 24 : 0) + 16 + instructionSize.height + 16 + MAX(16, self.message.frame.size.height);
  CGFloat top = MAX(150, (H - group) / 2), y = top;
  place(kicker, 0, y, W, kicker.frame.size.height);
  y += kicker.frame.size.height + 16;
  place(box, x, y, w, 60);
  y += 60;
  if (confirm) { place(self.match, x + 5, y + 9, w - 5, 24); y += 33; }
  y += 16;
  place(instruction, (W - iw) / 2, y, iw, instructionSize.height);
  y += instructionSize.height + 16;
  place(self.message, 0, y, W, self.message.frame.size.height);
  /* Inside the composer: "@", the field, the availability mark. */
  CGFloat fx = 18;
  for (NSView* s in box.subviews) if ([s.identifier isEqualToString:@"at"]) { [(NSTextField*)s sizeToFit]; place(s, 18, (60 - s.frame.size.height) / 2, s.frame.size.width, s.frame.size.height); fx = 18 + s.frame.size.width + 5; }
  CGFloat fh = ceil(self.field.intrinsicContentSize.height);
  place(self.field, fx, round((60 - fh) / 2), w - fx - 18 - 33, fh);
  place(self.indicator, w - 18 - 27, 16.5, 27, 27);
}
- (NSView*)buildWorking {
  WShimmer* s = [[WShimmer alloc] initWithFrame:NSZeroRect];
  [s setTitle:self.stage == WStageWorking ? self.workingTitle : self.stage == WStageCreating ? @"Creating your account…" : @"Entering Wyrm…"];
  return s;
}
- (void)showStage:(BOOL)animated {
  NSView* old = self.content;
  NSView* next;
  if (self.stage == WStageLanding) next = [self buildLanding];
  else if (self.credential) next = [self buildCredential];
  else if (self.stage == WStageCreating || self.stage == WStageSigningIn || self.stage == WStageWorking) next = [self buildWorking];
  else next = [WFlipped new];
  self.content = next;
  [self addSubview:next positioned:NSWindowBelow relativeTo:self.back];
  if (self.stage == WStageLanding && !self.dots) {
    self.dots = [WDotField new];
    [self addSubview:self.dots positioned:NSWindowBelow relativeTo:next];
    if (animated) WMaterialise(self.dots, YES, 0, 0.58, 0.86, nil);
  } else if (self.stage != WStageLanding && self.dots) {
    NSView* dots = self.dots;
    self.dots = nil;
    WMaterialise(dots, NO, 0, 0.58, 0.86, ^{ [dots removeFromSuperview]; });
  }
  [self layoutNow];
  if (animated) {
    WMaterialise(next, YES, 15, 0.58, 0.86, nil);
    if (old) WMaterialise(old, NO, 15, 0.58, 0.86, ^{ [old removeFromSuperview]; });
  } else [old removeFromSuperview];
  [self placeMark:animated];
  [self refreshChrome];
  [self refreshMessage];
}
- (void)refreshMessage {
  if (!self.credential || !self.message) return;
  NSString* text = self.error.length ? self.error : self.validation ?: @"";
  BOOL isError = self.error.length > 0;
  if ([self.message.stringValue isEqualToString:text]) return;
  self.message.stringValue = text;
  self.message.font = body(isError ? 12 : 11.5, 600);
  self.message.textColor = isError ? RED : QUIET;
  if (text.length) WMaterialise(self.message, YES, 15, 0.58, 0.86, nil);
  if (self.content) [self layoutCredential:(WFlipped*)self.content];
}
- (void)refreshChrome {
  BOOL back = self.credential, action = self.showsAction;
  if (back != self.backShown) {
    self.backShown = back;
    self.back.hidden = NO;
    WMaterialise(self.back, back, 15, 0.58, 0.86, back ? nil : ^{ if (!self.backShown) self.back.hidden = YES; });
  }
  [self.action setTitle:self.actionTitle enabled:self.actionEnabled];
  [self layoutChrome];
  if (action != self.actionShown) {
    self.actionShown = action;
    self.action.hidden = NO;
    WMaterialise(self.action, action, 15, 0.58, 0.86, action ? nil : ^{ if (!self.actionShown) self.action.hidden = YES; });
  }
  /* The availability mark and the confirmation line. */
  if (self.indicator) {
    for (NSView* s in self.indicator.subviews.copy) [s removeFromSuperview];
    NSView* mark = nil;
    NSRect at = NSMakeRect(1, 1, 25, 25);
    if (self.stage == WStageCreateUsername && usernameOK(self.username)) {
      if (self.availability == AV_CHECKING) { mark = [[WSpinner alloc] initWithFrame:NSMakeRect(0, 0, 17, 17)]; at = NSMakeRect(5, 5, 17, 17); }
      else if (self.availability == AV_AVAILABLE) mark = circleMark(@"checkmark", LIVE, 25, 12);
      else if (self.availability == AV_TAKEN) mark = circleMark(@"xmark", [RED colorWithAlphaComponent:0.88], 25, 10);
      else if (self.availability == AV_UNAVAILABLE) { mark = glyph(@"arrow.clockwise", 15, QUIET); at = NSMakeRect(5, 5, 17, 17); }
    }
    if (mark) { mark.frame = at; [self.indicator addSubview:mark]; }
  }
  if (self.match && self.stage == WStageCreateConfirmation) {
    for (NSView* s in self.match.subviews.copy) [s removeFromSuperview];
    if (self.confirmState == CF_CHECKING) [self.match addSubview:[[WSpinner alloc] initWithFrame:NSMakeRect(0, 3, 17, 17)]];
    else if (self.confirmState == CF_MATCHED || self.confirmState == CF_MISMATCHED) {
      BOOL ok = self.confirmState == CF_MATCHED;
      NSColor* colour = ok ? LIVE : RED;
      NSView* dot = circleMark(ok ? @"checkmark" : @"xmark", colour, 18, 8);
      dot.frame = NSMakeRect(0, 3, 18, 18);
      NSTextField* t = label(ok ? @"Password matched, continue!" : @"Password didn't match, recheck!", 11.5, 600, colour);
      placeLabel(t, 25, 3, 0);
      [self.match addSubview:dot];
      [self.match addSubview:t];
      WMaterialise(self.match, YES, 15, 0.58, 0.86, nil);
    }
  }
}
- (void)layoutChrome {
  NSSize s = self.bounds.size;
  place(self.back, 28, 24, 46, 46);
  CGFloat aw = self.action.width;
  place(self.action, (s.width - aw) / 2, s.height - 56 - 46, aw, 46);
}
- (void)layoutNow {
  NSSize s = self.bounds.size;
  self.mark.frame = self.bounds;
  if (self.dots) place(self.dots, 0, 0, s.width, MIN(280, MAX(232, s.height * 0.31)));
  if (self.content) {
    self.content.frame = self.bounds;
    if (self.stage == WStageLanding) [self layoutLanding:(WFlipped*)self.content animated:NO];
    else if (self.credential) [self layoutCredential:(WFlipped*)self.content];
    else if ([self.content isKindOfClass:WShimmer.class]) place(self.content, 0, s.height * 0.45 + 92 - 9, s.width, 20);
  }
  [self layoutChrome];
  if (self.privacy) self.privacy.frame = self.bounds;
}
- (void)layout {
  [super layout];
  [self layoutNow];
  [self placeMark:NO];
}

- (void)openPrivacy {
  if (self.privacy) return;
  WPrivacyPage* page = [WPrivacyPage new];
  __weak WAuthView* weak = self;
  page.onClose = ^{
    WPrivacyPage* p = weak.privacy;
    weak.privacy = nil;
    WMaterialise(p, NO, 15, 0.4, 1, ^{ [p removeFromSuperview]; });
    [weak.window makeFirstResponder:weak];
  };
  page.frame = self.bounds;
  [self addSubview:page];
  self.privacy = page;
  WMaterialise(page, YES, 15, 0.5, 0.9, nil);
  [self.window makeFirstResponder:page];
}
@end

#pragma mark - Session transition

@implementation WSessionView {
  WMarkLayerHost* _mark;
  WShimmer* _status;
}
- (instancetype)initWithTitle:(NSString*)title {
  if ((self = [super initWithFrame:NSZeroRect])) {
    self.wantsLayer = YES;
    self.layer.backgroundColor = PAPER.CGColor;
    _status = [[WShimmer alloc] initWithFrame:NSZeroRect];
    [_status setTitle:title];
    _mark = [[WMarkLayerHost alloc] initWithFrame:NSZeroRect];
    [self addSubview:_status];
    [self addSubview:_mark];
  }
  return self;
}
- (void)setTitle:(NSString*)title { [_status setTitle:title]; }
- (void)viewDidMoveToWindow {
  if (!self.window) return;
  [self layoutSubtreeIfNeeded];
  /* WyrmSessionTransition: the W and the line appear on a spring (0.56, 0.86). */
  CALayer* m = _mark.mark;
  [_mark size:118 centreY:self.bounds.size.height / 2 - 20 scale:1 alpha:1 blur:0 response:0.56 damping:0.86 animated:NO];
  [m addAnimation:WSpring(@"opacity", @0, @1, 0.56, 0.86) forKey:@"in"];
  [m addAnimation:WSpring(@"filters.blur.inputRadius", @14, @0, 0.56, 0.86) forKey:@"blur"];
  [m addAnimation:WSpring(@"transform", [NSValue valueWithCATransform3D:CATransform3DScale(m.transform, 0.86, 0.86, 1)],
                          [NSValue valueWithCATransform3D:m.transform], 0.56, 0.86) forKey:@"grow"];
  WMaterialise(_status, YES, 8, 0.56, 0.86, nil);
}
- (void)layout {
  [super layout];
  NSSize s = self.bounds.size;
  _mark.frame = self.bounds;
  [_mark size:118 centreY:s.height / 2 - 20 scale:1 alpha:1 blur:0 response:0.56 damping:0.86 animated:NO];
  place(_status, 0, s.height / 2 - 20 + 59 + 22, s.width, 20);
}
@end

#pragma mark - Log out dialogs (Android LogOutSheet / LogOutSaveFailed, centred)

@implementation WDialogHost {
  NSView* _scrim;
  NSView* _card;
}
- (instancetype)initWithCard:(NSView*)card {
  if ((self = [super initWithFrame:NSZeroRect])) {
    self.wantsLayer = YES;
    _scrim = [NSView new];
    _scrim.wantsLayer = YES;
    _scrim.layer.backgroundColor = rgba(0x52000000).CGColor;
    _card = card;
    [self addSubview:_scrim];
    [self addSubview:card];
  }
  return self;
}
- (BOOL)acceptsFirstResponder { return YES; }
- (void)keyDown:(NSEvent*)e {
  if (e.keyCode == 53 && self.onCancel) self.onCancel();
  else if ((e.keyCode == 36 || e.keyCode == 76) && self.onConfirm) self.onConfirm();
}
- (void)mouseDown:(NSEvent*)e {
  if (!NSPointInRect([self convertPoint:e.locationInWindow fromView:nil], _card.frame) && self.onCancel) self.onCancel();
}
- (void)present {
  [_scrim.layer addAnimation:WSpring(@"opacity", @0, @1, 0.3, 1) forKey:@"in"];
  [self layoutSubtreeIfNeeded];
  _card.wantsLayer = YES;
  CABasicAnimation* grow = [CABasicAnimation animationWithKeyPath:@"transform"];
  grow.fromValue = [NSValue valueWithCATransform3D:WScaleAbout(_card, 0.94)];
  grow.toValue = [NSValue valueWithCATransform3D:CATransform3DIdentity];
  grow.duration = 0.2;
  CABasicAnimation* fade = [CABasicAnimation animationWithKeyPath:@"opacity"];
  fade.fromValue = @0; fade.toValue = @1; fade.duration = 0.16;
  [_card.layer addAnimation:grow forKey:@"grow"];
  [_card.layer addAnimation:fade forKey:@"fade"];
  [self.window makeFirstResponder:self];
}
- (void)dismiss {
  [NSAnimationContext runAnimationGroup:^(NSAnimationContext* ctx) {
    ctx.duration = 0.16;
    self.animator.alphaValue = 0;
  } completionHandler:^{ [self removeFromSuperview]; }];
}
- (void)layout {
  [super layout];
  NSSize s = self.bounds.size;
  _scrim.frame = self.bounds;
  NSSize c = _card.frame.size;
  _card.frame = NSMakeRect(round((s.width - c.width) / 2), round((s.height - c.height) / 2), c.width, c.height);
}
@end

static WButton* sheetButton(NSString* title, NSColor* fill, NSColor* ink, NSString* icon) {
  WButton* b = [WButton tinted:title fill:fill ink:ink symbol:icon];
  b.layer.cornerRadius = 16;
  return b;
}

WDialogHost* WLogOutSheet(void (^onLogOut)(void), void (^onCancel)(void)) {
  WAccount* a = [WAccount shared];
  WFlipped* card = [WFlipped new];
  card.wantsLayer = YES;
  card.layer.backgroundColor = CARD.CGColor;
  card.layer.cornerRadius = 30;
  card.layer.cornerCurve = kCACornerCurveContinuous;
  CGFloat w = 440, inner = w - 44, y = 22;
  WAvatar* avatar = [[WAvatar alloc] initWithFrame:NSMakeRect((w - 64) / 2, y, 64, 64)];
  [avatar setURL:a.avatarURL initials:WInitials(a.displayName)];
  [card addSubview:avatar];
  y += 64 + 12;
  NSTextField* title = label(@"Log out of Wyrm?", 24, 600, INK);
  title.font = display(24, 600);
  title.alignment = NSTextAlignmentCenter;
  placeLabel(title, 22, y, inner);
  [card addSubview:title];
  y += title.frame.size.height + 4;
  NSTextField* who = label(a.handle.length ? [NSString stringWithFormat:@"%@ · %@", a.displayName, a.handle] : a.displayName, 13.5, 600, QUIET);
  who.alignment = NSTextAlignmentCenter;
  placeLabel(who, 22, y, inner);
  [card addSubview:who];
  y += who.frame.size.height + 16;
  WFlipped* note = [WFlipped new];
  note.wantsLayer = YES;
  note.layer.backgroundColor = WELL.CGColor;
  note.layer.cornerRadius = 16;
  note.layer.cornerCurve = kCACornerCurveContinuous;
  NSImageView* cloud = glyph(@"icloud.and.arrow.up", 17, INK);
  place(cloud, 14, 14, 22, 20);
  NSTextField* words = wrapLabel(@"Your settings, skin and layouts are saved to your account first. Then this computer forgets everything, and it all comes back when you log in again.", 13.5, 400, MUTE);
  lineHeight(words, 19, NSTextAlignmentLeft);
  CGFloat nh = placeWrap(words, 48, 14, inner - 48 - 14);
  [note addSubview:cloud];
  [note addSubview:words];
  place(note, 22, y, inner, nh + 28);
  [card addSubview:note];
  y += nh + 28 + 18;
  WButton* out = sheetButton(@"Log out", BADGE, NSColor.whiteColor, @"rectangle.portrait.and.arrow.right");
  out.onClick = onLogOut;
  place(out, 22, y, inner, 50);
  [card addSubview:out];
  y += 58;
  WButton* cancel = sheetButton(@"Cancel", WELL, INK, nil);
  cancel.onClick = onCancel;
  place(cancel, 22, y, inner, 50);
  [card addSubview:cancel];
  y += 50 + 22;
  card.frame = NSMakeRect(0, 0, w, y);
  WDialogHost* host = [[WDialogHost alloc] initWithCard:card];
  host.onCancel = onCancel;
  host.onConfirm = onLogOut;
  return host;
}

WDialogHost* WSaveFailedDialog(NSString* message, void (^onRetry)(void), void (^onAnyway)(void), void (^onStay)(void)) {
  WFlipped* card = [WFlipped new];
  card.wantsLayer = YES;
  card.layer.backgroundColor = CARD.CGColor;
  card.layer.cornerRadius = 30;
  card.layer.cornerCurve = kCACornerCurveContinuous;
  CGFloat w = 420, inner = w - 48, y = 26;
  WMark* mark = [[WMark alloc] initWithFrame:NSMakeRect((w - 134) / 2, y - 25, 134, 134)];
  mark.markSize = 84;
  [card addSubview:mark];
  y += 84 + 22;
  NSImageView* off = glyph(@"icloud.slash", 20, BADGE);
  place(off, (w - 26) / 2, y, 26, 22);
  [card addSubview:off];
  y += 22 + 10;
  NSTextField* title = label(@"Your settings could not be saved", 23, 600, INK);
  title.font = display(23, 600);
  title.alignment = NSTextAlignmentCenter;
  placeLabel(title, 24, y, inner);
  [card addSubview:title];
  y += title.frame.size.height + 8;
  NSTextField* words = wrapLabel(message, 14, 400, MUTE);
  lineHeight(words, 20, NSTextAlignmentCenter);
  y += placeWrap(words, 24, y, inner) + 22;
  [card addSubview:words];
  WButton* retry = sheetButton(@"Try again", INK, ON_INK, @"arrow.clockwise");
  retry.onClick = onRetry;
  WButton* anyway = sheetButton(@"Log out anyway", WELL, BADGE, nil);
  anyway.onClick = onAnyway;
  WButton* stay = sheetButton(@"Stay logged in", NSColor.clearColor, MUTE, nil);
  stay.onClick = onStay;
  for (WButton* b in @[retry, anyway, stay]) { place(b, 24, y, inner, 48); [card addSubview:b]; y += 56; }
  card.frame = NSMakeRect(0, 0, w, y + 14);
  WDialogHost* host = [[WDialogHost alloc] initWithCard:card];
  host.onCancel = onStay;
  host.onConfirm = onRetry;
  return host;
}

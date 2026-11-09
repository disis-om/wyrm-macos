#pragma once
#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>
#include "MacCompat.h"

/* The Mac shell's design kit: Wyrm's palettes (Android WyrmSurface.kt, the
   same eight themes and intensity rule), Manrope / Bodoni from the bundle,
   the iOS springs, and the controls every page shares. */

typedef struct {
  NSColor *paper, *card, *ink, *onInk, *quiet, *mute, *rule, *rowRule, *live, *link,
      *tabIdle, *tabBar, *chevron, *badge, *well, *track, *hover;
  BOOL dark;
} WPalette;

extern WPalette WP;
enum { WTHEME_COUNT = 8 };
extern NSString* const WThemeStored[WTHEME_COUNT];
extern NSString* const WThemeName[WTHEME_COUNT];
extern NSString* const WThemeDetail[WTHEME_COUNT];
int WThemeIndex(NSString* stored);
WPalette WThemePalette(int theme, CGFloat intensity);
void WThemeApply(int theme, CGFloat intensity);
/* The 12 roles the engine's own screens take (Android publishArenaTheme). */
void WThemePublishToEngine(void);
/* A theme shown live while a slider moves (the shell is built again on release). */
void WThemeLive(NSWindow* window, int theme, CGFloat intensity);
/* Every colour on screen that was a role of [from] becomes that role of WP. */
void WRecolour(NSWindow* window, WPalette from);

#define PAPER WP.paper
#define CARD WP.card
#define INK WP.ink
#define ON_INK WP.onInk
#define QUIET WP.quiet
#define MUTE WP.mute
#define RULE WP.rule
#define ROW_RULE WP.rowRule
#define TRACK WP.track
#define LIVE WP.live
#define LINK WP.link
#define FAINT WP.chevron
#define BADGE WP.badge
#define WELL WP.well
#define RED rgba(0xFFFF3B30)

NSColor* rgba(uint32_t argb);
NSColor* WMix(NSColor* a, NSColor* b, CGFloat t);
NSFont* body(CGFloat size, int weight);
NSFont* display(CGFloat size, int weight);
NSTextField* label(NSString* text, CGFloat size, int weight, NSColor* colour);
NSTextField* wrapLabel(NSString* text, CGFloat size, int weight, NSColor* colour);
CGFloat placeWrap(NSTextField* t, CGFloat x, CGFloat y, CGFloat w);
void lineHeight(NSTextField* t, CGFloat height, NSTextAlignment align);
void track(NSTextField* t, CGFloat kern);
NSImage* symbol(NSString* name, CGFloat size, NSFontWeight weight);
NSImageView* glyph(NSString* name, CGFloat size, NSColor* tint);
void place(NSView* v, CGFloat x, CGFloat y, CGFloat w, CGFloat h);
void placeLabel(NSTextField* t, CGFloat x, CGFloat y, CGFloat w);
NSString* grouped(long value);
NSView* rule(void);
NSView* well(NSString* symbolName);
NSTextField* section(NSString* text);
void WCopy(NSString* text);
void WOpenURL(NSString* url);

/* SwiftUI's .spring(response:dampingFraction:) as a Core Animation spring. */
CASpringAnimation* WSpring(NSString* keyPath, id from, id to, CGFloat response, CGFloat damping);
CAMediaTimingFunction* WFastOutSlowIn(void);
/* A layer-backed view's centre scale (its anchor stays at the origin). */
CATransform3D WScaleAbout(NSView* v, CGFloat scale);
/* `wyrmBlurFade`: materialise out of (or into) a blur, with fade and 0.985 scale. */
void WMaterialise(NSView* v, BOOL appear, CGFloat blur, CGFloat response, CGFloat damping, void (^done)(void));
void WAfter(double seconds, void (^block)(void));

@interface WFlipped : NSView
@end

/* IosPaperCard: 92% card, 17 continuous corners, rule stroke, soft ink shadow. */
@interface WCard : WFlipped
- (instancetype)initWithRadius:(CGFloat)radius;
@end

/* A clickable surface: hover well, press dim, hand cursor. */
@interface WTap : WFlipped
@property(copy) void (^onClick)(void);
@property(copy) void (^onRightClick)(NSEvent*);
@property(nonatomic) BOOL enabled;
@property(nonatomic, strong) NSColor* fill;
@property(nonatomic, strong) NSColor* hover;
@property BOOL inside, down;
@property BOOL pressScale;
- (void)refresh;
@end

@interface WButton : WTap
@property(strong) NSTextField* title;
@property(strong) NSImageView* icon;
@property BOOL iconTrailing;
+ (instancetype)primary:(NSString*)text;
+ (instancetype)well:(NSString*)symbolName text:(NSString*)text;
+ (instancetype)capsule:(NSString*)text filled:(BOOL)filled;
+ (instancetype)tinted:(NSString*)text fill:(NSColor*)fill ink:(NSColor*)ink symbol:(NSString*)symbolName;
@end

@interface WMetric : WFlipped
@property(strong) NSTextField *name, *value;
+ (instancetype)metric:(NSString*)name;
- (void)setNumber:(NSString*)text;
@end

/* The app's accent is Wyrm's live green (AppKit's glass controls tint with it). */
void WInstallAccent(void);

/* AppKit's own switch (Liquid Glass on macOS 26), green when on. */
@interface WSwitch : NSView
@property(nonatomic) BOOL on;
@property(copy) void (^onToggle)(BOOL);
- (void)setOn:(BOOL)on animated:(BOOL)animated;
- (void)click;
@end

/* AppKit's own slider (Liquid Glass on macOS 26), its track filled in ink. It
   follows a drag without a modal loop, so the arena keeps running under it. */
@interface WSlider : NSView
@property(nonatomic) CGFloat value, minimum, maximum;
@property(nonatomic) int steps;
@property(copy) void (^onChange)(CGFloat);
@property(copy) void (^onEnd)(void);
@end

/* The chosen-option thumb: a plain pill at rest ([rest], which the owner puts
   under its labels) and a lens of real Liquid Glass (this view, over them)
   while it is held. */
@interface WGlassThumb : NSView
@property(nonatomic) BOOL lifted;
@property(nonatomic, strong) NSColor* restFill;
@property(readonly) NSView* rest;
- (void)placeAt:(NSRect)frame;
- (void)glideTo:(NSRect)frame;
@end
/* A frame change on the shell's one smooth curve (no bounce). */
void WGlide(NSView* v, NSRect to);

/* LiquidSegmented: a capsule track and a draggable glass thumb under the chosen option. */
@interface WSegmented : NSView
@property(strong) NSArray<NSString*>* options;
@property(nonatomic) NSInteger selected;
@property(copy) void (^onSelect)(NSInteger);
- (instancetype)initWithOptions:(NSArray<NSString*>*)options;
@end

@interface WSpinner : NSView
@property(strong) NSColor* colour;
@end

/* The curving W (WyrmBrandMark), drawn with round caps and an ink gradient. */
@interface WMark : NSView
@property CGFloat markSize;
@end

/* Shimmer caps text (WorkingStatus). */
@interface WShimmer : NSView
@property(strong) NSTextField* text;
- (void)setTitle:(NSString*)title;
@end

/* A borderless text field in the page's fonts. */
NSTextField* WField(NSString* placeholder, CGFloat size, int weight, BOOL secure);

/* Avatars from the account (photo, or initials on ink); images are cached in memory. */
@interface WAvatar : NSView
@property CGFloat corner;
- (void)setURL:(NSString*)url initials:(NSString*)initials;
@end
NSString* WInitials(NSString* name);

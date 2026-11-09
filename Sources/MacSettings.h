#pragma once
#import "MacKit.h"

/* Settings for the Mac window: Wyrm Desktop's two-pane workspace (the
   sections on the left with search, the open page on the right), every page
   built from Android's rows, wording and engine settings. */
@interface WSettingsView : WFlipped
@property(copy) void (^onLogOut)(void);
- (void)reload;
/* How far the open page is scrolled (kept across a theme rebuild). */
@property(nonatomic) CGFloat pageOffset;
@end

/* The open Settings page survives a theme rebuild of the shell. */
extern NSInteger WSettingsOpenPage;

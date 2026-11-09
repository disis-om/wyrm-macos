#pragma once
#import "MacKit.h"

/* The sign-in (Wyrm Desktop's opening + the phones' cinematic flow). */
@interface WAuthView : WFlipped
@property(copy) void (^onComplete)(void);
/* The account was accepted (before its settings come down behind the W). */
@property(copy) void (^onAccountIn)(void);
/* [title]: start with the W in the middle and that line under it (launch sync, log out). */
- (instancetype)initWithFrame:(NSRect)frame working:(NSString*)title;
- (void)showWorking:(NSString*)title;
- (void)completeIntoApp;
- (void)showLanding;
@end

/* WyrmSessionTransition: the W and a shimmer line, for sync and sign-out. */
@interface WSessionView : WFlipped
- (instancetype)initWithTitle:(NSString*)title;
- (void)setTitle:(NSString*)title;
@end

/* A centred dialog over a scrim; Esc cancels, Enter confirms. */
@interface WDialogHost : WFlipped
@property(copy) void (^onCancel)(void);
@property(copy) void (^onConfirm)(void);
- (instancetype)initWithCard:(NSView*)card;
- (void)present;
- (void)dismiss;
@end

WDialogHost* WLogOutSheet(void (^onLogOut)(void), void (^onCancel)(void));
WDialogHost* WSaveFailedDialog(NSString* message, void (^onRetry)(void), void (^onAnyway)(void), void (^onStay)(void));
/* Android's privacy document (PRIVACY.md from the bundle), laid out at [width]. */
NSView* WPrivacyDocument(CGFloat width, CGFloat* height);

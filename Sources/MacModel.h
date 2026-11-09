#pragma once
#import <Foundation/Foundation.h>
#include "MacCompat.h"

/* What the Mac shell knows: the engine's own settings table (Android's
   SettingsCodec rows), the app's preference files, the Wyrm backend client
   and the account's life on this Mac (sign-in, settings sync, log out). */

extern NSString* const WSettingsChanged;
extern NSString* const WAccountChanged;
extern NSString* const WThemeChanged;

@interface WSetting : NSObject
@property(copy) NSString *ident, *group, *type, *label, *hint, *raw;
@property float minimum, maximum;
@property(copy) NSArray<NSString*>* options;
@property(readonly) float number;
@property(readonly) BOOL enabled;
@property(readonly) NSInteger index;
@property(readonly) NSArray<NSNumber*>* channels;
@property(readonly) BOOL isColour;
@end

@interface WHotkey : NSObject
@property int action, key, mode;
@property(copy) NSString *name, *keyName;
@property BOOL fixedMode, visible;
@property float x, y;
@end

@interface WEngine : NSObject
+ (NSArray<WSetting*>*)settings;
+ (void)refresh;
+ (BOOL)ready;
+ (WSetting*)named:(NSString*)ident;
+ (void)write:(WSetting*)setting values:(NSArray<NSNumber*>*)values;
+ (void)writeId:(NSString*)ident values:(NSArray<NSNumber*>*)values;
+ (NSString*)version;
+ (NSArray<WHotkey*>*)hotkeys;
+ (void)refreshKeys;
+ (NSString*)nameOfKey:(int)key;
/* A key belongs to one action: the action that had it takes this one's old key. */
+ (WHotkey*)bindKey:(int)key toAction:(int)action;
+ (void)setMode:(int)mode forAction:(int)action;
+ (void)resetKeys;
+ (void)resetAll;
+ (NSString*)formatted:(WSetting*)setting;
@end

/* Android's SharedPreferences files, one dictionary each, typed values kept. */
@interface WPrefs : NSObject
+ (id)get:(NSString*)file key:(NSString*)key;
+ (BOOL)boolIn:(NSString*)file key:(NSString*)key fallback:(BOOL)fallback;
+ (double)numberIn:(NSString*)file key:(NSString*)key fallback:(double)fallback;
+ (NSString*)stringIn:(NSString*)file key:(NSString*)key;
+ (void)set:(id)value in:(NSString*)file key:(NSString*)key;
+ (NSDictionary*)all:(NSString*)file;
+ (void)clear:(NSString*)file;
@end

/* The app settings Android keeps beside the engine. */
@interface WStore : NSObject
+ (int)theme;
+ (double)themeIntensity;
+ (void)setTheme:(int)theme;
+ (void)setThemeIntensity:(double)value;
+ (void)loadTheme;
+ (BOOL)themeDiffersFromShown;
+ (BOOL)nearOriginal;
+ (void)setNearOriginal:(BOOL)on;
+ (BOOL)lookAhead;
+ (void)setLookAhead:(BOOL)on;
+ (NSString*)nickname;
+ (void)setNickname:(NSString*)name chosen:(BOOL)chosen;
+ (BOOL)notifyKind:(NSString*)kind;
+ (void)setNotifyKind:(NSString*)kind on:(BOOL)on;
/* Everything the engine must know, once it runs and after a restore. */
+ (void)publishAll;
@end

/* TeamHudStore: the roster's, chat window's, stats' and board's look (wyrm_team_hud, synced). */
@interface WTeamHud : NSObject
+ (NSArray<NSString*>*)keys;
+ (float)value:(NSString*)key;
+ (float)minimum:(NSString*)key;
+ (float)maximum:(NSString*)key;
+ (void)apply:(NSString*)key value:(float)value;
+ (void)publish;
+ (NSArray<NSString*>*)colourNames;
+ (NSArray<NSNumber*>*)colourSwatches;  // ARGB, 0 = the theme's ink
@end

typedef void (^WApiDone)(id json, NSInteger status, NSString* error);
void WApi(NSString* method, NSString* path, id body, BOOL authenticated, WApiDone done);
void WApiBinary(NSString* method, NSString* path, NSString* contentType, NSData* data, WApiDone done);
NSString* WApiBase(void);
NSString* WAbsolute(NSString* url);

typedef NS_ENUM(NSInteger, WGate) { WGateResuming, WGateSignIn, WGateIn };

@interface WAccount : NSObject
+ (instancetype)shared;
@property(nonatomic) WGate gate;
@property(strong) NSDictionary* player;
@property(readonly) BOOL hasSession;
@property(nonatomic, copy) NSString* transitionTitle;
@property(copy) void (^onGate)(WGate gate);
@property(copy) void (^onTransition)(NSString* title);
@property(copy) void (^onLogOutFailed)(NSString* message);
@property(readonly) BOOL syncReady;

- (NSString*)displayName;
- (NSString*)handle;
- (NSString*)avatarURL;
- (long)highestScore;
- (long)kills;
- (BOOL)shareActivity;

- (void)checkUsername:(NSString*)name done:(void (^)(NSInteger availability))done;  // 2 ok, 3 taken, 4 unavailable
- (void)signUp:(NSString*)username password:(NSString*)password done:(void (^)(NSString* failure))done;
- (void)logIn:(NSString*)username password:(NSString*)password done:(void (^)(NSString* failure))done;
/* Launch with a saved session: still good? NO means sign in again. */
- (void)resume:(void (^)(BOOL signedIn))done;
/* Before Play shows: the player, and (fresh sign-in) the account's settings. */
- (void)bootstrap:(void (^)(void))done;
- (void)logOut:(BOOL)skipSave;
- (void)save:(BOOL)force done:(void (^)(BOOL ok))done;
- (void)saveBeforeQuit;
- (void)setActivitySharing:(BOOL)share;
- (void)syncIngameName:(NSString*)name;
- (void)refreshPlayer:(void (^)(void))done;
- (NSString*)friendlyError:(NSString*)code status:(NSInteger)status;
@end

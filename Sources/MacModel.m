#import "MacModel.h"
#import "MacKit.h"
#include <sys/sysctl.h>
#include <sys/stat.h>

void android_home_set_near_original(bool on, int server);

NSString* const WSettingsChanged = @"WyrmSettingsChanged";
NSString* const WAccountChanged = @"WyrmAccountChanged";
NSString* const WThemeChanged = @"WyrmThemeChanged";

static NSString* format(float v) {
  NSString* s = [NSString stringWithFormat:@"%.4f", v];
  while ([s containsString:@"."] && ([s hasSuffix:@"0"] || [s hasSuffix:@"."])) s = [s substringToIndex:s.length - 1];
  return s;
}

#pragma mark - Engine settings (SettingsCodec)

@implementation WSetting
- (float)number { return self.raw.floatValue; }
- (BOOL)enabled { return self.raw.floatValue >= 0.5f; }
- (NSInteger)index { return (NSInteger)lroundf(self.raw.floatValue); }
- (BOOL)isColour { return [self.type isEqualToString:@"color3"] || [self.type isEqualToString:@"color4"]; }
- (NSArray<NSNumber*>*)channels {
  NSMutableArray* out = [NSMutableArray new];
  for (NSString* part in [self.raw componentsSeparatedByString:@","]) [out addObject:@(part.floatValue)];
  while (out.count < 4) [out addObject:@1];
  return out;
}
@end

@implementation WHotkey
@end

static NSArray<WSetting*>* settingsCache;
static NSArray<WHotkey*>* hotkeyCache;
static NSArray<NSArray*>* keyOptionCache;
static NSString* versionCache = @"";

static NSString* take(char* text) {
  NSString* s = text ? @(text) : @"";
  free(text);
  return s ?: @"";
}

@implementation WEngine
+ (NSArray<WSetting*>*)settings { if (!settingsCache.count) [self refresh]; return settingsCache ?: @[]; }
+ (BOOL)ready { return [self settings].count > 0; }
+ (void)refresh {
  NSMutableArray* rows = [NSMutableArray new];
  for (NSString* line in [take(wyrm_mac_settings_snapshot()) componentsSeparatedByString:@"\n"]) {
    NSArray* f = [line componentsSeparatedByString:@"\t"];
    if (f.count < 9) continue;
    WSetting* s = [WSetting new];
    s.ident = f[0]; s.group = f[1]; s.type = f[2]; s.label = f[3]; s.hint = f[4]; s.raw = f[5];
    s.minimum = [f[6] floatValue]; s.maximum = [f[7] floatValue];
    s.options = [f[8] length] ? [f[8] componentsSeparatedByString:@"|"] : @[];
    [rows addObject:s];
  }
  if (rows.count) settingsCache = rows;
  NSString* v = take(wyrm_mac_settings_version());
  if (v.length) versionCache = v;
}
+ (WSetting*)named:(NSString*)ident {
  for (WSetting* s in [self settings]) if ([s.ident isEqualToString:ident]) return s;
  return nil;
}
+ (void)writeId:(NSString*)ident values:(NSArray<NSNumber*>*)values {
  if (!values.count) return;
  float v[4] = {0};
  for (NSUInteger i = 0; i < values.count && i < 4; i++) v[i] = values[i].floatValue;
  wyrm_mac_set_setting(ident.UTF8String, v, (int)MIN(4, values.count));
}
/* Android's writeSetting: to the engine, and the row shows it at once. */
+ (void)write:(WSetting*)setting values:(NSArray<NSNumber*>*)values {
  if (!setting || !values.count) return;
  [self writeId:setting.ident values:values];
  if (setting.isColour) {
    NSMutableArray* parts = [NSMutableArray new];
    for (NSNumber* n in values) [parts addObject:format(n.floatValue)];
    setting.raw = [parts componentsJoinedByString:@","];
  } else if ([setting.type isEqualToString:@"bool"]) setting.raw = values[0].floatValue != 0 ? @"1" : @"0";
  else setting.raw = format(values[0].floatValue);
}
+ (NSString*)version { if (!versionCache.length) [self refresh]; return versionCache; }
+ (NSArray<WHotkey*>*)hotkeys { if (!hotkeyCache.count) [self refreshKeys]; return hotkeyCache ?: @[]; }
+ (void)refreshKeys {
  NSMutableArray* rows = [NSMutableArray new];
  for (NSString* line in [take(wyrm_mac_hotkeys_snapshot()) componentsSeparatedByString:@"\n"]) {
    NSArray* f = [line componentsSeparatedByString:@"\t"];
    if (f.count < 9) continue;
    WHotkey* k = [WHotkey new];
    k.action = [f[0] intValue]; k.name = f[1]; k.key = [f[2] intValue]; k.keyName = f[3];
    k.mode = [f[4] intValue]; k.fixedMode = [f[5] isEqualToString:@"1"]; k.visible = [f[6] isEqualToString:@"1"];
    k.x = [f[7] floatValue]; k.y = [f[8] floatValue];
    [rows addObject:k];
  }
  if (rows.count) hotkeyCache = rows;
  NSMutableArray* options = [NSMutableArray new];
  for (NSString* line in [take(wyrm_mac_key_options()) componentsSeparatedByString:@"\n"]) {
    NSArray* f = [line componentsSeparatedByString:@"\t"];
    if (f.count >= 2) [options addObject:@[@([f[0] intValue]), f[1]]];
  }
  if (options.count) keyOptionCache = options;
}
+ (NSString*)nameOfKey:(int)key {
  for (NSArray* o in keyOptionCache) if ([o[0] intValue] == key) return o[1];
  return @"";
}
+ (void)send:(WHotkey*)k { wyrm_mac_set_hotkey(k.action, k.key, k.mode, k.visible, k.x, k.y); }
+ (WHotkey*)bindKey:(int)key toAction:(int)action {
  WHotkey *row = nil, *other = nil;
  for (WHotkey* k in [self hotkeys]) {
    if (k.action == action) row = k;
    else if (key >= 0 && k.key == key) other = k;
  }
  if (!row) return nil;
  WHotkey* swapped = nil;
  if (other) {
    swapped = [WHotkey new];
    swapped.action = other.action; swapped.key = other.key; swapped.keyName = other.keyName;
    other.key = row.key; other.keyName = row.keyName;
    [self send:other];
  }
  row.key = key;
  row.keyName = [self nameOfKey:key];
  [self send:row];
  WAfter(0.25, ^{ [self refreshKeys]; [NSNotificationCenter.defaultCenter postNotificationName:WSettingsChanged object:nil]; });
  return swapped;
}
+ (void)setMode:(int)mode forAction:(int)action {
  for (WHotkey* k in [self hotkeys]) if (k.action == action && !k.fixedMode) { k.mode = mode; [self send:k]; }
  WAfter(0.25, ^{ [self refreshKeys]; });
}
/* Wyrm Desktop's defaults (the engine's, with turns on A / D). */
+ (void)resetKeys {
  NSDictionary* defaults = @{@0: @[@72, @0], @1: @[@80, @0], @2: @[@70, @0], @3: @[@75, @1], @4: @[@84, @0],
                             @5: @[@90, @0], @6: @[@82, @1], @7: @[@81, @1], @8: @[@78, @0], @9: @[@77, @0],
                             @10: @[@32, @0], @11: @[@65, @0], @12: @[@68, @0], @14: @[@86, @0], @15: @[@69, @0]};
  for (WHotkey* k in [self hotkeys]) {
    NSArray* d = defaults[@(k.action)];
    if (!d) continue;
    k.key = [d[0] intValue];
    if (!k.fixedMode) k.mode = [d[1] intValue];
    [self send:k];
  }
  WAfter(0.25, ^{ [self refreshKeys]; [NSNotificationCenter.defaultCenter postNotificationName:WSettingsChanged object:nil]; });
}
+ (void)resetAll {
  wyrm_mac_settings_action(1);
  WAfter(0.4, ^{
    [self refresh];
    [self refreshKeys];
    [NSNotificationCenter.defaultCenter postNotificationName:WSettingsChanged object:nil];
  });
}
+ (NSString*)formatted:(WSetting*)s {
  if ([s.type isEqualToString:@"bool"]) return s.enabled ? @"On" : @"Off";
  if ([s.type isEqualToString:@"enum"]) return s.index >= 0 && s.index < (NSInteger)s.options.count ? s.options[s.index] : @"";
  if ([s.type isEqualToString:@"int"]) return [NSString stringWithFormat:@"%ld", lroundf(s.number)];
  if ([s.ident isEqualToString:@"general.death_hold"]) return [NSString stringWithFormat:@"%.2f s", s.number];
  if (s.isColour) return @"";
  return [NSString stringWithFormat:@"%.2f", s.number];
}
@end

#pragma mark - Preference files

@implementation WPrefs
+ (NSString*)slot:(NSString*)file { return [@"prefs." stringByAppendingString:file]; }
+ (NSDictionary*)all:(NSString*)file { return [NSUserDefaults.standardUserDefaults dictionaryForKey:[self slot:file]] ?: @{}; }
+ (id)get:(NSString*)file key:(NSString*)key { return [self all:file][key]; }
+ (BOOL)boolIn:(NSString*)file key:(NSString*)key fallback:(BOOL)fallback {
  id v = [self get:file key:key];
  return [v isKindOfClass:NSNumber.class] ? [v boolValue] : fallback;
}
+ (double)numberIn:(NSString*)file key:(NSString*)key fallback:(double)fallback {
  id v = [self get:file key:key];
  return [v isKindOfClass:NSNumber.class] ? [v doubleValue] : fallback;
}
+ (NSString*)stringIn:(NSString*)file key:(NSString*)key {
  id v = [self get:file key:key];
  return [v isKindOfClass:NSString.class] ? v : nil;
}
+ (void)set:(id)value in:(NSString*)file key:(NSString*)key {
  NSMutableDictionary* d = [[self all:file] mutableCopy];
  if (value) d[key] = value; else [d removeObjectForKey:key];
  [NSUserDefaults.standardUserDefaults setObject:d forKey:[self slot:file]];
}
+ (void)clear:(NSString*)file { [NSUserDefaults.standardUserDefaults removeObjectForKey:[self slot:file]]; }
@end

#pragma mark - App stores

static NSString* const UI = @"wyrm_ui_preferences";
static NSString* const NEAR = @"wyrm_near_original";
static NSString* const FEEL = @"wyrm_play_feel";
static NSString* const NOTIFY = @"wyrm_notification_preferences";
static NSString* const SYNCSTATE = @"wyrm_account_sync";
static NSString* const TEAMHUD = @"wyrm_team_hud";

@implementation WTeamHud
+ (NSArray<NSString*>*)keys {
  return @[@"team_scale", @"team_opacity", @"team_width", @"team_height", @"team_name", @"team_data",
           @"chat_width", @"chat_height", @"chat_name", @"chat_text", @"team_panel", @"chat_panel", @"stats_panel",
           @"stats_text", @"lb_width", @"lb_height", @"online_name", @"online_data", @"global_name", @"global_text",
           @"chatbtn_label", @"chatbtn_fill", @"chatbtn_scale", @"chatbtn_opacity"];
}
static const float HUD_DEFAULTS[] = {1, 1, 340, 210, 0, 0, 400, 270, 0, 0, 1, 1, 1, 0, 1, 1, 0, 0, 0, 0, 0, 9, 1, 0.9f};
static const float HUD_RANGES[][2] = {{0.65f, 1.6f}, {0.05f, 1}, {220, 900}, {120, 800}, {0, 8}, {0, 8}, {240, 1000}, {150, 900},
                                      {0, 8}, {0, 8}, {0, 1}, {0, 1}, {0, 1}, {0, 8}, {0.7f, 2.2f}, {1, 2.2f}, {0, 8}, {0, 8},
                                      {0, 8}, {0, 8}, {0, 8}, {0, 9}, {0.6f, 2.5f}, {0.1f, 1}};
+ (NSInteger)index:(NSString*)key { return [[self keys] indexOfObject:key]; }
+ (float)minimum:(NSString*)key { NSInteger i = [self index:key]; return i == NSNotFound ? 0 : HUD_RANGES[i][0]; }
+ (float)maximum:(NSString*)key { NSInteger i = [self index:key]; return i == NSNotFound ? 1 : HUD_RANGES[i][1]; }
+ (float)value:(NSString*)key {
  NSInteger i = [self index:key];
  if (i == NSNotFound) return 0;
  id stored = [WPrefs get:TEAMHUD key:key];
  /* GLOBAL used TEAM's colours until 2026-10-18: keep what was chosen. */
  if (!stored && [key hasPrefix:@"global_"]) stored = [WPrefs get:TEAMHUD key:[key isEqualToString:@"global_name"] ? @"chat_name" : @"chat_text"];
  float v = [stored isKindOfClass:NSNumber.class] ? [stored floatValue] : HUD_DEFAULTS[i];
  return isfinite(v) ? MAX(HUD_RANGES[i][0], MIN(HUD_RANGES[i][1], v)) : HUD_DEFAULTS[i];
}
+ (BOOL)isColour:(NSString*)key {
  return [key hasSuffix:@"_name"] || [key hasSuffix:@"_data"] || [key hasSuffix:@"_text"] || [key isEqualToString:@"chatbtn_label"] || [key isEqualToString:@"chatbtn_fill"];
}
+ (void)apply:(NSString*)key value:(float)value {
  NSInteger i = [self index:key];
  if (i == NSNotFound || !isfinite(value)) return;
  float v = MAX(HUD_RANGES[i][0], MIN(HUD_RANGES[i][1], value));
  if ([self isColour:key]) v = roundf(v);
  [WPrefs set:@(v) in:TEAMHUD key:key];
  [self publish];
}
+ (void)publish {
  NSArray* keys = [self keys];
  float values[32];
  for (NSUInteger i = 0; i < keys.count; i++) values[i] = [self value:keys[i]];
  wyrm_mac_set_team_hud_style(values, (int)keys.count);
}
+ (NSArray<NSString*>*)colourNames { return @[@"Theme", @"White", @"Black", @"Yellow", @"Cyan", @"Green", @"Pink", @"Orange", @"Red"]; }
+ (NSArray<NSNumber*>*)colourSwatches {
  return @[@0, @0xFFFFFFFF, @0xFF111111, @0xFFFFD54A, @0xFF4DD9FF, @0xFF5BE37D, @0xFFFF6FB5, @0xFFFF9A3C, @0xFFFF5A5A];
}
@end

@implementation WStore
+ (int)theme { return WThemeIndex([WPrefs stringIn:UI key:@"theme"] ?: @"paper"); }
+ (double)themeIntensity { return MAX(0, MIN(1, [WPrefs numberIn:UI key:@"theme_intensity" fallback:0.5])); }
static int appliedTheme = -1;
static double appliedIntensity = -1;
+ (void)loadTheme {
  appliedTheme = [self theme];
  appliedIntensity = [self themeIntensity];
  WThemeApply(appliedTheme, appliedIntensity);
}
+ (BOOL)themeDiffersFromShown { return [self theme] != appliedTheme || fabs([self themeIntensity] - appliedIntensity) > 0.0001; }
+ (void)setTheme:(int)theme {
  [WPrefs set:WThemeStored[theme] in:UI key:@"theme"];
  [self loadTheme];
  WThemePublishToEngine();
  [NSNotificationCenter.defaultCenter postNotificationName:WThemeChanged object:nil];
}
+ (void)setThemeIntensity:(double)value {
  [WPrefs set:@(MAX(0, MIN(1, value))) in:UI key:@"theme_intensity"];
  [self loadTheme];
  WThemePublishToEngine();
  [NSNotificationCenter.defaultCenter postNotificationName:WThemeChanged object:nil];
}
+ (BOOL)nearOriginal { return [WPrefs boolIn:NEAR key:@"on" fallback:NO]; }
+ (void)setNearOriginal:(BOOL)on {
  [WPrefs set:@(on) in:NEAR key:@"on"];
  android_home_set_near_original(on, 0);
}
+ (BOOL)lookAhead { return [WPrefs boolIn:FEEL key:@"look_ahead" fallback:NO]; }
+ (void)setLookAhead:(BOOL)on {
  [WPrefs set:@(on) in:FEEL key:@"look_ahead"];
  wyrm_mac_set_play_feel(false, on, 0);
}
+ (NSString*)nickname {
  NSString* saved = [WPrefs stringIn:UI key:@"nickname"];
  if (saved) return saved;
  const char* engine = wyrm_mac_saved_nickname();
  return engine ? @(engine) : @"";
}
+ (void)setNickname:(NSString*)name chosen:(BOOL)chosen {
  [WPrefs set:name in:UI key:@"nickname"];
  if (chosen) [WPrefs set:@YES in:UI key:@"nickname_chosen"];
  wyrm_mac_set_nickname(name.UTF8String);
}
+ (BOOL)notifyKind:(NSString*)kind { return [WPrefs boolIn:NOTIFY key:kind fallback:YES]; }
+ (void)setNotifyKind:(NSString*)kind on:(BOOL)on { [WPrefs set:@(on) in:NOTIFY key:kind]; }
+ (void)publishAll {
  [self loadTheme];
  WThemePublishToEngine();
  android_home_set_near_original([self nearOriginal], 0);
  wyrm_mac_set_play_feel(false, [self lookAhead], 0);
  [WTeamHud publish];
}
@end

#pragma mark - Backend client (WyrmRepository)

NSString* WApiBase(void) { return @"https://wyrm-api.165-99-223-123.sslip.io"; }
NSString* WAbsolute(NSString* url) {
  if (![url isKindOfClass:NSString.class] || !url.length || [url isEqualToString:@"null"]) return @"";
  return [url hasPrefix:@"/"] ? [WApiBase() stringByAppendingString:url] : url;
}

static NSString* sessionPath(void) {
  NSString* dir = [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject
                   stringByAppendingPathComponent:@"Wyrm"];
  [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
  return [dir stringByAppendingPathComponent:@"session"];
}
static NSString* readToken(void) {
  NSString* t = [NSString stringWithContentsOfFile:sessionPath() encoding:NSUTF8StringEncoding error:nil];
  t = [t stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
  return t.length ? t : nil;
}
static void writeToken(NSString* token) {
  if (!token) { [NSFileManager.defaultManager removeItemAtPath:sessionPath() error:nil]; return; }
  [token writeToFile:sessionPath() atomically:YES encoding:NSUTF8StringEncoding error:nil];
  chmod(sessionPath().fileSystemRepresentation, 0600);
}

static NSURLSession* apiSession(void) {
  static NSURLSession* s;
  if (!s) {
    NSURLSessionConfiguration* c = NSURLSessionConfiguration.ephemeralSessionConfiguration;
    c.timeoutIntervalForRequest = 15;
    c.timeoutIntervalForResource = 30;
    s = [NSURLSession sessionWithConfiguration:c];
  }
  return s;
}
static void finish(NSData* data, NSURLResponse* response, NSError* error, WApiDone done) {
  NSInteger status = [(NSHTTPURLResponse*)response statusCode];
  id json = data.length ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : @{};
  NSString* code = nil;
  if (error || !response) { status = 0; code = @"NETWORK"; }
  else if (status < 200 || status > 299) {
    code = [json isKindOfClass:NSDictionary.class] && [json[@"error"] isKindOfClass:NSString.class] && [json[@"error"] length]
               ? json[@"error"] : [NSString stringWithFormat:@"HTTP_%ld", (long)status];
  }
  dispatch_async(dispatch_get_main_queue(), ^{ if (done) done(code ? nil : (json ?: @{}), status, code); });
}
void WApi(NSString* method, NSString* path, id body, BOOL authenticated, WApiDone done) {
  NSMutableURLRequest* r = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:[WApiBase() stringByAppendingString:path]]];
  r.HTTPMethod = method;
  r.timeoutInterval = 12;
  [r setValue:@"application/json" forHTTPHeaderField:@"Accept"];
  [r setValue:@"1" forHTTPHeaderField:@"skip_zrok_interstitial"];
  NSString* token = readToken();
  if (authenticated && token) [r setValue:[@"Bearer " stringByAppendingString:token] forHTTPHeaderField:@"Authorization"];
  if (body) {
    r.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];
    [r setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
  }
  [[apiSession() dataTaskWithRequest:r completionHandler:^(NSData* d, NSURLResponse* resp, NSError* e) { finish(d, resp, e, done); }] resume];
}
void WApiBinary(NSString* method, NSString* path, NSString* contentType, NSData* data, WApiDone done) {
  NSMutableURLRequest* r = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:[WApiBase() stringByAppendingString:path]]];
  r.HTTPMethod = method;
  r.timeoutInterval = 30;
  [r setValue:@"application/json" forHTTPHeaderField:@"Accept"];
  [r setValue:@"1" forHTTPHeaderField:@"skip_zrok_interstitial"];
  [r setValue:contentType forHTTPHeaderField:@"Content-Type"];
  NSString* token = readToken();
  if (token) [r setValue:[@"Bearer " stringByAppendingString:token] forHTTPHeaderField:@"Authorization"];
  r.HTTPBody = data;
  [[apiSession() dataTaskWithRequest:r completionHandler:^(NSData* d, NSURLResponse* resp, NSError* e) { finish(d, resp, e, done); }] resume];
}

#pragma mark - Account

/* Android's AccountSync rules for platform "macos" (CLAUDE.md "Account-linked
   settings"): this Mac's own document holds the engine's settings table, its
   keys and the preference files marked SYNC; the shared document gets only
   the keys this Mac really has, written on top of the account's last copy, so
   the phones' and Windows' keys are carried through untouched. */
static NSString* const PLATFORM = @"macos";
static NSArray* syncFiles(void) { return @[UI, NEAR, FEEL, NOTIFY, TEAMHUD, @"wyrm_saved_arenas", @"wyrm_recent_arenas"]; }
static NSArray* wipeFiles(void) { return @[@"wyrm_support_seen", SYNCSTATE]; }

@interface WAccount ()
@property BOOL fresh, ready, sharedLoaded;
@property(strong) NSDictionary* sharedBase;
@property double lastSave;
@property(copy) NSString* lastIngame;
@end

@implementation WAccount
+ (instancetype)shared {
  static WAccount* a;
  if (!a) {
    a = [WAccount new];
    a.gate = readToken() ? WGateResuming : WGateSignIn;
  }
  return a;
}
- (BOOL)hasSession { return readToken() != nil; }
- (BOOL)syncReady { return self.ready; }
- (void)setGate:(WGate)gate {
  _gate = gate;
  if (self.onGate) self.onGate(gate);
}
- (void)setTransitionTitle:(NSString*)title {
  _transitionTitle = [title copy];
  if (self.onTransition) self.onTransition(title);
}
- (void)accept:(NSDictionary*)player {
  if (![player isKindOfClass:NSDictionary.class]) return;
  self.player = player;
  [NSNotificationCenter.defaultCenter postNotificationName:WAccountChanged object:nil];
}
static NSString* text(NSDictionary* d, NSString* key) {
  id v = d[key];
  return [v isKindOfClass:NSString.class] && ![v isEqualToString:@"null"] ? v : @"";
}
- (NSString*)displayName { NSString* n = text(self.player, @"displayName"); return n.length ? n : @"Wyrm"; }
- (NSString*)handle { NSString* u = text(self.player, @"username"); return u.length ? [@"@" stringByAppendingString:u] : @""; }
- (NSString*)avatarURL { return WAbsolute(text(self.player, @"avatarUrl")); }
- (long)highestScore { return [self.player[@"highestScore"] longValue]; }
- (long)kills { return [self.player[@"kills"] longValue]; }
- (BOOL)shareActivity { id v = self.player[@"shareActivity"]; return v ? [v boolValue] : YES; }

/* Android's friendlyAuthError, word for word. */
- (NSString*)friendlyError:(NSString*)code status:(NSInteger)status {
  if (status == 0 || !code.length) return @"Could not reach Wyrm. Check your connection and try again.";
  if ([code isEqualToString:@"USERNAME_TAKEN"]) return @"That username is already taken.";
  if ([code isEqualToString:@"INVALID_LOGIN"]) return @"Username or password is incorrect.";
  if ([code isEqualToString:@"NAME_CHANGE_LIMIT"] || [code isEqualToString:@"USERNAME_CHANGE_LIMIT"]) return @"The monthly name-change limit has been reached.";
  if ([code isEqualToString:@"IGN_TAKEN"]) return @"That arena name is already in use.";
  if ([code isEqualToString:@"INVALID_PROFILE"] || [code isEqualToString:@"INVALID_BODY"]) return @"Please check the fields and try again.";
  return [NSString stringWithFormat:@"Wyrm could not complete that request (%@).", code];
}

- (void)checkUsername:(NSString*)name done:(void (^)(NSInteger))done {
  NSString* q = [name stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLQueryAllowedCharacterSet];
  WApi(@"GET", [@"/v1/auth/username-availability?username=" stringByAppendingString:q], nil, NO, ^(id json, NSInteger status, NSString* error) {
    if (error) done(4); else done([json[@"available"] boolValue] ? 2 : 3);
  });
}
- (void)signedIn:(id)json error:(NSString*)error status:(NSInteger)status done:(void (^)(NSString*))done {
  if (error || ![json[@"token"] isKindOfClass:NSString.class]) { done([self friendlyError:error status:status]); return; }
  writeToken(json[@"token"]);
  self.fresh = YES;
  [self accept:json[@"player"]];
  done(nil);
}
/* As Android: the username is the honest default display name. */
- (void)signUp:(NSString*)username password:(NSString*)password done:(void (^)(NSString*))done {
  WApi(@"POST", @"/v1/auth/guest", @{@"displayName": username, @"username": username, @"password": password}, NO,
       ^(id json, NSInteger status, NSString* error) { [self signedIn:json error:error status:status done:done]; });
}
- (void)logIn:(NSString*)username password:(NSString*)password done:(void (^)(NSString*))done {
  WApi(@"POST", @"/v1/auth/login", @{@"username": username, @"password": password}, NO,
       ^(id json, NSInteger status, NSString* error) { [self signedIn:json error:error status:status done:done]; });
}
- (void)refreshPlayer:(void (^)(void))done {
  WApi(@"GET", @"/v1/me", nil, YES, ^(id json, NSInteger status, NSString* error) {
    if (!error) [self accept:json];
    if (done) done();
  });
}
- (void)resume:(void (^)(BOOL))done {
  WApi(@"GET", @"/v1/me", nil, YES, ^(id json, NSInteger status, NSString* error) {
    if (!error) { [self accept:json]; done(YES); return; }
    if (status == 401) { writeToken(nil); done(NO); return; }
    done(YES);  // Offline: keep the session; Play fills in when Wyrm can be reached.
  });
}
- (void)bootstrap:(void (^)(void))done {
  [self refreshPlayer:^{
    if (self.fresh) {
      self.fresh = NO;
      [self restore:^(BOOL ok) {
        if (!ok) [self resumeSync];
        done();
      }];
    } else {
      [self resumeSync];
      done();
    }
  }];
}
- (void)setActivitySharing:(BOOL)share {
  NSMutableDictionary* p = [self.player mutableCopy];
  BOOL before = self.shareActivity;
  p[@"shareActivity"] = @(share);
  [self accept:p];
  WApi(@"PUT", @"/v1/me/activity-sharing", @{@"share": @(share)}, YES, ^(id json, NSInteger status, NSString* error) {
    NSMutableDictionary* q = [self.player mutableCopy];
    q[@"shareActivity"] = error ? @(before) : (json[@"shareActivity"] ?: @(share));
    [self accept:q];
  });
}
/* The lobby name goes alone on Play (Edit profile never sends it). */
- (void)syncIngameName:(NSString*)name {
  if (!self.hasSession || [name isEqualToString:self.lastIngame]) return;
  self.lastIngame = name;
  WApi(@"PATCH", @"/v1/me", @{@"ingameName": name.length ? name : NSNull.null}, YES, ^(id json, NSInteger s, NSString* e) {
    if (e) self.lastIngame = nil; else [self accept:json];
  });
}

#pragma mark Settings documents

- (NSDictionary*)platformDocument {
  NSMutableDictionary* doc = [@{@"schema": @1, @"platform": PLATFORM} mutableCopy];
  [WEngine refresh];
  NSMutableDictionary* engine = [NSMutableDictionary new];
  for (WSetting* s in [WEngine settings]) engine[s.ident] = s.raw;
  if (engine.count) doc[@"engine"] = engine;
  [WEngine refreshKeys];
  NSMutableArray* keys = [NSMutableArray new];
  for (WHotkey* k in [WEngine hotkeys])
    [keys addObject:@{@"action": @(k.action), @"name": k.name, @"key": @(k.key), @"mode": @(k.mode),
                      @"visible": @(k.visible), @"x": @(k.x), @"y": @(k.y)}];
  if (keys.count) doc[@"hotkeys"] = keys;
  NSMutableDictionary* prefs = [NSMutableDictionary new];
  for (NSString* file in syncFiles()) {
    NSMutableDictionary* out = [NSMutableDictionary new];
    [[WPrefs all:file] enumerateKeysAndObjectsUsingBlock:^(NSString* key, id value, BOOL* stop) {
      if ([value isKindOfClass:NSString.class]) out[key] = @[@"s", value];
      else if ([value isKindOfClass:NSNumber.class]) {
        const char* t = [value objCType];
        if (!strcmp(t, @encode(BOOL)) || !strcmp(t, "c") || value == (id)kCFBooleanTrue || value == (id)kCFBooleanFalse) out[key] = @[@"b", @([value boolValue])];
        else out[key] = @[@"f", value];
      }
    }];
    if (out.count) prefs[file] = out;
  }
  doc[@"prefs"] = prefs;
  return doc;
}
- (NSDictionary*)sharedDocument {
  NSMutableDictionary* doc = [(self.sharedBase ?: @{}) mutableCopy];
  doc[@"schema"] = @1;
  NSString* name = [WStore nickname];
  doc[@"nickname"] = name;
  doc[@"nicknameChosen"] = @([WPrefs boolIn:UI key:@"nickname_chosen" fallback:name.length > 0]);
  doc[@"nearOriginal"] = @([WStore nearOriginal]);
  doc[@"lookAhead"] = @([WStore lookAhead]);
  NSDictionary* bools = @{@"general.auto_respawn": @"autoRestart", @"normal.spine": @"spineNormal", @"assist.spine": @"spineAssist",
                          @"assist.hide_cosmetics": @"assistHideCosmetics", @"normal.snake_shadow": @"snakeShadowNormal",
                          @"assist.snake_shadow": @"snakeShadowAssist", @"normal.spine_mine": @"spineMineNormal",
                          @"assist.spine_mine": @"spineMineAssist", @"normal.boost_own": @"boostOwnNormal",
                          @"assist.boost_own": @"boostOwnAssist"};
  [bools enumerateKeysAndObjectsUsingBlock:^(NSString* ident, NSString* key, BOOL* stop) {
    WSetting* s = [WEngine named:ident];
    if (s) doc[key] = @(s.enabled);
  }];
  WSetting *rn = [WEngine named:@"normal.render_mode"], *ra = [WEngine named:@"assist.render_mode"];
  if (rn) doc[@"renderModeNormal"] = @(MAX(0, MIN(3, rn.index)));
  if (ra) doc[@"renderModeAssist"] = @(MAX(0, MIN(3, ra.index)));
  WSetting *wn = [WEngine named:@"normal.spine_width"], *wa = [WEngine named:@"assist.spine_width"];
  if (wn) doc[@"spineWidthNormal"] = @(MAX(0, MIN(1, wn.number)));
  if (wa) doc[@"spineWidthAssist"] = @(MAX(0, MIN(1, wa.number)));
  return doc;
}
static id typed(NSArray* pair) {
  if (![pair isKindOfClass:NSArray.class] || pair.count < 2) return nil;
  NSString* t = pair[0];
  id v = pair[1];
  if ([t isEqualToString:@"b"] && [v isKindOfClass:NSNumber.class]) return @([v boolValue]);
  if (([t isEqualToString:@"i"] || [t isEqualToString:@"l"] || [t isEqualToString:@"f"]) && [v isKindOfClass:NSNumber.class]) return v;
  if ([t isEqualToString:@"s"] && [v isKindOfClass:NSString.class]) return v;
  return nil;
}
/* This Mac's saved copy, one key at a time: preference files first, then the engine. */
- (void)applyPlatform:(NSDictionary*)doc done:(void (^)(void))done {
  NSDictionary* prefs = [doc[@"prefs"] isKindOfClass:NSDictionary.class] ? doc[@"prefs"] : @{};
  for (NSString* file in prefs) {
    if (![syncFiles() containsObject:file] || ![prefs[file] isKindOfClass:NSDictionary.class]) continue;
    [prefs[file] enumerateKeysAndObjectsUsingBlock:^(NSString* key, id value, BOOL* stop) {
      id v = typed(value);
      if (v) [WPrefs set:v in:file key:key];
    }];
  }
  [WEngine refresh];
  NSMutableArray* changes = [NSMutableArray new];
  NSDictionary* engine = [doc[@"engine"] isKindOfClass:NSDictionary.class] ? doc[@"engine"] : @{};
  for (NSString* ident in engine) {
    WSetting* s = [WEngine named:ident];
    if (!s || ![engine[ident] isKindOfClass:NSString.class]) continue;
    NSMutableArray* values = [NSMutableArray new];
    for (NSString* part in [engine[ident] componentsSeparatedByString:@","]) {
      float f = [[part stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet] floatValue];
      if (isfinite(f)) [values addObject:@(s.isColour ? MAX(0, MIN(1, f)) : MAX(MIN(s.minimum, s.maximum), MIN(MAX(s.minimum, s.maximum), f)))];
    }
    if (!values.count) continue;
    if (!s.isColour) values = [@[values[0]] mutableCopy];
    BOOL same = YES;
    NSArray* now = s.channels;
    for (NSUInteger i = 0; i < values.count; i++)
      if (fabsf((s.isColour ? [now[i] floatValue] : s.number) - [values[i] floatValue]) >= 0.0006f) same = NO;
    if (!same) [changes addObject:@[ident, values]];
  }
  NSArray* rows = [doc[@"hotkeys"] isKindOfClass:NSArray.class] ? doc[@"hotkeys"] : @[];
  void (^keys)(void) = ^{
    [WEngine refreshKeys];
    for (NSDictionary* row in rows) {
      if (![row isKindOfClass:NSDictionary.class]) continue;
      WHotkey* target = nil;
      for (WHotkey* k in [WEngine hotkeys]) if ([k.name isEqualToString:row[@"name"]]) target = k;
      if (!target) for (WHotkey* k in [WEngine hotkeys]) if (k.action == [row[@"action"] intValue]) target = k;
      if (!target || ![row[@"x"] isKindOfClass:NSNumber.class] || ![row[@"y"] isKindOfClass:NSNumber.class]) continue;
      int mode = target.fixedMode ? target.mode : ([row[@"mode"] isKindOfClass:NSNumber.class] ? [row[@"mode"] intValue] : target.mode);
      wyrm_mac_set_hotkey(target.action, [row[@"key"] isKindOfClass:NSNumber.class] ? [row[@"key"] intValue] : target.key, mode,
                          row[@"visible"] ? [row[@"visible"] boolValue] : target.visible,
                          MAX(0, MIN(1, [row[@"x"] floatValue])), MAX(0, MIN(1, [row[@"y"] floatValue])));
    }
    done();
  };
  /* The engine's mailbox takes 128 changes a frame: batches of 40. */
  __block NSUInteger at = 0;
  __block void (^batch)(void) = ^{
    for (NSUInteger n = 0; n < 40 && at < changes.count; n++, at++) [WEngine writeId:changes[at][0] values:changes[at][1]];
    if (at < changes.count) WAfter(0.14, batch);
    else { WAfter(0.14, keys); batch = nil; }  // the last batch breaks the block's own cycle
  };
  batch();
}
/* The shared document: each key on its own; a missing one keeps this Mac's value. */
- (void)applyShared:(NSDictionary*)doc {
  if ([doc[@"nickname"] isKindOfClass:NSString.class]) {
    NSString* name = doc[@"nickname"];
    if (name.length > 24) name = [name substringToIndex:24];
    [WStore setNickname:name chosen:NO];
    [WPrefs set:@(doc[@"nicknameChosen"] ? [doc[@"nicknameChosen"] boolValue] : name.length > 0) in:UI key:@"nickname_chosen"];
  }
  if ([doc[@"nearOriginal"] isKindOfClass:NSNumber.class]) [WPrefs set:@([doc[@"nearOriginal"] boolValue]) in:NEAR key:@"on"];
  if ([doc[@"lookAhead"] isKindOfClass:NSNumber.class]) [WPrefs set:@([doc[@"lookAhead"] boolValue]) in:FEEL key:@"look_ahead"];
  NSDictionary* bools = @{@"autoRestart": @"general.auto_respawn", @"spineNormal": @"normal.spine", @"spineAssist": @"assist.spine",
                          @"assistHideCosmetics": @"assist.hide_cosmetics", @"snakeShadowNormal": @"normal.snake_shadow",
                          @"snakeShadowAssist": @"assist.snake_shadow", @"spineMineNormal": @"normal.spine_mine",
                          @"spineMineAssist": @"assist.spine_mine", @"boostOwnNormal": @"normal.boost_own",
                          @"boostOwnAssist": @"assist.boost_own"};
  [bools enumerateKeysAndObjectsUsingBlock:^(NSString* key, NSString* ident, BOOL* stop) {
    if ([doc[key] isKindOfClass:NSNumber.class] && [WEngine named:ident]) [WEngine writeId:ident values:@[@([doc[key] boolValue] ? 1 : 0)]];
  }];
  for (NSString* key in @[@"renderModeNormal", @"renderModeAssist"])
    if ([doc[key] isKindOfClass:NSNumber.class])
      [WEngine writeId:[key hasSuffix:@"Normal"] ? @"normal.render_mode" : @"assist.render_mode" values:@[@(MAX(0, MIN(3, [doc[key] intValue])))]];
  for (NSString* key in @[@"spineWidthNormal", @"spineWidthAssist"])
    if ([doc[key] isKindOfClass:NSNumber.class])
      [WEngine writeId:[key hasSuffix:@"Normal"] ? @"normal.spine_width" : @"assist.spine_width" values:@[@(MAX(0, MIN(1, [doc[key] doubleValue])))]];
}
- (void)reloadStores {
  BOOL rethemed = [WStore themeDiffersFromShown];
  [WStore publishAll];
  WAfter(0.35, ^{
    [WEngine refresh];
    [WEngine refreshKeys];
    if (rethemed) [NSNotificationCenter.defaultCenter postNotificationName:WThemeChanged object:nil];
    [NSNotificationCenter.defaultCenter postNotificationName:WSettingsChanged object:nil];
  });
}
/* The engine has described its settings (its title screen is up). */
- (void)waitForEngine:(int)tries then:(void (^)(void))next {
  [WEngine refresh];
  if ([WEngine ready] || tries <= 0) { next(); return; }
  WAfter(0.2, ^{ [self waitForEngine:tries - 1 then:next]; });
}
/* Log in: the account's copy goes in behind the W. NO when Wyrm could not be reached. */
- (void)restore:(void (^)(BOOL))done {
  NSString* owner = text(self.player, @"id");
  if (!owner.length) { done(NO); return; }
  self.ready = NO;
  [WPrefs set:owner in:SYNCSTATE key:@"restore_owed"];
  [self tryRestore:done];
}
- (void)tryRestore:(void (^)(BOOL))done {
  WApi(@"GET", [@"/v1/me/settings/" stringByAppendingString:PLATFORM], nil, YES, ^(id json, NSInteger status, NSString* error) {
    if (error) { done(NO); return; }
    NSDictionary* platform = [json[@"platform"] isKindOfClass:NSDictionary.class] ? json[@"platform"][@"doc"] : nil;
    NSDictionary* shared = [json[@"shared"] isKindOfClass:NSDictionary.class] ? json[@"shared"][@"doc"] : nil;
    [self waitForEngine:60 then:^{
      self.sharedBase = [shared isKindOfClass:NSDictionary.class] ? shared : nil;
      self.sharedLoaded = YES;
      void (^finished)(void) = ^{
        if ([shared isKindOfClass:NSDictionary.class]) [self applyShared:shared];
        [self reloadStores];
        [WPrefs set:nil in:SYNCSTATE key:@"restore_owed"];
        self.ready = YES;
        done(YES);
      };
      if ([platform isKindOfClass:NSDictionary.class]) [self applyPlatform:platform done:finished]; else finished();
    }];
  });
}
/* A relaunch: finish an owed restore (every 30 s while offline), or keep the account current. */
- (void)resumeSync {
  NSString* me = text(self.player, @"id");
  NSString* owed = [WPrefs stringIn:SYNCSTATE key:@"restore_owed"];
  if (owed.length && [owed isEqualToString:me]) {
    [self tryRestore:^(BOOL ok) { if (!ok && self.hasSession) WAfter(30, ^{ [self resumeSync]; }); }];
    return;
  }
  WApi(@"GET", [@"/v1/me/settings/" stringByAppendingString:PLATFORM], nil, YES, ^(id json, NSInteger status, NSString* error) {
    if (!error) {
      NSDictionary* shared = [json[@"shared"] isKindOfClass:NSDictionary.class] ? json[@"shared"][@"doc"] : nil;
      self.sharedBase = [shared isKindOfClass:NSDictionary.class] ? shared : nil;
      self.sharedLoaded = YES;
    }
    self.ready = YES;
    WAfter(6, ^{ [self save:NO done:nil]; });
  });
}
/* Refuses until this Mac holds the account's copy and the engine has described its settings. */
- (void)save:(BOOL)force done:(void (^)(BOOL))done {
  if (!self.hasSession || !self.ready) { if (done) done(NO); return; }
  double now = CFAbsoluteTimeGetCurrent();
  if (!force && now - self.lastSave < 20) { if (done) done(YES); return; }
  NSDictionary* platform = [self platformDocument];
  if (!platform[@"engine"]) { if (done) done(NO); return; }
  NSMutableDictionary* body = [@{@"doc": platform, @"appVersion": @"0.1.0"} mutableCopy];
  NSDictionary* shared = self.sharedLoaded ? [self sharedDocument] : nil;
  if (shared) body[@"shared"] = shared;
  WApi(@"PUT", [@"/v1/me/settings/" stringByAppendingString:PLATFORM], body, YES, ^(id json, NSInteger status, NSString* error) {
    if (!error) { self.lastSave = CFAbsoluteTimeGetCurrent(); if (shared) self.sharedBase = shared; }
    if (done) done(!error);
  });
}
/* On quit: one last save, waiting at most 4 s. */
- (void)saveBeforeQuit {
  if (!self.hasSession || !self.ready) return;
  __block BOOL finished = NO;
  [self save:YES done:^(BOOL ok) { finished = YES; }];
  NSDate* until = [NSDate dateWithTimeIntervalSinceNow:4];
  while (!finished && [until timeIntervalSinceNow] > 0)
    [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
}
/* Log out: every file not about this Mac, the engine back to its defaults, the session. */
- (void)wipe {
  self.ready = NO;
  self.sharedBase = nil;
  self.sharedLoaded = NO;
  for (NSString* file in [syncFiles() arrayByAddingObjectsFromArray:wipeFiles()]) [WPrefs clear:file];
  wyrm_mac_settings_action(1);
  wyrm_mac_set_nickname("");
  self.lastIngame = nil;
  [self reloadStores];
}
- (void)logOut:(BOOL)skipSave {
  if (self.transitionTitle) return;
  self.transitionTitle = @"Saving your settings…";
  void (^leave)(void) = ^{
    self.transitionTitle = @"Logging you out…";
    writeToken(nil);
    [self wipe];
    /* As on Android and iOS: the account's surfaces clear behind the W, then the sign-in. */
    WAfter(0.92, ^{
      self.player = nil;
      self.gate = WGateSignIn;
      self.transitionTitle = nil;
    });
  };
  if (skipSave || !self.ready) { leave(); return; }
  [self save:YES done:^(BOOL ok) {
    if (ok) { leave(); return; }
    self->_transitionTitle = nil;
    if (self.onTransition) self.onTransition(nil);
    if (self.onLogOutFailed)
      self.onLogOutFailed(@"Wyrm could not reach your account. If you log out anyway, the changes you made since the last save are cleared from this computer.");
  }];
}
@end

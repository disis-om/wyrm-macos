#import "MacKit.h"
#import "MacModel.h"
#import "MacAuth.h"
#import "MacSettings.h"
#include <SDL3/SDL.h>
#include <arpa/inet.h>
#include <fcntl.h>
#include <netdb.h>
#include <netinet/tcp.h>
#include <poll.h>
#include <sys/socket.h>

/* The native Mac shell: Wyrm Desktop's sign-in, floating tab bar, Play (Home
   and the Ready Room), Settings and the arena UI editor drawn by AppKit over
   the engine's SDL view, on the main thread that also runs the engine. Glass
   is Apple's Liquid Glass (NSGlassEffectView) on macOS 26. */

bool server_address_is_valid(const char* address);

#pragma mark - Liquid Glass tab bar

static NSString* const TabNames[] = {@"Trails", @"Social", @"Play", @"Skin", @"Settings"};
static NSString* const TabSymbols[] = {@"point.topleft.down.curvedto.point.bottomright.up", @"person.2",
                                       @"play.circle", @"circle.hexagongrid", @"slider.horizontal.3"};
enum { TAB_COUNT = 5, TAB_PLAY = 2, TAB_SETTINGS = 4 };

/* Wyrm Android's LiquidTabBar on a desktop: a glass capsule, and a glass pill
   under the chosen tab that can be clicked to or dragged along, lifting into
   a lens while it is held. */
@interface WTabBar : WFlipped
@property(strong) NSView* glass;
@property(strong) WFlipped* content;
@property(strong) WGlassThumb* pill;
@property(strong) NSMutableArray<NSImageView*>* icons;
@property(strong) NSMutableArray<NSTextField*>* names;
@property(nonatomic) int selected;
@property(copy) void (^onSelect)(int);
@property BOOL dragging, moved;
@property CGFloat grab, downX;
@end
@implementation WTabBar
- (instancetype)initWithSelected:(int)selected {
  if ((self = [super initWithFrame:NSZeroRect])) {
    _content = [WFlipped new];
    if (@available(macOS 26.0, *)) {
      NSGlassEffectView* glass = [NSGlassEffectView new];
      glass.style = NSGlassEffectViewStyleRegular;
      glass.contentView = _content;
      _glass = glass;
    } else {
      NSVisualEffectView* blur = [NSVisualEffectView new];
      blur.material = NSVisualEffectMaterialHUDWindow;
      blur.blendingMode = NSVisualEffectBlendingModeWithinWindow;
      blur.state = NSVisualEffectStateActive;
      blur.wantsLayer = YES;
      blur.layer.cornerCurve = kCACornerCurveContinuous;
      blur.layer.masksToBounds = YES;
      [blur addSubview:_content];
      _glass = blur;
    }
    [self addSubview:_glass];
    /* The pill rests under the names; held, its glass lens rises over the bar
       (glass is never nested in glass). */
    _pill = [WGlassThumb new];
    [_content addSubview:_pill.rest];
    _icons = [NSMutableArray new];
    _names = [NSMutableArray new];
    for (int i = 0; i < TAB_COUNT; i++) {
      NSImageView* icon = glyph(TabSymbols[i], i == TAB_PLAY ? 17 : 15, MUTE);
      NSTextField* name = label(TabNames[i], 14, 600, MUTE);
      [_content addSubview:icon];
      [_content addSubview:name];
      [_icons addObject:icon];
      [_names addObject:name];
    }
    [self addSubview:_pill];
    _selected = selected;
    [self paint:selected];
  }
  return self;
}
- (CGFloat)tabWidth { return (self.bounds.size.width - 12) / TAB_COUNT; }
- (NSRect)pillAt:(int)i { return NSMakeRect(6 + self.tabWidth * i, 6, self.tabWidth, self.bounds.size.height - 12); }
- (int)indexAt:(CGFloat)x { return MAX(0, MIN(TAB_COUNT - 1, (int)((x - 6) / self.tabWidth))); }
- (void)paint:(int)chosen {
  for (int i = 0; i < TAB_COUNT; i++) {
    BOOL on = i == chosen;
    self.icons[i].contentTintColor = on ? INK : MUTE;
    self.names[i].font = body(14, on ? 700 : 600);
    self.names[i].textColor = on ? INK : MUTE;
  }
  [self setNeedsLayout:YES];
}
- (void)choose:(int)index {
  self.selected = index;
  [self paint:index];
  [self.pill glideTo:[self pillAt:index]];
  if (self.onSelect) self.onSelect(index);
}
- (void)layout {
  [super layout];
  NSSize s = self.bounds.size;
  place(self.glass, 0, 0, s.width, s.height);
  if (@available(macOS 26.0, *)) ((NSGlassEffectView*)self.glass).cornerRadius = s.height / 2;
  else { self.glass.layer.cornerRadius = s.height / 2; place(self.content, 0, 0, s.width, s.height); }
  CGFloat w = self.tabWidth, h = s.height - 12;
  for (int i = 0; i < TAB_COUNT; i++) {
    NSTextField* name = self.names[i];
    [name sizeToFit];
    /* Room for the bold (chosen) weight, so choosing a tab never cuts its name. */
    CGFloat nw = ceil([name.stringValue sizeWithAttributes:@{NSFontAttributeName: body(14, 700)}].width) + 3;
    CGFloat iw = i == TAB_PLAY ? 20 : 18, total = iw + 7 + nw;
    CGFloat x = 6 + w * i + MAX(4, (w - total) / 2);
    place(self.icons[i], x, 6 + (h - iw) / 2, iw, iw);
    place(name, x + iw + 7, 6 + (h - name.frame.size.height) / 2, MIN(nw, w - iw - 15), name.frame.size.height);
  }
  /* Placed, never animated, by a layout: only a choice moves the pill. */
  if (!self.dragging) [self.pill placeAt:[self pillAt:self.selected]];
}
- (BOOL)acceptsFirstMouse:(NSEvent*)e { return YES; }
- (BOOL)mouseDownCanMoveWindow { return NO; }
- (NSView*)hitTest:(NSPoint)p { return NSPointInRect([self.superview convertPoint:p toView:self], self.bounds) ? self : nil; }
- (void)resetCursorRects { [self addCursorRect:self.bounds cursor:NSCursor.pointingHandCursor]; }
- (void)mouseDown:(NSEvent*)e {
  CGFloat x = [self convertPoint:e.locationInWindow fromView:nil].x;
  self.downX = x;
  self.moved = NO;
  self.dragging = x >= NSMinX(self.pill.frame) - 4 && x <= NSMaxX(self.pill.frame) + 4;
  self.grab = x - self.pill.frame.origin.x;
  if (self.dragging) self.pill.lifted = YES;
}
- (void)mouseDragged:(NSEvent*)e {
  if (!self.dragging) return;
  CGFloat x = [self convertPoint:e.locationInWindow fromView:nil].x;
  if (fabs(x - self.downX) > 2) self.moved = YES;
  NSRect f = self.pill.frame;
  f.origin.x = MAX(6, MIN(self.bounds.size.width - 6 - f.size.width, x - self.grab));
  [self.pill placeAt:f];
  [self paint:[self indexAt:NSMidX(f)]];
}
- (void)mouseUp:(NSEvent*)e {
  CGFloat x = [self convertPoint:e.locationInWindow fromView:nil].x;
  int target = self.dragging && self.moved ? [self indexAt:NSMidX(self.pill.frame)] : [self indexAt:x];
  self.dragging = NO;
  self.pill.lifted = NO;
  if (target != self.selected) [self choose:target];
  else { [self paint:target]; [self.pill glideTo:[self pillAt:target]]; }
}
@end

#pragma mark - Arena directory extras: pings, countries, flags, saved and recent arenas

/* Android's ArenaDirectory for this Mac: the web client's own ping
   (`ws://ip:80/ptc` with the page's Origin, one byte 'p' each way, three round
   trips, the fastest kept; a custom address with no /ptc gets a TCP dial of
   its own port), one per machine, remembered for a minute, and only while the
   picker is open (CLAUDE.md: the arena IP penalty). Countries from NTL's
   flags service, pictures from flagcdn, as Android and Wyrm Desktop. */
enum { PING_UNREACHABLE = -1 };
static NSMutableDictionary<NSString*, NSArray*>* measured;  // key -> @[time, ms]
static NSMutableSet<NSNumber*>* probeSockets;
static BOOL probesOpen;
static NSMutableDictionary<NSString*, NSString*>* countries;
static double countriesAt;
static NSCache<NSString*, NSImage*>* flagImages;
static NSMutableSet<NSString*>* flagLoading;

static BOOL probeRegister(int fd) {
  @synchronized(probeSockets) {
    if (!probesOpen) return NO;
    [probeSockets addObject:@(fd)];
    return YES;
  }
}
static void probeUnregister(int fd) { @synchronized(probeSockets) { [probeSockets removeObject:@(fd)]; } }
static void probesSetOpen(BOOL open) {
  if (!probeSockets) probeSockets = [NSMutableSet new];
  @synchronized(probeSockets) {
    probesOpen = open;
    /* Closing the picker (or Play) stops every probe still in flight. */
    if (!open) for (NSNumber* fd in probeSockets) shutdown(fd.intValue, SHUT_RDWR);
  }
}
static double nowMs(void) { return CFAbsoluteTimeGetCurrent() * 1000; }

/* A socket to [host]:[port] (IPv4 or IPv6), connected within [timeout] ms, or -1. */
static int dial(NSString* host, int port, int timeoutMs) {
  struct addrinfo hints = {0}, *res = NULL;
  hints.ai_family = AF_UNSPEC;
  hints.ai_socktype = SOCK_STREAM;
  hints.ai_flags = AI_NUMERICHOST;
  char service[8];
  snprintf(service, sizeof(service), "%d", port);
  if (getaddrinfo(host.UTF8String, service, &hints, &res) || !res) return -1;
  int fd = socket(res->ai_family, SOCK_STREAM, 0);
  if (fd < 0) { freeaddrinfo(res); return -1; }
  int one = 1;
  setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof(one));
  setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &one, sizeof(one));
  if (!probeRegister(fd)) { close(fd); freeaddrinfo(res); return -1; }
  int flags = fcntl(fd, F_GETFL, 0);
  fcntl(fd, F_SETFL, flags | O_NONBLOCK);
  int r = connect(fd, res->ai_addr, res->ai_addrlen);
  freeaddrinfo(res);
  if (r < 0 && errno == EINPROGRESS) {
    struct pollfd p = {fd, POLLOUT, 0};
    int error = 0;
    socklen_t len = sizeof(error);
    if (poll(&p, 1, timeoutMs) != 1 || getsockopt(fd, SOL_SOCKET, SO_ERROR, &error, &len) || error) r = -1;
    else r = 0;
  }
  if (r < 0) { probeUnregister(fd); close(fd); return -1; }
  fcntl(fd, F_SETFL, flags);
  return fd;
}
static BOOL sendAll(int fd, const void* data, size_t n) {
  const char* p = data;
  while (n) { ssize_t w = send(fd, p, n, 0); if (w <= 0) return NO; p += w; n -= (size_t)w; }
  return YES;
}
static int readByte(int fd) { unsigned char c; return recv(fd, &c, 1, 0) == 1 ? c : -1; }
/* Frames until the server's one-byte 'p' (YES) or a close (NO). */
static BOOL readPong(int fd) {
  while (YES) {
    int first = readByte(fd), second = readByte(fd);
    if (first < 0 || second < 0) return NO;
    long length = second & 0x7F;
    if (length == 126) { int a = readByte(fd), b = readByte(fd); if (a < 0 || b < 0) return NO; length = (a << 8) | b; }
    else if (length == 127) { length = 0; for (int i = 0; i < 8; i++) { int b = readByte(fd); if (b < 0) return NO; length = (length << 8) | b; } }
    unsigned char mask[4] = {0};
    BOOL masked = (second & 0x80) != 0;
    if (masked) for (int i = 0; i < 4; i++) { int b = readByte(fd); if (b < 0) return NO; mask[i] = (unsigned char)b; }
    if (length > 64) return NO;
    unsigned char payload[64];
    for (long i = 0; i < length; i++) { int b = readByte(fd); if (b < 0) return NO; payload[i] = (unsigned char)b ^ (masked ? mask[i % 4] : 0); }
    int op = first & 0x0F;
    if (op == 0x8) return NO;
    if ((op == 0x1 || op == 0x2) && length == 1 && payload[0] == 112) return YES;
  }
}
static int ptc(NSString* address) {
  int fd = dial(address, 80, 1500);
  if (fd < 0) return PING_UNREACHABLE;
  struct timeval tv = {2, 500000};
  setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
  double deadline = nowMs() + 2500, best = -1;
  unsigned char key[16];
  arc4random_buf(key, sizeof(key));
  NSString* request = [NSString stringWithFormat:@"GET /ptc HTTP/1.1\r\nHost: %@\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
                       "Sec-WebSocket-Key: %@\r\nSec-WebSocket-Version: 13\r\nOrigin: https://slither.io\r\n\r\n",
                       address, [[NSData dataWithBytes:key length:16] base64EncodedStringWithOptions:0]];
  if (sendAll(fd, request.UTF8String, strlen(request.UTF8String))) {
    char head[4097];
    int n = 0;
    while (n < 4096 && !(n >= 4 && !memcmp(head + n - 4, "\r\n\r\n", 4))) { int c = readByte(fd); if (c < 0) break; head[n++] = (char)c; }
    head[n] = 0;
    if (!strncmp(head, "HTTP/1.1 101", 12) || !strncmp(head, "HTTP/1.0 101", 12)) {
      for (int round = 0; round < 3 && nowMs() < deadline; round++) {
        unsigned char frame[7] = {0x82, 0x81};
        arc4random_buf(frame + 2, 4);
        frame[6] = 112 ^ frame[2];
        double sent = nowMs();
        if (!sendAll(fd, frame, 7) || !readPong(fd)) break;
        double ms = nowMs() - sent;
        if (best < 0 || ms < best) best = ms;
      }
      unsigned char bye[6] = {0x88, 0x80};
      arc4random_buf(bye + 2, 4);
      sendAll(fd, bye, 6);
    }
  }
  probeUnregister(fd);
  close(fd);
  return best < 0 ? PING_UNREACHABLE : MAX(1, (int)best);
}
static int tcpProbe(NSString* address, int port) {
  double start = nowMs();
  int fd = dial(address, port, 1500);
  if (fd < 0) return PING_UNREACHABLE;
  probeUnregister(fd);
  close(fd);
  return MAX(1, (int)(nowMs() - start));
}

/* "1.2.3.4:444" / "[v6]:444" into its address (no brackets) and port. */
static BOOL splitEndpoint(NSString* endpoint, NSString** address, int* port) {
  NSRange colon = [endpoint rangeOfString:@":" options:NSBackwardsSearch];
  if (colon.location == NSNotFound) return NO;
  NSString* host = [endpoint substringToIndex:colon.location];
  if ([host hasPrefix:@"["] && [host hasSuffix:@"]"]) host = [host substringWithRange:NSMakeRange(1, host.length - 2)];
  *address = host;
  *port = [endpoint substringFromIndex:colon.location + 1].intValue;
  return host.length && *port > 0;
}
/* Every arena given, one probe per machine (custom addresses each their own),
   twelve at a time; each result lands on the main queue as it comes. */
static void pingArenas(NSArray<NSString*>* endpoints, NSSet<NSString*>* custom, void (^result)(NSString* endpoint, int ms)) {
  if (!measured) measured = [NSMutableDictionary new];
  NSMutableDictionary<NSString*, NSMutableArray*>* groups = [NSMutableDictionary new];
  for (NSString* e in endpoints) {
    NSString* address;
    int port;
    if (!splitEndpoint(e, &address, &port)) continue;
    NSString* key = [custom containsObject:e] ? e : address;
    if (!groups[key]) groups[key] = [NSMutableArray new];
    [groups[key] addObject:e];
  }
  static dispatch_semaphore_t gate;
  if (!gate) gate = dispatch_semaphore_create(12);
  for (NSString* key in groups) {
    NSArray* group = groups[key];
    NSArray* last;
    @synchronized(measured) { last = measured[key]; }
    if (last && nowMs() - [last[0] doubleValue] < 60000) {
      for (NSString* e in group) result(e, [last[1] intValue]);
      continue;
    }
    BOOL isCustom = [custom containsObject:group[0]];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
      dispatch_semaphore_wait(gate, DISPATCH_TIME_FOREVER);
      NSString* address;
      int port;
      splitEndpoint(group[0], &address, &port);
      int ms = PING_UNREACHABLE;
      BOOL open;
      @synchronized(probeSockets) { open = probesOpen; }
      if (open) {
        ms = [address containsString:@":"] ? PING_UNREACHABLE : ptc(address);
        if (ms == PING_UNREACHABLE && isCustom) ms = tcpProbe(address, port);
      }
      dispatch_semaphore_signal(gate);
      @synchronized(probeSockets) { open = probesOpen; }
      /* A probe closed by the picker closing measured nothing; only a completed one counts. */
      if (!open) return;
      @synchronized(measured) { measured[key] = @[@(nowMs()), @(ms)]; }
      dispatch_async(dispatch_get_main_queue(), ^{ for (NSString* e in group) result(e, ms); });
    });
  }
}

/* NTL's flags service, at most sixty machines a call, asked again only for unknown ones every five minutes. */
static void loadCountries(NSArray<NSString*>* addresses, void (^done)(void)) {
  if (!countries) countries = [NSMutableDictionary new];
  NSMutableOrderedSet* missing = [NSMutableOrderedSet new];
  for (NSString* a in addresses) if (![a containsString:@":"] && !countries[a]) [missing addObject:a];
  if (!missing.count || nowMs() - countriesAt < 5 * 60000) return;
  countriesAt = nowMs();
  NSRegularExpression* code = [NSRegularExpression regularExpressionWithPattern:@"(?:^|/)([a-z]{2})(?:\\.png)?$" options:0 error:nil];
  NSArray* all = missing.array;
  for (NSUInteger at = 0; at < all.count; at += 60) {
    NSArray* chunk = [all subarrayWithRange:NSMakeRange(at, MIN(60, all.count - at))];
    NSString* query = [[chunk componentsJoinedByString:@","] stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.alphanumericCharacterSet];
    NSURL* url = [NSURL URLWithString:[@"https://ntl-slither.com/ss/flags.php?ips=" stringByAppendingString:query]];
    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:12];
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    [[NSURLSession.sharedSession dataTaskWithRequest:request completionHandler:^(NSData* data, NSURLResponse* response, NSError* error) {
      NSDictionary* body = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
      NSMutableDictionary* found = [NSMutableDictionary new];
      if ([body isKindOfClass:NSDictionary.class] && [body[@"ok"] boolValue] && [body[@"flags"] isKindOfClass:NSDictionary.class])
        [body[@"flags"] enumerateKeysAndObjectsUsingBlock:^(NSString* ip, id value, BOOL* stop) {
          if (![value isKindOfClass:NSString.class]) return;
          NSString* v = [[value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet] lowercaseString];
          NSTextCheckingResult* m = [code firstMatchInString:v options:0 range:NSMakeRange(0, v.length)];
          if (m) found[ip] = [v substringWithRange:[m rangeAtIndex:1]];
        }];
      dispatch_async(dispatch_get_main_queue(), ^{
        if (!found.count) countriesAt = 0;
        [countries addEntriesFromDictionary:found];
        if (found.count && done) done();
      });
    }] resume];
  }
}
static NSString* countryOf(NSString* address) { return countries[address].uppercaseString ?: @""; }
static NSImage* flagFor(NSString* country, void (^loaded)(void)) {
  if (country.length != 2) return nil;
  if (!flagImages) { flagImages = [NSCache new]; flagLoading = [NSMutableSet new]; }
  NSImage* image = [flagImages objectForKey:country];
  if (image || [flagLoading containsObject:country]) return image;
  [flagLoading addObject:country];
  NSURL* url = [NSURL URLWithString:[NSString stringWithFormat:@"https://flagcdn.com/w160/%@.png", country.lowercaseString]];
  [[NSURLSession.sharedSession dataTaskWithURL:url completionHandler:^(NSData* data, NSURLResponse* response, NSError* error) {
    NSImage* picture = data.length ? [[NSImage alloc] initWithData:data] : nil;
    dispatch_async(dispatch_get_main_queue(), ^{
      [flagLoading removeObject:country];
      if (!picture) return;
      [flagImages setObject:picture forKey:country];
      if (loaded) loaded();
    });
  }] resume];
  return nil;
}

/* Android's SavedArenas (24, newest first) and RecentArenas (5): synced preference files. */
static NSArray<NSString*>* endpointsIn(NSString* file) {
  NSMutableArray* out = [NSMutableArray new];
  for (NSString* line in [[WPrefs stringIn:file key:@"endpoints"] ?: @"" componentsSeparatedByString:@"\n"]) {
    NSString* e = [line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    if (e.length && server_address_is_valid(e.UTF8String) && ![out containsObject:e]) [out addObject:e];
  }
  return out;
}
static void writeEndpoints(NSString* file, NSArray* list) { [WPrefs set:[list componentsJoinedByString:@"\n"] in:file key:@"endpoints"]; }
static NSArray<NSString*>* savedArenas(void) { NSArray* a = endpointsIn(@"wyrm_saved_arenas"); return a.count > 24 ? [a subarrayWithRange:NSMakeRange(0, 24)] : a; }
static NSArray<NSString*>* saveArena(NSString* e) {
  NSMutableArray* next = [@[e] mutableCopy];
  for (NSString* x in savedArenas()) if (![x isEqualToString:e]) [next addObject:x];
  if (next.count > 24) [next removeObjectsInRange:NSMakeRange(24, next.count - 24)];
  writeEndpoints(@"wyrm_saved_arenas", next);
  return next;
}
static NSArray<NSString*>* removeArena(NSString* e) {
  NSMutableArray* next = [savedArenas() mutableCopy];
  [next removeObject:e];
  writeEndpoints(@"wyrm_saved_arenas", next);
  return next;
}
static NSArray<NSString*>* recentArenas(void) { NSArray* a = endpointsIn(@"wyrm_recent_arenas"); return a.count > 5 ? [a subarrayWithRange:NSMakeRange(0, 5)] : a; }
static void pushRecentArena(NSString* e) {
  if (!server_address_is_valid(e.UTF8String)) return;
  NSMutableArray* next = [@[e] mutableCopy];
  for (NSString* x in recentArenas()) if (![x isEqualToString:e] && next.count < 5) [next addObject:x];
  writeEndpoints(@"wyrm_recent_arenas", next);
}
/* A typed address with Slither's 444 when no port was given; a bare IPv6 gets its brackets. */
static NSString* withDefaultPort(NSString* raw) {
  NSString* t = [raw stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
  if ([t hasPrefix:@"["]) return [t hasSuffix:@"]"] ? [t stringByAppendingString:@":444"] : t;
  if ([t componentsSeparatedByString:@":"].count > 2) return [NSString stringWithFormat:@"[%@]:444", t];
  if ([t containsString:@":"]) return t;
  return [t stringByAppendingString:@":444"];
}

/* An arena as the picker shows it: id -1 for a custom address. */
@interface WArena : NSObject
@property(copy) NSString *endpoint, *address;
@property int players, ident;
- (NSString*)code;
- (NSString*)title;
@end
@implementation WArena
- (NSString*)code { return [NSString stringWithFormat:@"%04d", self.ident % 10000]; }
- (NSString*)title { return self.ident < 0 ? @"Custom arena" : [@"Arena " stringByAppendingString:self.code]; }
@end
static NSArray<WArena*>* liveArenas(void) {
  NSMutableArray* out = [NSMutableArray new];
  for (int i = 0; i < wyrm_mac_arena_count(); i++) {
    WArena* a = [WArena new];
    int players = 0;
    a.endpoint = @(wyrm_mac_arena(i, &players));
    a.players = players;
    a.ident = wyrm_mac_arena_id(i);
    NSString* address;
    int port;
    if (!splitEndpoint(a.endpoint, &address, &port)) continue;
    a.address = address;
    [out addObject:a];
  }
  return out;
}
static WArena* customArena(NSString* raw) {
  NSString* e = withDefaultPort(raw);
  NSString* address;
  int port;
  if (!server_address_is_valid(e.UTF8String) || !splitEndpoint(e, &address, &port)) return nil;
  WArena* a = [WArena new];
  a.endpoint = e;
  a.address = address;
  a.ident = -1;
  return a;
}
static WArena* liveArenaFor(NSString* endpoint) {
  for (WArena* a in liveArenas()) if ([a.endpoint isEqualToString:endpoint]) return a;
  return nil;
}

/* CountryBadge: the flag with rounded corners and a hairline, then its code; nothing while unknown. */
static NSView* countryBadge(NSString* country, void (^loaded)(void)) {
  if (country.length != 2) return nil;
  WFlipped* v = [WFlipped new];
  NSImageView* flag = [NSImageView new];
  flag.wantsLayer = YES;
  flag.layer.cornerRadius = 3;
  flag.layer.masksToBounds = YES;
  flag.layer.backgroundColor = TRACK.CGColor;
  flag.layer.borderWidth = 0.5;
  flag.layer.borderColor = [INK colorWithAlphaComponent:0.14].CGColor;
  flag.imageScaling = NSImageScaleAxesIndependently;
  flag.image = flagFor(country, loaded);
  NSTextField* code = label(country, 10.5, 700, QUIET);
  track(code, 0.6);
  [code sizeToFit];
  place(flag, 0, 0, 20, 14);
  place(code, 25, (14 - code.frame.size.height) / 2, code.frame.size.width, code.frame.size.height);
  [v addSubview:flag];
  [v addSubview:code];
  v.frame = NSMakeRect(0, 0, 25 + code.frame.size.width, 14);
  return v;
}

#pragma mark - Play (Wyrm Desktop's Home)

/* Kept across theme rebuilds of the shell. */
static NSString* chosenEndpoint = @"";
static BOOL hasLastRun;
static int lastScore, lastKills;
static long lastSeconds;
static int openTab = TAB_PLAY;
static NSArray* alertRows;

static CGFloat lineH(NSTextField* t) { [t sizeToFit]; return t.frame.size.height; }
/* A field exactly one line of its font tall: its text starts at its top edge,
   so the field is placed where the line should be. */
static CGFloat fieldHeight(NSTextField* f) { return ceil(f.intrinsicContentSize.height); }
/* A wrapping label's height at a width, without moving it. */
static CGFloat wrapHeight(NSTextField* t, CGFloat w) {
  t.preferredMaxLayoutWidth = w;
  return ceil([t.cell cellSizeForBounds:NSMakeRect(0, 0, w, 10000)].height);
}
static NSString* timeText(long s) { return [NSString stringWithFormat:@"%ld:%02ld", s / 60, s % 60]; }

/* IosLoadoutRow / IosListRow: a leading well, title (and detail), value, chevron. */
@interface WHomeRow : WTap
@property(strong) NSView* lead;
@property(strong) NSTextField *title, *detail, *value, *chevron;
@property(strong) NSView* hairline;
@property(strong) NSView* trailing;
@end
@implementation WHomeRow
- (void)layout {
  [super layout];
  NSSize s = self.bounds.size;
  if (self.hairline) place(self.hairline, 0, 0, s.width, 1);
  place(self.lead, 14, (s.height - self.lead.frame.size.height) / 2, self.lead.frame.size.width, self.lead.frame.size.height);
  CGFloat right = s.width - 14;
  if (self.trailing) {
    NSSize t = self.trailing.frame.size;
    place(self.trailing, right - t.width, (s.height - t.height) / 2, t.width, t.height);
    right -= t.width + 10;
  } else {
    [self.chevron sizeToFit];
    place(self.chevron, right - self.chevron.frame.size.width, (s.height - self.chevron.frame.size.height) / 2,
          self.chevron.frame.size.width, self.chevron.frame.size.height);
    right -= self.chevron.frame.size.width + 6;
    [self.value sizeToFit];
    place(self.value, right - self.value.frame.size.width, (s.height - self.value.frame.size.height) / 2,
          self.value.frame.size.width, self.value.frame.size.height);
    right -= self.value.frame.size.width + 8;
  }
  CGFloat x = 14 + self.lead.frame.size.width + 12, tw = right - x;
  [self.title sizeToFit];
  CGFloat th = self.title.frame.size.height, dh = self.detail ? placeWrap(self.detail, x, 0, tw) : 0;
  CGFloat y = (s.height - th - (dh ? dh + 1 : 0)) / 2;
  place(self.title, x, y, tw, th);
  if (self.detail) place(self.detail, x, y + th + 1, tw, dh);
}
@end
static WHomeRow* homeRow(NSView* lead, NSString* title, NSString* detail, NSString* value, BOOL first, void (^open)(void)) {
  WHomeRow* r = [WHomeRow new];
  r.fill = NSColor.clearColor;
  r.hover = [INK colorWithAlphaComponent:0.03];
  r.pressScale = open != nil;
  r.lead = lead;
  r.title = label(title, 15.5, 400, INK);
  if (detail) {
    r.detail = wrapLabel(detail, 12, 400, QUIET);
    lineHeight(r.detail, 15, NSTextAlignmentLeft);
  }
  r.value = label(value ?: @"", 13.5, 400, QUIET);
  r.chevron = label(@"›", 17, 400, FAINT);
  r.onClick = open;
  for (NSView* v in @[lead, r.title, r.value, r.chevron]) [r addSubview:v];
  if (r.detail) [r addSubview:r.detail];
  if (!first) { r.hairline = rule(); [r addSubview:r.hairline]; }
  return r;
}
static NSView* loadoutIcon(NSString* symbolName, NSColor* tint) {
  WFlipped* w = [WFlipped new];
  w.wantsLayer = YES;
  w.layer.backgroundColor = (tint ? [tint colorWithAlphaComponent:0.14] : WELL).CGColor;
  w.layer.cornerRadius = 8;
  w.layer.cornerCurve = kCACornerCurveContinuous;
  w.frame = NSMakeRect(0, 0, 26, 26);
  NSImageView* i = glyph(symbolName, 13, tint ?: MUTE);
  place(i, 4, 4, 18, 18);
  [w addSubview:i];
  return w;
}
/* IosFoodWell: three pellets in a well. */
@interface WFoodWell : NSView
@end
@implementation WFoodWell
- (BOOL)isFlipped { return YES; }
- (void)drawRect:(NSRect)r {
  [WELL setFill];
  [[NSBezierPath bezierPathWithRoundedRect:self.bounds xRadius:8 yRadius:8] fill];
  CGFloat s = self.bounds.size.width, d = s * 0.115;
  void (^dot)(NSColor*, CGFloat, CGFloat, CGFloat) = ^(NSColor* c, CGFloat x, CGFloat y, CGFloat k) {
    [c setFill];
    [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(s * x - d * k, s * y - d * k, 2 * d * k, 2 * d * k)] fill];
  };
  dot(LIVE, 0.32, 0.38, 1);
  dot(LINK, 0.68, 0.34, 0.82);
  dot(rgba(0xFFD38B5D), 0.55, 0.69, 1.08);
}
@end

@interface WPlayPage : WFlipped <NSTextFieldDelegate>
@property(strong) NSTextField *kicker, *nickname, *nicknameHint, *who, *whoDetail;
@property(strong) WAvatar* avatar;
@property(strong) WTap* bell;
@property(strong) NSTextField* bellBadge;
@property(strong) WCard *arenaCard, *lastCard, *loadoutCard, *roomsCard;
@property(strong) NSView *liveDot, *barTrack, *barFill, *arenaRule, *metricRule, *arenaFlag;
@property(strong) NSTextField *liveLabel, *arenaTitle, *arenaPlayers, *arenaDetail, *lastLabel, *loadoutLabel, *roomsLabel, *notice;
@property(strong) WButton *enter, *pick;
@property(strong) WMetric *best, *kills;
@property(strong) NSArray<WMetric*>* last;
@property(strong) NSArray<NSView*>* lastRules;
@property(strong) NSArray<WHomeRow*>* loadout;
@property(strong) WHomeRow* team;
@property(strong) WSwitch* nearSwitch;
@property(copy) void (^onPick)(void);
@property(copy) void (^onEnter)(void);
@property(copy) void (^onAlerts)(void);
@property CGFloat barFraction;
@end

@implementation WPlayPage
- (instancetype)init {
  if (!(self = [super initWithFrame:NSZeroRect])) return nil;
  __weak WPlayPage* weak = self;
  /* Android Home's header: in-game name (click to rename), the bell, name, @handle, avatar. */
  _kicker = label(@"Wyrm", 10.5, 700, QUIET);
  track(_kicker, 1);
  _nickname = WField(@"Wyrm Player", 29, 700, NO);
  _nickname.placeholderAttributedString = [[NSAttributedString alloc] initWithString:@"Wyrm Player"
      attributes:@{NSFontAttributeName: body(29, 700), NSForegroundColorAttributeName: FAINT}];
  _nickname.stringValue = [WStore nickname];
  _nickname.delegate = self;
  _nicknameHint = label(@"Click to rename in-game name", 9.5, 400, [QUIET colorWithAlphaComponent:0.55]);
  _who = label(@"", 12, 700, INK);
  _who.alignment = NSTextAlignmentRight;
  _whoDetail = label(@"", 10.5, 400, QUIET);
  _whoDetail.alignment = NSTextAlignmentRight;
  _avatar = [[WAvatar alloc] initWithFrame:NSZeroRect];
  _avatar.corner = 10.8;
  _bell = [WTap new];
  _bell.fill = CARD;
  _bell.hover = WELL;
  _bell.layer.cornerRadius = 20;
  _bell.layer.borderWidth = 1;
  _bell.layer.borderColor = RULE.CGColor;
  NSImageView* bellIcon = glyph(@"bell.badge", 15, INK);
  place(bellIcon, 10, 10, 20, 20);
  [_bell addSubview:bellIcon];
  _bell.onClick = ^{ if (weak.onAlerts) weak.onAlerts(); };
  _bellBadge = label(@"", 10, 700, NSColor.whiteColor);
  _bellBadge.alignment = NSTextAlignmentCenter;
  _bellBadge.wantsLayer = YES;
  _bellBadge.drawsBackground = YES;
  _bellBadge.backgroundColor = BADGE;
  _bellBadge.layer.cornerRadius = 8;
  _bellBadge.layer.masksToBounds = YES;
  for (NSView* v in @[_kicker, _nickname, _nicknameHint, _who, _whoDetail, _avatar, _bell, _bellBadge]) [self addSubview:v];

  /* Android's IosArenaCard, with the account's metrics under it. */
  _arenaCard = [WCard new];
  _liveDot = [NSView new];
  _liveDot.wantsLayer = YES;
  _liveDot.layer.cornerRadius = 3;
  _liveLabel = label(@"ARENA DIRECTORY", 10.5, 700, QUIET);
  _arenaTitle = label(@"Pick a server", 21, 700, INK);
  _arenaPlayers = label(@"", 11.5, 400, QUIET);
  _arenaPlayers.alignment = NSTextAlignmentRight;
  _arenaDetail = label(@"", 12.5, 400, MUTE);
  _barTrack = [NSView new];
  _barTrack.wantsLayer = YES;
  _barTrack.layer.backgroundColor = TRACK.CGColor;
  _barTrack.layer.cornerRadius = 2;
  _barFill = [NSView new];
  _barFill.wantsLayer = YES;
  _barFill.layer.backgroundColor = INK.CGColor;
  _barFill.layer.cornerRadius = 2;
  [_barTrack addSubview:_barFill];
  _enter = [WButton primary:@"Enter lobby"];
  _enter.pressScale = YES;
  /* IosArenaCard's server button: a hairline square with the globe. */
  _pick = [WButton well:@"globe" text:nil];
  _pick.fill = NSColor.clearColor;
  _pick.hover = [INK colorWithAlphaComponent:0.05];
  _pick.layer.borderWidth = 1;
  _pick.layer.borderColor = RULE.CGColor;
  _pick.icon.image = symbol(@"globe", 17, NSFontWeightSemibold);
  _pick.icon.contentTintColor = MUTE;
  _enter.onClick = ^{ if (server_address_is_valid(chosenEndpoint.UTF8String)) { if (weak.onEnter) weak.onEnter(); } else if (weak.onPick) weak.onPick(); };
  _pick.onClick = ^{ if (weak.onPick) weak.onPick(); };
  _arenaRule = rule();
  _metricRule = rule();
  _best = [WMetric metric:@"BEST SCORE"];
  _kills = [WMetric metric:@"TOTAL KILLS"];
  for (NSView* v in @[_liveDot, _liveLabel, _arenaTitle, _arenaPlayers, _arenaDetail, _barTrack, _enter, _pick,
                      _arenaRule, _metricRule, _best, _kills]) [_arenaCard addSubview:v];
  [self addSubview:_arenaCard];

  _lastLabel = section(@"Last run");
  _lastCard = [WCard new];
  _last = @[[WMetric metric:@"SCORE"], [WMetric metric:@"KILLS"], [WMetric metric:@"TIME"]];
  _lastRules = @[rule(), rule()];
  for (NSView* v in [(NSArray<NSView*>*)_last arrayByAddingObjectsFromArray:_lastRules]) [_lastCard addSubview:v];
  [self addSubview:_lastLabel];
  [self addSubview:_lastCard];
  _notice = label(@"", 14, 400, BADGE);
  [self addSubview:_notice];

  /* Loadout: Food, Mode and Near Original, as Desktop's Home. */
  _loadoutLabel = section(@"Loadout");
  _loadoutCard = [WCard new];
  WSetting* food = [WEngine named:@"normal.food_type"];
  NSString* foodLabel = food && food.index < (NSInteger)food.options.count ? food.options[food.index] : @"Original";
  WFoodWell* pellets = [[WFoodWell alloc] initWithFrame:NSMakeRect(0, 0, 26, 26)];
  WHomeRow* foodRow = homeRow(pellets, @"Food", nil, foodLabel, YES, ^{ [NSNotificationCenter.defaultCenter postNotificationName:@"WyrmOpenSettings" object:@4]; });
  WHomeRow* modeRow = homeRow(loadoutIcon(@"scope", nil), @"Mode", nil, @"", NO, ^{ [NSNotificationCenter.defaultCenter postNotificationName:@"WyrmOpenSettings" object:@2]; });
  _nearSwitch = [WSwitch new];
  _nearSwitch.frame = NSMakeRect(0, 0, 63, 28);
  _nearSwitch.on = [WStore nearOriginal];
  _nearSwitch.onToggle = ^(BOOL on) { [WStore setNearOriginal:on]; };
  WHomeRow* nearRow = homeRow(loadoutIcon(@"arrow.clockwise", nil), @"Near Original",
                              @"Slither's own minimap, leaderboard and HUD. The mouse and your keys still steer.", nil, NO,
                              ^{ [weak.nearSwitch click]; });
  nearRow.pressScale = NO;
  nearRow.trailing = _nearSwitch;
  [nearRow addSubview:_nearSwitch];
  [nearRow.value removeFromSuperview];
  [nearRow.chevron removeFromSuperview];
  _loadout = @[foodRow, modeRow, nearRow];
  for (NSView* v in _loadout) [_loadoutCard addSubview:v];
  [self addSubview:_loadoutLabel];
  [self addSubview:_loadoutCard];

  _roomsLabel = section(@"Rooms & team");
  _roomsCard = [WCard new];
  _team = homeRow(loadoutIcon(@"person.2", LIVE), @"Team mode", @"Connect your NTL team", @"Open", YES, ^{
    weak.notice.stringValue = @"Team mode comes to Wyrm for Mac next.";
    [weak setNeedsLayout:YES];
  });
  [_roomsCard addSubview:_team];
  [self addSubview:_roomsLabel];
  [self addSubview:_roomsCard];
  [self refreshAccount];
  [self showLastRun];
  [self refreshArena];
  return self;
}

/* Android keeps the name to 24 UTF-8 bytes, sent as typed (blank is allowed). */
- (void)controlTextDidChange:(NSNotification*)note {
  NSString* text = self.nickname.stringValue;
  while ([text lengthOfBytesUsingEncoding:NSUTF8StringEncoding] > 24)
    text = [text substringToIndex:[text rangeOfComposedCharacterSequenceAtIndex:text.length - 1].location];
  if (![text isEqualToString:self.nickname.stringValue]) self.nickname.stringValue = text;
}
- (void)controlTextDidEndEditing:(NSNotification*)note {
  [WStore setNickname:self.nickname.stringValue chosen:YES];
  [self.window makeFirstResponder:nil];
}
- (void)refreshAccount {
  WAccount* a = [WAccount shared];
  NSString* name = a.displayName;
  self.who.stringValue = name;
  self.whoDetail.stringValue = a.handle;
  [self.avatar setURL:a.avatarURL initials:WInitials(name)];
  [self.best setNumber:a.player ? grouped(a.highestScore) : @"0"];
  [self.kills setNumber:a.player ? grouped(a.kills) : @"0"];
  NSInteger unread = 0;
  for (NSDictionary* n in alertRows) if (![n[@"read"] boolValue]) unread++;
  self.bellBadge.stringValue = unread > 99 ? @"99+" : [NSString stringWithFormat:@"%ld", (long)unread];
  self.bellBadge.hidden = unread == 0;
  [self setNeedsLayout:YES];
}
- (void)showLastRun {
  for (NSView* v in @[self.lastLabel, self.lastCard]) v.hidden = !hasLastRun;
  [self.last[0] setNumber:grouped(lastScore)];
  [self.last[1] setNumber:grouped(lastKills)];
  [self.last[2] setNumber:timeText(lastSeconds)];
  [self setNeedsLayout:YES];
}
- (void)choose:(NSString*)endpoint {
  chosenEndpoint = endpoint ?: @"";
  [self refreshArena];
}
/* Desktop's arenaTitle: "Arena 4817" with its flag, a typed custom one, or "Pick a server". */
- (void)refreshArena {
  int count = wyrm_mac_arena_count(), players = -1;
  __weak WPlayPage* weak = self;
  if (!chosenEndpoint.length) {
    const char* saved = wyrm_mac_saved_arena();
    if (saved && server_address_is_valid(saved)) chosenEndpoint = @(saved);
  }
  if (!chosenEndpoint.length && count) {
    int best = 0, most = -1;
    for (int i = 0; i < count; i++) {
      int p;
      wyrm_mac_arena(i, &p);
      if (p > most) { most = p; best = i; }
    }
    chosenEndpoint = @(wyrm_mac_arena(best, NULL));
  }
  for (int i = 0; i < count; i++) {
    int p;
    if (!strcmp(wyrm_mac_arena(i, &p), chosenEndpoint.UTF8String)) players = p;
  }
  BOOL live = players >= 0, valid = server_address_is_valid(chosenEndpoint.UTF8String);
  WArena* arena = liveArenaFor(chosenEndpoint);
  NSMutableArray* addresses = [NSMutableArray new];
  for (WArena* a in liveArenas()) [addresses addObject:a.address];
  loadCountries(addresses, ^{ [weak refreshArena]; });
  self.liveDot.layer.backgroundColor = (live ? LIVE : QUIET).CGColor;
  self.liveLabel.stringValue = live ? @"LIVE ARENA" : @"ARENA DIRECTORY";
  self.liveLabel.textColor = live ? LIVE : QUIET;
  track(self.liveLabel, 0.8);
  self.arenaTitle.stringValue = arena ? arena.title : valid ? @"Custom arena" : @"Pick a server";
  [self.arenaFlag removeFromSuperview];
  self.arenaFlag = arena && arena.ident >= 0 ? countryBadge(countryOf(arena.address), ^{ [weak refreshArena]; }) : nil;
  if (self.arenaFlag) [self.arenaCard addSubview:self.arenaFlag];
  self.arenaPlayers.stringValue = valid ? [NSString stringWithFormat:@"%d players", MAX(0, players)] : @"";
  self.arenaDetail.stringValue = valid ? chosenEndpoint : @"Choose a live arena or enter an address.";
  self.barFill.hidden = !live || players <= 0;
  self.barFraction = MIN(1.0, MAX(0, players) / 2000.0);
  self.enter.fill = valid ? INK : [INK colorWithAlphaComponent:0.35];
  [self setNeedsLayout:YES];
}

/* Desktop's Home: the header across, then two columns (max 1180). */
- (CGFloat)layoutForWidth:(CGFloat)width {
  CGFloat maxW = MIN(1180, width), x0 = (width - maxW) / 2 + 28, inner = maxW - 56;
  CGFloat y = 92;
  /* Header: padding 20 / 15. */
  CGFloat hx = x0 + 20, hw = inner - 40;
  placeLabel(self.kicker, hx, y + 15, 0);
  CGFloat ny = y + 15 + self.kicker.frame.size.height;
  CGFloat fh = fieldHeight(self.nickname);
  place(self.nickname, hx - 2, ny + 4, hw - 300, fh);
  placeLabel(self.nicknameHint, hx, ny + 4 + fh + 1, 0);
  CGFloat bottom = NSMaxY(self.nicknameHint.frame);
  CGFloat ax = hx + hw - 4 - 36;
  place(self.avatar, ax, bottom - 36 - 2, 36, 36);
  [self.who sizeToFit];
  [self.whoDetail sizeToFit];
  CGFloat nw = MIN(220, MAX(self.who.frame.size.width, self.whoDetail.frame.size.width));
  CGFloat nameBlock = self.who.frame.size.height + (self.whoDetail.stringValue.length ? self.whoDetail.frame.size.height : 0);
  CGFloat nyy = NSMidY(self.avatar.frame) - nameBlock / 2;
  place(self.who, ax - 9 - nw, nyy, nw, self.who.frame.size.height);
  place(self.whoDetail, ax - 9 - nw, nyy + self.who.frame.size.height, nw, self.whoDetail.frame.size.height);
  CGFloat bx = ax - 9 - nw - 4 - 16 - 40;
  place(self.bell, bx, NSMidY(self.avatar.frame) - 20, 40, 40);
  [self.bellBadge sizeToFit];
  CGFloat bw = MAX(16, self.bellBadge.frame.size.width + 8);
  place(self.bellBadge, bx + 40 - bw + 4, NSMidY(self.avatar.frame) - 24, bw, 16);
  y = bottom + 15;

  CGFloat colW = (inner - 24) / 2, lx = x0, rx = x0 + colW + 24;
  /* IosPaperCard has 16 aside inside its column. */
  CGFloat cw = colW - 32, top = y;
  {
    CGFloat p = 18, w = cw - p * 2, cy = p;
    place(self.liveDot, p, cy + 4, 6, 6);
    placeLabel(self.liveLabel, p + 12, cy, 0);
    cy += 14 + 11;
    placeLabel(self.arenaPlayers, p, cy + 12, w);
    [self.arenaTitle sizeToFit];
    CGFloat flagW = self.arenaFlag ? 8 + self.arenaFlag.frame.size.width : 0;
    CGFloat titleW = MIN(self.arenaTitle.frame.size.width, w - 110 - flagW);
    place(self.arenaTitle, p, cy, titleW, self.arenaTitle.frame.size.height);
    if (self.arenaFlag)
      place(self.arenaFlag, p + titleW + 8, cy + (self.arenaTitle.frame.size.height - 14) / 2, self.arenaFlag.frame.size.width, 14);
    cy += 28 + 3;
    placeLabel(self.arenaDetail, p, cy, w);
    cy += 17 + 13;
    place(self.barTrack, p, cy, w, 4);
    place(self.barFill, 0, 0, w * self.barFraction, 4);
    cy += 4 + 16;
    place(self.enter, p, cy, w - 46 - 9, 46);
    place(self.pick, p + w - 46, cy, 46, 46);
    cy += 46 + p;
    place(self.arenaRule, 0, cy, cw, 1);
    cy += 1;
    place(self.best, 0, cy, cw / 2, 64);
    place(self.metricRule, cw / 2, cy + 7, 1, 50);
    place(self.kills, cw / 2 + 1, cy, cw / 2 - 1, 64);
    cy += 64;
    place(self.arenaCard, lx + 16, top, cw, cy);
    y = top + cy;
  }
  if (hasLastRun) {
    placeLabel(self.lastLabel, lx + 20, y + 22, 0);
    y += 22 + self.lastLabel.frame.size.height + 8;
    CGFloat third = cw / 3;
    for (int i = 0; i < 3; i++) place(self.last[i], third * i + (i ? 1 : 0), 0, third - (i ? 1 : 0), 64);
    place(self.lastRules[0], third, 7, 1, 50);
    place(self.lastRules[1], third * 2, 7, 1, 50);
    place(self.lastCard, lx + 16, y, cw, 64);
    y += 64;
  }
  if (self.notice.stringValue.length) {
    placeLabel(self.notice, lx + 32, y + 12, cw - 32);
    y += 12 + self.notice.frame.size.height;
  }
  CGFloat leftBottom = y;
  y = top - 22 - 13 - 8;
  placeLabel(self.loadoutLabel, rx + 20, y + 22, 0);
  y += 22 + self.loadoutLabel.frame.size.height + 8;
  CGFloat ly = 0;
  for (WHomeRow* r in self.loadout) {
    CGFloat h = r.detail ? MAX(52, 20 + lineH(r.title) + 1 + wrapHeight(r.detail, cw - 52 - 14 - 63 - 10)) : 52;
    place(r, 0, ly, cw, h);
    [r setNeedsLayout:YES];
    ly += h;
  }
  place(self.loadoutCard, rx + 16, y, cw, ly);
  y += ly;
  placeLabel(self.roomsLabel, rx + 20, y + 22, 0);
  y += 22 + self.roomsLabel.frame.size.height + 8;
  place(self.team, 0, 0, cw, 62);
  place(self.roomsCard, rx + 16, y, cw, 62);
  y += 62;
  return MAX(leftBottom, y) + 32;
}
- (void)layout {
  [super layout];
  CGFloat h = [self layoutForWidth:self.bounds.size.width];
  NSScrollView* scroll = self.enclosingScrollView;
  CGFloat want = MAX(h, scroll ? scroll.contentSize.height : h);
  if (fabs(self.frame.size.height - want) > 0.5) [self setFrameSize:NSMakeSize(self.frame.size.width, want)];
}
@end

#pragma mark - Ready Room (Desktop's lobby)

@interface WLobby : WFlipped <NSTextFieldDelegate>
@property(strong) WMark* mark;
@property(strong) NSView* column;
@property(strong) NSTextField *kicker, *title, *address, *players, *name;
@property(strong) WTap* arenaCard;
@property(strong) WFlipped* nameCard;
@property(strong) NSTextField* lastStrip;
@property(strong) WButton *home, *ai, *play;
@property BOOL entering;
@property(copy) void (^onHome)(void);
@property(copy) void (^onPick)(void);
@end
@implementation WLobby
static WButton* lobbyButton(NSString* text, NSString* icon) {
  WButton* b = [WButton well:icon text:text];
  b.fill = CARD;
  b.hover = WELL;
  b.pressScale = YES;
  b.layer.cornerRadius = 27;
  b.layer.borderWidth = 1;
  b.layer.borderColor = RULE.CGColor;
  b.title.font = body(14.5, 700);
  b.icon.image = symbol(icon, 15, NSFontWeightSemibold);
  return b;
}
- (instancetype)init {
  if (!(self = [super initWithFrame:NSZeroRect])) return nil;
  self.wantsLayer = YES;
  self.layer.backgroundColor = PAPER.CGColor;
  __weak WLobby* weak = self;
  _mark = [[WMark alloc] initWithFrame:NSZeroRect];
  _mark.markSize = 520;
  _mark.alphaValue = 0.045;
  [self addSubview:_mark];
  _column = [WFlipped new];
  [self addSubview:_column];
  _kicker = label(@"READY ROOM", 11.5, 700, QUIET);
  _kicker.alignment = NSTextAlignmentCenter;
  track(_kicker, 1.6);
  _title = label(@"Enter the arena", 36, 700, INK);
  _title.alignment = NSTextAlignmentCenter;
  track(_title, -0.8);
  _arenaCard = [WTap new];
  _arenaCard.fill = CARD;
  _arenaCard.hover = CARD;
  _arenaCard.pressScale = YES;
  _arenaCard.layer.cornerRadius = 20;
  _arenaCard.layer.borderWidth = 1;
  _arenaCard.layer.borderColor = RULE.CGColor;
  _arenaCard.onClick = ^{ if (weak.onPick) weak.onPick(); };
  NSTextField* selected = label(@"SELECTED ARENA", 11, 700, QUIET);
  track(selected, 1.3);
  selected.identifier = @"k";
  NSTextField* change = label(@"Change", 13, 600, LINK);
  change.identifier = @"change";
  _address = label(@"", 36, 400, INK);
  _address.font = display(36, 400);
  _players = label(@"", 13, 700, INK);
  for (NSView* v in @[selected, change, _address, _players]) [_arenaCard addSubview:v];
  _nameCard = [WFlipped new];
  _nameCard.wantsLayer = YES;
  _nameCard.layer.backgroundColor = CARD.CGColor;
  _nameCard.layer.cornerRadius = 20;
  _nameCard.layer.borderWidth = 1;
  _nameCard.layer.borderColor = RULE.CGColor;
  NSTextField* playing = label(@"PLAYING AS", 11, 700, QUIET);
  track(playing, 1.3);
  playing.identifier = @"k";
  _name = WField(@"Wyrm Player", 32, 400, NO);
  _name.font = display(32, 400);
  _name.placeholderAttributedString = [[NSAttributedString alloc] initWithString:@"Wyrm Player"
      attributes:@{NSFontAttributeName: display(32, 400), NSForegroundColorAttributeName: FAINT}];
  _name.stringValue = [WStore nickname];
  _name.delegate = self;
  [_nameCard addSubview:playing];
  [_nameCard addSubview:_name];
  _lastStrip = label(@"", 13, 400, MUTE);
  _lastStrip.wantsLayer = YES;
  _home = lobbyButton(@"Home", @"house");
  _home.onClick = ^{ if (weak.onHome) weak.onHome(); };
  _ai = lobbyButton(@"Play with AI", @"cpu");
  _ai.onClick = ^{ [weak playAI]; };
  _play = [WButton capsule:@"PLAY" filled:YES];
  _play.title.font = body(16, 700);
  track(_play.title, 2.4);
  _play.onClick = ^{ [weak playOnline]; };
  for (NSView* v in @[_kicker, _title, _arenaCard, _nameCard, _lastStrip, _home, _ai, _play]) [_column addSubview:v];
  [self refresh];
  return self;
}
- (BOOL)acceptsFirstResponder { return YES; }
- (void)keyDown:(NSEvent*)e {
  if (e.keyCode == 36 || e.keyCode == 76) [self playOnline];
  else if (e.keyCode == 53 && self.onHome) self.onHome();
}
- (BOOL)control:(NSControl*)c textView:(NSTextView*)v doCommandBySelector:(SEL)cmd {
  if (cmd == @selector(insertNewline:)) { [self playOnline]; return YES; }
  if (cmd == @selector(cancelOperation:)) { if (self.onHome) self.onHome(); return YES; }
  return NO;
}
- (void)controlTextDidChange:(NSNotification*)n {
  NSString* text = self.name.stringValue;
  while ([text lengthOfBytesUsingEncoding:NSUTF8StringEncoding] > 24)
    text = [text substringToIndex:[text rangeOfComposedCharacterSequenceAtIndex:text.length - 1].location];
  if (![text isEqualToString:self.name.stringValue]) self.name.stringValue = text;
  [WStore setNickname:text chosen:YES];
}
- (void)refresh {
  self.address.stringValue = chosenEndpoint.length ? chosenEndpoint : @"Pick an arena";
  self.address.textColor = chosenEndpoint.length ? INK : QUIET;
  int players = -1;
  for (int i = 0; i < wyrm_mac_arena_count(); i++) { int p; if (!strcmp(wyrm_mac_arena(i, &p), chosenEndpoint.UTF8String)) players = p; }
  self.players.stringValue = players >= 0 ? [NSString stringWithFormat:@"PLAYING   %d", players] : @"";
  self.lastStrip.hidden = !hasLastRun;
  self.lastStrip.stringValue = [NSString stringWithFormat:@"LAST RUN        Score %@     Kills %d     Time %@", grouped(lastScore), lastKills, timeText(lastSeconds)];
  BOOL ready = server_address_is_valid(chosenEndpoint.UTF8String);
  self.play.enabled = ready && !self.entering;
  self.play.title.stringValue = self.entering ? @"Entering…" : @"PLAY";
  [self setNeedsLayout:YES];
}
- (void)playOnline {
  if (!server_address_is_valid(chosenEndpoint.UTF8String) || self.entering) return;
  self.entering = YES;
  [self refresh];
  [WStore setNickname:self.name.stringValue chosen:YES];
  [[WAccount shared] syncIngameName:self.name.stringValue];
  /* The picker's "Recently joined" (Android's RecentArenas.push on Play). */
  pushRecentArena(chosenEndpoint);
  probesSetOpen(NO);
  wyrm_mac_play(self.name.stringValue.UTF8String, chosenEndpoint.UTF8String, false);
}
- (void)playAI {
  if (self.entering) return;
  self.entering = YES;
  [self refresh];
  wyrm_mac_play((self.name.stringValue.length ? self.name.stringValue : @"Wyrm Player").UTF8String, "", true);
}
- (void)viewDidMoveToWindow {
  if (!self.window) return;
  self.entering = NO;
  [self refresh];
  [self layoutSubtreeIfNeeded];
  /* Everything arrives out of a blur, as the sign-in does (620 ms). */
  WMaterialise(self.column, YES, 14, 0.62, 1, nil);
  [self.window makeFirstResponder:self];
}
- (void)layout {
  [super layout];
  NSSize s = self.bounds.size;
  place(self.mark, (s.width - 832) / 2, (s.height - 832) / 2, 832, 832);
  CGFloat w = 600, y = 0;
  placeLabel(self.kicker, 0, y, w);
  y += self.kicker.frame.size.height + 4;
  placeLabel(self.title, 0, y, w);
  y += self.title.frame.size.height + 28;
  CGFloat cy = 20;
  for (NSView* v in self.arenaCard.subviews) {
    if ([v.identifier isEqualToString:@"k"]) placeLabel((NSTextField*)v, 26, cy, 0);
    if ([v.identifier isEqualToString:@"change"]) { [(NSTextField*)v sizeToFit]; place(v, w - 26 - v.frame.size.width, cy, v.frame.size.width, v.frame.size.height); }
  }
  cy += 22;
  placeLabel(self.address, 26, cy, w - 52);
  cy += self.address.frame.size.height;
  if (self.players.stringValue.length) { placeLabel(self.players, 26, cy + 12, 0); cy += 12 + self.players.frame.size.height; }
  cy += 20;
  place(self.arenaCard, 0, y, w, cy);
  y += cy + 14;
  CGFloat ny = 18;
  for (NSView* v in self.nameCard.subviews) if ([v.identifier isEqualToString:@"k"]) placeLabel((NSTextField*)v, 26, ny, 0);
  ny += 22;
  CGFloat fh = fieldHeight(self.name);
  place(self.name, 24, ny, w - 50, fh);
  ny += fh + 18;
  place(self.nameCard, 0, y, w, ny);
  y += ny;
  if (!self.lastStrip.hidden) {
    y += 14;
    placeLabel(self.lastStrip, 22, y + 12, w - 44);
    y += self.lastStrip.frame.size.height + 24;
  }
  y += 30;
  CGFloat bx = (w - (128 + 10 + 170 + 10 + 220)) / 2;
  place(self.home, bx, y + 2, 128, 54);
  place(self.ai, bx + 138, y + 2, 170, 54);
  place(self.play, bx + 318, y, 220, 58);
  y += 58;
  place(self.column, (s.width - w) / 2, (s.height - y) / 2, w, y);
}
@end

#pragma mark - Alerts (a glass panel from the right)

@interface WAlerts : WFlipped
@property(strong) NSView* panel;
@property(strong) WFlipped* inside;
@property(strong) NSScrollView* scroll;
@property(copy) void (^onClose)(void);
@end
@implementation WAlerts
- (instancetype)init {
  if (!(self = [super initWithFrame:NSZeroRect])) return nil;
  self.wantsLayer = YES;
  self.layer.backgroundColor = rgba(0x38000000).CGColor;
  _inside = [WFlipped new];
  if (@available(macOS 26.0, *)) {
    NSGlassEffectView* g = [NSGlassEffectView new];
    g.cornerRadius = 26;
    g.tintColor = [PAPER colorWithAlphaComponent:0.8];
    g.contentView = _inside;
    _panel = g;
  } else {
    _panel = [WFlipped new];
    _panel.wantsLayer = YES;
    _panel.layer.backgroundColor = PAPER.CGColor;
    _panel.layer.cornerRadius = 26;
    [_panel addSubview:_inside];
  }
  [self addSubview:_panel];
  _scroll = [NSScrollView new];
  _scroll.drawsBackground = NO;
  _scroll.hasVerticalScroller = NO;
  _scroll.autohidesScrollers = YES;
  [_inside addSubview:_scroll];
  [self rebuild];
  WApi(@"GET", @"/v1/notifications", nil, YES, ^(id json, NSInteger s, NSString* e) {
    if (e) return;
    alertRows = [json[@"notifications"] isKindOfClass:NSArray.class] ? json[@"notifications"] : @[];
    [self rebuild];
    [NSNotificationCenter.defaultCenter postNotificationName:WAccountChanged object:nil];
  });
  return self;
}
- (BOOL)acceptsFirstResponder { return YES; }
- (void)keyDown:(NSEvent*)e { if (e.keyCode == 53 && self.onClose) self.onClose(); }
- (void)mouseDown:(NSEvent*)e { if (!NSPointInRect([self convertPoint:e.locationInWindow fromView:nil], self.panel.frame) && self.onClose) self.onClose(); }
- (void)rebuild {
  for (NSView* v in self.inside.subviews.copy) if (v != self.scroll) [v removeFromSuperview];
  NSTextField* kicker = label(@"INBOX", 10.5, 700, QUIET);
  track(kicker, 1);
  NSTextField* title = label(@"Alerts", 26, 700, INK);
  WButton* read = [WButton well:nil text:@"Read all"];
  read.fill = NSColor.clearColor;
  read.title.textColor = LINK;
  read.onClick = ^{
    WApi(@"POST", @"/v1/notifications/read", nil, YES, ^(id j, NSInteger s, NSString* e) {});
    NSMutableArray* rows = [NSMutableArray new];
    for (NSDictionary* n in alertRows) { NSMutableDictionary* m = [n mutableCopy]; m[@"read"] = @YES; [rows addObject:m]; }
    alertRows = rows;
    [self rebuild];
    [NSNotificationCenter.defaultCenter postNotificationName:WAccountChanged object:nil];
  };
  for (NSView* v in @[kicker, title, read]) { v.identifier = @"head"; [self.inside addSubview:v]; }
  WFlipped* list = [WFlipped new];
  CGFloat w = 360, y = 0;
  if (!alertRows.count) {
    NSTextField* none = wrapLabel(alertRows ? @"Nothing new. Notices, events and replies from Wyrm land here." : @"Loading…", 14, 400, QUIET);
    y += placeWrap(none, 4, 8, w - 8) + 16;
    [list addSubview:none];
  }
  for (NSDictionary* n in alertRows) {
    WCard* c = [[WCard alloc] initWithRadius:16];
    c.layer.shadowOpacity = 0;
    NSString* kind = [n[@"kind"] isKindOfClass:NSString.class] ? [n[@"kind"] uppercaseString] : @"BROADCAST";
    NSTextField* k = label([kind stringByReplacingOccurrencesOfString:@"_" withString:@" "], 9.5, 700, [n[@"read"] boolValue] ? QUIET : LIVE);
    track(k, 0.8);
    NSTextField* t = wrapLabel([n[@"title"] isKindOfClass:NSString.class] ? n[@"title"] : @"", 15, 700, INK);
    NSTextField* b = wrapLabel([n[@"body"] isKindOfClass:NSString.class] ? n[@"body"] : @"", 13, 400, MUTE);
    lineHeight(b, 19, NSTextAlignmentLeft);
    CGFloat cy = 14;
    placeLabel(k, 14, cy, w - 28);
    cy += k.frame.size.height + 4;
    cy += placeWrap(t, 14, cy, w - 28) + 4;
    cy += placeWrap(b, 14, cy, w - 28) + 14;
    for (NSView* v in @[k, t, b]) [c addSubview:v];
    place(c, 0, y, w, cy);
    [list addSubview:c];
    y += cy + 10;
  }
  list.frame = NSMakeRect(0, 0, w, y);
  self.scroll.documentView = list;
  [self setNeedsLayout:YES];
}
- (void)layout {
  [super layout];
  NSSize s = self.bounds.size;
  CGFloat w = 400, h = s.height - 32;
  place(self.panel, s.width - w - 16, 16, w, h);
  if (@available(macOS 26.0, *)) {} else place(self.inside, 0, 0, w, h);
  CGFloat y = 22;
  for (NSView* v in self.inside.subviews) {
    if (![v.identifier isEqualToString:@"head"]) continue;
    if ([v isKindOfClass:WButton.class]) { place(v, w - 20 - 90, 30, 90, 32); continue; }
    placeLabel((NSTextField*)v, 20, y, 0);
    y += v.frame.size.height;
  }
  place(self.scroll, 20, y + 14, w - 40, h - y - 30);
}
- (void)viewDidMoveToWindow {
  if (!self.window) return;
  [self layoutSubtreeIfNeeded];
  CABasicAnimation* slide = [CABasicAnimation animationWithKeyPath:@"transform.translation.x"];
  slide.fromValue = @(self.panel.frame.size.width + 20);
  slide.toValue = @0;
  slide.duration = 0.38;
  slide.timingFunction = [CAMediaTimingFunction functionWithControlPoints:0.22 :0.8 :0.24 :1];
  self.panel.wantsLayer = YES;
  [self.panel.layer addAnimation:slide forKey:@"in"];
  [self.window makeFirstResponder:self];
}
@end

/* The tabs not ported yet (one page at a time). */
@interface WSoonPage : WFlipped
@property(strong) NSTextField *title, *detail;
@property(strong) NSImageView* icon;
@end
@implementation WSoonPage
- (instancetype)init {
  if ((self = [super initWithFrame:NSZeroRect])) {
    _icon = glyph(@"sparkles", 30, FAINT);
    _title = label(@"", 29, 700, INK);
    _title.alignment = NSTextAlignmentCenter;
    _detail = label(@"Coming to Wyrm for Mac next.", 14, 400, QUIET);
    _detail.alignment = NSTextAlignmentCenter;
    for (NSView* v in @[_icon, _title, _detail]) [self addSubview:v];
  }
  return self;
}
- (void)show:(int)tab {
  self.title.stringValue = TabNames[tab];
  self.icon.image = symbol(TabSymbols[tab], 30, NSFontWeightSemibold);
  [self setNeedsLayout:YES];
}
- (void)layout {
  [super layout];
  NSSize s = self.bounds.size;
  CGFloat y = s.height / 2 - 60;
  place(self.icon, (s.width - 40) / 2, y, 40, 40);
  placeLabel(self.title, 20, y + 52, s.width - 40);
  placeLabel(self.detail, 20, y + 94, s.width - 40);
}
@end

#pragma mark - Arena picker (Wyrm Desktop's ArenaPicker: a sheet over a dim, not glass)

/* One arena: its code, flag and tag, its address, its latency (and Remove for a saved one). */
@interface WArenaRowView : WTap
@property BOOL chosen;
@end
@implementation WArenaRowView
- (void)refresh {
  [super refresh];
  self.alphaValue = 1;
  self.layer.backgroundColor = (self.inside && !self.chosen ? CARD : [CARD colorWithAlphaComponent:0.9 * CARD.alphaComponent]).CGColor;
}
@end

@interface WPicker : WFlipped <NSTextFieldDelegate>
@property(strong) WFlipped *panel, *panelClip, *list, *addBox;
@property(strong) NSScrollView* scroll;
@property(strong) NSTextField *status, *search, *custom;
@property(strong) WTap *plus, *closeLink;
@property(strong) NSImageView* plusIcon;
@property(strong) NSView* searchBox;
@property(strong) NSMutableDictionary<NSString*, NSNumber*>* pings;
@property(strong) NSArray<NSString*>* saved;
@property(strong) NSArray<NSString*>* recent;
@property BOOL showAll, showSaved, showAdd, addressError, rebuildQueued, closing;
@property(copy) void (^onChoose)(NSString*);
@property(copy) void (^onClose)(void);
@end

@implementation WPicker
- (instancetype)init {
  if (!(self = [super initWithFrame:NSZeroRect])) return nil;
  self.wantsLayer = YES;
  self.layer.backgroundColor = [NSColor colorWithWhite:0 alpha:0.22].CGColor;
  _pings = [NSMutableDictionary new];
  _saved = savedArenas();
  _recent = recentArenas();
  __weak WPicker* weak = self;
  /* GlassSheet = paperPanel: paper at 97%, a hairline, a soft deep shadow, corners 26. */
  _panel = [WFlipped new];
  _panel.wantsLayer = YES;
  _panel.layer.cornerRadius = 26;
  _panel.layer.cornerCurve = kCACornerCurveContinuous;
  _panel.layer.shadowColor = NSColor.blackColor.CGColor;
  _panel.layer.shadowOpacity = 0.22;
  _panel.layer.shadowRadius = 24;
  _panel.layer.shadowOffset = CGSizeMake(0, -10);
  _panelClip = [WFlipped new];
  _panelClip.wantsLayer = YES;
  _panelClip.layer.cornerRadius = 26;
  _panelClip.layer.cornerCurve = kCACornerCurveContinuous;
  _panelClip.layer.masksToBounds = YES;
  _panelClip.layer.backgroundColor = [PAPER colorWithAlphaComponent:0.97].CGColor;
  _panelClip.layer.borderWidth = 1;
  _panelClip.layer.borderColor = RULE.CGColor;
  [_panel addSubview:_panelClip];
  [self addSubview:_panel];

  NSTextField* kicker = label(@"LIVE DIRECTORY", 10, 700, LIVE);
  track(kicker, 1);
  kicker.identifier = @"kicker";
  NSTextField* title = label(@"Pick a server", 27, 700, INK);
  title.identifier = @"title";
  _status = label(@"", 12, 400, QUIET);
  _plus = [WTap new];
  _plus.layer.cornerRadius = 18;
  _plus.layer.borderWidth = 1;
  _plus.layer.borderColor = RULE.CGColor;
  _plusIcon = glyph(@"plus", 15, INK);
  [_plus addSubview:_plusIcon];
  _plus.onClick = ^{ weak.showAdd = !weak.showAdd; weak.addressError = NO; [weak paintPlus]; [weak rebuild]; };
  _closeLink = [WTap new];
  _closeLink.fill = NSColor.clearColor;
  _closeLink.hover = NSColor.clearColor;
  NSTextField* close = label(@"Close", 13, 600, LINK);
  [close sizeToFit];
  [_closeLink addSubview:close];
  _closeLink.frame = NSMakeRect(0, 0, close.frame.size.width + 8, close.frame.size.height + 16);
  place(close, 4, 8, close.frame.size.width, close.frame.size.height);
  _closeLink.onClick = ^{ if (weak.onClose) weak.onClose(); };

  _searchBox = [WFlipped new];
  _searchBox.wantsLayer = YES;
  _searchBox.layer.cornerRadius = 13;
  _searchBox.layer.cornerCurve = kCACornerCurveContinuous;
  _searchBox.layer.backgroundColor = [CARD colorWithAlphaComponent:0.82 * CARD.alphaComponent].CGColor;
  _searchBox.layer.borderWidth = 1;
  _searchBox.layer.borderColor = RULE.CGColor;
  NSImageView* magnifier = glyph(@"magnifyingglass", 13, INK);
  magnifier.identifier = @"magnifier";
  _search = WField(@"Arena code or IP", 13, 400, NO);
  _search.placeholderAttributedString = [[NSAttributedString alloc] initWithString:@"Arena code or IP"
      attributes:@{NSFontAttributeName: body(13, 400), NSForegroundColorAttributeName: [QUIET colorWithAlphaComponent:0.7]}];
  _search.delegate = self;
  [_searchBox addSubview:magnifier];
  [_searchBox addSubview:_search];

  _list = [WFlipped new];
  _scroll = [NSScrollView new];
  _scroll.drawsBackground = NO;
  _scroll.hasVerticalScroller = NO;
  _scroll.documentView = _list;
  for (NSView* v in @[kicker, title, _status, _plus, _closeLink, _searchBox, _scroll]) [_panelClip addSubview:v];
  [self paintPlus];

  /* Probes only while this sheet is open. */
  probesSetOpen(YES);
  [self reload];
  return self;
}
- (void)paintPlus {
  self.plus.fill = self.showAdd ? INK : CARD;
  self.plus.hover = self.showAdd ? INK : WELL;
  self.plusIcon.contentTintColor = self.showAdd ? ON_INK : INK;
}
- (BOOL)acceptsFirstResponder { return YES; }
- (void)cancelOperation:(id)sender { if (self.onClose) self.onClose(); }
- (void)keyDown:(NSEvent*)e { if (e.keyCode == 53 && self.onClose) self.onClose(); }
- (void)mouseDown:(NSEvent*)e {
  NSPoint p = [self convertPoint:e.locationInWindow fromView:nil];
  if (!NSPointInRect(p, self.panel.frame) && self.onClose) self.onClose();
}
- (void)scrollWheel:(NSEvent*)e {}
/* The directory (again), its countries, then a ping for every arena on screen. */
- (void)reload {
  __weak WPicker* weak = self;
  NSArray* live = liveArenas();
  NSMutableArray* addresses = [NSMutableArray new];
  for (WArena* a in live) [addresses addObject:a.address];
  loadCountries(addresses, ^{ [weak queueRebuild]; });
  NSMutableArray* endpoints = [NSMutableArray new];
  for (WArena* a in live) [endpoints addObject:a.endpoint];
  NSMutableSet* custom = [NSMutableSet new];
  for (NSString* e in [self.saved arrayByAddingObject:chosenEndpoint ?: @""]) {
    WArena* c = customArena(e);
    if (c && !liveArenaFor(c.endpoint)) { [custom addObject:c.endpoint]; [endpoints addObject:c.endpoint]; }
  }
  for (NSString* e in self.recent) if (!liveArenaFor(e) && [self.saved containsObject:e]) { [custom addObject:e]; [endpoints addObject:e]; }
  pingArenas(endpoints, custom, ^(NSString* e, int ms) {
    WPicker* me = weak;
    if (!me || me.closing) return;
    me.pings[e] = @(ms);
    [me queueRebuild];
  });
  [self rebuild];
}
- (void)queueRebuild {
  if (self.rebuildQueued) return;
  self.rebuildQueued = YES;
  __weak WPicker* weak = self;
  WAfter(0.12, ^{ weak.rebuildQueued = NO; [weak rebuild]; });
}
- (void)controlTextDidChange:(NSNotification*)note {
  if (note.object == self.custom) {
    NSString* t = [self.custom.stringValue stringByReplacingOccurrencesOfString:@"\n" withString:@""];
    if (t.length > 64) self.custom.stringValue = [t substringToIndex:64];
    if (self.addressError) { self.addressError = NO; [self rebuild]; }
    return;
  }
  if (self.search.stringValue.length > 64) self.search.stringValue = [self.search.stringValue substringToIndex:64];
  [self rebuild];
}
- (BOOL)control:(NSControl*)control textView:(NSTextView*)view doCommandBySelector:(SEL)command {
  if (control == self.custom && command == @selector(insertNewline:)) { [self saveCustom]; return YES; }
  if (command == @selector(cancelOperation:)) { if (self.onClose) self.onClose(); return YES; }
  return NO;
}
- (void)saveCustom {
  WArena* a = customArena(self.custom.stringValue ?: @"");
  if (!a) { self.addressError = YES; [self rebuild]; return; }
  self.addressError = NO;
  self.saved = saveArena(a.endpoint);
  self.showSaved = YES;
  self.showAdd = NO;
  [self paintPlus];
  [self.addBox removeFromSuperview];
  self.addBox = nil;
  self.custom = nil;
  [self reload];
}
- (void)pick:(WArena*)a {
  if (self.onChoose) self.onChoose(a.endpoint);
}
- (int)latency:(WArena*)a { NSNumber* n = self.pings[a.endpoint]; return n ? n.intValue : 0; }
- (BOOL)measured:(WArena*)a { return self.pings[a.endpoint] != nil; }
- (BOOL)matches:(WArena*)a {
  NSString* q = [self.search.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
  return !q.length || [a.endpoint containsString:q] || [a.title rangeOfString:q options:NSCaseInsensitiveSearch].location != NSNotFound;
}

#pragma mark Rows

- (NSTextField*)sectionLabel:(NSString*)text {
  NSTextField* t = label(text, 10, 700, QUIET);
  track(t, 0.8);
  return t;
}
- (NSColor*)latencyColour:(WArena*)a low:(int)low high:(int)high {
  if (![self measured:a]) return QUIET;
  int v = [self latency:a];
  if (v <= 0) return [NSColor colorWithSRGBRed:0.75 green:0.25 blue:0.22 alpha:1];
  CGFloat ratio = high == low ? 0 : MAX(0, MIN(1, (CGFloat)(v - low) / (high - low)));
  return [NSColor colorWithSRGBRed:0.18 + 0.68 * ratio green:0.68 - 0.45 * ratio blue:0.27 - 0.08 * ratio alpha:1];
}
- (NSString*)latencyText:(WArena*)a {
  if (![self measured:a]) return @"—";
  int v = [self latency:a];
  return v > 0 ? [NSString stringWithFormat:@"%dms", v] : @"Unavailable";
}
- (NSView*)rowFor:(WArena*)a width:(CGFloat)w tag:(NSString*)tagText remove:(void (^)(void))remove low:(int)low high:(int)high {
  __weak WPicker* weak = self;
  WArenaRowView* r = [WArenaRowView new];
  r.chosen = [chosenEndpoint isEqualToString:a.endpoint];
  r.layer.cornerRadius = 15;
  r.layer.borderWidth = r.chosen ? 2 : 1;
  r.layer.borderColor = (r.chosen ? INK : RULE).CGColor;
  r.fill = [CARD colorWithAlphaComponent:0.9 * CARD.alphaComponent];
  r.hover = CARD;
  r.onClick = ^{ [weak pick:a]; };
  NSTextField* title = label(a.title, 15, 700, INK);
  NSTextField* address = label(a.endpoint, 10.5, 400, QUIET);
  NSTextField* latency = label([self latencyText:a], 12, 700, [self latencyColour:a low:low high:high]);
  [title sizeToFit];
  [address sizeToFit];
  [latency sizeToFit];
  CGFloat right = w - 14;
  WTap* removeTap = nil;
  if (remove) {
    removeTap = [WTap new];
    removeTap.fill = removeTap.hover = NSColor.clearColor;
    NSTextField* t = label(@"Remove", 12, 600, BADGE);
    [t sizeToFit];
    [removeTap addSubview:t];
    place(t, 4, 4, t.frame.size.width, t.frame.size.height);
    removeTap.onClick = remove;
    CGFloat rw = t.frame.size.width + 8;
    right -= rw;
    removeTap.frame = NSMakeRect(right, 0, rw, t.frame.size.height + 8);
    right -= 12 - 4;
  }
  CGFloat th = title.frame.size.height, ah = address.frame.size.height, h = 14 + th + 3 + ah + 14;
  place(latency, right - latency.frame.size.width, (h - latency.frame.size.height) / 2, latency.frame.size.width, latency.frame.size.height);
  CGFloat maxTitle = right - latency.frame.size.width - 10 - 14;
  place(title, 14, 14, MIN(title.frame.size.width, maxTitle), th);
  place(address, 14, 14 + th + 3, MIN(address.frame.size.width, maxTitle), ah);
  [r addSubview:title];
  [r addSubview:address];
  [r addSubview:latency];
  CGFloat x = 14 + title.frame.size.width;
  if (a.ident >= 0) {
    NSView* badge = countryBadge(countryOf(a.address), ^{ [weak queueRebuild]; });
    if (badge) {
      place(badge, x + 8, 14 + (th - 14) / 2, badge.frame.size.width, 14);
      [r addSubview:badge];
      x += 8 + badge.frame.size.width;
    }
  }
  if (tagText) {
    NSTextField* tag = label(tagText, 10, 700, LIVE);
    [tag sizeToFit];
    WFlipped* pill = [WFlipped new];
    pill.wantsLayer = YES;
    pill.layer.backgroundColor = [LIVE colorWithAlphaComponent:0.12].CGColor;
    pill.layer.cornerRadius = (tag.frame.size.height + 4) / 2;
    [pill addSubview:tag];
    place(tag, 7, 2, tag.frame.size.width, tag.frame.size.height);
    place(pill, x + 8, 14 + (th - tag.frame.size.height - 4) / 2, tag.frame.size.width + 14, tag.frame.size.height + 4);
    [r addSubview:pill];
  }
  if (removeTap) {
    NSRect f = removeTap.frame;
    f.origin.y = (h - f.size.height) / 2;
    removeTap.frame = f;
    [r addSubview:removeTap];
  }
  r.frame = NSMakeRect(0, 0, w, h);
  return r;
}
/* Every section of the list, top to bottom (LazyColumn's items, 9 apart). */
- (void)rebuild {
  if (self.closing) return;
  __weak WPicker* weak = self;
  CGFloat w = MAX(200, self.scroll.contentSize.width - 32);
  NSMutableArray<NSView*>* items = [NSMutableArray new];
  NSMutableArray<NSNumber*>* gaps = [NSMutableArray new];  // space above each item
  void (^add)(NSView*, CGFloat) = ^(NSView* v, CGFloat gap) { [items addObject:v]; [gaps addObject:@(gap)]; };
  void (^section)(NSString*) = ^(NSString* text) {
    NSTextField* t = [weak sectionLabel:text];
    [t sizeToFit];
    WFlipped* holder = [WFlipped new];
    holder.frame = NSMakeRect(0, 0, w, 12 + t.frame.size.height + 3);
    place(t, 0, 12, w, t.frame.size.height);
    [holder addSubview:t];
    add(holder, 9);
  };
  NSArray<WArena*>* live = liveArenas();
  NSString* q = [self.search.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
  int low = INT_MAX, high = 0;
  for (NSNumber* n in self.pings.allValues) if (n.intValue > 0) { low = MIN(low, n.intValue); high = MAX(high, n.intValue); }
  if (low == INT_MAX) low = 0;
  NSMutableArray<WArena*>* filtered = [NSMutableArray new];
  for (WArena* a in live) if ([self matches:a]) [filtered addObject:a];
  [filtered sortUsingComparator:^NSComparisonResult(WArena* x, WArena* y) {
    int px = [weak latency:x] > 0 ? [weak latency:x] : INT_MAX, py = [weak latency:y] > 0 ? [weak latency:y] : INT_MAX;
    if (px != py) return px < py ? NSOrderedAscending : NSOrderedDescending;
    return [x.code compare:y.code];
  }];
  NSMutableArray<WArena*>* recentRows = [NSMutableArray new];
  for (NSString* e in self.recent) {
    WArena* a = liveArenaFor(e) ?: ([self.saved containsObject:e] ? customArena(e) : nil);
    if (a && [self matches:a]) [recentRows addObject:a];
  }
  [recentRows sortUsingComparator:^NSComparisonResult(WArena* x, WArena* y) {
    int px = [weak latency:x] > 0 ? [weak latency:x] : INT_MAX, py = [weak latency:y] > 0 ? [weak latency:y] : INT_MAX;
    return px < py ? NSOrderedAscending : px > py ? NSOrderedDescending : NSOrderedSame;
  }];
  WArena* best = nil;
  if (!q.length) for (WArena* a in live) if ([self latency:a] > 0 && (!best || [self latency:a] < [self latency:best])) best = a;
  NSMutableArray<WArena*>* ranked = [NSMutableArray new];
  for (WArena* a in filtered) if (![self.recent containsObject:a.endpoint]) [ranked addObject:a];

  BOOL first = YES;
  if (self.showAdd) {
    /* Built once while open, so a ping landing never takes the typing away. */
    if (!self.addBox) {
      WFlipped* box = [WFlipped new];
      box.wantsLayer = YES;
      box.layer.cornerRadius = 14;
      box.layer.cornerCurve = kCACornerCurveContinuous;
      box.layer.backgroundColor = CARD.CGColor;
      box.layer.borderWidth = 1;
      box.layer.borderColor = RULE.CGColor;
      self.custom = WField(@"IP address:port", 13, 400, NO);
      self.custom.placeholderAttributedString = [[NSAttributedString alloc] initWithString:@"IP address:port"
          attributes:@{NSFontAttributeName: body(13, 400), NSForegroundColorAttributeName: [QUIET colorWithAlphaComponent:0.7]}];
      self.custom.delegate = self;
      WTap* save = [WTap new];
      save.identifier = @"save";
      save.fill = save.hover = NSColor.clearColor;
      NSTextField* st = label(@"Save", 13, 700, LINK);
      [st sizeToFit];
      [save addSubview:st];
      place(st, 4, 4, st.frame.size.width, st.frame.size.height);
      save.frame = NSMakeRect(0, 0, st.frame.size.width + 8, st.frame.size.height + 8);
      save.onClick = ^{ [weak saveCustom]; };
      [box addSubview:self.custom];
      [box addSubview:save];
      self.addBox = box;
      WAfter(0.05, ^{ [weak.window makeFirstResponder:weak.custom]; });
    }
    CGFloat fh = 22, bh = 14 + fh + 14;
    for (NSView* v in self.addBox.subviews)
      if ([v.identifier isEqualToString:@"save"]) {
        place(v, w - 14 - v.frame.size.width + 4, (bh - v.frame.size.height) / 2, v.frame.size.width, v.frame.size.height);
        place(self.custom, 14, 14, w - 28 - v.frame.size.width - 4, fh);
      }
    self.addBox.frame = NSMakeRect(0, 0, w, bh);
    add(self.addBox, 0);
    first = NO;
    if (self.addressError) {
      NSTextField* err = wrapLabel(@"Enter an IPv4 address or [IPv6] address and a port (1–65535).", 11, 400, RED);
      WFlipped* holder = [WFlipped new];
      CGFloat eh = placeWrap(err, 0, 0, w);
      holder.frame = NSMakeRect(0, 0, w, eh);
      [holder addSubview:err];
      add(holder, 9);
    }
  } else { [self.addBox removeFromSuperview]; self.addBox = nil; self.custom = nil; }
  if (best) {
    section(@"BEST FOR YOU");
    add([self rowFor:best width:w tag:@"Lowest ping" remove:nil low:low high:high], 9);
  }
  if (recentRows.count) {
    section(@"RECENTLY JOINED");
    for (WArena* a in recentRows) add([self rowFor:a width:w tag:nil remove:nil low:low high:high], 9);
  }
  section(q.length ? @"SEARCH RESULTS" : @"ARENAS");
  NSArray* shown = self.showAll || q.length || ranked.count <= 10 ? ranked : [ranked subarrayWithRange:NSMakeRange(0, 10)];
  for (WArena* a in shown) add([self rowFor:a width:w tag:nil remove:nil low:low high:high], 9);
  if (!q.length && ranked.count > 10) {
    WTap* more = [WTap new];
    more.fill = more.hover = NSColor.clearColor;
    NSTextField* t = label(self.showAll ? @"Show less" : @"See all", 13, 700, INK);
    t.alignment = NSTextAlignmentCenter;
    [t sizeToFit];
    [more addSubview:t];
    place(t, 0, 14, w, t.frame.size.height);
    more.frame = NSMakeRect(0, 0, w, t.frame.size.height + 28);
    more.onClick = ^{ weak.showAll = !weak.showAll; [weak rebuild]; };
    add(more, 9);
  }
  NSMutableArray<WArena*>* savedRows = [NSMutableArray new];
  for (NSString* e in self.saved) { WArena* a = customArena(e); if (a && [self matches:a]) [savedRows addObject:a]; }
  if (self.saved.count) {
    WFlipped* card = [WFlipped new];
    card.wantsLayer = YES;
    card.layer.cornerRadius = 15;
    card.layer.cornerCurve = kCACornerCurveContinuous;
    card.layer.backgroundColor = [CARD colorWithAlphaComponent:0.9 * CARD.alphaComponent].CGColor;
    card.layer.borderWidth = 1;
    card.layer.borderColor = RULE.CGColor;
    WTap* head = [WTap new];
    head.fill = head.hover = NSColor.clearColor;
    NSTextField* t = [self sectionLabel:[NSString stringWithFormat:@"SAVED ARENAS · %lu", (unsigned long)self.saved.count]];
    [t sizeToFit];
    NSImageView* chevron = glyph(self.showSaved ? @"chevron.down" : @"chevron.right", 11, INK);
    [head addSubview:t];
    [head addSubview:chevron];
    CGFloat iw = w - 28;
    place(t, 0, 0, iw - 20, t.frame.size.height);
    place(chevron, iw - 14, (t.frame.size.height - 14) / 2, 14, 14);
    head.frame = NSMakeRect(14, 14, iw, t.frame.size.height);
    head.onClick = ^{ weak.showSaved = !weak.showSaved; [weak rebuild]; };
    [card addSubview:head];
    CGFloat cy = 14 + t.frame.size.height + 14;
    if (self.showSaved) {
      cy = 14 + t.frame.size.height + 9;
      for (WArena* a in savedRows) {
        NSString* endpoint = a.endpoint;
        NSView* row = [self rowFor:a width:iw tag:nil remove:^{ weak.saved = removeArena(endpoint); [weak rebuild]; } low:low high:high];
        place(row, 14, cy, iw, row.frame.size.height);
        [card addSubview:row];
        cy += row.frame.size.height + 9;
      }
      cy += 14 - 9;
    }
    card.frame = NSMakeRect(0, 0, w, cy);
    add(card, 9);
  }
  if (!filtered.count && !recentRows.count && !self.saved.count) {
    BOOL loading = wyrm_mac_arena_count() == 0 && [@(wyrm_mac_directory_status()) hasPrefix:@"Loading"];
    NSTextField* t = wrapLabel(loading ? @"Loading the live directory…" : @"No active arenas right now. Try again in a moment or add a custom IP.", 12, 400, QUIET);
    WFlipped* holder = [WFlipped new];
    CGFloat th = placeWrap(t, 20, 20, w - 40);
    holder.frame = NSMakeRect(0, 0, w, th + 40);
    [holder addSubview:t];
    add(holder, 9);
  }
  /* Laid into the document: 14 on top, 18 under, 16 aside. */
  for (NSView* v in self.list.subviews.copy) if (v != self.addBox) [v removeFromSuperview];
  CGFloat y = 14;
  for (NSUInteger i = 0; i < items.count; i++) {
    if (i) y += [gaps[i] doubleValue];
    NSView* v = items[i];
    place(v, 16, y, w, v.frame.size.height);
    if (v.superview != self.list) [self.list addSubview:v];
    y += v.frame.size.height;
  }
  y += 18;
  [self.list setFrameSize:NSMakeSize(self.scroll.contentSize.width, MAX(y, self.scroll.contentSize.height))];
  /* Status beside the title. */
  BOOL loading = wyrm_mac_arena_count() == 0 && [@(wyrm_mac_directory_status()) hasPrefix:@"Loading"];
  self.status.stringValue = loading ? @"Loading…" : wyrm_mac_arena_count() ? [NSString stringWithFormat:@"%d live", wyrm_mac_arena_count()]
                                                                             : @"The arena list could not be reached.";
  [self setNeedsLayout:YES];
}
- (void)layout {
  [super layout];
  NSSize s = self.bounds.size;
  CGFloat w = MIN(680, s.width - 48), h = MIN(s.height * 0.84, s.height - 32);
  NSRect f = NSMakeRect(round((s.width - w) / 2), round((s.height - h) / 2), w, h);
  if (!NSEqualRects(self.panel.frame, f)) {
    BOOL resized = fabs(self.panel.frame.size.width - w) > 0.5;
    place(self.panel, f.origin.x, f.origin.y, w, h);
    place(self.panelClip, 0, 0, w, h);
    if (resized) WAfter(0, ^{ [self rebuild]; });
  }
  /* Header: 22 in, 20 down, the column's bottom on one line with the controls. */
  NSTextField *kicker = nil, *title = nil;
  for (NSView* v in self.panelClip.subviews) {
    if ([v.identifier isEqualToString:@"kicker"]) kicker = (NSTextField*)v;
    if ([v.identifier isEqualToString:@"title"]) title = (NSTextField*)v;
  }
  [kicker sizeToFit];
  [title sizeToFit];
  CGFloat bottom = 20 + kicker.frame.size.height + 2 + title.frame.size.height;
  place(kicker, 22, 20, kicker.frame.size.width, kicker.frame.size.height);
  place(title, 22, 20 + kicker.frame.size.height + 2, title.frame.size.width, title.frame.size.height);
  CGFloat x = w - 18 - self.closeLink.frame.size.width;
  place(self.closeLink, x, bottom - self.closeLink.frame.size.height, self.closeLink.frame.size.width, self.closeLink.frame.size.height);
  x -= 10 + 36;
  place(self.plus, x, bottom - 36, 36, 36);
  place(self.plusIcon, 9, 9, 18, 18);
  [self.status sizeToFit];
  place(self.status, x - 12 - self.status.frame.size.width, bottom - 8 - self.status.frame.size.height,
        self.status.frame.size.width, self.status.frame.size.height);
  CGFloat sy = bottom + 14;
  place(self.searchBox, 16, sy, w - 32, 44);
  for (NSView* v in self.searchBox.subviews)
    if ([v.identifier isEqualToString:@"magnifier"]) place(v, 14, 13, 18, 18);
  place(self.search, 14 + 18 + 8, 11, w - 32 - 14 - 18 - 8 - 14, 22);
  place(self.scroll, 0, sy + 44, w, h - sy - 44);
}
/* Scale in from 0.94 out of a dim (Desktop's spring), back out to 0.96. */
- (void)present {
  [self layoutSubtreeIfNeeded];
  [self rebuild];
  [self layoutSubtreeIfNeeded];
  self.layer.opacity = 1;
  [self.layer addAnimation:WSpring(@"opacity", @0, @1, 0.4, 1) forKey:@"dim"];
  CALayer* p = self.panel.layer;
  [p addAnimation:WSpring(@"opacity", @0, @1, 0.4, 0.9) forKey:@"fade"];
  [p addAnimation:WSpring(@"transform", [NSValue valueWithCATransform3D:WScaleAbout(self.panel, 0.94)],
                          [NSValue valueWithCATransform3D:CATransform3DIdentity], 0.45, 0.82) forKey:@"scale"];
  [self.window makeFirstResponder:self.search];
}
- (void)dismiss:(void (^)(void))done {
  self.closing = YES;
  probesSetOpen(NO);
  [CATransaction begin];
  [CATransaction setCompletionBlock:done];
  CABasicAnimation* fade = [CABasicAnimation animationWithKeyPath:@"opacity"];
  fade.fromValue = @1;
  fade.toValue = @0;
  fade.duration = 0.26;
  self.layer.opacity = 0;
  [self.layer addAnimation:fade forKey:@"out"];
  CABasicAnimation* shrink = [CABasicAnimation animationWithKeyPath:@"transform"];
  shrink.fromValue = [NSValue valueWithCATransform3D:CATransform3DIdentity];
  shrink.toValue = [NSValue valueWithCATransform3D:WScaleAbout(self.panel, 0.96)];
  shrink.duration = 0.26;
  shrink.fillMode = kCAFillModeForwards;
  shrink.removedOnCompletion = NO;
  [self.panel.layer addAnimation:shrink forKey:@"out"];
  [CATransaction commit];
}
@end

#pragma mark - Death card and entering toast

@interface WFloat : WFlipped
@property(strong) NSView* glass;
@property(strong) WFlipped* content;
@end
@implementation WFloat
- (instancetype)init {
  if ((self = [super initWithFrame:NSZeroRect])) {
    _content = [WFlipped new];
    if (@available(macOS 26.0, *)) {
      NSGlassEffectView* glass = [NSGlassEffectView new];
      glass.cornerRadius = 24;
      glass.tintColor = [PAPER colorWithAlphaComponent:0.55];
      glass.contentView = _content;
      _glass = glass;
    } else {
      NSVisualEffectView* blur = [NSVisualEffectView new];
      blur.material = NSVisualEffectMaterialHUDWindow;
      blur.blendingMode = NSVisualEffectBlendingModeWithinWindow;
      blur.state = NSVisualEffectStateActive;
      blur.wantsLayer = YES;
      blur.layer.cornerRadius = 24;
      blur.layer.cornerCurve = kCACornerCurveContinuous;
      blur.layer.masksToBounds = YES;
      [blur addSubview:_content];
      _glass = blur;
    }
    [self addSubview:_glass];
  }
  return self;
}
- (void)layout {
  [super layout];
  place(self.glass, 0, 0, self.bounds.size.width, self.bounds.size.height);
  if (@available(macOS 26.0, *)) {} else place(self.content, 0, 0, self.bounds.size.width, self.bounds.size.height);
}
@end

#pragma mark - Arrange arena UI (Desktop's HudEditor)

/* The arena UI pieces (Android's ArenaHudTarget: same ids, same defaults). */
typedef struct { const char* prefix; const char* title; float fx, fy; BOOL fixedInNearOriginal; } WHudPiece;
static const WHudPiece PIECES[] = {
  {"hud.minimap", "MINIMAP", 0.095f, 0.205f, YES}, {"hud.leaderboard", "LEADERBOARD", 0.905f, 0.155f, YES},
  {"hud.stats", "STATS", 0.945f, 0.530f, YES}, {"hud.team", "TEAM", 0.095f, 0.610f, NO}, {"hud.chat", "CHAT", 0.790f, 0.075f, NO}};
enum { P_MINIMAP, P_BOARD, P_STATS, P_TEAM, P_CHAT, P_COUNT };
static NSArray* sizeIds(void) {
  return @[@"general.minimap_size", @"general.lb_font", @"general.stats_font", @"layout.stats_scale", @"layout.stats_opacity",
           @"layout.chat_scale", @"layout.chat_opacity"];
}

@interface WHudEditor : WFlipped
@property(strong) NSDictionary* before;      // engine settings as they were (Cancel)
@property(strong) NSDictionary* teamBefore;  // the team HUD look (Cancel)
@property(strong) NSMutableDictionary* positions;
@property(strong) NSView* bar;
@property(strong) WFlipped* barInside;
@property(strong) NSView* options;
@property NSInteger dragging, optionsPiece, chatTab;
@property NSPoint grab, pressedAt;
@property(strong) NSTimer* hold;
@property(copy) void (^onClose)(void);
- (void)close:(BOOL)save;
@end

@implementation WHudEditor
- (instancetype)init {
  if (!(self = [super initWithFrame:NSZeroRect])) return nil;
  _dragging = -1;
  _optionsPiece = -1;
  [WEngine refresh];
  NSMutableDictionary* before = [NSMutableDictionary new];
  for (WSetting* s in [WEngine settings]) before[s.ident] = s.raw;
  _before = before;
  NSMutableDictionary* team = [NSMutableDictionary new];
  for (NSString* k in [WTeamHud keys]) team[k] = @([WTeamHud value:k]);
  _teamBefore = team;
  _positions = [NSMutableDictionary new];
  for (int i = 0; i < P_COUNT; i++) {
    NSString* p = @(PIECES[i].prefix);
    WSetting *x = [WEngine named:[p stringByAppendingString:@"_x"]], *y = [WEngine named:[p stringByAppendingString:@"_y"]];
    _positions[p] = [NSValue valueWithPoint:NSMakePoint(x ? x.number : PIECES[i].fx, y ? y.number : PIECES[i].fy)];
  }
  /* The bar: what to do, and the three ways out. */
  _barInside = [WFlipped new];
  if (@available(macOS 26.0, *)) {
    NSGlassEffectView* g = [NSGlassEffectView new];
    g.cornerRadius = 28;
    g.tintColor = [PAPER colorWithAlphaComponent:0.7];
    g.contentView = _barInside;
    _bar = g;
  } else {
    _bar = [WFlipped new];
    _bar.wantsLayer = YES;
    _bar.layer.backgroundColor = [PAPER colorWithAlphaComponent:0.94].CGColor;
    _bar.layer.cornerRadius = 28;
    [_bar addSubview:_barInside];
  }
  NSTextField* t = label(@"Drag the arena UI into place", 14, 700, INK);
  NSTextField* d = label([WStore nearOriginal] ? @"Near Original: team and chat move · hold or right-click for options"
                                               : @"Hold or right-click any piece for its size, opacity and more", 12, 400, MUTE);
  __weak WHudEditor* weak = self;
  WButton* cancel = [self pill:@"Cancel" filled:NO];
  cancel.onClick = ^{ [weak close:NO]; };
  WButton* reset = [self pill:@"Reset" filled:NO];
  reset.onClick = ^{ [weak resetLayout]; };
  WButton* save = [self pill:@"Save" filled:YES];
  save.onClick = ^{ [weak close:YES]; };
  for (NSView* v in @[t, d, cancel, reset, save]) [_barInside addSubview:v];
  [self addSubview:_bar];
  wyrm_mac_enter_layout_editor(([WStore nickname].length ? [WStore nickname] : @"Wyrm Player").UTF8String);
  return self;
}
- (WButton*)pill:(NSString*)text filled:(BOOL)filled {
  WButton* b = filled ? [WButton primary:text] : [WButton well:nil text:text];
  if (!filled) { b.fill = NSColor.clearColor; b.hover = [INK colorWithAlphaComponent:0.07]; }
  b.title.font = body(13.5, 700);
  b.layer.cornerRadius = 19;
  return b;
}
- (BOOL)acceptsFirstResponder { return YES; }
- (void)keyDown:(NSEvent*)e {
  if (e.keyCode != 53) return;
  if (self.options) [self closeOptions]; else [self close:NO];
}
- (CGFloat)scale { return self.window.backingScaleFactor ?: 1; }
- (CGFloat)number:(NSString*)ident fallback:(CGFloat)f { WSetting* s = [WEngine named:ident]; return s ? s.number : f; }
/* Where the engine draws a piece, in points (Desktop's pieceRect, from pixels). */
- (NSRect)rectOf:(NSInteger)piece {
  CGFloat k = self.scale;
  NSSize canvas = self.bounds.size;
  if (piece == P_TEAM || piece == P_CHAT) {
    float r[8];
    wyrm_mac_team_rects(r);
    int at = piece == P_TEAM ? 0 : 4;
    if (r[at + 2] > 1 && r[at + 3] > 1) return NSMakeRect(r[at] / k, r[at + 1] / k, r[at + 2] / k, r[at + 3] / k);
  }
  CGFloat (^font)(NSString*) = ^CGFloat(NSString* ident) {
    CGFloat sizes[3] = {0.84, 1, 1.18};
    return sizes[MAX(0, MIN(2, (int)lround([self number:ident fallback:1])))];
  };
  NSSize size;
  switch (piece) {
    case P_MINIMAP: { CGFloat m = [self number:@"general.minimap_size" fallback:300]; size = NSMakeSize(m, m); break; }
    case P_BOARD: { CGFloat f = font(@"general.lb_font"); size = NSMakeSize(464 * [WTeamHud value:@"lb_width"] * f, 378 * (0.4 + 0.6 * [WTeamHud value:@"lb_height"]) * f); break; }
    case P_STATS: { CGFloat f = font(@"general.stats_font") * [self number:@"layout.stats_scale" fallback:1]; size = NSMakeSize(330 * f, 342 * f); break; }
    case P_TEAM: { CGFloat s = [WTeamHud value:@"team_scale"]; size = NSMakeSize([WTeamHud value:@"team_width"] * s, [WTeamHud value:@"team_height"] * s); break; }
    default: { CGFloat s = [self number:@"layout.chat_scale" fallback:1]; size = NSMakeSize([WTeamHud value:@"chat_width"] * s, [WTeamHud value:@"chat_height"] * s); }
  }
  size.width /= k;
  size.height /= k;
  NSPoint c = [self.positions[@(PIECES[piece].prefix)] pointValue];
  CGFloat edge = 16 / k;
  CGFloat x = MAX(edge, MIN(MAX(edge, canvas.width - edge - size.width), c.x * canvas.width - size.width / 2));
  CGFloat y = MAX(edge, MIN(MAX(edge, canvas.height - edge - size.height), c.y * canvas.height - size.height / 2));
  return NSMakeRect(x, y, size.width, size.height);
}
- (BOOL)editable:(NSInteger)piece { return !([WStore nearOriginal] && PIECES[piece].fixedInNearOriginal); }
/* The piece under the pointer: the chat and roster first (drawn last, on top), the map last. */
- (NSInteger)pieceAt:(NSPoint)p {
  NSInteger order[] = {P_CHAT, P_TEAM, P_STATS, P_BOARD, P_MINIMAP};
  for (int i = 0; i < 5; i++) {
    NSInteger piece = order[i];
    if (![self editable:piece]) continue;
    NSRect r = NSInsetRect([self rectOf:piece], -8, -8);
    if (piece == P_MINIMAP ? hypot(p.x - NSMidX(r), p.y - NSMidY(r)) <= r.size.width / 2 : NSPointInRect(p, r)) return piece;
  }
  return -1;
}
- (void)updateTrackingAreas {
  for (NSTrackingArea* a in self.trackingAreas) [self removeTrackingArea:a];
  [self addTrackingArea:[[NSTrackingArea alloc] initWithRect:NSZeroRect
      options:NSTrackingMouseMoved | NSTrackingActiveInKeyWindow | NSTrackingInVisibleRect owner:self userInfo:nil]];
  [super updateTrackingAreas];
}
- (void)mouseMoved:(NSEvent*)e {
  NSPoint p = [self convertPoint:e.locationInWindow fromView:nil];
  [([self pieceAt:p] >= 0 && !self.options ? NSCursor.openHandCursor : NSCursor.arrowCursor) set];
}
- (void)mouseDown:(NSEvent*)e {
  if (self.options) { if (!NSPointInRect([self convertPoint:e.locationInWindow fromView:nil], self.options.frame)) [self closeOptions]; return; }
  NSPoint p = [self convertPoint:e.locationInWindow fromView:nil];
  NSInteger piece = [self pieceAt:p];
  if (piece < 0) return;
  self.dragging = piece;
  self.pressedAt = p;
  NSRect r = [self rectOf:piece];
  self.grab = NSMakePoint(p.x - NSMidX(r), p.y - NSMidY(r));
  [NSCursor.closedHandCursor set];
  /* Hold for its options (Android's long-press). */
  __weak WHudEditor* weak = self;
  [self.hold invalidate];
  self.hold = [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:NO block:^(NSTimer* t) {
    NSInteger held = weak.dragging;
    weak.dragging = -1;
    if (held >= 0) [weak openOptions:held];
  }];
}
- (void)mouseDragged:(NSEvent*)e {
  if (self.dragging < 0) return;
  NSPoint p = [self convertPoint:e.locationInWindow fromView:nil];
  if (hypot(p.x - self.pressedAt.x, p.y - self.pressedAt.y) <= 3 && self.hold.valid) return;
  [self.hold invalidate];
  NSSize c = self.bounds.size;
  CGFloat x = MAX(0, MIN(1, (p.x - self.grab.x) / c.width)), y = MAX(0, MIN(1, (p.y - self.grab.y) / c.height));
  NSString* prefix = @(PIECES[self.dragging].prefix);
  self.positions[prefix] = [NSValue valueWithPoint:NSMakePoint(x, y)];
  float v[2] = {(float)x, (float)y};
  wyrm_mac_set_setting(prefix.UTF8String, v, 2);
}
- (void)mouseUp:(NSEvent*)e { [self.hold invalidate]; self.dragging = -1; }
- (void)rightMouseDown:(NSEvent*)e {
  NSInteger piece = [self pieceAt:[self convertPoint:e.locationInWindow fromView:nil]];
  if (piece >= 0) [self openOptions:piece];
}

#pragma mark Options (Android's EditorOptionsPopup for a mouse)

- (void)closeOptions {
  if (self.optionsPiece == P_CHAT) wyrm_mac_set_chat_tab(-1);
  [self.options removeFromSuperview];
  self.options = nil;
  self.optionsPiece = -1;
  [self.window makeFirstResponder:self];
}
- (NSArray*)optionsFor:(NSInteger)piece {
  /* (label, kind, key, min, max, steps): kind e = engine, t = team HUD, c = colours. */
  switch (piece) {
    case P_MINIMAP: return @[@[@"SIZE", @"e", @"general.minimap_size", @128, @512, @0]];
    case P_BOARD: return @[@[@"TEXT SIZE", @"e", @"general.lb_font", @0, @2, @1], @[@"WIDTH", @"t", @"lb_width"], @[@"HEIGHT", @"t", @"lb_height"]];
    case P_STATS: return @[@[@"SIZE", @"e", @"layout.stats_scale", @0.65, @1.6, @0], @[@"OPACITY", @"e", @"layout.stats_opacity", @0.05, @1, @0],
                           @[@"BACK", @"t", @"stats_panel"], @[@"TEXT", @"c", @"stats_text"]];
    case P_TEAM: return @[@[@"SIZE", @"t", @"team_scale"], @[@"OPACITY", @"t", @"team_opacity"], @[@"BACK", @"t", @"team_panel"],
                          @[@"WIDTH", @"t", @"team_width"], @[@"HEIGHT", @"t", @"team_height"],
                          @[@"PLAYER NAME AND SCORE", @"c", @"team_name"], @[@"KEY NAME AND SERVER", @"c", @"team_data"]];
    default: {
      NSArray* base = @[@[@"SIZE", @"e", @"layout.chat_scale", @0.65, @1.6, @0], @[@"OPACITY", @"e", @"layout.chat_opacity", @0.05, @1, @0],
                        @[@"BACK", @"t", @"chat_panel"], @[@"WIDTH", @"t", @"chat_width"], @[@"HEIGHT", @"t", @"chat_height"]];
      NSArray* tab = self.chatTab == 1 ? @[@[@"PLAYER NAME", @"c", @"global_name"], @[@"MESSAGES", @"c", @"global_text"]]
                   : self.chatTab == 2 ? @[@[@"PLAYER NAME", @"c", @"online_name"], @[@"USERNAME AND SERVER", @"c", @"online_data"]]
                   : self.chatTab == 3 ? @[@[@"BUTTON SIZE", @"t", @"chatbtn_scale"], @[@"BUTTON OPACITY", @"t", @"chatbtn_opacity"],
                                           @[@"TEXT AND BORDER", @"c", @"chatbtn_label"], @[@"FILL", @"c", @"chatbtn_fill"]]
                   : @[@[@"PLAYER NAME", @"c", @"chat_name"], @[@"MESSAGES", @"c", @"chat_text"]];
      return [base arrayByAddingObjectsFromArray:tab];
    }
  }
}
static NSString* shownValue(NSString* label, NSString* key, CGFloat v) {
  if ([key isEqualToString:@"general.lb_font"]) return @[@"Small", @"Medium", @"Large"][MAX(0, MIN(2, (int)lround(v)))];
  if ([key hasSuffix:@"_width"] && ![key hasPrefix:@"lb"]) return [NSString stringWithFormat:@"%ld px", lround(v)];
  if ([key hasSuffix:@"_height"] && ![key hasPrefix:@"lb"]) return [NSString stringWithFormat:@"%ld px", lround(v)];
  if ([key isEqualToString:@"general.minimap_size"]) return [NSString stringWithFormat:@"%ld px", lround(v)];
  return [NSString stringWithFormat:@"%ld%%", lround(v * 100)];
}
- (void)openOptions:(NSInteger)piece {
  if (self.options) [self.options removeFromSuperview];
  self.optionsPiece = piece;
  if (piece == P_CHAT) wyrm_mac_set_chat_tab((int)self.chatTab);
  WFlipped* inside = [WFlipped new];
  NSView* panel;
  if (@available(macOS 26.0, *)) {
    NSGlassEffectView* g = [NSGlassEffectView new];
    g.cornerRadius = 24;
    g.tintColor = [PAPER colorWithAlphaComponent:0.86];
    g.contentView = inside;
    panel = g;
  } else {
    panel = [WFlipped new];
    panel.wantsLayer = YES;
    panel.layer.backgroundColor = PAPER.CGColor;
    panel.layer.cornerRadius = 24;
    [panel addSubview:inside];
  }
  __weak WHudEditor* weak = self;
  CGFloat w = 360, y = 22, inner = w - 44;
  NSTextField* title = label(@(PIECES[piece].title), 13, 700, INK);
  track(title, 1.4);
  placeLabel(title, 22, y, 0);
  [inside addSubview:title];
  y += title.frame.size.height + 10;
  if (piece == P_CHAT) {
    WSegmented* tabs = [[WSegmented alloc] initWithOptions:@[@"Team", @"Global", @"Online", @"Button"]];
    tabs.selected = self.chatTab;
    tabs.onSelect = ^(NSInteger i) { weak.chatTab = i; [weak openOptions:P_CHAT]; };
    place(tabs, 22, y, inner, 32);
    [inside addSubview:tabs];
    y += 42;
  }
  for (NSArray* o in [self optionsFor:piece]) {
    NSString *name = o[0], *kind = o[1], *key = o[2];
    BOOL engine = [kind isEqualToString:@"e"];
    CGFloat value = engine ? [self number:key fallback:1] : [WTeamHud value:key];
    NSTextField* head = label(name, 10.5, 700, QUIET);
    track(head, 1);
    placeLabel(head, 22, y, 0);
    [inside addSubview:head];
    if ([kind isEqualToString:@"c"]) {
      NSInteger selected = lround(value);
      NSArray* names = [WTeamHud colourNames];
      NSTextField* shown = label(selected == 9 ? @"Grey" : selected < (NSInteger)names.count ? names[selected] : @"Theme", 13, 400, MUTE);
      [shown sizeToFit];
      place(shown, w - 22 - shown.frame.size.width, y, shown.frame.size.width, shown.frame.size.height);
      [inside addSubview:shown];
      y += head.frame.size.height + 8;
      NSMutableArray* swatches = [[WTeamHud colourSwatches] mutableCopy];
      if ([key isEqualToString:@"chatbtn_fill"]) [swatches addObject:@0xFF808080];
      for (NSUInteger i = 0; i < swatches.count; i++) {
        WTap* dot = [WTap new];
        uint32_t argb = [swatches[i] unsignedIntValue];
        dot.fill = argb ? rgba(argb) : INK;
        dot.hover = dot.fill;
        dot.layer.cornerRadius = 11;
        dot.layer.borderWidth = (NSInteger)i == selected ? 3 : 1;
        dot.layer.borderColor = ((NSInteger)i == selected ? INK : RULE).CGColor;
        dot.onClick = ^{ [WTeamHud apply:key value:i]; [weak openOptions:piece]; };
        place(dot, 22 + i * 30, y, 24, 24);
        [inside addSubview:dot];
      }
      y += 34;
      continue;
    }
    CGFloat min = engine ? [o[3] doubleValue] : [WTeamHud minimum:key], max = engine ? [o[4] doubleValue] : [WTeamHud maximum:key];
    int steps = engine ? [o[5] intValue] : 0;
    NSTextField* shown = label(shownValue(name, key, value), 13, 400, MUTE);
    [shown sizeToFit];
    place(shown, w - 22 - 80, y, 80, shown.frame.size.height);
    shown.alignment = NSTextAlignmentRight;
    [inside addSubview:shown];
    y += head.frame.size.height + 4;
    WSlider* slider = [[WSlider alloc] initWithFrame:NSZeroRect];
    slider.minimum = min;
    slider.maximum = max;
    slider.steps = steps;
    slider.value = MAX(min, MIN(max, value));
    slider.onChange = ^(CGFloat v) {
      CGFloat stepped = steps > 0 ? round(v) : v;
      if (engine) [WEngine writeId:key values:@[@(stepped)]]; else [WTeamHud apply:key value:stepped];
      shown.stringValue = shownValue(name, key, stepped);
      if (engine) { WSetting* s = [WEngine named:key]; if (s) s.raw = [NSString stringWithFormat:@"%.4f", stepped]; }
    };
    place(slider, 22, y, inner, 30);
    [inside addSubview:slider];
    y += 38;
  }
  WButton* done = [WButton primary:@"Done"];
  done.layer.cornerRadius = 19;
  done.onClick = ^{ [weak closeOptions]; };
  place(done, w - 22 - 90, y + 4, 90, 38);
  [inside addSubview:done];
  y += 4 + 38 + 22;
  panel.frame = NSMakeRect((self.bounds.size.width - w) / 2, MAX(16, (self.bounds.size.height - MIN(y, 560)) / 2), w, MIN(y, self.bounds.size.height - 32));
  inside.frame = NSMakeRect(0, 0, w, y);
  self.options = panel;
  [self addSubview:panel];
  WMaterialise(panel, YES, 10, 0.45, 0.8, nil);
}
- (void)resetLayout {
  wyrm_mac_settings_action(8);
  WAfter(0.3, ^{
    [WEngine refresh];
    for (int i = 0; i < P_COUNT; i++) {
      NSString* p = @(PIECES[i].prefix);
      WSetting *x = [WEngine named:[p stringByAppendingString:@"_x"]], *y = [WEngine named:[p stringByAppendingString:@"_y"]];
      self.positions[p] = [NSValue valueWithPoint:NSMakePoint(x ? x.number : PIECES[i].fx, y ? y.number : PIECES[i].fy)];
    }
  });
}
- (void)close:(BOOL)save {
  if (!save) {
    for (int i = 0; i < P_COUNT; i++) {
      NSString* p = @(PIECES[i].prefix);
      NSString *x = self.before[[p stringByAppendingString:@"_x"]], *y = self.before[[p stringByAppendingString:@"_y"]];
      if (x && y) { float v[2] = {x.floatValue, y.floatValue}; wyrm_mac_set_setting(p.UTF8String, v, 2); }
    }
    for (NSString* ident in sizeIds()) {
      NSString* raw = self.before[ident];
      if (raw) [WEngine writeId:ident values:@[@(raw.floatValue)]];
    }
    [self.teamBefore enumerateKeysAndObjectsUsingBlock:^(NSString* k, NSNumber* v, BOOL* stop) { [WTeamHud apply:k value:v.floatValue]; }];
  }
  if (self.optionsPiece == P_CHAT) wyrm_mac_set_chat_tab(-1);
  wyrm_mac_exit_layout_editor();
  WAfter(0.3, ^{ [WEngine refresh]; [NSNotificationCenter.defaultCenter postNotificationName:WSettingsChanged object:nil]; });
  if (self.onClose) self.onClose();
}
- (void)layout {
  [super layout];
  NSSize s = self.bounds.size;
  NSArray* parts = self.barInside.subviews;
  NSTextField *t = parts[0], *d = parts[1];
  [t sizeToFit];
  [d sizeToFit];
  CGFloat textW = MAX(t.frame.size.width, d.frame.size.width), x = 22 + textW + 18;
  CGFloat widths[3] = {0, 0, 0};
  for (int i = 0; i < 3; i++) { WButton* b = parts[2 + i]; [b.title sizeToFit]; widths[i] = b.title.frame.size.width + 36; }
  CGFloat w = x + widths[0] + widths[1] + widths[2] + 16 + 10, h = 58;
  place(self.bar, (s.width - w) / 2, s.height - 26 - h, w, h);
  place(self.barInside, 0, 0, w, h);
  place(t, 22, 10, textW, t.frame.size.height);
  place(d, 22, 10 + t.frame.size.height, textW, d.frame.size.height);
  for (int i = 0; i < 3; i++) { place(parts[2 + i], x, 10, widths[i], 38); x += widths[i] + 8; }
}
- (void)viewDidMoveToWindow {
  if (!self.window) return;
  [self layoutSubtreeIfNeeded];
  CABasicAnimation* rise = [CABasicAnimation animationWithKeyPath:@"transform.translation.y"];
  rise.fromValue = @50;
  rise.toValue = @0;
  rise.duration = 0.45;
  rise.timingFunction = [CAMediaTimingFunction functionWithControlPoints:0.22 :0.8 :0.24 :1];
  self.bar.wantsLayer = YES;
  [self.bar.layer addAnimation:rise forKey:@"rise"];
  [self.window makeFirstResponder:self];
}
@end

#pragma mark - Shell root

static void sizeWindow(NSWindow* window, BOOL app, BOOL animated, BOOL onScreen);

@interface WShell : WFlipped
@property(strong) NSView* paper;
@property(strong) NSScrollView* scroll;
@property(strong) WPlayPage* play;
@property(strong) WSoonPage* soon;
@property(strong) WSettingsView* settings;
@property(strong) WTabBar* tabs;
@property(strong) WPicker* picker;
@property(strong) WLobby* lobby;
@property(strong) WAlerts* alerts;
@property(strong) WHudEditor* editor;
@property(strong) WFloat *death, *entering;
@property(strong) NSTextField *deathTitle, *deathScore, *enterTitle, *enterHint;
@property(strong) WButton *again, *home;
@property(strong) WAuthView* auth;
@property(strong) WDialogHost* dialog;
@property int state;
@property(strong) NSArray* observers;
- (void)adoptAuth:(WAuthView*)auth;
- (void)setShellState:(int)state score:(int)score;
@end

static BOOL lobbyOpen;

@implementation WShell
- (instancetype)init {
  if (!(self = [super initWithFrame:NSZeroRect])) return nil;
  self.wantsLayer = YES;
  _paper = [NSView new];
  _paper.wantsLayer = YES;
  _paper.layer.backgroundColor = PAPER.CGColor;
  [self addSubview:_paper];
  _play = [WPlayPage new];
  _scroll = [NSScrollView new];
  _scroll.drawsBackground = NO;
  _scroll.hasVerticalScroller = NO;
  _scroll.documentView = _play;
  [self addSubview:_scroll];
  _soon = [WSoonPage new];
  [self addSubview:_soon];
  _settings = [WSettingsView new];
  __weak WShell* weak = self;
  _settings.onLogOut = ^{ [weak askLogOut]; };
  [self addSubview:_settings];
  _tabs = [[WTabBar alloc] initWithSelected:openTab];
  _tabs.onSelect = ^(int tab) { [weak showTab:tab]; };
  [self addSubview:_tabs];
  _play.onPick = ^{ [weak openPicker]; };
  _play.onEnter = ^{ [weak openLobby]; };
  _play.onAlerts = ^{ [weak openAlerts]; };

  _death = [WFloat new];
  _deathTitle = label(@"One more round?", 22, 700, INK);
  _deathScore = label(@"", 13, 500, MUTE);
  _again = [WButton primary:@"Play again"];
  _again.onClick = ^{ wyrm_mac_death(false); };
  _home = [WButton well:nil text:@"Back to Play"];
  _home.onClick = ^{ wyrm_mac_death(true); };
  for (NSView* v in @[_deathTitle, _deathScore, _again, _home]) [_death.content addSubview:v];
  _death.hidden = YES;
  [self addSubview:_death];

  _entering = [WFloat new];
  _enterTitle = label(@"Entering arena…", 15, 700, INK);
  _enterHint = label(@"Press Escape to cancel", 12, 400, QUIET);
  [_entering.content addSubview:_enterTitle];
  [_entering.content addSubview:_enterHint];
  _entering.hidden = YES;
  [self addSubview:_entering];
  _state = -1;
  [self showTab:openTab];
  if (lobbyOpen) [self openLobby];
  NSNotificationCenter* nc = NSNotificationCenter.defaultCenter;
  _observers = @[[nc addObserverForName:WAccountChanged object:nil queue:nil usingBlock:^(NSNotification* n) { [weak.play refreshAccount]; }],
                 [nc addObserverForName:@"WyrmOpenSettings" object:nil queue:nil usingBlock:^(NSNotification* n) {
                   WSettingsOpenPage = [n.object integerValue];
                   [weak.tabs choose:TAB_SETTINGS];
                 }],
                 [nc addObserverForName:@"WyrmOpenHudEditor" object:nil queue:nil usingBlock:^(NSNotification* n) { [weak openEditor]; }]];
  return self;
}
- (void)dealloc { for (id o in self.observers) [NSNotificationCenter.defaultCenter removeObserver:o]; }

/* Home and the account screens cover the engine; in a match only the cards take clicks. */
- (BOOL)coversEngine {
  return self.state == WYRM_SHELL_HOME || [WAccount shared].gate != WGateIn || self.auth || self.dialog || self.editor;
}
- (NSView*)hitTest:(NSPoint)point {
  NSView* hit = [super hitTest:point];
  if (self.coversEngine) return hit;
  if (hit && hit != self) return hit;
  return nil;
}
- (void)showTab:(int)tab {
  openTab = tab;
  self.scroll.hidden = tab != TAB_PLAY;
  self.settings.hidden = tab != TAB_SETTINGS;
  self.soon.hidden = tab == TAB_PLAY || tab == TAB_SETTINGS;
  if (!self.soon.hidden) [self.soon show:tab];
  if (tab == TAB_SETTINGS) [self.settings reload];
  [self.window makeFirstResponder:nil];
}
- (void)openPicker {
  if (self.picker) return;
  WPicker* picker = [WPicker new];
  __weak WShell* weak = self;
  __weak WPicker* weakPicker = picker;
  picker.onClose = ^{ [weak closePicker]; };
  picker.onChoose = ^(NSString* endpoint) {
    [weak.play choose:endpoint];
    [weak.lobby refresh];
    [weak closePicker];
  };
  picker.frame = self.bounds;
  [self addSubview:picker positioned:NSWindowBelow relativeTo:self.death];
  self.picker = picker;
  [picker present];
  (void)weakPicker;
}
- (void)closePicker {
  WPicker* picker = self.picker;
  if (!picker) return;
  self.picker = nil;
  [self.window makeFirstResponder:self.lobby];
  [picker dismiss:^{ [picker removeFromSuperview]; }];
}
/* Home's arena card leads to the Ready Room; matches start from it. */
- (void)openLobby {
  lobbyOpen = YES;
  if (self.lobby) return;
  self.lobby = [WLobby new];
  __weak WShell* weak = self;
  self.lobby.onHome = ^{ [weak closeLobby]; };
  self.lobby.onPick = ^{ [weak openPicker]; };
  self.lobby.frame = self.bounds;
  [self addSubview:self.lobby positioned:NSWindowBelow relativeTo:self.death];
}
- (void)closeLobby {
  lobbyOpen = NO;
  WLobby* l = self.lobby;
  self.lobby = nil;
  [NSAnimationContext runAnimationGroup:^(NSAnimationContext* ctx) { ctx.duration = 0.2; l.animator.alphaValue = 0; }
                      completionHandler:^{ [l removeFromSuperview]; }];
  [self.play refreshArena];
  [self.window makeFirstResponder:nil];
}
- (void)openAlerts {
  if (self.alerts) return;
  self.alerts = [WAlerts new];
  __weak WShell* weak = self;
  self.alerts.onClose = ^{
    WAlerts* a = weak.alerts;
    weak.alerts = nil;
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext* ctx) { ctx.duration = 0.2; a.animator.alphaValue = 0; }
                        completionHandler:^{ [a removeFromSuperview]; }];
  };
  self.alerts.frame = self.bounds;
  [self addSubview:self.alerts positioned:NSWindowBelow relativeTo:self.death];
}
- (void)openEditor {
  if (self.editor) return;
  self.editor = [WHudEditor new];
  __weak WShell* weak = self;
  self.editor.onClose = ^{
    [weak.editor removeFromSuperview];
    weak.editor = nil;
    [weak.window makeFirstResponder:nil];
  };
  self.editor.frame = self.bounds;
  [self addSubview:self.editor];
}
- (void)directoryChanged {
  [self.play refreshArena];
  [self.lobby refresh];
  [self.picker reload];
}

#pragma mark Account: one W for launch, sign-in and log out

- (void)working:(NSString*)title {
  if (self.auth) { [self.auth showWorking:title]; return; }
  [self adoptAuth:[[WAuthView alloc] initWithFrame:self.bounds working:title]];
}
/* The sign-in goes over everything here (only a dialog stays above it). */
- (void)adoptAuth:(WAuthView*)auth {
  [auth removeFromSuperview];
  auth.frame = self.bounds;
  self.auth = auth;
  [self wireAuth];
  if (self.dialog.superview == self) [self addSubview:auth positioned:NSWindowBelow relativeTo:self.dialog];
  else [self addSubview:auth positioned:NSWindowAbove relativeTo:nil];
  [self.window makeFirstResponder:auth];
}
- (void)wireAuth {
  __weak WShell* weak = self;
  self.auth.onComplete = ^{ [WAccount shared].gate = WGateIn; [weak.play refreshAccount]; };
  /* The account is in: the window grows to the app around the W (Desktop). */
  self.auth.onAccountIn = ^{ sizeWindow(weak.window, YES, YES, NO); };
}
- (void)dropAuth {
  WAuthView* a = self.auth;
  self.auth = nil;
  [NSAnimationContext runAnimationGroup:^(NSAnimationContext* ctx) { ctx.duration = 0.3; a.animator.alphaValue = 0; }
                      completionHandler:^{ [a removeFromSuperview]; }];
}
- (void)applyGate:(WGate)gate {
  if (gate == WGateSignIn) {
    if (self.auth) [self.auth showLanding];
    else [self adoptAuth:[[WAuthView alloc] initWithFrame:self.bounds]];
    [self.window makeFirstResponder:self.auth];
  } else if (gate == WGateResuming) {
    [self working:@"Syncing your Wyrm…"];
  } else {
    if (self.auth) [self dropAuth];
    [self.play refreshAccount];
    [self.settings reload];
  }
  [self setNeedsLayout:YES];
}
- (void)transition:(NSString*)title {
  if (title) [self working:title];
  else if ([WAccount shared].gate == WGateIn && self.auth) [self dropAuth];
}
- (void)askLogOut {
  __weak WShell* weak = self;
  self.dialog = WLogOutSheet(^{ [weak closeDialog]; [[WAccount shared] logOut:NO]; }, ^{ [weak closeDialog]; });
  [self presentDialog];
}
- (void)saveFailed:(NSString*)message {
  __weak WShell* weak = self;
  self.dialog = WSaveFailedDialog(message, ^{ [weak closeDialog]; [[WAccount shared] logOut:NO]; },
                                  ^{ [weak closeDialog]; [[WAccount shared] logOut:YES]; }, ^{ [weak closeDialog]; });
  [self presentDialog];
}
- (void)presentDialog {
  self.dialog.frame = self.bounds;
  [self addSubview:self.dialog];
  [self.dialog present];
}
- (void)closeDialog {
  [self.dialog dismiss];
  self.dialog = nil;
}

- (void)setShellState:(int)state score:(int)score {
  if (state == self.state) return;
  self.state = state;
  BOOL home = state == WYRM_SHELL_HOME;
  if (!home && self.picker) [self closePicker];
  if (!home && self.alerts) self.alerts.onClose();
  /* Faded-out pages are hidden too, so they neither draw nor take the engine's mouse. */
  NSMutableArray* pages = [@[self.paper, self.tabs, openTab == TAB_PLAY ? self.scroll : openTab == TAB_SETTINGS ? self.settings : self.soon] mutableCopy];
  if (self.lobby) [pages addObject:self.lobby];
  if (home) for (NSView* v in pages) v.hidden = NO;
  [NSAnimationContext runAnimationGroup:^(NSAnimationContext* ctx) {
    ctx.duration = 0.2;
    for (NSView* v in pages) v.animator.alphaValue = home ? 1 : 0;
  } completionHandler:^{
    if (self.state != WYRM_SHELL_HOME) for (NSView* v in pages) v.hidden = YES;
  }];
  self.entering.hidden = state != WYRM_SHELL_CONNECTING || self.editor;
  self.death.hidden = state != WYRM_SHELL_DEAD;
  if (state == WYRM_SHELL_DEAD) self.deathScore.stringValue = [NSString stringWithFormat:@"Score  %@", grouped(score)];
  if (home) { [self.play showLastRun]; [self.lobby refresh]; if (self.lobby.entering) { self.lobby.entering = NO; [self.lobby refresh]; } }
  /* Keys go back to the engine's view in a match. */
  if (!home && !self.editor) [self.window makeFirstResponder:self.window.contentView];
  [self setNeedsLayout:YES];
}
- (void)layout {
  [super layout];
  NSSize s = self.bounds.size;
  place(self.paper, 0, 0, s.width, s.height);
  place(self.scroll, 0, 0, s.width, s.height);
  NSSize content = self.scroll.contentSize;
  if (fabs(self.play.frame.size.width - content.width) > 0.5)
    [self.play setFrameSize:NSMakeSize(content.width, MAX(self.play.frame.size.height, content.height))];
  [self.play setNeedsLayout:YES];
  place(self.soon, 0, 0, s.width, s.height);
  place(self.settings, 0, 0, s.width, s.height);
  CGFloat tw = MIN(640, MAX(480, s.width * 0.48));
  tw = MIN(tw, s.width - 32);
  place(self.tabs, (s.width - tw) / 2, 18, tw, 56);
  for (NSView* v in @[self.picker ?: NSNull.null, self.auth ?: NSNull.null, self.dialog ?: NSNull.null, self.lobby ?: NSNull.null,
                      self.alerts ?: NSNull.null, self.editor ?: NSNull.null])
    if ([v isKindOfClass:NSView.class]) v.frame = self.bounds;
  CGFloat dw = MIN(380, s.width - 48), dh = 196;
  place(self.death, (s.width - dw) / 2, s.height - dh - 48, dw, dh);
  placeLabel(self.deathTitle, 24, 22, dw - 48);
  placeLabel(self.deathScore, 24, 56, dw - 48);
  place(self.again, 24, 88, dw - 48, 44);
  place(self.home, 24, 140, dw - 48, 36);
  CGFloat ew = 280;
  place(self.entering, (s.width - ew) / 2, 28, ew, 64);
  placeLabel(self.enterTitle, 22, 13, ew - 44);
  placeLabel(self.enterHint, 22, 35, ew - 44);
}
@end

#pragma mark - Window: the sign-in card and the app

static const CGFloat SIGN_IN_W = 860, SIGN_IN_H = 540, APP_W = 1280, APP_H = 800;
static void* sdlWindow;
static NSTimer* sizing;
static int windowShape = -1;  // 0 the card, 1 the app

static CGFloat easeAt(CGFloat p) {
  /* FastOutSlowIn (0.4, 0, 0.2, 1), solved for the time fraction. */
  CGFloat lo = 0, hi = 1, m = p;
  for (int i = 0; i < 20; i++) {
    m = (lo + hi) / 2;
    CGFloat x = 3 * (1 - m) * (1 - m) * m * 0.4 + 3 * (1 - m) * m * m * 0.2 + m * m * m;
    if (x < p) lo = m; else hi = m;
  }
  return 3 * (1 - m) * m * m + m * m * m;
}
static void minimumFor(BOOL app) {
  SDL_SetWindowMinimumSize(sdlWindow, app ? 1000 : SIGN_IN_W, app ? 640 : SIGN_IN_H);
  SDL_SetWindowResizable(sdlWindow, app);
}
/* Wyrm Desktop's window (Main.kt applyWindowSize): the card (860 × 540) while
   signed out, the app (1280 × 800) once the account is in. Between them it
   grows or shrinks on all four sides around its own centre in 520 ms
   (FastOutSlowIn); [onScreen] puts that centre in the middle of the screen
   (the first show). Log out leaves full screen first. */
static void sizeWindow(NSWindow* window, BOOL app, BOOL animated, BOOL onScreen) {
  if (!window) return;
  int shape = app ? 1 : 0;
  if (shape == windowShape && animated) return;
  windowShape = shape;
  [sizing invalidate];
  sizing = nil;
  if (window.styleMask & NSWindowStyleMaskFullScreen) {
    if (app) { minimumFor(YES); return; }
    [window toggleFullScreen:nil];
    WAfter(0.9, ^{ windowShape = 1; sizeWindow(window, NO, YES, NO); });
    return;
  }
  /* Shrinking needs the card's minimum first; growing takes the app's at the end. */
  if (!app) minimumFor(NO);
  NSRect from = window.frame;
  NSRect content = [window contentRectForFrameRect:from];
  NSRect screen = window.screen.visibleFrame;
  if (NSIsEmptyRect(screen)) screen = NSScreen.mainScreen.visibleFrame;
  NSPoint centre = onScreen ? NSMakePoint(NSMidX(screen), NSMidY(screen)) : NSMakePoint(NSMidX(content), NSMidY(content));
  NSSize to = app ? NSMakeSize(MIN(APP_W, screen.size.width), MIN(APP_H, screen.size.height - 28)) : NSMakeSize(SIGN_IN_W, SIGN_IN_H);
  NSRect target = [window frameRectForContentRect:NSMakeRect(centre.x - to.width / 2, centre.y - to.height / 2, to.width, to.height)];
  /* Kept on the screen it is on. */
  target.origin.x = MAX(screen.origin.x, MIN(NSMaxX(screen) - target.size.width, target.origin.x));
  target.origin.y = MAX(screen.origin.y, MIN(NSMaxY(screen) - target.size.height, target.origin.y));
  if (!animated || NSEqualRects(from, target)) {
    [window setFrame:target display:YES];
    if (app) minimumFor(YES);
    return;
  }
  CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
  sizing = [NSTimer timerWithTimeInterval:1.0 / 120 repeats:YES block:^(NSTimer* t) {
    CGFloat p = MIN(1, (CFAbsoluteTimeGetCurrent() - start) / 0.52), e = easeAt(p);
    NSRect r = NSMakeRect(from.origin.x + (target.origin.x - from.origin.x) * e, from.origin.y + (target.origin.y - from.origin.y) * e,
                          from.size.width + (target.size.width - from.size.width) * e, from.size.height + (target.size.height - from.size.height) * e);
    [window setFrame:NSIntegralRect(r) display:YES];
    if (p >= 1) {
      [t invalidate];
      sizing = nil;
      [window setFrame:target display:YES];
      if (app) minimumFor(YES);
    }
  }];
  [NSRunLoop.mainRunLoop addTimer:sizing forMode:NSRunLoopCommonModes];
}

#pragma mark - Engine bridge

static WShell* shell;
static int seenGeneration = -1, lastState = -1;
static double runStart;
static BOOL started, rebuildOwed;
static WPalette shownPalette;  // the palette the shell on screen was built with

/* While the shell covers the engine, the keyboard is the shell's alone. */
static bool keyFilter(void* data, SDL_Event* e) {
  (void)data;
  if (!shell || !shell.coversEngine) return true;
  switch (e->type) {
    case SDL_EVENT_KEY_DOWN: case SDL_EVENT_KEY_UP: case SDL_EVENT_TEXT_INPUT: case SDL_EVENT_TEXT_EDITING: return false;
    default: return true;
  }
}

/* As Android and iOS: the engine draws only where it can be seen (a match,
   the AI editors, the arena UI editor), never under Play, Settings or the
   sign-in. Its mailboxes and settings still run every pass (MacUI.c settles a
   few frames, then stops drawing). */
bool wyrm_mac_shell_shows_engine(void) {
  if (!shell || !shell.superview || [WAccount shared].gate != WGateIn || shell.auth) return false;
  return shell.editor || (shell.state >= 0 && shell.state != WYRM_SHELL_HOME);
}

/* The shell built again (a theme, a log out, a new account): the sign-in's W,
   if it is up, moves across whole, so it never starts over. */
static void buildShell(NSView* root) {
  WShell* old = shell;
  WAuthView* auth = old.auth;
  CGFloat settingsOffset = old ? old.settings.pageOffset : 0;
  int state = old ? old.state : -1;
  [old removeFromSuperview];
  shell = [WShell new];
  shell.frame = root.bounds;
  shell.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  root.window.backgroundColor = PAPER;
  root.window.appearance = [NSAppearance appearanceNamed:WP.dark ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua];
  [root addSubview:shell positioned:NSWindowAbove relativeTo:nil];
  if (auth) [shell adoptAuth:auth];
  if (state >= 0) [shell setShellState:state score:0];
  [shell layoutSubtreeIfNeeded];
  if (settingsOffset > 0) shell.settings.pageOffset = settingsOffset;
  shownPalette = WP;
  lastState = -1;
}
/* A theme builds the shell again (every surface reads its colours when built).
   Under the sign-in's W or the arena UI editor it recolours what is on screen
   at once instead, and the shell is built again when Play comes back. */
static void themeChanged(void) {
  if (!shell.superview) return;
  if (shell.auth || shell.editor || [WAccount shared].gate != WGateIn) {
    WRecolour(shell.window, shownPalette);
    shownPalette = WP;
    rebuildOwed = YES;
    return;
  }
  rebuildOwed = NO;
  buildShell(shell.superview);
}
/* Log out wipes this Mac (MacModel), so the app's own memory goes too: Play
   opens fresh for the next account. */
static void forgetAccount(void) {
  hasLastRun = NO;
  lastScore = lastKills = 0;
  lastSeconds = 0;
  alertRows = nil;
  openTab = TAB_PLAY;
  WSettingsOpenPage = 0;
  lobbyOpen = NO;
  chosenEndpoint = @"";
}

/* `--shell-page play|settings:N`: an offline look at one page (Desktop's pageShot), no account. */
const char* wyrm_mac_shell_page;
const char* wyrm_mac_shell_snapshot_path;

/* Layer-backed views draw through Core Animation, so the page is rendered from
   its layer tree (glass is drawn by the window server and does not appear). */
static void snapshot(NSView* view, NSString* path) {
  [view layoutSubtreeIfNeeded];
  [view displayIfNeeded];
  CGFloat scale = view.window.backingScaleFactor ?: 2;
  NSSize s = view.bounds.size;
  NSBitmapImageRep* rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:(NSInteger)(s.width * scale)
      pixelsHigh:(NSInteger)(s.height * scale) bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
      colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
  NSGraphicsContext* g = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
  CGContextRef c = g.CGContext;
  CGContextScaleCTM(c, scale, scale);
  [PAPER setFill];
  CGContextSetFillColorWithColor(c, PAPER.CGColor);
  CGContextFillRect(c, CGRectMake(0, 0, s.width, s.height));
  if (view.isFlipped) { CGContextTranslateCTM(c, 0, s.height); CGContextScaleCTM(c, 1, -1); }
  [view.layer renderInContext:c];
  [[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES];
}

static void start(NSWindow* window) {
  started = YES;
  [WStore loadTheme];
  [WStore publishAll];
  SDL_SetEventFilter(keyFilter, NULL);
  WAccount* account = [WAccount shared];
  if (wyrm_mac_shell_page) {
    account.gate = WGateIn;
    NSString* page = @(wyrm_mac_shell_page);
    if ([page hasPrefix:@"settings:"]) { openTab = TAB_SETTINGS; WSettingsOpenPage = [[page substringFromIndex:9] integerValue]; }
    buildShell(window.contentView);
    sizeWindow(window, YES, NO, YES);
    /* WYRM_SHELL_SWEEP=<dir>: every page, the picker, the lobby, alerts and the
       editor once, each saved as a picture in <dir>, then quit (a crash and
       layout check that never shows the window). */
    const char* sweep = getenv("WYRM_SHELL_SWEEP");
    if (sweep) {
      NSString* dir = @(sweep);
      [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
      double t = 1.5;
      WAfter(t, ^{ snapshot(shell, [dir stringByAppendingPathComponent:@"play.png"]); });
      t += 0.6;
      for (int i = 0; i < 12; i++, t += 0.9) {
        WAfter(t, ^{
          SDL_Log("Wyrm sweep: settings page %d", i);
          [NSNotificationCenter.defaultCenter postNotificationName:@"WyrmOpenSettings" object:@(i)];
        });
        WAfter(t + 0.7, ^{ snapshot(shell, [dir stringByAppendingPathComponent:[NSString stringWithFormat:@"settings-%02d.png", i]]); });
      }
      WAfter(t, ^{ SDL_Log("Wyrm sweep: play + picker"); [shell.tabs choose:TAB_PLAY]; [shell openPicker]; });
      WAfter(t + 2.5, ^{ snapshot(shell, [dir stringByAppendingPathComponent:@"picker.png"]); [shell closePicker]; [shell openLobby]; });
      WAfter(t + 3.5, ^{ snapshot(shell, [dir stringByAppendingPathComponent:@"lobby.png"]); [shell closeLobby]; [shell openAlerts]; });
      WAfter(t + 4.5, ^{ snapshot(shell, [dir stringByAppendingPathComponent:@"alerts.png"]); if (shell.alerts.onClose) shell.alerts.onClose(); });
      WAfter(t + 5.2, ^{ SDL_Log("Wyrm sweep: editor"); [shell openEditor]; });
      WAfter(t + 8, ^{ snapshot(shell, [dir stringByAppendingPathComponent:@"editor.png"]); [shell.editor close:NO]; });
      WAfter(t + 9, ^{
        WAuthView* auth = [[WAuthView alloc] initWithFrame:shell.bounds];
        [shell adoptAuth:auth];
      });
      WAfter(t + 12, ^{ snapshot(shell, [dir stringByAppendingPathComponent:@"auth.png"]); });
      WAfter(t + 13, ^{
        SDL_Log("WYRM_SHELL_SWEEP_OK");
        SDL_Event quit = {0};
        quit.type = SDL_EVENT_QUIT;
        SDL_PushEvent(&quit);
      });
    } else WAfter(0.15, ^{ window.animator.alphaValue = 1; });
    return;
  }
  account.onGate = ^(WGate gate) {
    if (gate == WGateSignIn) {
      /* Signed out (or the saved session was refused): a fresh app behind the W. */
      forgetAccount();
      rebuildOwed = NO;
      buildShell(window.contentView);
    } else if (gate == WGateIn && rebuildOwed) {
      rebuildOwed = NO;
      buildShell(window.contentView);
    }
    [shell applyGate:gate];
    sizeWindow(window, gate != WGateSignIn, YES, NO);
  };
  account.onTransition = ^(NSString* title) { [shell transition:title]; };
  account.onLogOutFailed = ^(NSString* message) { [shell saveFailed:message]; };
  [NSNotificationCenter.defaultCenter addObserverForName:WThemeChanged object:nil queue:nil usingBlock:^(NSNotification* n) {
    dispatch_async(dispatch_get_main_queue(), ^{ themeChanged(); });
  }];
  [NSNotificationCenter.defaultCenter addObserverForName:NSWindowDidResignKeyNotification object:window queue:nil usingBlock:^(NSNotification* n) {
    [[WAccount shared] save:NO done:nil];
  }];
  /* Signed in already: the app's size in the middle of the screen from the
     first frame; otherwise the card there (Desktop). */
  sizeWindow(window, account.gate != WGateSignIn, NO, YES);
  [shell applyGate:account.gate];
  WAfter(0.12, ^{
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext* ctx) {
      ctx.duration = 0.18;
      window.animator.alphaValue = 1;
    }];
  });
  if (account.gate == WGateResuming) {
    [account resume:^(BOOL signedIn) {
      if (!signedIn) { account.gate = WGateSignIn; return; }
      [account bootstrap:^{ [shell.auth completeIntoApp]; }];
    }];
  }
}

void wyrm_mac_shell_frame(void* window_, int state, int score) {
  if (!window_) return;
  sdlWindow = window_;
  NSWindow* window = (__bridge NSWindow*)SDL_GetPointerProperty(SDL_GetWindowProperties(window_), SDL_PROP_WINDOW_COCOA_WINDOW_POINTER, NULL);
  NSView* root = window.contentView;
  if (!root) return;
  if (!started) {
    [WStore loadTheme];
    buildShell(root);
    start(window);
  }
  /* SDL adds its Metal view when Vulkan starts: keep the shell above it. */
  if (shell.superview != root || root.subviews.lastObject != shell)
    [root addSubview:shell positioned:NSWindowAbove relativeTo:nil];
  int generation = wyrm_mac_directory_generation();
  if (generation != seenGeneration) {
    seenGeneration = generation;
    [shell directoryChanged];
  }
  if (state != lastState) {
    double now = CFAbsoluteTimeGetCurrent();
    if (state == WYRM_SHELL_PLAYING && lastState != WYRM_SHELL_PLAYING) runStart = now;
    if (state == WYRM_SHELL_DEAD && runStart > 0 && !shell.editor) {
      hasLastRun = YES;
      lastScore = score;
      lastKills = wyrm_mac_kills();
      lastSeconds = (long)(now - runStart);
      runStart = 0;
    }
    lastState = state;
  }
  [shell setShellState:state score:score];
}

void wyrm_mac_shell_will_quit(void) { [[WAccount shared] saveBeforeQuit]; }

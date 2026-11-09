#import <AppKit/AppKit.h>
#include <SDL3/SDL.h>
#include <unistd.h>
#include <ctype.h>
#include <SDL3/SDL_main.h>
#include "MacCompat.h"
void WInstallAccent(void);
extern bool wyrm_mac_smoke_enabled, wyrm_mac_smoke_passed;
extern const char* wyrm_mac_shell_snapshot_path;
extern const char* wyrm_mac_shell_page;

static char sessionPath[PATH_MAX];
static char files[3][PATH_MAX];
static char endpoints[2048][64];
static int populations[2048], ids[2048], arenaCount;
static char directoryStatus[160] = "Loading arenas...";
static bool loading;
static int directoryGeneration;

void* SDL_GetAndroidJNIEnv(void) { return NULL; }
void* SDL_GetAndroidActivity(void) { return NULL; }
void wyrm_desktop_initial_size(int* w, int* h) { *w = 1280; *h = 800; }
/* Invisible until the shell is on it (MacShell fades it in): no engine frame,
   minimap or wrong size ever shows first. */
void wyrm_desktop_window_created(void* p) {
  SDL_SetWindowMinimumSize(p, 660, 600);
  if (wyrm_mac_smoke_enabled) return;
  NSWindow* w = (__bridge NSWindow*)SDL_GetPointerProperty(SDL_GetWindowProperties(p), SDL_PROP_WINDOW_COCOA_WINDOW_POINTER, NULL);
  w.alphaValue = 0;
}
void wyrm_desktop_apply_size(void* p) { (void)p; }
const char* wyrm_desktop_user_file(const char* suffix) {
  int n = !strcmp(suffix, ".tmp") ? 1 : !strcmp(suffix, ".bak") ? 2 : 0;
  return files[n];
}
int wyrm_mac_arena_count(void) { return arenaCount; }
const char* wyrm_mac_arena(int n, int* players) {
  if (n < 0 || n >= arenaCount) { if (players) *players = 0; return ""; }
  if (players) *players = populations[n];
  return endpoints[n];
}
int wyrm_mac_arena_id(int n) { return n >= 0 && n < arenaCount ? ids[n] : -1; }
const char* wyrm_mac_directory_status(void) { return directoryStatus; }
int wyrm_mac_directory_generation(void) { return directoryGeneration; }

/* Same bounded nibble decoder and 28/11-byte records as Android's directory.
   Background fetch publishes only on the main queue, drained by SDL's Cocoa pump. */
void wyrm_mac_refresh_directory(void) {
  if (loading) return;
  loading = true;
  snprintf(directoryStatus, sizeof(directoryStatus), "Loading arenas...");
  directoryGeneration++;
  NSURLSessionConfiguration* config = NSURLSessionConfiguration.ephemeralSessionConfiguration;
  config.timeoutIntervalForRequest = 10;
  config.timeoutIntervalForResource = 15;
  NSURLSession* session = [NSURLSession sessionWithConfiguration:config];
  NSURL* url = [NSURL URLWithString:@"https://slither.io/i80124.txt"];
  [[session dataTaskWithURL:url completionHandler:^(NSData* data, NSURLResponse* response, NSError* error) {
    NSMutableData* decoded = [NSMutableData data];
    BOOL ok = !error && [(NSHTTPURLResponse*)response statusCode] == 200 && data.length <= 128*1024;
    const unsigned char* b = data.bytes;
    NSUInteger end = data.length;
    while (end && isspace(b[end-1])) end--;
    ok = ok && end >= 3 && (end - 1) % 2 == 0;
    int shift = 0, high = 0;
    if (ok) for (NSUInteger i = 0; i < end-1; i++) {
      int v = ((int)b[i+1] - 'a' - shift) % 26;
      if (v < 0) v += 26;
      if (v > 15) { ok = NO; break; }
      if (i % 2 == 0) high = v << 4;
      else { unsigned char v8 = high | v; [decoded appendBytes:&v8 length:1]; }
      shift = (shift + 7) % 26;
    }
    int record = decoded.length && decoded.length % 28 == 0 ? 28 :
                 decoded.length && decoded.length % 11 == 0 ? 11 : 0;
    ok = ok && record;
    dispatch_async(dispatch_get_main_queue(), ^{
      if (ok) {
        arenaCount = 0;
        const unsigned char* bytes = decoded.bytes;
        for (NSUInteger i = 0; i + record <= decoded.length && arenaCount < 2048; i += record) {
          const unsigned char* r = bytes + i;
          int at = record == 28 ? 1 : 0;
          int port = record == 28 ? (r[21]<<8)|r[22] : (r[4]<<16)|(r[5]<<8)|r[6];
          if (!port || port > 65535 || !(r[at]|r[at+1]|r[at+2]|r[at+3])) continue;
          snprintf(endpoints[arenaCount], 64, "%u.%u.%u.%u:%d",r[at],r[at+1],r[at+2],r[at+3],port);
          ids[arenaCount] = record == 28 ? (r[26]<<8)|r[27] : (int)(i / record) + 1;
          populations[arenaCount++] = record == 28 ? (r[23]<<8)|r[24] : (r[7]<<16)|(r[8]<<8)|r[9];
        }
        snprintf(directoryStatus, sizeof(directoryStatus), "%d live arenas. Select one or enter a custom address.", arenaCount);
      } else snprintf(directoryStatus, sizeof(directoryStatus), "Couldn't load arenas. Refresh or enter an IP:port; AI works offline.");
      loading = false;
      directoryGeneration++;
    });
    [session finishTasksAndInvalidate];
  }] resume];
}

int main(int argc, char** argv) {
  @autoreleasepool {
    WInstallAccent();
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    NSString* logs = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Logs/Wyrm"];
    [NSFileManager.defaultManager createDirectoryAtPath:logs withIntermediateDirectories:YES attributes:nil error:nil];
    freopen([[logs stringByAppendingPathComponent:@"engine.log"] fileSystemRepresentation], "w", stderr);
    setvbuf(stderr, NULL, _IOLBF, 0);
    /* This engine uses five ordinary bindings, not bindless resources. Metal 2
       virtual Intel drivers abort inside MoltenVK's argument-encoder probe. */
    setenv("MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS", "0", 1);
    NSString* resources = NSBundle.mainBundle.resourcePath;
    if (!resources || chdir(resources.fileSystemRepresentation)) return 1;
    /* Accounts arrived (2026-10-21): the engine's settings file persists like
       Desktop's %APPDATA%\Wyrm, and log out resets it (MacModel wipe). */
    NSString* support = [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject
                         stringByAppendingPathComponent:@"Wyrm"];
    [NSFileManager.defaultManager createDirectoryAtPath:support withIntermediateDirectories:YES attributes:nil error:nil];
    for (int n = 1; n < argc; n++)
      if (!strcmp(argv[n], "--smoke-ai")) wyrm_mac_smoke_enabled = true;
    /* The offline check never touches the player's own file. */
    if (wyrm_mac_smoke_enabled) support = [NSTemporaryDirectory() stringByAppendingPathComponent:@"Wyrm-smoke"];
    [NSFileManager.defaultManager createDirectoryAtPath:support withIntermediateDirectories:YES attributes:nil error:nil];
    snprintf(sessionPath, sizeof(sessionPath), "%s", support.fileSystemRepresentation);
    snprintf(files[0], PATH_MAX, "%s/user.dat", sessionPath);
    snprintf(files[1], PATH_MAX, "%s/user.dat.tmp", sessionPath);
    snprintf(files[2], PATH_MAX, "%s/user.dat.bak", sessionPath);
    SDL_SetMainReady();
    for (int n = 1; n < argc; n++)
      if (!strcmp(argv[n], "--smoke-ai")) wyrm_mac_smoke_enabled = true;
      else if (!strcmp(argv[n], "--shell-snapshot") && n + 1 < argc) wyrm_mac_shell_snapshot_path = argv[++n];
      else if (!strcmp(argv[n], "--shell-page") && n + 1 < argc) wyrm_mac_shell_page = argv[++n];
    if (!wyrm_mac_smoke_enabled) wyrm_mac_refresh_directory();
    int result = wyrm_engine_main(argc, argv);
    if (!wyrm_mac_smoke_enabled) wyrm_mac_shell_will_quit();
    SDL_Quit();
    if (wyrm_mac_smoke_enabled) return result ? result : wyrm_mac_smoke_passed ? 0 : 2;
    if (result) {
      NSAlert* alert = [[NSAlert alloc] init];
      alert.messageText = @"Wyrm couldn't start the engine";
      alert.informativeText = @"Check that Metal graphics acceleration is working. Details are in ~/Library/Logs/Wyrm/engine.log.";
      [alert runModal];
    }
    return result;
  }
}

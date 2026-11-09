#include "user.h"
#include "platform/android_home.h"
#include <SDL3/SDL.h>

bool wyrm_mac_smoke_enabled, wyrm_mac_smoke_passed;
static void smoke_tick(tenv* env) {
  if (!wyrm_mac_smoke_enabled) return;
  static unsigned ticks, frames;
  ticks++;
  if (ticks == 5) wyrm_mac_play("Mac engine check", "", true);
  if (ticks == 10 || ticks == 11) {
    SDL_Event event = {0};
    event.type = ticks == 10 ? SDL_EVENT_KEY_DOWN : SDL_EVENT_KEY_UP;
    event.key.windowID = SDL_GetWindowID(env->wnd->handle);
    event.key.scancode = SDL_SCANCODE_RETURN;
    event.key.key = SDLK_RETURN;
    event.key.down = ticks == 10;
    SDL_PushEvent(&event);
  }
  if (env->usr->gdata.ai_mode && env->ctx->last_present_succeeded) frames++;
  if (frames >= 120) {
    int snakes = tdarray_length(env->usr->gdata.data.snakes);
    wyrm_mac_smoke_passed = snakes > 0 && !env->usr->gdata.connection;
    SDL_Log("WYRM_MAC_SMOKE_%s presented=%u snakes=%d socket=%p",
            wyrm_mac_smoke_passed ? "OK" : "FAILED", frames, snakes,
            (void*)env->usr->gdata.connection);
    env->config.running = false;
  }
}

static tenv* shell_env;
const char* wyrm_mac_saved_nickname(void) { return shell_env ? shell_env->usr->usrs.nickname : NULL; }
int wyrm_mac_kills(void) { return shell_env ? shell_env->usr->gdata.data.kills : 0; }
const char* wyrm_mac_saved_arena(void) { return shell_env ? user_settings_arena(&shell_env->usr->usrs) : NULL; }

/* Android's wyrm_engine_visible for the Mac: drawn in a match, the AI editors
   and the arena UI editor; under Play, Settings and the sign-in a few settle
   frames, then nothing (the mailboxes and settings still run every pass). */
#define WYRM_MAC_SETTLE_FRAMES 4
bool wyrm_mac_engine_visible(tenv* env) {
  static int settle = WYRM_MAC_SETTLE_FRAMES;
  if (wyrm_mac_smoke_enabled || !env->ctx->last_present_succeeded) return true;
  if (wyrm_mac_shell_shows_engine()) { settle = WYRM_MAC_SETTLE_FRAMES; return true; }
  if (settle > 0) { settle--; return true; }
  return false;
}

/* The launcher is the native AppKit shell (MacShell.m); the engine only reports its state. */
void wyrm_mac_ui(tenv* env) {
  smoke_tick(env);
  shell_env = env;
  tuser_data* user = env->usr;
  bool home = user->gdata.curr_screen == TITLE_SCREEN ||
              (user->gdata.curr_screen == LOBBY && user->gdata.conn == DISCONNECTED);
  int state = android_home_death_active() ? WYRM_SHELL_DEAD
            : home ? WYRM_SHELL_HOME
            : user->gdata.conn == CONNECTING ? WYRM_SHELL_CONNECTING
            : WYRM_SHELL_PLAYING;
  wyrm_mac_shell_frame(env->wnd->handle, state, user->gdata.data.score);
}

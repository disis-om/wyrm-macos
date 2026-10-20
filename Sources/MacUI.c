#include "user.h"
#include "network/server.h"
#include "platform/android_home.h"
#include <SDL3/SDL.h>
#include <string.h>

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

/* Paper, dark ink, generous spacing: intentionally small engine-first launcher. */
void wyrm_mac_ui(tenv* env) {
  smoke_tick(env);
  tuser_data* user = env->usr;
  bool home = user->gdata.curr_screen == TITLE_SCREEN ||
              (user->gdata.curr_screen == LOBBY && user->gdata.conn == DISCONNECTED);
  bool dead = android_home_death_active();
  bool connecting = user->gdata.conn == CONNECTING;
  if (!home && !dead && !connecting) return;
  ImGuiViewport* vp = igGetMainViewport();
  float width = fminf(560, vp->Size.x - 40);
  igSetNextWindowPos((ImVec2){vp->Size.x * .5f, vp->Size.y * .5f},
                    ImGuiCond_Always, (ImVec2){.5f, .5f});
  igSetNextWindowSize((ImVec2){width, home ? fminf(720, vp->Size.y - 40) : 0}, ImGuiCond_Always);
  igPushStyleVar_Vec2(ImGuiStyleVar_WindowPadding, (ImVec2){32, 28});
  igPushStyleVar_Vec2(ImGuiStyleVar_ItemSpacing, (ImVec2){12, 14});
  igPushStyleVar_Vec2(ImGuiStyleVar_FramePadding, (ImVec2){12, 10});
  igPushStyleVar_Float(ImGuiStyleVar_WindowRounding, 16);
  igPushStyleVar_Float(ImGuiStyleVar_FrameRounding, 8);
  igPushStyleColor_Vec4(ImGuiCol_WindowBg, (ImVec4){.969f,.965f,.953f,1});
  igPushStyleColor_Vec4(ImGuiCol_Text, (ImVec4){.12f,.16f,.13f,1});
  igPushStyleColor_Vec4(ImGuiCol_FrameBg, (ImVec4){.88f,.90f,.87f,1});
  igPushStyleColor_Vec4(ImGuiCol_Button, (ImVec4){.30f,.50f,.32f,1});
  igPushStyleColor_Vec4(ImGuiCol_ButtonHovered, (ImVec4){.42f,.64f,.42f,1});
  igPushStyleColor_Vec4(ImGuiCol_ButtonActive, (ImVec4){.24f,.42f,.26f,1});
  igBegin("Wyrm for Mac", NULL, ImGuiWindowFlags_NoTitleBar | ImGuiWindowFlags_NoResize |
          ImGuiWindowFlags_NoCollapse | ImGuiWindowFlags_NoMove |
          ImGuiWindowFlags_NoSavedSettings | ImGuiWindowFlags_AlwaysAutoResize);
  igPushFont(user->imgui_data.body_font[0], 18);
  igPushFont(user->imgui_data.display_font[1], 32);
  igTextUnformatted("W Y R M   /   M A C", NULL);
  igPopFont();
  igSeparator();
  if (dead) {
    igTextUnformatted("One more round?", NULL);
    igText("Score  %d", user->gdata.data.score);
    if (igButton("Play again", (ImVec2){width - 64, 44})) wyrm_mac_death(false);
    if (igButton("Back to arenas", (ImVec2){width - 64, 40})) wyrm_mac_death(true);
  } else if (connecting || (!home && user->gdata.conn != DISCONNECTED)) {
    igTextUnformatted("Entering arena...", NULL);
    igTextWrapped("Press Escape to cancel and choose again.");
  } else {
    static char name[MAX_NICKNAME_LEN + 1] = "Wyrm";
    static char arena[MAX_ARENA_LEN + 1] = "";
    static int selected = 0;
    igTextUnformatted("Pick an arena. Make it yours.", NULL);
    igSetNextItemWidth(-1);
    igInputText("##name", name, sizeof(name), ImGuiInputTextFlags_None, NULL, NULL);
    int count = wyrm_mac_arena_count();
    if (count && !arena[0]) snprintf(arena, sizeof(arena), "%s", wyrm_mac_arena(0, NULL));
    igTextUnformatted("Arena", NULL);
    igSetNextItemWidth(-1);
    if (igBeginCombo("##arena", arena[0] ? arena : "Choose an arena", 0)) {
      for (int i = 0; i < count; i++) {
        int players;
        const char* endpoint = wyrm_mac_arena(i, &players);
        char label[128];
        snprintf(label, sizeof(label), "%s   /   %d players", endpoint, players);
        if (igSelectable_Bool(label, selected == i, 0, (ImVec2){0,0})) {
          selected = i;
          snprintf(arena, sizeof(arena), "%s", endpoint);
        }
      }
      igEndCombo();
    }
    igSetNextItemWidth(-1);
    igInputTextWithHint("##endpoint", "Or enter IP:port", arena, sizeof(arena), 0, NULL, NULL);
    igTextWrapped("%s", wyrm_mac_directory_status());
    if (igSmallButton("Refresh arenas")) wyrm_mac_refresh_directory();
    bool valid = name[0] && server_address_is_valid(arena);
    igBeginDisabled(!valid);
    if (igButton("Play", (ImVec2){width - 64, 48})) wyrm_mac_play(name, arena, false);
    igEndDisabled();
    if (igButton("Practice with AI", (ImVec2){width - 64, 40}))
      wyrm_mac_play(name[0] ? name : "Wyrm", "", true);
    igTextWrapped("Mouse to steer  /  Click or Space to boost\nP assist  /  Q leave  /  F11 fullscreen");
  }
  igPopFont();
  igEnd();
  igPopStyleColor(6);
  igPopStyleVar(5);
}

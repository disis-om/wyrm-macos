#pragma once
#include <stdbool.h>
#include <vulkan/vulkan.h>
#ifdef __cplusplus
extern "C" {
#endif
struct tenv;
void* SDL_GetAndroidJNIEnv(void);
void* SDL_GetAndroidActivity(void);
void wyrm_desktop_initial_size(int*, int*);
void wyrm_desktop_window_created(void*);
void wyrm_desktop_apply_size(void*);
void wyrm_mac_ui(struct tenv*);
void wyrm_mac_play(const char*, const char*, bool);
void wyrm_mac_death(bool);
VkResult wyrm_mac_create_instance(const VkInstanceCreateInfo*, const VkAllocationCallbacks*, VkInstance*);
VkResult wyrm_mac_create_device(VkPhysicalDevice, const VkDeviceCreateInfo*, const VkAllocationCallbacks*, VkDevice*);
int wyrm_engine_main(int, char**);
int wyrm_mac_arena_count(void);
const char* wyrm_mac_arena(int, int*);
const char* wyrm_mac_directory_status(void);
void wyrm_mac_refresh_directory(void);
int wyrm_mac_directory_generation(void);
int wyrm_mac_arena_id(int);
extern bool wyrm_mac_smoke_enabled;
bool wyrm_mac_engine_visible(struct tenv*);
bool wyrm_mac_shell_shows_engine(void);
enum { WYRM_SHELL_HOME, WYRM_SHELL_CONNECTING, WYRM_SHELL_PLAYING, WYRM_SHELL_DEAD };
void wyrm_mac_shell_frame(void* sdl_window, int state, int score);
/* MacJNI.c: the engine's JNI bridges called without a JVM. Strings are malloc'd. */
char* wyrm_mac_settings_snapshot(void);
char* wyrm_mac_hotkeys_snapshot(void);
char* wyrm_mac_key_options(void);
char* wyrm_mac_settings_version(void);
void wyrm_mac_set_setting(const char* id, const float* values, int count);
void wyrm_mac_set_hotkey(int action, int key, int mode, bool visible, float x, float y);
void wyrm_mac_settings_action(int action);
void wyrm_mac_set_nickname(const char* name);
void wyrm_mac_set_arena_theme(const int* roles, int count, bool dark);
void wyrm_mac_set_play_feel(bool original_arrow, bool look_ahead, int zoom_style);
void wyrm_mac_enter_layout_editor(const char* nickname);
void wyrm_mac_exit_layout_editor(void);
void wyrm_mac_team_rects(float out[8]);
void wyrm_mac_set_chat_tab(int tab);
void wyrm_mac_set_team_hud_style(const float* values, int count);
/* MacUI.c: what the engine's settings file holds. */
const char* wyrm_mac_saved_nickname(void);
const char* wyrm_mac_saved_arena(void);
int wyrm_mac_kills(void);
void wyrm_mac_shell_will_quit(void);
#ifdef __cplusplus
}
#endif

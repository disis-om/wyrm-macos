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
#ifdef __cplusplus
}
#endif

#include <jni.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>

/* The engine's settings, nickname, theme and play-feel bridges are the
   Android/Desktop JNI entry points. The Mac has no JVM, so they are called
   through a JNIEnv whose table holds only what those functions use: strings
   are plain UTF-8 buffers and the one int array is a length-prefixed block. */

typedef struct { jsize length; jint values[]; } mac_int_array;
typedef struct { jsize length; jfloat values[]; } mac_float_array;

static jstring new_string(JNIEnv* env, const char* text) { (void)env; return (jstring)strdup(text ? text : ""); }
static const char* string_chars(JNIEnv* env, jstring s, jboolean* copy) {
  (void)env;
  if (copy) *copy = JNI_FALSE;
  return (const char*)s;
}
static void release_chars(JNIEnv* env, jstring s, const char* chars) { (void)env; (void)s; (void)chars; }
static jsize array_length(JNIEnv* env, jarray a) { (void)env; return a ? ((mac_int_array*)a)->length : 0; }
static void int_region(JNIEnv* env, jintArray a, jsize start, jsize len, jint* out) {
  (void)env;
  mac_int_array* array = (mac_int_array*)a;
  for (jsize i = 0; i < len && start + i < array->length; i++) out[i] = array->values[start + i];
}
static jboolean no_exception(JNIEnv* env) { (void)env; return JNI_FALSE; }
static jfloatArray new_floats(JNIEnv* env, jsize n) {
  (void)env;
  mac_float_array* a = calloc(1, sizeof(mac_float_array) + sizeof(jfloat) * (size_t)n);
  a->length = n;
  return (jfloatArray)a;
}
static void set_floats(JNIEnv* env, jfloatArray a, jsize start, jsize len, const jfloat* in) {
  (void)env;
  mac_float_array* array = (mac_float_array*)a;
  for (jsize i = 0; i < len && start + i < array->length; i++) array->values[start + i] = in[i];
}
static void get_floats(JNIEnv* env, jfloatArray a, jsize start, jsize len, jfloat* out) {
  (void)env;
  mac_float_array* array = (mac_float_array*)a;
  for (jsize i = 0; i < len && start + i < array->length; i++) out[i] = array->values[start + i];
}

static struct JNINativeInterface_ table = {
  .NewStringUTF = new_string,
  .GetStringUTFChars = string_chars,
  .ReleaseStringUTFChars = release_chars,
  .GetArrayLength = array_length,
  .GetIntArrayRegion = int_region,
  .ExceptionCheck = no_exception,
  .NewFloatArray = new_floats,
  .SetFloatArrayRegion = set_floats,
  .GetFloatArrayRegion = get_floats,
};
static const struct JNINativeInterface_* table_ref = &table;
#define ENV ((JNIEnv*)&table_ref)

jstring Java_com_wyrm_omrajput_WyrmActivity_nativeSettingsSnapshot(JNIEnv*, jclass);
jstring Java_com_wyrm_omrajput_WyrmActivity_nativeHotkeysSnapshot(JNIEnv*, jclass);
jstring Java_com_wyrm_omrajput_WyrmActivity_nativeKeyOptions(JNIEnv*, jclass);
jstring Java_com_wyrm_omrajput_WyrmActivity_nativeSettingsVersion(JNIEnv*, jclass);
void Java_com_wyrm_omrajput_WyrmActivity_nativeSetSetting(JNIEnv*, jclass, jstring, jfloat, jfloat, jfloat, jfloat, jint);
void Java_com_wyrm_omrajput_WyrmActivity_nativeSetHotkey(JNIEnv*, jclass, jint, jint, jint, jboolean, jfloat, jfloat);
void Java_com_wyrm_omrajput_WyrmActivity_nativeSettingsAction(JNIEnv*, jclass, jint);
void Java_com_wyrm_omrajput_WyrmActivity_nativeSetNickname(JNIEnv*, jclass, jstring);
void Java_com_wyrm_omrajput_WyrmActivity_nativeSetArenaTheme(JNIEnv*, jclass, jintArray, jboolean);
void Java_com_wyrm_omrajput_WyrmActivity_nativeSetPlayFeel(JNIEnv*, jclass, jboolean, jboolean, jint);
void Java_com_wyrm_omrajput_WyrmActivity_nativeEnterAiLayoutEditor(JNIEnv*, jclass, jstring);
void Java_com_wyrm_omrajput_WyrmActivity_nativeExitAiLayoutEditor(JNIEnv*, jclass);
jfloatArray Java_com_wyrm_omrajput_WyrmActivity_nativeDesktopTeamRects(JNIEnv*, jclass);
void Java_com_wyrm_omrajput_WyrmActivity_nativeSetChatTab(JNIEnv*, jclass, jint);
void Java_com_wyrm_omrajput_WyrmActivity_nativeSetTeamHudStyle(JNIEnv*, jclass, jfloatArray);

char* wyrm_mac_settings_snapshot(void) { return (char*)Java_com_wyrm_omrajput_WyrmActivity_nativeSettingsSnapshot(ENV, NULL); }
char* wyrm_mac_hotkeys_snapshot(void) { return (char*)Java_com_wyrm_omrajput_WyrmActivity_nativeHotkeysSnapshot(ENV, NULL); }
char* wyrm_mac_key_options(void) { return (char*)Java_com_wyrm_omrajput_WyrmActivity_nativeKeyOptions(ENV, NULL); }
char* wyrm_mac_settings_version(void) { return (char*)Java_com_wyrm_omrajput_WyrmActivity_nativeSettingsVersion(ENV, NULL); }

void wyrm_mac_set_setting(const char* id, const float* v, int count) {
  float a[4] = {0};
  for (int i = 0; i < count && i < 4; i++) a[i] = v[i];
  Java_com_wyrm_omrajput_WyrmActivity_nativeSetSetting(ENV, NULL, (jstring)id, a[0], a[1], a[2], a[3], count);
}
void wyrm_mac_set_hotkey(int action, int key, int mode, bool visible, float x, float y) {
  Java_com_wyrm_omrajput_WyrmActivity_nativeSetHotkey(ENV, NULL, action, key, mode, visible ? JNI_TRUE : JNI_FALSE, x, y);
}
void wyrm_mac_settings_action(int action) { Java_com_wyrm_omrajput_WyrmActivity_nativeSettingsAction(ENV, NULL, action); }
void wyrm_mac_set_nickname(const char* name) { Java_com_wyrm_omrajput_WyrmActivity_nativeSetNickname(ENV, NULL, (jstring)name); }
void wyrm_mac_set_arena_theme(const int* roles, int count, bool dark) {
  mac_int_array* array = malloc(sizeof(mac_int_array) + sizeof(jint) * (size_t)count);
  array->length = count;
  for (int i = 0; i < count; i++) array->values[i] = roles[i];
  Java_com_wyrm_omrajput_WyrmActivity_nativeSetArenaTheme(ENV, NULL, (jintArray)array, dark ? JNI_TRUE : JNI_FALSE);
  free(array);
}
void wyrm_mac_set_play_feel(bool original_arrow, bool look_ahead, int zoom_style) {
  Java_com_wyrm_omrajput_WyrmActivity_nativeSetPlayFeel(ENV, NULL, original_arrow, look_ahead, zoom_style);
}

/* Settings > Display > Arrange arena UI (Desktop's HudEditor). */
void wyrm_mac_enter_layout_editor(const char* nickname) {
  Java_com_wyrm_omrajput_WyrmActivity_nativeEnterAiLayoutEditor(ENV, NULL, (jstring)nickname);
}
void wyrm_mac_exit_layout_editor(void) { Java_com_wyrm_omrajput_WyrmActivity_nativeExitAiLayoutEditor(ENV, NULL); }
void wyrm_mac_team_rects(float out[8]) {
  mac_float_array* a = (mac_float_array*)Java_com_wyrm_omrajput_WyrmActivity_nativeDesktopTeamRects(ENV, NULL);
  for (int i = 0; i < 8; i++) out[i] = a && i < a->length ? a->values[i] : 0;
  free(a);
}
void wyrm_mac_set_chat_tab(int tab) { Java_com_wyrm_omrajput_WyrmActivity_nativeSetChatTab(ENV, NULL, tab); }
void wyrm_mac_set_team_hud_style(const float* values, int count) {
  mac_float_array* a = (mac_float_array*)new_floats(ENV, count);
  for (int i = 0; i < count; i++) a->values[i] = values[i];
  Java_com_wyrm_omrajput_WyrmActivity_nativeSetTeamHudStyle(ENV, NULL, (jfloatArray)a);
  free(a);
}

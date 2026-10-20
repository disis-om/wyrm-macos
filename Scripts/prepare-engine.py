"""Verify the Desktop engine transport and generate only host adaptations."""
import hashlib
import json
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'SharedEngine'
OUT = ROOT / 'Generated'
manifest = json.loads((SOURCE / 'SHA256.json').read_text())
for name, digest in manifest['files'].items():
    assert hashlib.sha256((SOURCE / name).read_bytes()).hexdigest() == digest, name
assert set(manifest['files']) == {p.relative_to(SOURCE).as_posix() for p in SOURCE.rglob('*')
                                 if p.is_file() and p.name != 'SHA256.json'}
if OUT.exists():
    shutil.rmtree(OUT)
shutil.copytree(SOURCE, OUT)

def patch(name, old, new, count=1):
    path = OUT / name
    value = path.read_text()
    assert value.count(old) == count, f'{name}: adaptation anchor changed: {old[:70]}'
    path.write_text(value.replace(old, new))

# Keep desktop input, but remove Windows-only CPU readback/presentation.
patch('thermite/src/graphics/tcontext.c', '#ifdef WYRM_DESKTOP',
      '#if defined(WYRM_DESKTOP) && !defined(WYRM_MACOS)', 4)
patch('thermite/src/graphics/tcontext.c', 'vkCreateInstance(', 'wyrm_mac_create_instance(')
patch('thermite/src/graphics/tcontext.c', 'vkCreateDevice(', 'wyrm_mac_create_device(')
patch('thermite/src/framework/twindow.c',
      'SDL_WINDOW_VULKAN | SDL_WINDOW_HIDDEN | SDL_WINDOW_RESIZABLE',
      'SDL_WINDOW_VULKAN | SDL_WINDOW_RESIZABLE')
patch('thermite/src/framework/twindow.c', '    case SDL_EVENT_QUIT:',
      '    case SDL_EVENT_WINDOW_FOCUS_LOST:\n'
      '      memset(desktop_held, 0, sizeof(desktop_held));\n'
      '      break;\n    case SDL_EVENT_QUIT:')
patch('app/src/mobile/mobile_controls.c',
      '  if (ai_mode_notice_process_event(env, raw_event)) return true;',
      '  if (event->type == SDL_EVENT_WINDOW_FOCUS_LOST) {\n'
      '    reset_touches(state);\n    return false;\n  }\n'
      '  if (ai_mode_notice_process_event(env, raw_event)) return true;')
# Use 1:1 window pixels in this bring-up, avoiding logical/pixel pointer mismatch.
patch('thermite/src/framework/twindow.c', '(void)window;\n#elif defined(WYRM_SDL_JNI)',
      'bool on = !(SDL_GetWindowFlags(window->handle) & SDL_WINDOW_FULLSCREEN);\n'
      '  SDL_SetWindowFullscreen(window->handle, on);\n'
      '  window->env->config.fullscreen = on;\n#elif defined(WYRM_SDL_JNI)')
patch('app/src/main.c', 'TDEF_ENTRY();',
      'int wyrm_engine_main(int argc, char** argv) { return tentry(argc, argv, sizeof(tuser_data)); }')
patch('app/src/main.c', '  ui_theme_transition_end(env);',
      '  ui_theme_transition_end(env);\n  wyrm_mac_ui(env);')
patch('app/src/main.c', 'bool draw = !wyrm_background() && wyrm_engine_visible(env);',
      'bool draw = !wyrm_background(); /* Native launcher also needs presentation. */')
patch('app/src/game/ui_overlay.c', '#ifdef WYRM_DESKTOP\n        /* Draw the line',
      '#if defined(WYRM_DESKTOP) && !defined(WYRM_MACOS)\n        /* Draw the line')
patch('app/src/platform/android_home.c',
      '    SDL_Log("Wyrm home: JNI environment unavailable");', '')
patch('app/src/platform/android_update.c',
      '    SDL_Log("Wyrm updater: JNI environment unavailable");', '')
with (OUT / 'app/src/platform/android_home.c').open('a') as f:
    f.write('\n#include "MacMailbox.inc"\n')
print(f'Verified {len(manifest["files"])} engine files; generated macOS host adaptations.')

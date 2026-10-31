// On-screen controls for touch screens (runtime/hle/touch.c).
#pragma once
#include <SDL3/SDL.h>
#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

bool touch_handle_event(const SDL_Event *e, SDL_Window *w);  // main thread; true = a finger the controls took
bool touch_active(void);         // the controls are showing (fingers are theirs, not the mouse's)
void touch_reset(void);          // let every finger go (a menu took focus)
uint64_t touch_buttons(void);    // held, in input.c's button bits
void touch_stick(int32_t *x, int32_t *y);  // the left stick, -32767..32767, y up

// What to draw (runtime/ui/menu.mm), in the output's pixels: the window's units times scale
typedef struct { float x, y, r; const char *label; bool held; } TouchShape;
int touch_shapes(TouchShape *out, int max, float scale_x, float scale_y);

// (runtime/hle/input.c) a finger on the game's touch screen, in window units
void input_touch_screen(SDL_Window *w, float x, float y, bool down);
// (runtime/ui/menu.mm) the settings open / closed
void menu_toggle_settings(void);

#ifdef __cplusplus
}
#endif

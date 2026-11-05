// On-screen controls for touch screens (Android; LARECOMP_TOUCH=1 shows them on the desktop, the mouse as a finger):
// a stick that starts where the left thumb lands, A B X Y on the right (the Switch's places: A east), L / ZL and R / ZR
// in the top corners, - and + at the top, and a settings button between them. A finger anywhere else is a finger on
// the game's touch screen (the petting mode, the berry button). The controls show from the first touch and
// hide when a controller or the keyboard is used. Drawn by runtime/ui/menu.mm (touch_shapes).
#include <SDL3/SDL.h>
#include <math.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>

#include "../hle.h"
#include "../input_bind.h"
#include "touch.h"

extern bool menu_input_captured(void);  // runtime/ui/menu.mm

enum { B_A = 0, B_B, B_X, B_Y, B_LS, B_RS, B_L, B_R, B_ZL, B_ZR, B_PLUS, B_MINUS };  // (input.c's button bits)

// The controls, in window units: x from the left or (negative) the right edge, y from the top or (negative) the
// bottom, all in heights of the window (so they keep their size on any width); r = radius.
typedef struct { const char *label; int bit; float x, y, r; } Ctl;
#define SETTINGS_BIT 63  // (not a game button: opens the settings, menu.mm)
static const Ctl k_ctl[] = {
    {"A", B_A, -0.10f, -0.36f, 0.065f}, {"B", B_B, -0.22f, -0.24f, 0.065f},
    {"X", B_X, -0.22f, -0.48f, 0.065f}, {"Y", B_Y, -0.34f, -0.36f, 0.065f},
    {"L", B_L, 0.10f, 0.20f, 0.055f},   {"ZL", B_ZL, 0.10f, 0.07f, 0.05f},
    {"R", B_R, -0.10f, 0.20f, 0.055f},  {"ZR", B_ZR, -0.10f, 0.07f, 0.05f},
    {"-", B_MINUS, 0.30f, 0.07f, 0.045f}, {"+", B_PLUS, -0.30f, 0.07f, 0.045f},
    {"=", SETTINGS_BIT, 0, 0.07f, 0.045f},  // (x 0: the middle)
};
#define N_CTL (int)(sizeof k_ctl / sizeof *k_ctl)
#define STICK_R 0.13f      // the stick's travel
#define STICK_ZONE 0.42f   // the stick starts in the left part of the window (in window widths), below the top row
#define HIT 1.35f          // a button takes touches a little outside what is drawn

static _Atomic int g_shown = -1;  // -1: not decided yet (on by default on Android, LARECOMP_TOUCH elsewhere)
static _Atomic uint64_t g_buttons;
static _Atomic int32_t g_lx, g_ly;
static _Atomic float g_stick_x, g_stick_y, g_knob_x, g_knob_y;  // window pixels; g_stick_x < 0: no stick held
static float g_w = 1280, g_h = 720;  // the window, in its own units (the events')

// Fingers, by id: what each one holds
typedef struct { SDL_FingerID id; int ctl; float ox, oy; } Finger;  // ctl: index in k_ctl, -1 stick, -2 the screen
static Finger g_fingers[10];
static int g_nfingers;

static bool shown(void) {
    int s = g_shown;
    if (s < 0) {
        const char *e = getenv("LARECOMP_TOUCH");
#ifdef __ANDROID__
        s = !e || atoi(e) != 0 ? 1 : 0;
#else
        s = e && atoi(e) != 0 ? 1 : 0;
#endif
        g_shown = s;
    }
    return s > 0;
}

static float cx(const Ctl *c) { return c->x == 0 ? g_w * 0.5f : c->x > 0 ? c->x * g_h : g_w + c->x * g_h; }
static float cy(const Ctl *c) { return c->y >= 0 ? c->y * g_h : g_h + c->y * g_h; }

static int hit(float x, float y) {
    for (int i = 0; i < N_CTL; i++) {
        float dx = x - cx(&k_ctl[i]), dy = y - cy(&k_ctl[i]), r = k_ctl[i].r * g_h * HIT;
        if (dx * dx + dy * dy <= r * r) return i;
    }
    if (x < g_w * STICK_ZONE && y > 0.28f * g_h) return -1;
    return -2;
}

static void recompute(void) {
    uint64_t b = 0;
    bool stick = false;
    for (int i = 0; i < g_nfingers; i++) {
        Finger *f = &g_fingers[i];
        if (f->ctl >= 0 && k_ctl[f->ctl].bit != SETTINGS_BIT) b |= 1ull << k_ctl[f->ctl].bit;
        if (f->ctl == -1) stick = true;
    }
    g_buttons = b;
    if (!stick) { g_lx = g_ly = 0; g_stick_x = -1; }
}

static Finger *finger(SDL_FingerID id) {
    for (int i = 0; i < g_nfingers; i++)
        if (g_fingers[i].id == id) return &g_fingers[i];
    return NULL;
}

static void stick_move(Finger *f, float x, float y) {
    float dx = x - f->ox, dy = y - f->oy, r = STICK_R * g_h, m = sqrtf(dx * dx + dy * dy);
    if (m > r) dx *= r / m, dy *= r / m;
    g_lx = (int32_t)lroundf(dx / r * 32767), g_ly = (int32_t)lroundf(-dy / r * 32767);
    g_stick_x = f->ox, g_stick_y = f->oy, g_knob_x = f->ox + dx, g_knob_y = f->oy + dy;
}

bool touch_handle_event(const SDL_Event *e, SDL_Window *w) {
    switch (e->type) {
    case SDL_EVENT_KEY_DOWN: case SDL_EVENT_GAMEPAD_BUTTON_DOWN:
        if (shown() && !g_nfingers) g_shown = 0;  // (a controller or the keyboard: the controls step aside)
        return false;
    case SDL_EVENT_FINGER_DOWN: case SDL_EVENT_FINGER_MOTION: case SDL_EVENT_FINGER_UP: case SDL_EVENT_FINGER_CANCELED:
        break;
    default:
        return false;
    }
    if (g_shown == 0 && e->type == SDL_EVENT_FINGER_DOWN) g_shown = 1;
    if (!shown()) return false;
    if (menu_input_captured() && e->type == SDL_EVENT_FINGER_DOWN) return false;  // (the menu's: through SDL's mouse)
    int ww = 0, wh = 0;
    if (w && SDL_GetWindowSize(w, &ww, &wh) && ww > 0 && wh > 0) g_w = (float)ww, g_h = (float)wh;
    float x = e->tfinger.x * g_w, y = e->tfinger.y * g_h;  // (finger positions: 0..1 of the window)
    Finger *f = finger(e->tfinger.fingerID);
    if (e->type == SDL_EVENT_FINGER_DOWN) {
        if (f || g_nfingers == (int)(sizeof g_fingers / sizeof *g_fingers)) return true;
        f = &g_fingers[g_nfingers++];
        *f = (Finger){e->tfinger.fingerID, hit(x, y), x, y};
        if (f->ctl >= 0 && k_ctl[f->ctl].bit == SETTINGS_BIT) menu_toggle_settings();
        if (f->ctl == -1) stick_move(f, x, y);
        if (f->ctl == -2) input_touch_screen(w, x, y, true);
    } else if (!f) {
        return true;
    } else if (e->type == SDL_EVENT_FINGER_MOTION) {
        if (f->ctl == -1) stick_move(f, x, y);
        else if (f->ctl == -2) input_touch_screen(w, x, y, true);
        else if (f->ctl >= 0 && k_ctl[f->ctl].bit != SETTINGS_BIT) {  // (sliding between A B X Y)
            int h = hit(x, y);
            if (h >= 0 && k_ctl[h].bit != SETTINGS_BIT) f->ctl = h;
        }
    } else {
        if (f->ctl == -2) input_touch_screen(w, x, y, false);
        *f = g_fingers[--g_nfingers];
    }
    recompute();
    return true;
}

void touch_reset(void) {
    g_nfingers = 0;
    recompute();
}

uint64_t touch_buttons(void) { return g_buttons; }
void touch_stick(int32_t *x, int32_t *y) { *x = g_lx, *y = g_ly; }
bool touch_active(void) { return shown(); }

int touch_shapes(TouchShape *out, int max, float scale_x, float scale_y) {
    if (!shown()) return 0;
    uint64_t b = g_buttons;
    int n = 0;
    for (int i = 0; i < N_CTL && n < max; i++)
        out[n++] = (TouchShape){cx(&k_ctl[i]) * scale_x, cy(&k_ctl[i]) * scale_y, k_ctl[i].r * g_h * scale_y,
                                k_ctl[i].label, k_ctl[i].bit != SETTINGS_BIT && (b >> k_ctl[i].bit & 1)};
    float sx = g_stick_x;
    if (sx >= 0 && n + 2 <= max) {
        out[n++] = (TouchShape){sx * scale_x, g_stick_y * scale_y, STICK_R * g_h * scale_y, "", false};
        out[n++] = (TouchShape){g_knob_x * scale_x, g_knob_y * scale_y, 0.06f * g_h * scale_y, "", true};
    }
    return n;
}

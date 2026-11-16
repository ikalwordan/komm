/* HELLO KAP: the smallest complete native app. A square moves on a sine path; X adds a point,
 * the best total is saved. Build: bash tools/build.sh hello-kap/main.kap hello-kap/main.c */
#include "kap.h"

KAP_MEMORY(64 * 1024, 0);          /* 64 KiB heap on every PSP, nothing extra on 64 MB models */

static const KapHost *H;
static unsigned int keyX;
static float t;
static int points;

static void saveBest(void) {
    char buf[12]; int n = 0, v = points, i;
    char tmp[12];
    do { tmp[n++] = (char)('0' + v % 10); v /= 10; } while (v && n < 11);
    for (i = 0; i < n; i++) buf[i] = tmp[n - 1 - i];
    H->save(buf, n);
}

static void loadBest(void) {
    char buf[12]; int n = H->load(buf, sizeof buf), i;
    points = 0;
    for (i = 0; i < n && buf[i] >= '0' && buf[i] <= '9'; i++) points = points * 10 + (buf[i] - '0');
}

static void update(float dt) {
    t += dt;
    if (H->pressed(keyX)) points++;
}

static void draw(void) {
    char line[24] = "POINTS ";
    int n = 7, v = points, d = 1;
    while (v / d >= 10) d *= 10;
    for (; d; d /= 10) line[n++] = (char)('0' + (v / d) % 10);
    line[n] = 0;
    H->clear(H->color(0, 0, 0));
    H->rect(232 + (int)(150.0f * H->sin(t)), 128 + (int)(60.0f * H->cos(t * 1.3f)), 16, 16, H->color(255, 42, 42));
    H->text(8, 8, "HELLO KAP", H->color(255, 255, 255), 2);
    H->text(8, 30, line, H->color(255, 255, 255), 1);
}

static void destroy(void) { saveBest(); }   /* normal exit: HOME > QUIT or kom quit */

int kap_main(const KapHost *host, KapApp *app) {
    if (host->abi != KAP_ABI || host->size < sizeof *host) return 0;   /* shell too old: refuse to start */
    H = host;
    keyX = H->buttonMask("X");               /* look button masks up once, not every frame */
    loadBest();
    app->update = update;
    app->draw = draw;
    app->destroy = destroy;
    return 1;
}

/* KAP V1: trusted C apps, host-owned lifecycle. Append services only; bump ABI
 * for incompatible changes. No PSP headers: the same app can use a host twin. */
#ifndef KAP_H
#define KAP_H
#include <stdint.h>
#include "kap_gpu.h"
#include "kap_io.h"
#include "kap_document.h"
#define KAP_ABI 1u
/* V1454 tail types (localTime, textInput below). KAP_HAS_DATE_TAIL tells app code built against an
 * older copy of this header (KARDS carried its own) that the real fields are here. */
#define KAP_HAS_DATE_TAIL 1
typedef struct { uint16_t year; uint8_t month, day, hour, minute, second, weekday; } KapDate;
enum { KTXT_BEGIN = 1, KTXT_POLL, KTXT_CANCEL };
typedef struct { const char *title; char *buf; uint32_t cap; } KapTextArgs;
typedef struct {
    uint32_t abi, size;
    void *(*alloc)(uint32_t bytes); /* zeroed, 16-byte aligned, freed on unload */
    int (*width)(void), (*height)(void);
    unsigned int (*color)(int r,int g,int b), (*theme)(int index);
    void (*clear)(unsigned int), (*rect)(int,int,int,int,unsigned int);
    void (*text)(int,int,const char *,unsigned int,int);
    int (*button)(unsigned int), (*pressed)(unsigned int);
    unsigned int (*buttonMask)(const char *);
    void (*analog)(int *,int *);
    float (*time)(void);
    void (*tone)(int,int,int,int,int);
    int (*save)(const char *,int), (*load)(char *,int);
    int (*image)(const char *);
    void (*imageDraw)(int,int,int,int,int);
    int (*sound)(const char *);
    void (*play)(int);
    void (*camera)(float,float,float,float,float,float,float,float,float,float);
    void (*box)(float,float,float,float,float,float,float,float,float,int,float,float,int,float);
    int (*meshNew)(int,int);
    void (*meshVert)(int,int,float,float,float);
    int (*meshFace)(int,int,const int *,float,float,float,float,int,float);
    void (*meshDraw)(int,const float *,int,float,float,float,float,int,float,int);
    void (*meshFree)(int), (*flush3d)(void);
    float (*sin)(float), (*cos)(float), (*sqrt)(float);
    void (*menu)(int), (*perfNote)(const char *,const char *);
    void (*line)(int,int,int,int,unsigned int);
    void (*triangle)(int,int,int,int,int,int,unsigned int);
    void (*circle)(int,int,int,unsigned int), (*frame)(int,int,int,int,unsigned int);
    int (*textWidth)(const char *,int), (*imageWidth)(int), (*imageHeight)(int);
    int (*readAsset)(const char *,int,unsigned char *,int);
    void (*light)(float,float,float,float,float,float), (*haze)(int,int,int);
    void (*fps)(int);
    /* Optional tail: exclusive, bounded native-app ad hoc session. No borrowing
     * a chat/transfer session. 0/down, 1/joining, 2/up; negative = error. */
    int (*adhocOpen)(void);
    void (*adhocClose)(void);
    int (*adhocPoll)(float);
    int (*adhocSend)(const unsigned char *,const void *,int);
    int (*adhocRecv)(unsigned char *,void *,int);
    void (*adhocMac)(unsigned char *);
    const char *(*adhocError)(void);
    /* Optional persistence tail: same per-app identity; bounded 8KiB writes,
     * staged replacement with previous .bak; recovery is app-validated. */
    int (*saveAtomic)(const char *,int);
    int (*loadBackup)(char *,int);
    /* Optional native GPU/PCM tail. GPU V1 currently requires fullscreen. */
    const KapGpu *(*gpu)(void);
    void (*pcmStart)(void);
    int (*pcmWritable)(void);
    int (*pcmPush)(const short *,int);
    void (*pcmStop)(void);
    int (*assetIo)(uint32_t,KapIoArgs *);
    /* Optional measured time for the current shell frame, microseconds.
     * Sampled even while an app is paused by shell UI. App owns hitch clamping;
     * update(dt) keeps its legacy fixed-step meaning for existing packages. */
    uint32_t (*frameElapsedUs)(void);
    /* Optional mesh-look tail (V1199), GE only: per-face alpha / additive / planar
     * texture (komgl.h k3MeshLook), and textures 8..256 px a side, power of two,
     * 0xAABBGGRR, copied (ids 1..8). Check size before use; older shells lack it. */
    void (*meshLook)(int,int,int,int,int,float);
    int (*texNew)(const unsigned int *,int,int);
    void (*texFree)(int);
    /* Optional audio-route tail (V1201): 1 = something is plugged into the
     * headphone / remote jack, 0 = the built-in speaker, -1 = cannot tell. Cheap;
     * poll a few times a second. Bluetooth (Go) and TV-out are not the jack. */
    int (*audioRoute)(void);
    /* V1327: explicit document actions in this app's private document folder.
     * Flat filenames only, <=1MiB, staged writes retaining the previous .bak. */
    int (*document)(uint32_t,const KapDocumentArgs *);
    /* V1344: the app asks the shell to close it (the same as HOME, then X on the quit prompt,
     * without the prompt: the app has already asked its own user). Takes effect after the
     * current update returns. Check size before use; older shells lack it. */
    void (*quit)(void);
    /* V1344: microseconds from a free-running 32-bit clock (wraps in 71 minutes; take
     * differences). The float time() above is about 1 ms coarse, useless for a 0.3 ms phase. */
    uint32_t (*micros)(void);
    /* V1409: report a score; the shell's HOME menu shows the highest one it has seen for this
     * app as BEST SCORE (higher is better). Call it when a run ends. Check size before use;
     * older shells lack it. */
    void (*best)(int);
    /* V1452 MEMORY TIERS (APP_ENGINE_GUIDE.md "Memory tiers"): 1 when the app runs on the HIGH tier (a 64 MB PSP, the
     * low-memory setting off, and the arena with the package's extra heap fitted), 0 on the LOW tier (a PSP-1000, the
     * setting on, or the extra did not fit). *heapBytes (may be NULL): the heap still free for alloc() now. Ask once
     * at start and size your buffers from it. Check size before use; older shells lack it (treat as LOW). */
    uint32_t (*memInfo)(uint32_t *heapBytes);
    /* V1454 CLOCK, UNICODE TEXT, KEYBOARD (APP_SDK_NATIVE.md "V1454 tail"). Check size before use; older shells
     * lack all four. localTime: the PSP's local date and time (the clock the user set, which can be wrong or
     * jump: keep your own guard); 1 = *out filled (weekday 0 = Sunday), 0 = no clock. textUni: UTF-8 text with
     * the shell's Latin accents (the Unicode font: Latin glyphs 6 px a character and up to 2*scale px above y,
     * other scripts 9 px), clipped per glyph to maxW px. textUniWidth: its width, no trailing gap.
     * textInput: the shell's on-screen keyboard over the app. KTXT_BEGIN (title, buf = the start text,
     * cap = buf size; the keyboard takes at most 59 characters): 0 = it is up, -1 = refused. While it is
     * up the shell does NOT call update (draw still runs, the keyboard drawn over it). KTXT_POLL (buf, cap):
     * 0 = still typing, 1 = accepted and buf holds the text (trailing spaces trimmed), -1 = cancelled or
     * nothing pending (buf untouched; an emptied field reads as cancelled). KTXT_CANCEL drops a result
     * not yet polled. */
    int (*localTime)(KapDate *out);
    void (*textUni)(int x, int y, const char *utf8, unsigned int col, int scale, int maxW);
    int (*textUniWidth)(const char *utf8, int scale);
    int (*textInput)(uint32_t op, KapTextArgs *args);
    /* V1459 SERVICES + PNG EXPORT (APP_SDK_NATIVE.md "V1459 tail"). Check size before use; older shells lack both.
     * service(name, version): that service's table (it starts { version, size }: check size covers the calls you
     * use), or NULL when this shell lacks it: use your fallback. V1459 has "inbox" (KapInboxSvc below); "gps",
     * "mic" and "stats" answer NULL until a later shell. service sits FIRST after textInput: KOMOCHI 1.0 was built
     * against exactly that slot (its KapHostNext).
     * exportPng(name, png, bytes): a finished PNG into PICTURE/<APP ID>/<name>.PNG for the PHOTO tab and the PC;
     * name 1..32 of A-Z a-z 0-9 _ - without extension, bytes <= 2 MiB, replaces a file of the same name; returns
     * the bytes written or -1. */
    const void *(*service)(const char *name, uint32_t version);
    int (*exportPng)(const char *name, const void *png, uint32_t bytes);
} KapHost;
/* The V1459 service tables. inbox: small append-only boxes one app writes and another reads (box = 1..16 of A-Z
 * 0-9; a box holds at most 32 KiB, an append past that is refused). read: the oldest bytes up to cap, 0 = empty;
 * ack: drop the first `bytes` (what you used); append: one record of 1..1024 bytes, -1 = refused. The record layout
 * belongs to the apps that share the box (STUDY: KapStudyRec, one per KARDS review session). */
#define KAP_HAS_SERVICE_TAIL 1
typedef struct { uint32_t version, size; int (*read)(const char *box, void *buf, int cap); int (*ack)(const char *box, int bytes);
                 int (*append)(const char *box, const void *rec, int bytes); } KapInboxSvc;
typedef struct { uint16_t cards, right; int32_t localMinute; char deck[24]; } KapStudyRec;   /* box "STUDY" */
/* V1452: declare the app's memory once in its source; tools/kap/pack.py reads it from the .kapmem section.
 * heap: what the app needs on the LOW tier (memory + heap <= 8 MiB). extra: what it adds on the HIGH tier
 * (memory + heap + extra <= 16 MiB). Without it, pack.py --heap (default 256 KiB) and no extra. */
#define KAP_MEMORY(heapBytes, extraBytes) \
    __attribute__((section(".kapmem"), used)) const unsigned int kap_memory_request[2] = { (heapBytes), (extraBytes) }
typedef struct {
    uint32_t abi, size;
    void (*update)(float dt);
    void (*draw)(void);
    void (*destroy)(void);
} KapApp;
/* Entry fills callbacks; returns 1 on success. No threads/OS/GU ownership. */
typedef int (*KapEntry)(const KapHost *, KapApp *);
int kap_main(const KapHost *host, KapApp *app);
#endif

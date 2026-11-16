/* Native GPU V1: trusted app buffers, host frame/VRAM ownership.
 * Commands use PSP GU numeric formats, but never expose GU list/swap ownership.
 * All pointers remain valid until the shell finishes the current GE frame.
 */
#ifndef KAP_GPU_H
#define KAP_GPU_H
#include <stdint.h>
typedef struct {
    uint32_t u[8];
    float f[16];
    const void *p[2];
} KapGpuArgs;
enum {
    KGPU_BEGIN=1, KGPU_END, KGPU_STATE, KGPU_DEPTH_MASK, KGPU_DEPTH_OFFSET,
    KGPU_COLOR, KGPU_BLEND, KGPU_MATRIX_MODE, KGPU_IDENTITY, KGPU_MATRIX,
    KGPU_PERSPECTIVE, KGPU_ROTATE, KGPU_TRANSLATE, KGPU_TEX_FILTER,
    KGPU_TEX_FUNC, KGPU_TEX_IMAGE, KGPU_TEX_MODE, KGPU_DRAW,
    /* V1467 (KapGpu.version 2): the stencil, for shadows darkened once. u[0] func (GU_NEVER..GU_GEQUAL), u[1] ref,
     * u[2] mask, u[3..5] fail / zfail / zpass ops (GU_KEEP..GU_DECR). Enable with KGPU_STATE GU_STENCIL_TEST (3).
     * The stencil is the framebuffer's alpha: after an opaque pass it reads 255; the shell puts 255 back at
     * KGPU_END. Check version >= 2 first: a version 1 shell refuses the command, which ends the app. */
    KGPU_STENCIL,
    /* V1497 (KapGpu.version 3): the depth compare, u[0] GU_NEVER..GU_GEQUAL (BEGIN sets GU_GEQUAL, the shell's
     * inverted range: far = 0). With GU_ALWAYS and writes on, a screen-space sprite at z 0 puts FAR back under a
     * stencil mark, so a second camera (a portal's view) can draw there through the depth of the first. The PSP
     * writes no depth while the depth test is off, so that cannot be done with KGPU_STATE alone. */
    KGPU_DEPTH_FUNC
};
typedef struct {
    uint32_t version,size;
    int (*command)(uint32_t,const KapGpuArgs *);
    void *(*scratch)(uint32_t); /* uncached, 16-byte aligned, frame-lived */
    void (*writeback)(const void *,uint32_t);
} KapGpu;
#endif

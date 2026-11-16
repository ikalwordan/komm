#ifndef KAP_IO_H
#define KAP_IO_H
#include <stdint.h>
/* V1448 appends KIO_READ_ASYNC and KIO_POLL (append-only: the numbers of the
 * older ops never move). An older shell answers -1 to both, which is how an app
 * learns to fall back to KIO_READ.
 *   KIO_READ_ASYNC: handle, data, bytes (<= 2 MiB), offset (file position).
 *       Seeks, then starts the read and returns 0 at once; -1 if it cannot.
 *       One read in flight per handle; data must stay untouched until KIO_POLL
 *       reports it finished.
 *   KIO_POLL: handle. 1 = still reading, 0 = finished with bytes = what was read,
 *       -1 = failed (the handle is idle again either way). 0 with bytes 0 when
 *       nothing was in flight. */
enum { KIO_OPEN=1,KIO_READ,KIO_SEEK,KIO_CLOSE,KIO_DOPEN,KIO_DREAD,KIO_DCLOSE,KIO_READ_ASYNC,KIO_POLL };
typedef struct { uint32_t mode; char name[256]; } KapDirEntry;
typedef struct {
    const char *name;
    void *data;
    int32_t handle,bytes,offset,whence;
} KapIoArgs;
#endif

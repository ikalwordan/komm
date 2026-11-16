#ifndef KAP_DOCUMENT_H
#define KAP_DOCUMENT_H
#include <stdint.h>
/* V1459 appends KDOC_DELETE (name only: removes the document and its .bak; 0 = something removed, -1 = nothing
 * there or a bad name) and KDOC_LIST (name unused: data = a char buffer, bytes = its size; the document names,
 * each followed by '\n', then a NUL; .bak/.tmp never listed; returns how many names fit, -1 = bad args).
 * Older shells refuse both with -1, so check the shell's KapHost size (the V1459 tail) before relying on them. */
enum {KDOC_WRITE=1,KDOC_READ,KDOC_BACKUP,KDOC_DELETE,KDOC_LIST};
typedef struct {const char *name;void *data;uint32_t bytes;} KapDocumentArgs;
#endif

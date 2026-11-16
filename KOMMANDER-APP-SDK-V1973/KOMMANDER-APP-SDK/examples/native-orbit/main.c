#include "scene.h"
int kap_main(const KapHost *h,KapApp *app) {
    if(h->abi!=KAP_ABI || h->size<sizeof *h)return 0;
    scene_init(h);app->update=scene_update;app->draw=scene_draw;return 1;
}

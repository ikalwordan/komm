#include "scene.h"
static const KapHost *host;
static float angle;
/* Keep one data pointer as well as code relocations in the loader fixture. */
static const char *volatile title="NATIVE ORBIT / C MODULES";
void scene_init(const KapHost *h){host=h;angle=0;host->perfNote("KAP","NATIVE ORBIT");}
void scene_update(float dt){angle+=dt*0.5f;}
void scene_draw(void){
    int x,z;
    host->clear(host->theme(0));
    host->camera(host->sin(angle)*16,10,host->cos(angle)*16,0,0,0,240,136,260,0.35f);
    for(z=-4;z<=4;z++)for(x=-4;x<=4;x++){
        float height=1.0f+host->sin(angle*2+x*0.4f+z*0.5f)*0.7f;
        host->box(x*2,0,z*2,0.6f,height,0.6f,70+x*15,150+z*12,220,0,0,0,0,0);
    }
    host->flush3d();host->text(12,12,title,host->theme(4),1);
}

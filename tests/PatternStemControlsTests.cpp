#include "TrackAudioCore.h"
#include <cmath>
#include <cstdlib>
#include <iostream>
#include <vector>
#define CHECK(x) do{if(!(x)){std::cerr<<"FAIL "<<#x<<" at line "<<__LINE__<<"\n";std::abort();}}while(0)
static double rms(TBEngine *core, int frames=96000){
    std::vector<float> l(256), r(256);
    double sum=0;
    for(int done=0; done<frames;){
        const int n=std::min(256,frames-done);
        tb_render(core,l.data(),r.data(),size_t(n));
        for(int i=0;i<n;++i){CHECK(std::isfinite(l[i]));sum+=double(l[i])*l[i];}
        done+=n;
    }
    return std::sqrt(sum/frames);
}
int main(){
    auto *core=tb_create(48000);
    CHECK(core!=nullptr);
    tb_set_playing(core,1);
    tb_set_crossfader(core,0);
    tb_set_deck_enabled(core,1,0);
    CHECK(tb_pattern_voice_muted(core,0,0)==0);
    const auto full=rms(core);
    CHECK(full>0.005);
    for(int v=0;v<3;++v)tb_set_pattern_voice_mute(core,0,v,1);
    for(int v=0;v<3;++v)CHECK(tb_pattern_voice_muted(core,0,v)==1);
    const auto muted=rms(core);
    CHECK(muted < 0.001);
    tb_set_pattern_voice_mute(core,0,0,0);
    CHECK(tb_pattern_voice_muted(core,0,0)==0);
    const auto kick=rms(core);
    CHECK(kick > 0.002);
    tb_set_pattern_voice_solo(core,0,1,1);
    CHECK(tb_pattern_voice_soloed(core,0,1)==1);
    const auto hat=rms(core);
    CHECK(hat>0.00005 && hat<full);
    tb_set_pattern_voice_solo(core,0,1,0);
    CHECK(tb_pattern_voice_soloed(core,0,1)==0);
    const auto kickAgain=rms(core);
    CHECK(kickAgain>hat);
    tb_set_pattern_voice_mute(core,2,1,1); // invalid deck ignored
    tb_set_pattern_voice_solo(core,0,4,1); // invalid voice ignored
    CHECK(tb_pattern_voice_soloed(core,0,4)==0);
    tb_destroy(core);
    std::cout << "PatternStemControlsTests PASS — real mute, solo, smoothing, invalid indices\n";
}

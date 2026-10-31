#include "TrackAudioCore.h"
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <fstream>
#include <iostream>
#include <vector>

namespace {
void u16(std::ofstream &out, uint16_t value) {
    const char bytes[2] = {char(value), char(value>>8)};
    out.write(bytes, 2);
}
void u32(std::ofstream &out, uint32_t value) {
    const char bytes[4] = {char(value), char(value>>8), char(value>>16), char(value>>24)};
    out.write(bytes, 4);
}
uint16_t toPCM(float value) {
    return uint16_t(int16_t(std::lround(std::clamp(value, -1.0f, 1.0f) * 32767.0f)));
}
}

// This demonstrates ORIGINAL synthesized Kick/Hat/Bass voice isolation,
// not extracted audio-file stems or DJ file source separation.
int main(int argc, char **argv) {
    if (argc != 2) {
        std::cerr << "Usage: render_stem_demo <output.wav>\n";
        return 2;
    }
    constexpr uint32_t rate = 48000;
    constexpr uint32_t total = rate * 16;
    std::ofstream out(argv[1], std::ios::binary);
    if (!out) return 1;
    out.write("RIFF",4); u32(out,36+total*4); out.write("WAVE",4);
    out.write("fmt ",4); u32(out,16); u16(out,1); u16(out,2);
    u32(out,rate); u32(out,rate*4); u16(out,4); u16(out,16);
    out.write("data",4); u32(out,total*4);
    TBEngine *engine=tb_create(rate);
    if (!engine) return 1;
    tb_set_bpm(engine,132);
    tb_set_crossfader(engine,0.0f);
    tb_set_deck_enabled(engine,1,0);
    tb_set_playing(engine,1);
    std::vector<float> left(256),right(256);
    bool mutedBass=false,soloHat=false,restored=false;
    for(uint32_t at=0; at<total;) {
        if (!mutedBass && at>=rate*4) {
            tb_set_pattern_voice_mute(engine,0,2,1); // drop synth bass
            mutedBass=true;
        }
        if (!soloHat && at>=rate*8) {
            tb_set_pattern_voice_mute(engine,0,2,0);
            tb_set_pattern_voice_solo(engine,0,1,1); // only hi hats
            soloHat=true;
        }
        if (!restored && at>=rate*12) {
            tb_set_pattern_voice_solo(engine,0,1,0);
            tb_set_deck_delay(engine,0,0.28f); // original echo on full mix
            restored=true;
        }
        const uint32_t frames=std::min<uint32_t>(uint32_t(left.size()),total-at);
        tb_render(engine,left.data(),right.data(),frames);
        for (uint32_t index=0;index<frames;++index) {
            u16(out,toPCM(left[index])); u16(out,toPCM(right[index]));
        }
        at+=frames;
    }
    tb_destroy(engine);
    if (!out) return 1;
    std::cout << "Original synth-only: 0–4s full, 4–8s bass mute, "
                 "8–12s hats solo, 12–16s full with delay.\n";
}

#include "SpectralEnvelope.h"
#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <iostream>
#include <vector>
#define CHECK(x) do {if(!(x)) {std::cerr<<"FAIL "<<#x<<" @"<<__LINE__<<"\n";std::abort();}} while(0)
constexpr double PI=3.14159265358979323846;
struct Result { std::vector<float> peak, bands; };
Result analyze(double freq, size_t frames=48000, size_t block=511, bool nonfinite=false) {
    TBSpectralEnvelope *core=tb_spectral_create(48000.,frames,64);
    CHECK(core!=nullptr);
    std::vector<float> l(block),r(block);
    size_t start=0;
    while(start<frames){
        const size_t n=std::min(block,frames-start);
        for(size_t i=0;i<n;++i){
            const double angle=2.*PI*freq*double(start+i)/48000.;
            l[i]=r[i]=float(0.5*std::sin(angle));
            if(nonfinite && start+i==123) l[i]=NAN;
            if(nonfinite && start+i==456) r[i]=INFINITY;
        }
        CHECK(tb_spectral_push(core,l.data(),r.data(),n)==n);
        start+=n;
    }
    CHECK(tb_spectral_consumed(core)==frames);
    CHECK(tb_spectral_push(core,l.data(),r.data(),12)==0);
    Result out{std::vector<float>(64),std::vector<float>(64*5)};
    CHECK(!tb_spectral_finish(core,out.peak.data(),out.bands.data(),63));
    CHECK(tb_spectral_finish(core,out.peak.data(),out.bands.data(),64));
    tb_spectral_destroy(core);
    return out;
}
size_t dominant(const Result &out){
    double means[5]={};
    for(size_t bin=0;bin<64;++bin)for(int band=0;band<5;++band)
        means[band]+=out.bands[bin*5+band];
    return size_t(std::max_element(means,means+5)-means);
}
int main(){
    CHECK(tb_spectral_create(NAN,10000,64)==nullptr);
    CHECK(tb_spectral_create(48000,0,64)==nullptr);
    CHECK(tb_spectral_create(48000,10000,3)==nullptr);
    CHECK(tb_spectral_create(48000,10000,9000)==nullptr);
    CHECK(tb_spectral_consumed(nullptr)==0);
    const auto low=analyze(60);
    const auto middle=analyze(900);
    const auto high=analyze(10000);
    CHECK(dominant(low)<=1);
    CHECK(dominant(middle)>=1 && dominant(middle)<=3);
    CHECK(dominant(high)>=3);
    for(const auto &r:{low,middle,high}){
        for(float p:r.peak) CHECK(std::isfinite(p) && p>=0 && p<=1);
        for(float p:r.bands) CHECK(std::isfinite(p) && p>=0 && p<=1);
        CHECK(*std::max_element(r.peak.begin(),r.peak.end())>0.90f);
    }
    const auto a=analyze(400,48000,1),b=analyze(400,48000,511);
    for(size_t i=0;i<a.peak.size();++i) CHECK(std::abs(a.peak[i]-b.peak[i])<0.000001);
    for(size_t i=0;i<a.bands.size();++i) CHECK(std::abs(a.bands[i]-b.bands[i])<0.000002);
    // Real stereo widening may invert phase. Frequency energy must not
    // collapse to zero even when the L+R mono sum would cancel perfectly.
    auto *inverted = tb_spectral_create(48000.,48000,64);
    CHECK(inverted != nullptr);
    std::vector<float> opposedLeft(257), opposedRight(257);
    for(size_t pos=0; pos<48000;){
        const size_t n=std::min<size_t>(opposedLeft.size(),48000-pos);
        for(size_t i=0; i<n; ++i){
            opposedLeft[i]=float(0.5*std::sin(2.*PI*900.*(pos+i)/48000.));
            opposedRight[i]=-opposedLeft[i];
        }
        CHECK(tb_spectral_push(inverted,opposedLeft.data(),opposedRight.data(),n)==n);
        pos+=n;
    }
    Result opposed{std::vector<float>(64),std::vector<float>(64*5)};
    CHECK(tb_spectral_finish(inverted,opposed.peak.data(),opposed.bands.data(),64));
    CHECK(*std::max_element(opposed.bands.begin(),opposed.bands.end())>0.5f);
    CHECK(dominant(opposed)>=1 && dominant(opposed)<=3);
    tb_spectral_destroy(inverted);
    const auto invalid=analyze(1000,48000,511,true);
    for(float v:invalid.bands) CHECK(std::isfinite(v));
    auto *silent=tb_spectral_create(48000,8192,64);
    std::vector<float> zeros(8192), peak(64), bands(320);
    CHECK(tb_spectral_push(silent,zeros.data(),zeros.data(),8192)==8192);
    CHECK(tb_spectral_finish(silent,peak.data(),bands.data(),64));
    CHECK(std::all_of(peak.begin(),peak.end(),[](float v){return v==0;}));
    CHECK(std::all_of(bands.begin(),bands.end(),[](float v){return v==0;}));
    tb_spectral_destroy(silent);
    std::cout<<"SpectralEnvelopeTests PASS (stereo-aware 5 bands, phase inversion, chunk invariance, NaN, silence)\n";
}

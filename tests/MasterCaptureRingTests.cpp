#include "MasterCaptureRing.h"
#include <cmath>
#include <cstdlib>
#include <iostream>
#include <thread>
#include <vector>
#define CHECK(x) do{if(!(x)){std::cerr<<"FAIL "<<#x<<":"<<__LINE__<<"\n";std::abort();}}while(0)

int main() {
    CHECK(tb_capture_create(0) == nullptr);
    CHECK(tb_capture_create(1024) == nullptr);
    auto *ring = tb_capture_create(4096);
    CHECK(ring != nullptr && tb_capture_active(ring) == 1);
    std::vector<float> a(10000), b(10000), la(4096), rb(4096);
    for (int i=0;i<10000;++i) { a[i]=i*0.0001f; b[i]=-a[i]; }
    CHECK(tb_capture_push(ring,a.data(),b.data(),1000) == 1000);
    CHECK(tb_capture_available(ring) == 1000);
    CHECK(tb_capture_pop(ring,la.data(),rb.data(),750) == 750);
    for (int i=0;i<750;++i) { CHECK(la[i]==a[i]); CHECK(rb[i]==b[i]); }
    CHECK(tb_capture_push(ring,a.data(),b.data(),4000) == 3846);
    CHECK(tb_capture_dropped(ring) == 154);
    CHECK(tb_capture_available(ring) == 4096);
    CHECK(tb_capture_pop(ring,la.data(),rb.data(),4096) == 4096);
    for (int i=0;i<250;++i) CHECK(la[i] == a[i+750]);
    for (int i=0;i<3846;++i) CHECK(la[i+250] == a[i]);
    CHECK(tb_capture_available(ring) == 0);
    CHECK(tb_capture_inflight(ring) == 0);
    tb_capture_stop(ring);
    CHECK(tb_capture_active(ring) == 0);
    CHECK(tb_capture_push(ring,a.data(),b.data(),50) == 0);
    tb_capture_destroy(ring);

    // Concurrent SPSC verifies linearizable ordering across >100k samples.
    ring = tb_capture_create(8192);
    const int total=150000;
    std::vector<float> inL(512),inR(512),outL(512),outR(512);
    std::thread producer([&](){
        int next=0;
        while(next<total){
            const int block=std::min(512,total-next);
            for(int i=0;i<block;++i){inL[i]=float(next+i);inR[i]=-float(next+i);}
            const size_t done=tb_capture_push(ring,inL.data(),inR.data(),block);
            next+=int(done);
            if(!done) std::this_thread::yield();
        }
        tb_capture_stop(ring);
    });
    int read=0;
    while(tb_capture_active(ring) || tb_capture_available(ring)>0 || tb_capture_inflight(ring)>0){
        const size_t n=tb_capture_pop(ring,outL.data(),outR.data(),512);
        for(size_t i=0;i<n;++i){CHECK(outL[i] == float(read));CHECK(outR[i] == -float(read));++read;}
        if(!n) std::this_thread::yield();
    }
    producer.join();
    CHECK(read==total);
    // The producer may have registered dropped attempts under pressure;
    // accepted samples are not dropped or reordered.
    tb_capture_destroy(ring);
    std::cout<<"MasterCaptureRingTests PASS\n";
}

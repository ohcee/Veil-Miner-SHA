/* Veil SHA256Dv OpenCL kernel.
 * Hashes the 80-byte Veil header (20 big-endian message words m[0..19]),
 * sweeping word 19 (the swept half of the 64-bit nonce), and reports any
 * message-word-19 value whose SHA256d is <= target. Validated against
 * OpenSSL sha256d. */

__constant uint K[64] = {
 0x428a2f98u,0x71374491u,0xb5c0fbcfu,0xe9b5dba5u,0x3956c25bu,0x59f111f1u,0x923f82a4u,0xab1c5ed5u,
 0xd807aa98u,0x12835b01u,0x243185beu,0x550c7dc3u,0x72be5d74u,0x80deb1feu,0x9bdc06a7u,0xc19bf174u,
 0xe49b69c1u,0xefbe4786u,0x0fc19dc6u,0x240ca1ccu,0x2de92c6fu,0x4a7484aau,0x5cb0a9dcu,0x76f988dau,
 0x983e5152u,0xa831c66du,0xb00327c8u,0xbf597fc7u,0xc6e00bf3u,0xd5a79147u,0x06ca6351u,0x14292967u,
 0x27b70a85u,0x2e1b2138u,0x4d2c6dfcu,0x53380d13u,0x650a7354u,0x766a0abbu,0x81c2c92eu,0x92722c85u,
 0xa2bfe8a1u,0xa81a664bu,0xc24b8b70u,0xc76c51a3u,0xd192e819u,0xd6990624u,0xf40e3585u,0x106aa070u,
 0x19a4c116u,0x1e376c08u,0x2748774cu,0x34b0bcb5u,0x391c0cb3u,0x4ed8aa4au,0x5b9cca4fu,0x682e6ff3u,
 0x748f82eeu,0x78a5636fu,0x84c87814u,0x8cc70208u,0x90befffau,0xa4506cebu,0xbef9a3f7u,0xc67178f2u};

inline uint rotr(uint x, uint n){ return (x>>n)|(x<<(32u-n)); }

void sha256_block(uint st[8], const uint in[16]) {
  uint w[64];
  for(int i=0;i<16;i++) w[i]=in[i];
  for(int i=16;i<64;i++){
    uint s0=rotr(w[i-15],7)^rotr(w[i-15],18)^(w[i-15]>>3);
    uint s1=rotr(w[i-2],17)^rotr(w[i-2],19)^(w[i-2]>>10);
    w[i]=w[i-16]+s0+w[i-7]+s1;
  }
  uint a=st[0],b=st[1],c=st[2],d=st[3],e=st[4],f=st[5],g=st[6],h=st[7];
  for(int i=0;i<64;i++){
    uint S1=rotr(e,6)^rotr(e,11)^rotr(e,25);
    uint ch=(e&f)^((~e)&g);
    uint t1=h+S1+ch+K[i]+w[i];
    uint S0=rotr(a,2)^rotr(a,13)^rotr(a,22);
    uint maj=(a&b)^(a&c)^(b&c);
    uint t2=S0+maj;
    h=g;g=f;f=e;e=d+t1;d=c;c=b;b=a;a=t1+t2;
  }
  st[0]+=a;st[1]+=b;st[2]+=c;st[3]+=d;st[4]+=e;st[5]+=f;st[6]+=g;st[7]+=h;
}

inline void sha256d80(const uint m[19], uint word19, uint out[8]) {
  const uint H[8]={0x6a09e667u,0xbb67ae85u,0x3c6ef372u,0xa54ff53au,0x510e527fu,0x9b05688cu,0x1f83d9abu,0x5be0cd19u};
  uint st[8]; for(int i=0;i<8;i++) st[i]=H[i];
  uint b1[16]; for(int i=0;i<16;i++) b1[i]=m[i];
  sha256_block(st,b1);
  uint b2[16];
  b2[0]=m[16]; b2[1]=m[17]; b2[2]=m[18]; b2[3]=word19;
  b2[4]=0x80000000u; for(int i=5;i<15;i++) b2[i]=0u; b2[15]=0x280u;
  sha256_block(st,b2);
  uint st2[8]; for(int i=0;i<8;i++) st2[i]=H[i];
  uint b3[16];
  for(int i=0;i<8;i++) b3[i]=st[i];
  b3[8]=0x80000000u; for(int i=9;i<15;i++) b3[i]=0u; b3[15]=0x100u;
  sha256_block(st2,b3);
  for(int i=0;i<8;i++) out[i]=st2[i];
}

/* out[0]=count, out[1..]=winning word19 values (=swab32(nonce_hi)). */
#define MAX_RESULTS 15
__kernel void veil_search(__global const uint* m,          /* 19 words m[0..18] */
                          const uint start_word19,
                          __global const uint* target,     /* target[8], MSW at [7] */
                          __global uint* out) {
  uint gid = get_global_id(0);
  uint word19 = start_word19 + gid;
  uint mm[19]; for(int i=0;i<19;i++) mm[i]=m[i];
  uint h[8];
  sha256d80(mm, word19, h);
  /* MSW-first compare: digest word 7 is most significant */
  bool ok = true;
  for(int i=7;i>=0;i--){ if(h[i]>target[i]){ok=false;break;} if(h[i]<target[i]){break;} }
  if(ok){
    uint idx = atomic_inc(&out[0]);
    if(idx < MAX_RESULTS) out[1+idx]=word19;
  }
}

/* self-test entry: hash m[0..18]+word19 once, write 8-word digest to out */
__kernel void veil_hash1(__global const uint* m, const uint word19, __global uint* out){
  uint mm[19]; for(int i=0;i<19;i++) mm[i]=m[i];
  uint h[8]; sha256d80(mm, word19, h);
  for(int i=0;i<8;i++) out[i]=h[i];
}

/* Veil SHA256Dv OpenCL miner — minimal, one GPU per process (use -d on mixed rigs).
 * deps: OpenCL, pthread, libcrypto. Build: make. */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <unistd.h>
#include <errno.h>
#include <time.h>
#include <pthread.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <arpa/inet.h>
#include <netdb.h>
#include <openssl/sha.h>
#ifdef __APPLE__
  #include <OpenCL/opencl.h>
#else
  #include <CL/cl.h>
#endif

/* ---------- endianness + hex ---------- */
static inline uint32_t be32dec(const void*pp){const uint8_t*p=pp;return (uint32_t)p[0]<<24|(uint32_t)p[1]<<16|(uint32_t)p[2]<<8|p[3];}
static inline void le32enc(void*pp,uint32_t x){uint8_t*p=pp;p[0]=x;p[1]=x>>8;p[2]=x>>16;p[3]=x>>24;}
static inline uint32_t swab32(uint32_t x){return __builtin_bswap32(x);}
static int hex2bin(uint8_t*out,const char*hex,size_t len){for(size_t i=0;i<len;i++){unsigned v;if(sscanf(hex+2*i,"%2x",&v)!=1)return -1;out[i]=(uint8_t)v;}return 0;}
static void bin2hex(char*out,const uint8_t*in,size_t len){static const char*h="0123456789abcdef";for(size_t i=0;i<len;i++){out[2*i]=h[in[i]>>4];out[2*i+1]=h[in[i]&15];}out[2*len]=0;}

static void diff_to_target(uint32_t*target,double diff){
  uint64_t m; int k;
  for(k=6;k>0&&diff>1.0;k--) diff/=4294967296.0;
  m=(uint64_t)(4294901760.0/diff);
  if(m==0&&k==6) memset(target,0xff,32);
  else { memset(target,0,32); target[k]=(uint32_t)m; target[k+1]=(uint32_t)(m>>32); }
}

/* ---------- job state ---------- */
typedef struct {
  char job_id[128];
  uint32_t version;
  uint8_t  midstate_be[32];
  uint8_t  merkle_be[32];
  uint32_t ntime;
  uint32_t nonce_hi;
} job_t;

static pthread_mutex_t g_lock = PTHREAD_MUTEX_INITIALIZER;
static job_t   g_job;
static int     g_have_job = 0;
static uint32_t g_gen = 0;
static double  g_diff = 1.0;
static int     g_sock = -1;
static const char* g_user = "veiltest.amd";
static const char* g_pass = "x";
static long    g_accepted = 0, g_rejected = 0;

static void build_stage2(uint8_t out[80], const job_t*j, uint32_t nlo, uint32_t nhi){
  le32enc(out+0, j->version);
  memcpy(out+4, j->midstate_be, 32);
  for(int i=0;i<32;i++) out[36+i]=j->merkle_be[31-i];
  le32enc(out+68, j->ntime);
  le32enc(out+72, nlo);
  le32enc(out+76, nhi);
}

/* ---------- tiny stratum ---------- */
static int send_line(const char*s){
  char buf[2048]; int n=snprintf(buf,sizeof buf,"%s\n",s);
  int off=0; while(off<n){int w=send(g_sock,buf+off,n-off,0); if(w<=0)return -1; off+=w;} return 0;
}
/* extract flat scalar elements of the "params" array; strings unquoted. */
static int parse_params(const char*line,char els[][160],int maxel){
  const char*p=strstr(line,"\"params\""); if(!p)return -1;
  p=strchr(p,'['); if(!p)return -1; p++;
  int n=0;
  while(*p&&n<maxel){
    while(*p==' '||*p==',')p++;
    if(*p==']'||!*p)break;
    char*o=els[n]; int oi=0;
    if(*p=='"'){p++; while(*p&&*p!='"'&&oi<159)o[oi++]=*p++; if(*p=='"')p++;}
    else { while(*p&&*p!=','&&*p!=']'&&oi<159)o[oi++]=*p++; }
    o[oi]=0; n++;
  }
  return n;
}
static int json_str(const char*line,const char*key,char*out,int outsz){
  char pat[64]; snprintf(pat,sizeof pat,"\"%s\"",key);
  const char*p=strstr(line,pat); if(!p)return -1; p+=strlen(pat);
  while(*p&&(*p==' '||*p==':'))p++;
  if(*p!='"')return -1; p++;
  int i=0; while(*p&&*p!='"'&&i<outsz-1)out[i++]=*p++; out[i]=0; return 0;
}
static void handle_line(const char*line){
  char method[64];
  if(json_str(line,"method",method,sizeof method)!=0){
    /* a response, not a request; only care about our submit (id 4) */
    if(strstr(line,"\"id\":4")||strstr(line,"\"id\": 4")){
      if(strstr(line,"\"result\":true")||strstr(line,"\"result\": true")){ g_accepted++; fprintf(stderr,"[share] ACCEPTED (%ld/%ld)\n",g_accepted,g_accepted+g_rejected); }
      else { g_rejected++; fprintf(stderr,"[share] REJECTED: %s\n",line); }
    }
    return;
  }
  if(!strcmp(method,"mining.notify")){
    char els[12][160]; int n=parse_params(line,els,12);
    if(n<11){fprintf(stderr,"notify: got %d params\n",n);return;}
    job_t j; memset(&j,0,sizeof j);
    snprintf(j.job_id,sizeof j.job_id,"%s",els[0]);
    j.version=(uint32_t)strtoul(els[1],0,10);
    if(strlen(els[2])!=64||strlen(els[3])!=64){fprintf(stderr,"notify: bad midstate/merkle len\n");return;}
    hex2bin(j.midstate_be,els[2],32);
    hex2bin(j.merkle_be,els[3],32);
    j.ntime=(uint32_t)strtoul(els[5],0,10);
    j.nonce_hi=(uint32_t)strtoul(els[7],0,10);
    pthread_mutex_lock(&g_lock);
    g_job=j; g_have_job=1; g_gen++;
    pthread_mutex_unlock(&g_lock);
    fprintf(stderr,"[job %s] ntime=%08x nonce_hi=%08x diff=%.4g\n",j.job_id,j.ntime,j.nonce_hi,g_diff);
  } else if(!strcmp(method,"mining.set_difficulty")){
    char els[4][160]; int n=parse_params(line,els,4);
    if(n>=1){ pthread_mutex_lock(&g_lock); g_diff=atof(els[0]); pthread_mutex_unlock(&g_lock);
      fprintf(stderr,"[diff] %.6g\n",g_diff); }
  }
}
static void* recv_thread(void*arg){(void)arg;
  char buf[8192]; int len=0;
  for(;;){
    int r=recv(g_sock,buf+len,sizeof(buf)-1-len,0);
    if(r<=0){fprintf(stderr,"connection closed\n");exit(1);}
    len+=r; buf[len]=0;
    char*nl;
    while((nl=memchr(buf,'\n',len))){
      *nl=0; if(nl>buf) handle_line(buf);
      int rest=len-(int)(nl+1-buf); memmove(buf,nl+1,rest); len=rest;
    }
    if(len>=(int)sizeof(buf)-1) len=0;
  }
  return 0;
}
static void submit_share(const job_t*j,uint32_t nonce_hi,uint32_t nonce_lo){
  uint8_t ehi[4],elo[4],ent[4]; le32enc(ehi,nonce_hi); le32enc(elo,nonce_lo); le32enc(ent,j->ntime);
  char hi[9],lo[9],nt[9]; bin2hex(hi,ehi,4); bin2hex(lo,elo,4); bin2hex(nt,ent,4);
  char s[512];
  snprintf(s,sizeof s,"{\"id\":4,\"method\":\"mining.submit\",\"params\":[\"%s\",\"%s\",\"%s\",\"%s\",\"%s\"]}",
    g_user,j->job_id,hi,nt,lo);
  send_line(s);
  fprintf(stderr,"[submit] job=%s nonce_hi=%08x nonce_lo=%08x\n",j->job_id,nonce_hi,nonce_lo);
}

/* ---------- opencl ---------- */
static char* slurp(const char*path,size_t*len){FILE*f=fopen(path,"rb");if(!f){perror(path);exit(1);}fseek(f,0,SEEK_END);long n=ftell(f);fseek(f,0,SEEK_SET);char*b=malloc(n+1);fread(b,1,n,f);b[n]=0;fclose(f);if(len)*len=n;return b;}
#define CK(x) do{cl_int _e=(x); if(_e){fprintf(stderr,"CL error %d at %s:%d\n",_e,__FILE__,__LINE__);exit(1);}}while(0)

int main(int argc,char**argv){
  const char*url="stratum+tcp://veil.yadaminers.pl:3333";
  int devindex=-2; const char*clpath="veil_sha256dv.cl"; uint32_t batch_log=22;
  for(int i=1;i<argc;i++){
    if(!strcmp(argv[i],"-o")&&i+1<argc) url=argv[++i];
    else if(!strcmp(argv[i],"-u")&&i+1<argc) g_user=argv[++i];
    else if(!strcmp(argv[i],"-p")&&i+1<argc) g_pass=argv[++i];
    else if(!strcmp(argv[i],"-d")&&i+1<argc) devindex=atoi(argv[++i]);
    else if(!strcmp(argv[i],"-k")&&i+1<argc) clpath=argv[++i];
    else if(!strcmp(argv[i],"--batch")&&i+1<argc) batch_log=atoi(argv[++i]);
    else if(!strcmp(argv[i],"--list")){ devindex=-1; }
  }
  /* enumerate all GPU devices across platforms */
  cl_platform_id plats[16]; cl_uint nplat=0; clGetPlatformIDs(16,plats,&nplat);
  cl_device_id devs[64]; char devnames[64][128]; char devvendor[64][128]; int ndev=0;
  for(cl_uint p=0;p<nplat;p++){
    cl_device_id d[32]; cl_uint nd=0; clGetDeviceIDs(plats[p],CL_DEVICE_TYPE_GPU,32,d,&nd);
    for(cl_uint i=0;i<nd&&ndev<64;i++){ devs[ndev]=d[i]; clGetDeviceInfo(d[i],CL_DEVICE_NAME,128,devnames[ndev],0); clGetDeviceInfo(d[i],CL_DEVICE_VENDOR,128,devvendor[ndev],0); ndev++; }
  }
  fprintf(stderr,"OpenCL GPU devices:\n"); for(int i=0;i<ndev;i++) fprintf(stderr,"  [%d] %s\n",i,devnames[i]);
  if(devindex==-1) return 0;                 /* --list */
  if(devindex==-2){                            /* auto: prefer an AMD GPU */
    devindex=0;
    for(int i=0;i<ndev;i++){ if(strstr(devvendor[i],"Advanced Micro Devices")||strstr(devvendor[i],"AMD")){devindex=i;break;} }
  }
  if(devindex>=ndev){fprintf(stderr,"device %d not found\n",devindex);return 1;}
  cl_device_id dev=devs[devindex];
  fprintf(stderr,"mining on [%d] %s\n",devindex,devnames[devindex]);

  cl_context ctx=clCreateContext(0,1,&dev,0,0,0);
  cl_command_queue q=clCreateCommandQueue(ctx,dev,0,0);
  size_t sl; char*src=slurp(clpath,&sl); const char*sp=src;
  cl_program prog=clCreateProgramWithSource(ctx,1,&sp,&sl,0);
  if(clBuildProgram(prog,1,&dev,"",0,0)){char log[8192];clGetProgramBuildInfo(prog,dev,CL_PROGRAM_BUILD_LOG,sizeof log,log,0);fprintf(stderr,"build log:\n%s\n",log);return 1;}
  cl_kernel ksearch=clCreateKernel(prog,"veil_search",0);
  cl_mem bm=clCreateBuffer(ctx,CL_MEM_READ_ONLY,19*4,0,0);
  cl_mem bt=clCreateBuffer(ctx,CL_MEM_READ_ONLY,8*4,0,0);
  cl_mem bo=clCreateBuffer(ctx,CL_MEM_READ_WRITE,16*4,0,0);

  /* connect */
  char host[256]; int port=3333; { const char*h=url; const char*s=strstr(h,"://"); if(s)h=s+3; snprintf(host,sizeof host,"%s",h); char*c=strchr(host,':'); if(c){*c=0;port=atoi(c+1);} }
  struct hostent*he=gethostbyname(host); if(!he){fprintf(stderr,"dns fail %s\n",host);return 1;}
  g_sock=socket(AF_INET,SOCK_STREAM,0);
  struct sockaddr_in sa; memset(&sa,0,sizeof sa); sa.sin_family=AF_INET; sa.sin_port=htons(port); memcpy(&sa.sin_addr,he->h_addr,he->h_length);
  if(connect(g_sock,(struct sockaddr*)&sa,sizeof sa)){perror("connect");return 1;}
  int one=1; setsockopt(g_sock,IPPROTO_TCP,TCP_NODELAY,&one,sizeof one);
  fprintf(stderr,"connected %s:%d\n",host,port);
  pthread_t rt; pthread_create(&rt,0,recv_thread,0);
  send_line("{\"id\":1,\"method\":\"mining.subscribe\",\"params\":[\"veil-miner-sha-amd/0.1\"]}");
  char auth[256]; snprintf(auth,sizeof auth,"{\"id\":2,\"method\":\"mining.authorize\",\"params\":[\"%s\",\"%s\"]}",g_user,g_pass); send_line(auth);

  /* mining loop */
  uint32_t cur_gen=(uint32_t)-1; job_t job; uint32_t m[20],target[8],startw; int have=0;
  size_t batch=(size_t)1<<batch_log; uint32_t base=0; long hashes=0; time_t t0=time(0);
  for(;;){
    pthread_mutex_lock(&g_lock);
    int changed = (g_gen!=cur_gen);
    if(changed){ cur_gen=g_gen; job=g_job; have=g_have_job; double d=g_diff;
      if(have){ uint8_t s2[80]; build_stage2(s2,&job,0,job.nonce_hi);
        for(int i=0;i<20;i++) m[i]=be32dec(s2+4*i); startw=m[19]; base=startw; diff_to_target(target,d);
        clEnqueueWriteBuffer(q,bm,CL_TRUE,0,19*4,m,0,0,0);
        clEnqueueWriteBuffer(q,bt,CL_TRUE,0,8*4,target,0,0,0);
      }
    }
    pthread_mutex_unlock(&g_lock);
    if(!have){ usleep(100000); continue; }
    /* clear result count */
    uint32_t zero=0; clEnqueueWriteBuffer(q,bo,CL_TRUE,0,4,&zero,0,0,0);
    clSetKernelArg(ksearch,0,sizeof bm,&bm);
    clSetKernelArg(ksearch,1,sizeof(uint32_t),&base);
    clSetKernelArg(ksearch,2,sizeof bt,&bt);
    clSetKernelArg(ksearch,3,sizeof bo,&bo);
    CK(clEnqueueNDRangeKernel(q,ksearch,1,0,&batch,0,0,0,0));
    uint32_t res[16]; clEnqueueReadBuffer(q,bo,CL_TRUE,0,16*4,res,0,0,0);
    if(res[0]){
      for(uint32_t i=0;i<res[0]&&i<15;i++){
        uint32_t W=res[1+i], nonce_hi=swab32(W);
        uint8_t s2[80]; build_stage2(s2,&job,0,nonce_hi);
        uint8_t h1[32],h2[32]; SHA256(s2,80,h1); SHA256(h1,32,h2);
        uint32_t hl[8]; for(int k=0;k<8;k++) hl[k]=be32dec(h2+4*k);
        int ok=1; for(int k=7;k>=0;k--){ if(hl[k]>target[k]){ok=0;break;} if(hl[k]<target[k])break; }
        if(ok) submit_share(&job,nonce_hi,0);
        else fprintf(stderr,"[warn] gpu nonce %08x failed CPU verify\n",W);
      }
    }
    hashes+=batch; base+=batch;
    time_t now=time(0);
    if(now-t0>=5){ double mhs=hashes/1e6/(now-t0); fprintf(stderr,"[hashrate] %.2f MH/s  base=%08x  A/R %ld/%ld\n",mhs,base,g_accepted,g_rejected); hashes=0; t0=now; }
  }
  return 0;
}

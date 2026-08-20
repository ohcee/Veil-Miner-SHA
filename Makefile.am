# allow to use Host cuda functions in C/C++
DEF_INCLUDES = @CUDA_INCLUDES@

if WANT_JANSSON
JANSSON_INCLUDES= -I$(top_srcdir)/compat/jansson
else
JANSSON_INCLUDES=
endif

EXTRA_DIST	= autogen.sh README.md README.txt LICENSE.txt \
		  ccminer.sln ccminer.vcxproj ccminer.vcxproj.filters \
		  compat/gettimeofday.c compat/getopt/getopt_long.c

SUBDIRS = compat

bin_PROGRAMS = ccminer

# Veil-Miner-SHA: SHA256D only. Stripped from ccminer 2.3.1.
ccminer_SOURCES	= elist.h miner.h compat.h \
		  compat/inttypes.h compat/stdbool.h compat/unistd.h \
		  compat/sys/time.h compat/getopt/getopt.h \
		  crc32.c \
		  ccminer.cpp pools.cpp util.cpp bench.cpp bignum.cpp \
		  api.cpp hashlog.cpp nvml.cpp stats.cpp sysinfos.cpp cuda.cpp \
		  nvsettings.cpp \
		  uint256.h \
		  cuda_checkhash.cu \
		  sph/sha2.c \
		  sha256/sha256d.cu sha256/cuda_sha256d.cu

if HAVE_NVML
nvml_defs = -DUSE_WRAPNVML
nvml_libs = -ldl
endif

if HAVE_WINDOWS
ccminer_SOURCES += compat/winansi.c
endif

ccminer_LDFLAGS  = $(PTHREAD_FLAGS) @CUDA_LDFLAGS@
ccminer_LDADD    = @LIBCURL@ @JANSSON_LIBS@ @PTHREAD_LIBS@ @WS2_LIBS@ @CUDA_LIBS@ @OPENMP_CFLAGS@ @LIBS@ $(nvml_libs)
ccminer_CPPFLAGS = @LIBCURL_CPPFLAGS@ @OPENMP_CFLAGS@ $(CPPFLAGS) $(PTHREAD_FLAGS) -fno-strict-aliasing $(JANSSON_INCLUDES) $(DEF_INCLUDES) $(nvml_defs)

if HAVE_OSX
ccminer_CPPFLAGS += -I/usr/local/llvm/lib/clang/4.0.0/include
ccminer_LDFLAGS += -L/usr/local/llvm/lib
ccminer_LDADD += -lomp
endif

ccminer_LDADD += -lcuda

nvcc_ARCH :=
nvcc_ARCH += -gencode=arch=compute_75,code=sm_75
nvcc_ARCH += -gencode=arch=compute_80,code=sm_80
nvcc_ARCH += -gencode=arch=compute_86,code=sm_86
nvcc_ARCH += -gencode=arch=compute_89,code=sm_89
nvcc_ARCH += -gencode=arch=compute_90,code=sm_90
nvcc_ARCH += -gencode=arch=compute_90,code=compute_90

nvcc_FLAGS = $(nvcc_ARCH) @CUDA_INCLUDES@ -I. @CUDA_CFLAGS@
nvcc_FLAGS += $(JANSSON_INCLUDES) --ptxas-options="-v"

.cu.o:
	$(NVCC) $(nvcc_FLAGS) --maxrregcount=128 -o $@ -c $<

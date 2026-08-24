/* The vendored curl/openssl/zlib x64 static libs were built before Visual
   Studio 2015. The Universal CRT that ships with newer toolsets no longer
   exports __iob_func (old code reached stdin/stdout/stderr through it), so
   provide the shim here. printf/vfprintf and friends are restored by adding
   legacy_stdio_definitions.lib to the link. */
#if defined(_MSC_VER)
#include <stdio.h>

FILE *__cdecl __iob_func(void)
{
    static FILE bucket[3];
    bucket[0] = *stdin;
    bucket[1] = *stdout;
    bucket[2] = *stderr;
    return bucket;
}
#endif

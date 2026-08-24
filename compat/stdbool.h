#pragma once

/* Old MSVC shipped no <stdbool.h>, so this shim stood in for it. Modern
   toolchains have bool natively, and in C++ it is a keyword the standard
   library forbids macroizing (MSVC C1189), so only define it for C. */
#ifndef __cplusplus
#define false   0
#define true    1
#define bool    int
#endif

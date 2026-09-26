/*
 * Hand-written for Adit (macOS only). Replaces the CMake-generated header from
 * git2_features.h.in. Keep in sync with the options in VENDORED.md.
 */
#ifndef INCLUDE_features_h__
#define INCLUDE_features_h__

#define GIT_THREADS 1
#define GIT_ARCH_64 1

#define GIT_USE_ICONV 1
#define GIT_USE_NSEC 1
#define GIT_USE_STAT_MTIMESPEC 1
#define GIT_USE_FUTIMENS 1

#define GIT_REGEX_REGCOMP_L 1
#define GIT_QSORT_BSD 1

#define GIT_HTTPPARSER_BUILTIN 1

#define GIT_SHA1_COMMON_CRYPTO 1
#define GIT_SHA256_COMMON_CRYPTO 1

#define GIT_COMPRESSION_ZLIB 1

#define GIT_RAND_GETLOADAVG 1

#define GIT_IO_POLL 1

#endif

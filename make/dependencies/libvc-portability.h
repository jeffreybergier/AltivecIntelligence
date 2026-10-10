#ifndef RC_LIBVC_PORTABILITY_H
#define RC_LIBVC_PORTABILITY_H

/* Upstream uses strcasecmp without including strings.h. */
#include <strings.h>
#include <stdio.h>
#include <sys/types.h>

#ifdef __APPLE__
/* count_vcards references getline, which Tiger does not provide. */
ssize_t RCLibVCGetLine(char **line, size_t *capacity, FILE *stream);
#define getline RCLibVCGetLine
#endif

#endif

#include "libvc-portability.h"

#ifdef __APPLE__
#include <errno.h>
#include <limits.h>
#include <stdlib.h>

ssize_t RCLibVCGetLine(char **line, size_t *capacity, FILE *stream)
{
  size_t length = 0;
  int ch;
  if (line == NULL || capacity == NULL || stream == NULL) {
    errno = EINVAL;
    return -1;
  }
  if (*line == NULL) *capacity = 0;
  while ((ch = fgetc(stream)) != EOF) {
    if (length >= (size_t)SSIZE_MAX - 1) {
      errno = EOVERFLOW;
      return -1;
    }
    if (length + 1 >= *capacity) {
      size_t next = *capacity > (size_t)SSIZE_MAX / 2 ?
          (size_t)SSIZE_MAX : (*capacity == 0 ? 128 : *capacity * 2);
      char *grown = realloc(*line, next);
      if (grown == NULL) return -1;
      *line = grown;
      *capacity = next;
    }
    (*line)[length++] = (char)ch;
    if (ch == '\n') break;
  }
  if (*line != NULL && *capacity > length) (*line)[length] = '\0';
  return length == 0 ? -1 : (ssize_t)length;
}
#endif

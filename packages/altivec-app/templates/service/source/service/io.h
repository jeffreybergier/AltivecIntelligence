#ifndef ALTIVEC_IPC_IO_H
#define ALTIVEC_IPC_IO_H
#include <unistd.h>
/* Stream sockets may split a four-byte message across multiple reads/writes. */
static int ipc_read_four(int fd, char *bytes) {
  size_t offset = 0;
  while (offset < 4) {
    ssize_t count = read(fd, bytes + offset, 4 - offset);
    if (count <= 0) return -1;
    offset += (size_t)count;
  }
  return 0;
}
static int ipc_write_four(int fd, const char *bytes) {
  size_t offset = 0;
  while (offset < 4) {
    ssize_t count = write(fd, bytes + offset, 4 - offset);
    if (count <= 0) return -1;
    offset += (size_t)count;
  }
  return 0;
}
#endif

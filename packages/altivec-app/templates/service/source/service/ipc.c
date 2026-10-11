#include "ipc.h"
#include "io.h"
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/time.h>
#include <unistd.h>
#include <string.h>
int ipc_request(const char *path) {
  struct sockaddr_un address;
  struct timeval timeout;
  char reply[4]; int fd, count;
  if (!path || strlen(path) >= sizeof(address.sun_path)) return -1;
  memset(&address, 0, sizeof(address)); address.sun_family = AF_UNIX;
  strcpy(address.sun_path, path);
  fd = socket(AF_UNIX, SOCK_STREAM, 0); if (fd < 0) return -1;
  timeout.tv_sec = 3; timeout.tv_usec = 0;
  setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
  setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout));
  if (connect(fd, (struct sockaddr *)&address, sizeof(address)) != 0) { close(fd); return -1; }
  if (ipc_write_four(fd, "PING") != 0) { close(fd); return -1; }
  count = ipc_read_four(fd, reply); close(fd);
  return count == 0 && memcmp(reply, "PONG", 4) == 0 ? 0 : -1;
}

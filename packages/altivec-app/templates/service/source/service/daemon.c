#include "io.h"
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <signal.h>
#include <unistd.h>
#include <string.h>
#include <stdio.h>
#include <errno.h>
static volatile sig_atomic_t running = 1;
static void stop(int sig) { (void)sig; running = 0; }
int main(int argc, char **argv) {
  struct sockaddr_un address; struct sigaction action;
  struct timeval timeout; int fd;
  if (argc != 2 || strlen(argv[1]) >= sizeof(address.sun_path)) return 2;
  memset(&address, 0, sizeof(address)); address.sun_family = AF_UNIX;
  strcpy(address.sun_path, argv[1]);
  memset(&action, 0, sizeof(action)); action.sa_handler = stop;
  sigaction(SIGTERM, &action, 0); sigaction(SIGINT, &action, 0); signal(SIGPIPE, SIG_IGN);
  umask(0077);
  fd = socket(AF_UNIX, SOCK_STREAM, 0); if (fd < 0) return 1;
  /* launchd may kill a service before cleanup. Reclaim only our own socket,
   * and only after a connect proves that no server is listening there. */
  {
    struct stat info;
    if (lstat(argv[1], &info) == 0) {
      int probe, connected, failure;
      if (!S_ISSOCK(info.st_mode) || info.st_uid != geteuid()) { close(fd); return 1; }
      probe = socket(AF_UNIX, SOCK_STREAM, 0);
      if (probe < 0) { close(fd); return 1; }
      connected = connect(probe, (struct sockaddr *)&address, sizeof(address));
      failure = errno;
      close(probe);
      if (connected == 0 || failure != ECONNREFUSED || unlink(argv[1]) != 0) {
        close(fd); return 1;
      }
    } else if (errno != ENOENT) { close(fd); return 1; }
  }
  if (bind(fd, (struct sockaddr *)&address, sizeof(address)) || listen(fd, 8)) {
    perror("bind/listen"); close(fd); return 1;
  }
  while (running) {
    char request[4]; int client = accept(fd, 0, 0);
    if (client < 0) { if (errno == EINTR) continue; break; }
    timeout.tv_sec = 2; timeout.tv_usec = 0;
    setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
    if (ipc_read_four(client, request) == 0 && memcmp(request, "PING", 4) == 0)
      (void)ipc_write_four(client, "PONG");
    close(client);
  }
  close(fd); unlink(argv[1]); return 0;
}

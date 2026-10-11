#include "ipc.h"
#include <stdio.h>
#include <signal.h>
int main(int argc, char **argv) {
  signal(SIGPIPE, SIG_IGN);
  if (argc != 2) { fprintf(stderr, "usage: client SOCKET\n"); return 2; }
  if (ipc_request(argv[1]) != 0) return 1;
  puts("PONG"); return 0;
}

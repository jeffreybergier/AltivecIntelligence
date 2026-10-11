#ifndef ALTIVEC_IPC_H
#define ALTIVEC_IPC_H
/* One request/response per connection. A caller supplies its writable socket path. */
int ipc_request(const char *path);
#endif

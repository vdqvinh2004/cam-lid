#ifndef CLRB_PEER_IDENTITY_H
#define CLRB_PEER_IDENTITY_H
#include <stdint.h>

typedef struct {
    uint32_t uid;
    int32_t pid;
    int32_t pid_version;
    char cdhash[41];
} CLRBPeerIdentity;

// Public Darwin/Security APIs only. Output is populated only on success.
int32_t CLRBReadPeerIdentity(int fd, CLRBPeerIdentity *identity);
int32_t CLRBExecutableHash(const char *path, char hash[41]);
int32_t CLRBCurrentHash(char hash[41]);
#endif

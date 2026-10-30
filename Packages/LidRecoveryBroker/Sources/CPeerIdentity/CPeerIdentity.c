#include "CPeerIdentity.h"
#include <Security/Security.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <bsm/libbsm.h>
#include <errno.h>
#include <string.h>

static OSStatus copy_hash(SecCodeRef code, char output[41]) {
    CFDictionaryRef information = NULL;
    OSStatus status = SecCodeCopySigningInformation(code, kSecCSSigningInformation, &information);
    if (status != errSecSuccess) return status;
    CFTypeRef value = CFDictionaryGetValue(information, kSecCodeInfoUnique);
    if (!value || CFGetTypeID(value) != CFDataGetTypeID() || CFDataGetLength(value) != 20) {
        CFRelease(information);
        return errSecCSUnsigned;
    }
    const UInt8 *bytes = CFDataGetBytePtr(value);
    const char *hex = "0123456789abcdef";
    for (int i = 0; i < 20; ++i) {
        output[i * 2] = hex[bytes[i] >> 4];
        output[i * 2 + 1] = hex[bytes[i] & 15];
    }
    output[40] = 0;
    CFRelease(information);
    return errSecSuccess;
}

int32_t CLRBExecutableHash(const char *path, char output[41]) {
    CFURLRef url = CFURLCreateFromFileSystemRepresentation(NULL, (const UInt8 *)path, strlen(path), false);
    if (!url) return errSecParam;
    SecStaticCodeRef code = NULL;
    OSStatus status = SecStaticCodeCreateWithPath(url, kSecCSDefaultFlags, &code);
    CFRelease(url);
    if (status != errSecSuccess) return status;
    status = SecStaticCodeCheckValidity(code, kSecCSStrictValidate, NULL);
    if (status == errSecSuccess) status = copy_hash((SecCodeRef)code, output);
    CFRelease(code);
    return status;
}

int32_t CLRBCurrentHash(char output[41]) {
    SecCodeRef code = NULL;
    OSStatus status = SecCodeCopySelf(kSecCSDefaultFlags, &code);
    if (status != errSecSuccess) return status;
    status = SecCodeCheckValidity(code, kSecCSStrictValidate, NULL);
    if (status == errSecSuccess) status = copy_hash(code, output);
    CFRelease(code);
    return status;
}

int32_t CLRBReadPeerIdentity(int fd, CLRBPeerIdentity *output) {
    audit_token_t token = {0};
    socklen_t length = sizeof(token);
    if (getsockopt(fd, SOL_LOCAL, LOCAL_PEERTOKEN, &token, &length) != 0) return errno;
    if (length != sizeof(token)) return EIO;
    CFDataRef data = CFDataCreate(NULL, (const UInt8 *)&token, sizeof(token));
    const void *keys[] = { kSecGuestAttributeAudit };
    const void *values[] = { data };
    CFDictionaryRef attributes = CFDictionaryCreate(NULL, keys, values, 1,
        &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    SecCodeRef code = NULL;
    OSStatus status = SecCodeCopyGuestWithAttributes(NULL, attributes, kSecCSDefaultFlags, &code);
    CFRelease(attributes);
    CFRelease(data);
    if (status != errSecSuccess) return status;
    CLRBPeerIdentity identity = {0};
    status = SecCodeCheckValidity(code, kSecCSStrictValidate, NULL);
    if (status == errSecSuccess) status = copy_hash(code, identity.cdhash);
    CFRelease(code);
    if (status != errSecSuccess) return status;
    identity.uid = audit_token_to_euid(token);
    identity.pid = audit_token_to_pid(token);
    identity.pid_version = audit_token_to_pidversion(token);
    if (identity.pid <= 0) return EIO;
    *output = identity;
    return 0;
}

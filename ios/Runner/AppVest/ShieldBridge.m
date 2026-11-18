#import "ShieldBridge.h"
#import <string.h>

#if TARGET_OS_SIMULATOR

int ShieldInit(NSString *accessKey, NSString *uuid) {
    (void)accessKey;
    (void)uuid;
    return -1;
}

int ShieldLocalPort(char *ipOut, int ipLen, int *portOut, NSString *host) {
    (void)host;
    if (ipOut != NULL && ipLen > 0) {
        ipOut[0] = '\0';
    }
    if (portOut != NULL) {
        *portOut = -1;
    }
    return -1;
}

int ShieldStop(void) {
    return 0;
}

int ShieldReinit(void) {
    return -1;
}

#else

#import "appvest.h"

static AppVest *ShieldVest(void) {
    static AppVest *vest;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        vest = [[AppVest alloc] init];
    });
    return vest;
}

int ShieldInit(NSString *accessKey, NSString *uuid) {
    if (accessKey.length == 0 || uuid.length == 0) {
        return -1;
    }
    return [ShieldVest() init:accessKey uuid:uuid];
}

int ShieldLocalPort(char *ipOut, int ipLen, int *portOut, NSString *host) {
    security_connection_t conn;
    memset(&conn, 0, sizeof(conn));
    if (host == nil) {
        host = @"";
    }
    int rc = [ShieldVest() getServerIPAndPort:&conn host:host port:443];
    if (rc != 0 || conn.port <= 0 || conn.ip[0] == '\0') {
        return -1;
    }
    strlcpy(ipOut, conn.ip, (size_t)ipLen);
    *portOut = conn.port;
    return 0;
}

int ShieldStop(void) {
    return [ShieldVest() stopAllListenerPorts];
}

int ShieldReinit(void) {
    return [ShieldVest() reinit];
}

#endif

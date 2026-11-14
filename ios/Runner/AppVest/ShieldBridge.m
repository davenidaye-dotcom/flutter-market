#import "ShieldBridge.h"
#import "appvest.h"
#import <string.h>

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

int ShieldLocalPort(char *ipOut, int ipLen, int *portOut) {
    security_connection_t conn;
    memset(&conn, 0, sizeof(conn));
    int rc = [ShieldVest() getServerIPAndPort:&conn host:@"" port:443];
    if (rc != 0 || conn.port <= 0 || conn.ip[0] == '\0') {
        return -1;
    }
    strlcpy(ipOut, conn.ip, (size_t)ipLen);
    *portOut = conn.port;
    return 0;
}

//
//  appvest.h, for ios SDK header
//  appvest
//

#ifndef appvest_h
#define appvest_h

#import <Foundation/Foundation.h>

typedef struct security_connection_s {
    char     ip[32];
    int      port;
} security_connection_t;

__attribute__((visibility("default")))
@interface AppVest : NSObject

-(int)init: (NSString*)accessKey  uuid:(NSString*)uuid;
-(int)reinit;
-(int)addListeningPort: (int)port __attribute__((deprecated));
-(int)getLocalPort: (int)port __attribute__((deprecated));
-(int)getHttpLocalPort: (NSString*)host  port:(int)port __attribute__((deprecated));
-(NSString*)getClientIP;
-(NSString*)getProxyServerIP;
-(int)setTimeouts:(int)read_timeout  write_timeout: (int)write_timeout;
-(int)getServerIPAndPort: (security_connection_t*)conn host:(NSString*)host port:(int)port;
-(int)setCredit: (NSString*)uid  credit:(int)credit;

@end

#endif /* appvest_h */

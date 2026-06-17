#import "ObjCExceptionCatcher.h"

@implementation ObjCExceptionCatcher

+ (NSError * _Nullable)catchExceptionInBlock:(void (NS_NOESCAPE ^)(void))block {
    @try {
        block();
        return nil;
    } @catch (NSException *exception) {
        NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
        userInfo[NSLocalizedDescriptionKey] = exception.reason ?: exception.name;
        if (exception.userInfo) {
            userInfo[@"ExceptionUserInfo"] = exception.userInfo;
        }
        return [NSError errorWithDomain:@"ACSExceptionDomain"
                                   code:-1
                               userInfo:userInfo];
    }
}

@end

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Bridges Objective-C @try/@catch exception handling into Swift.
/// Swift's do-catch cannot catch NSException (ObjC exceptions),
/// so this helper converts them into NSError for safe Swift handling.
@interface ObjCExceptionCatcher : NSObject

/// Executes the block inside @try/@catch.
/// Returns nil on success. If an NSException is thrown, returns the exception as NSError.
+ (NSError * _Nullable)catchExceptionInBlock:(void (NS_NOESCAPE ^)(void))block;

@end

NS_ASSUME_NONNULL_END

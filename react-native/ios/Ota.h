#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// What the app calls while it starts.
@interface Ota : NSObject

/// The bundle to load: the newest patch that hasn't failed, or nil for the
/// bundle inside the app.
+ (nullable NSURL *)bundleURL;

@end

NS_ASSUME_NONNULL_END

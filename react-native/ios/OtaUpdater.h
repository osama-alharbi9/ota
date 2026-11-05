#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Downloads patches and decides which bundle boots.
///
/// A patch moves through three slots: `next` when it is downloaded, `booting`
/// while its first launch is unproven, and `current` once the running app confirms
/// it. If the app starts and finds a patch still in `booting`, that launch crashed,
/// so the patch is marked failed and never boots again.
///
/// state.json is the only source of truth. It is rewritten whole on every change.
@interface OtaUpdater : NSObject

+ (instancetype)shared;

/// Picks the bundle for this launch. Returns nil for the bundle inside the app.
- (nullable NSURL *)prepareBoot;

/// The running bundle works. Promotes it and clears out older patches.
- (void)markReady;

- (NSDictionary *)stateDictionary;

/// Asks the server for a newer patch and downloads it. Blocks: call off the main
/// thread. Returns nil and sets `error` if the check failed.
- (nullable NSDictionary *)checkForUpdateWithError:(NSError **)error;

@end

NS_ASSUME_NONNULL_END

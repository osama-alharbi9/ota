#import <OtaSpec/OtaSpec.h>

#import "OtaUpdater.h"

@interface OtaModule : NSObject <NativeOtaSpec>
@end

@implementation OtaModule

RCT_EXPORT_MODULE(Ota)

- (void)getState:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject
{
  resolve([[OtaUpdater shared] stateDictionary]);
}

- (void)checkForUpdate:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject
{
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
    NSError *error;
    NSDictionary *result = [[OtaUpdater shared] checkForUpdateWithError:&error];
    if (result) {
      resolve(result);
    } else {
      reject(@"ota_check_failed", error.localizedDescription, error);
    }
  });
}

- (void)markReady
{
  [[OtaUpdater shared] markReady];
}

- (std::shared_ptr<facebook::react::TurboModule>)getTurboModule:(const facebook::react::ObjCTurboModule::InitParams &)params
{
  return std::make_shared<facebook::react::NativeOtaSpecJSI>(params);
}

@end

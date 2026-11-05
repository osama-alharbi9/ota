#import "Ota.h"

#import "OtaUpdater.h"

@implementation Ota

+ (NSURL *)bundleURL
{
  return [[OtaUpdater shared] prepareBoot];
}

@end

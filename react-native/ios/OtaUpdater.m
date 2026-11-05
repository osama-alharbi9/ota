#import "OtaUpdater.h"

#import <CommonCrypto/CommonDigest.h>
#import <compression.h>

static NSString *const kBundleName = @"main.jsbundle";
static NSString *const kArch = @"js";
static NSString *const kPlatform = @"ios";
static NSString *const kErrorDomain = @"dev.ota.reactnative";
static const NSTimeInterval kTimeout = 15;

static NSError *OtaError(NSString *message)
{
  return [NSError errorWithDomain:kErrorDomain code:1 userInfo:@{NSLocalizedDescriptionKey : message}];
}

@implementation OtaUpdater {
  NSString *_root;
  NSString *_patches;
  NSString *_statePath;
  NSString *_releaseVersion;
  NSDictionary<NSString *, NSString *> *_config;
  NSMutableDictionary *_state;
  NSNumber *_bootedPatch;
}

+ (instancetype)shared
{
  static OtaUpdater *instance;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    instance = [OtaUpdater new];
  });
  return instance;
}

- (instancetype)init
{
  if (self = [super init]) {
    NSString *support = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject;
    _root = [support stringByAppendingPathComponent:@"ota"];
    _patches = [_root stringByAppendingPathComponent:@"patches"];
    _statePath = [_root stringByAppendingPathComponent:@"state.json"];
    NSDictionary *info = NSBundle.mainBundle.infoDictionary;
    _releaseVersion = [NSString stringWithFormat:@"%@+%@", info[@"CFBundleShortVersionString"], info[@"CFBundleVersion"]];
    _config = [self loadConfig];
    _state = [self loadState];
  }
  return self;
}

#pragma mark - Boot

- (NSURL *)prepareBoot
{
  @synchronized(self) {
    NSNumber *crashed = _state[@"booting"];
    if (crashed) {
      NSLog(@"ota: patch %@ did not confirm its last launch. Removing it.", crashed);
      [_state removeObjectForKey:@"booting"];
      NSMutableArray *failed = [_state[@"failed"] mutableCopy];
      [failed addObject:crashed];
      _state[@"failed"] = failed;
      if ([_state[@"next"] isEqual:crashed]) [_state removeObjectForKey:@"next"];
      if ([_state[@"current"] isEqual:crashed]) [_state removeObjectForKey:@"current"];
      [NSFileManager.defaultManager removeItemAtPath:[self patchDir:crashed] error:nil];
      [self queueEvent:@"__patch_install_failure__" patch:crashed];
    }

    NSNumber *candidate = _state[@"next"] ?: _state[@"current"];
    if (candidate && ([_state[@"failed"] containsObject:candidate] || ![self bundleExists:candidate])) {
      // A patch whose files vanished can't boot. Forget it and use what's left.
      if ([_state[@"next"] isEqual:candidate]) [_state removeObjectForKey:@"next"];
      if ([_state[@"current"] isEqual:candidate]) [_state removeObjectForKey:@"current"];
      candidate = _state[@"current"];
      if (candidate && ![self bundleExists:candidate]) {
        [_state removeObjectForKey:@"current"];
        candidate = nil;
      }
    }

    _bootedPatch = candidate;
    if (candidate && ![candidate isEqual:_state[@"current"]]) _state[@"booting"] = candidate;
    [self saveState];
    [self removeUnusedPatches];

    if (!candidate) return nil;
    NSLog(@"ota: booting patch %@", candidate);
    return [NSURL fileURLWithPath:[[self patchDir:candidate] stringByAppendingPathComponent:kBundleName]];
  }
}

- (void)markReady
{
  @synchronized(self) {
    NSNumber *confirmed = _state[@"booting"];
    if (!confirmed || ![confirmed isEqual:_bootedPatch]) return;
    [_state removeObjectForKey:@"booting"];
    _state[@"current"] = confirmed;
    if ([_state[@"next"] isEqual:confirmed]) [_state removeObjectForKey:@"next"];
    [self saveState];
    [self queueEvent:@"__patch_install__" patch:confirmed];
    [self removeUnusedPatches];
  }
}

- (NSDictionary *)stateDictionary
{
  @synchronized(self) {
    NSNumber *next = [_state[@"next"] isEqual:_bootedPatch] ? nil : _state[@"next"];
    return @{
      @"releaseVersion" : _releaseVersion,
      @"bootedPatch" : _bootedPatch ?: NSNull.null,
      @"currentPatch" : _state[@"current"] ?: NSNull.null,
      @"nextPatch" : next ?: NSNull.null,
      @"configured" : @(_config != nil),
      @"appId" : _config[@"app_id"] ?: NSNull.null,
      @"channel" : _config[@"channel"] ?: @"stable",
      @"autoUpdate" : @(_config != nil && ![_config[@"auto_update"] isEqualToString:@"false"]),
    };
  }
}

#pragma mark - Update check

- (NSDictionary *)checkForUpdateWithError:(NSError **)error
{
  NSString *appId = _config[@"app_id"];
  NSString *baseUrl = _config[@"base_url"];
  if (!appId || !baseUrl) return @{@"status" : @"disabled"};

  [self flushEvents];

  NSMutableDictionary *body = [@{
    @"app_id" : appId,
    @"channel" : _config[@"channel"] ?: @"stable",
    @"release_version" : _releaseVersion,
    @"platform" : kPlatform,
    @"arch" : kArch,
  } mutableCopy];
  @synchronized(self) {
    body[@"client_id"] = _state[@"client_id"];
    NSNumber *current = _state[@"current"];
    if (current) {
      body[@"patch_number"] = current;
      body[@"current_patch_number"] = current;
    }
  }

  NSString *checkUrl = [baseUrl stringByAppendingString:@"/api/v1/patches/check"];
  NSData *data = [self post:checkUrl json:body error:error];
  if (!data) return nil;
  NSDictionary *response = [NSJSONSerialization JSONObjectWithData:data options:0 error:error];
  if (![response isKindOfClass:NSDictionary.class]) return nil;

  [self applyRollbacks:response[@"rolled_back_patch_numbers"]];

  NSDictionary *patch = response[@"patch"];
  if (![response[@"patch_available"] boolValue] || ![patch isKindOfClass:NSDictionary.class]) {
    return @{@"status" : @"up-to-date"};
  }
  NSNumber *number = patch[@"number"];
  @synchronized(self) {
    if ([number isEqual:_state[@"current"]] || [number isEqual:_state[@"next"]] || [_state[@"failed"] containsObject:number]) {
      return @{@"status" : @"up-to-date"};
    }
  }

  if (![self install:number url:patch[@"download_url"] hash:patch[@"hash"] error:error]) return nil;
  @synchronized(self) {
    _state[@"next"] = number;
    [self saveState];
    [self queueEvent:@"__patch_download__" patch:number];
  }
  [self flushEvents];
  NSLog(@"ota: patch %@ is ready for the next launch", number);
  return @{@"status" : @"downloaded", @"patchNumber" : number};
}

- (void)applyRollbacks:(id)numbers
{
  if (![numbers isKindOfClass:NSArray.class]) return;
  @synchronized(self) {
    for (NSNumber *number in numbers) {
      if ([_state[@"next"] isEqual:number]) {
        [_state removeObjectForKey:@"next"];
        [NSFileManager.defaultManager removeItemAtPath:[self patchDir:number] error:nil];
      }
      // The running code stays until the app restarts, then the next boot skips it.
      // Its files are kept for now because this launch may still read its assets.
      if ([_state[@"current"] isEqual:number]) [_state removeObjectForKey:@"current"];
    }
    [self saveState];
  }
}

#pragma mark - Install

- (BOOL)install:(NSNumber *)number url:(NSString *)urlString hash:(NSString *)expectedHash error:(NSError **)error
{
  NSFileManager *files = NSFileManager.defaultManager;
  NSString *work = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
  [files createDirectoryAtPath:work withIntermediateDirectories:YES attributes:nil error:nil];
  NSString *staging = [_patches stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.staging", number]];
  NSString *archive = [work stringByAppendingPathComponent:@"update.tar.gz"];
  NSString *tar = [work stringByAppendingPathComponent:@"update.tar"];

  BOOL ok = [self download:urlString to:archive error:error] && [self file:archive matchesHash:expectedHash error:error];
  if (ok) ok = [self gunzip:archive to:tar error:error];
  if (ok) {
    [files removeItemAtPath:staging error:nil];
    ok = [files createDirectoryAtPath:staging withIntermediateDirectories:YES attributes:nil error:error];
  }
  if (ok) ok = [self untar:tar to:staging error:error];
  if (ok && ![files fileExistsAtPath:[staging stringByAppendingPathComponent:kBundleName]]) {
    if (error) *error = OtaError(@"The patch has no bundle");
    ok = NO;
  }
  if (ok) {
    NSString *target = [self patchDir:number];
    [files removeItemAtPath:target error:nil];
    ok = [files moveItemAtPath:staging toPath:target error:error];
  }

  [files removeItemAtPath:work error:nil];
  [files removeItemAtPath:staging error:nil];
  return ok;
}

- (BOOL)download:(NSString *)urlString to:(NSString *)destination error:(NSError **)error
{
  NSURL *url = [NSURL URLWithString:urlString];
  if (!url) {
    if (error) *error = OtaError(@"The server sent an invalid download URL");
    return NO;
  }
  dispatch_semaphore_t done = dispatch_semaphore_create(0);
  __block NSError *failure;
  NSURLRequest *request = [NSURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:kTimeout];
  [[NSURLSession.sharedSession downloadTaskWithRequest:request completionHandler:^(NSURL *location, NSURLResponse *response, NSError *taskError) {
    NSInteger status = [(NSHTTPURLResponse *)response statusCode];
    if (taskError) {
      failure = taskError;
    } else if (status != 200) {
      failure = OtaError([NSString stringWithFormat:@"Download failed with status %ld", (long)status]);
    } else {
      NSError *moveError;
      if (![NSFileManager.defaultManager moveItemAtPath:location.path toPath:destination error:&moveError]) {
        failure = moveError;
      }
    }
    dispatch_semaphore_signal(done);
  }] resume];
  dispatch_semaphore_wait(done, DISPATCH_TIME_FOREVER);
  if (failure && error) *error = failure;
  return failure == nil;
}

- (BOOL)file:(NSString *)path matchesHash:(NSString *)expected error:(NSError **)error
{
  NSData *data = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:error];
  if (!data) return NO;
  unsigned char digest[CC_SHA256_DIGEST_LENGTH];
  CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
  NSMutableString *actual = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
  for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) [actual appendFormat:@"%02x", digest[i]];
  if ([actual caseInsensitiveCompare:expected] != NSOrderedSame) {
    if (error) *error = OtaError(@"The patch does not match its hash");
    return NO;
  }
  return YES;
}

/// Inflates a gzip file. Apple's COMPRESSION_ZLIB is raw DEFLATE, so the gzip
/// header and trailer are skipped by hand.
- (BOOL)gunzip:(NSString *)source to:(NSString *)destination error:(NSError **)error
{
  NSData *data = [NSData dataWithContentsOfFile:source options:NSDataReadingMappedIfSafe error:error];
  if (!data) return NO;
  const uint8_t *bytes = data.bytes;
  size_t length = data.length;
  if (length < 18 || bytes[0] != 0x1f || bytes[1] != 0x8b || bytes[2] != 8) {
    if (error) *error = OtaError(@"The patch is not a gzip file");
    return NO;
  }
  uint8_t flags = bytes[3];
  size_t offset = 10;
  if (flags & 4) offset += 2 + (size_t)(bytes[offset] | (bytes[offset + 1] << 8));
  if (flags & 8) { while (offset < length && bytes[offset++]) {} }
  if (flags & 16) { while (offset < length && bytes[offset++]) {} }
  if (flags & 2) offset += 2;
  if (offset + 8 > length) {
    if (error) *error = OtaError(@"The patch is truncated");
    return NO;
  }

  FILE *output = fopen(destination.fileSystemRepresentation, "wb");
  if (!output) {
    if (error) *error = OtaError(@"Could not write the patch");
    return NO;
  }
  compression_stream stream;
  if (compression_stream_init(&stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB) != COMPRESSION_STATUS_OK) {
    fclose(output);
    if (error) *error = OtaError(@"Could not start decompression");
    return NO;
  }
  stream.src_ptr = bytes + offset;
  stream.src_size = length - offset - 8;
  size_t capacity = 64 * 1024;
  uint8_t *buffer = malloc(capacity);
  compression_status status;
  BOOL ok = YES;
  do {
    stream.dst_ptr = buffer;
    stream.dst_size = capacity;
    status = compression_stream_process(&stream, COMPRESSION_STREAM_FINALIZE);
    if (status == COMPRESSION_STATUS_ERROR) {
      ok = NO;
      break;
    }
    size_t produced = capacity - stream.dst_size;
    if (fwrite(buffer, 1, produced, output) != produced) {
      ok = NO;
      break;
    }
  } while (status == COMPRESSION_STATUS_OK);
  free(buffer);
  compression_stream_destroy(&stream);
  fclose(output);
  if (!ok && error) *error = OtaError(@"Could not decompress the patch");
  return ok;
}

static NSString *TarField(const uint8_t *header, size_t offset, size_t length)
{
  size_t end = offset;
  while (end < offset + length && header[end]) end++;
  return [[NSString alloc] initWithBytes:header + offset length:end - offset encoding:NSUTF8StringEncoding] ?: @"";
}

/// Reads a ustar file. Regular files only, and nothing may escape `destination`.
- (BOOL)untar:(NSString *)source to:(NSString *)destination error:(NSError **)error
{
  NSData *data = [NSData dataWithContentsOfFile:source options:NSDataReadingMappedIfSafe error:error];
  if (!data) return NO;
  const uint8_t *bytes = data.bytes;
  NSFileManager *files = NSFileManager.defaultManager;
  size_t offset = 0;
  while (offset + 512 <= data.length) {
    const uint8_t *header = bytes + offset;
    BOOL empty = YES;
    for (int i = 0; i < 512 && empty; i++) empty = header[i] == 0;
    if (empty) return YES;

    NSString *name = TarField(header, 0, 100);
    NSString *prefix = TarField(header, 345, 155);
    NSString *path = prefix.length ? [NSString stringWithFormat:@"%@/%@", prefix, name] : name;
    unsigned long long size = strtoull(TarField(header, 124, 12).UTF8String, NULL, 8);
    uint8_t type = header[156];
    offset += 512;
    if (size > data.length - offset) {
      if (error) *error = OtaError(@"The patch is truncated");
      return NO;
    }

    if (type == '0' || type == 0) {
      if ([path hasPrefix:@"/"] || [path.pathComponents containsObject:@".."]) {
        if (error) *error = OtaError(@"The patch contains an unsafe path");
        return NO;
      }
      NSString *target = [destination stringByAppendingPathComponent:path];
      [files createDirectoryAtPath:target.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
      NSData *contents = [NSData dataWithBytesNoCopy:(void *)(bytes + offset) length:(NSUInteger)size freeWhenDone:NO];
      if (![contents writeToFile:target options:0 error:error]) return NO;
    }
    offset += (size_t)((size + 511) / 512) * 512;
  }
  return YES;
}

#pragma mark - Events

- (void)queueEvent:(NSString *)type patch:(NSNumber *)number
{
  NSString *appId = _config[@"app_id"];
  if (!appId) return;
  @synchronized(self) {
    NSMutableArray *events = [_state[@"events"] mutableCopy];
    [events addObject:@{
      @"app_id" : appId,
      @"arch" : kArch,
      @"client_id" : _state[@"client_id"],
      @"type" : type,
      @"patch_number" : number,
      @"platform" : kPlatform,
      @"release_version" : _releaseVersion,
      @"timestamp" : @((long long)NSDate.date.timeIntervalSince1970),
    }];
    _state[@"events"] = events;
    [self saveState];
  }
}

/// Sends queued events. Failures keep them queued for the next check.
- (void)flushEvents
{
  NSString *baseUrl = _config[@"base_url"];
  if (!baseUrl) return;
  NSArray *pending;
  @synchronized(self) {
    pending = [_state[@"events"] copy];
  }
  NSUInteger sent = 0;
  NSString *url = [baseUrl stringByAppendingString:@"/api/v1/patches/events"];
  for (NSDictionary *event in pending) {
    NSError *error;
    if (![self post:url json:@{@"event" : event} error:&error]) {
      NSLog(@"ota: could not send update events: %@", error.localizedDescription);
      break;
    }
    sent++;
  }
  if (sent == 0) return;
  @synchronized(self) {
    NSMutableArray *events = [_state[@"events"] mutableCopy];
    [events removeObjectsInRange:NSMakeRange(0, sent)];
    _state[@"events"] = events;
    [self saveState];
  }
}

- (NSData *)post:(NSString *)urlString json:(NSDictionary *)json error:(NSError **)error
{
  NSData *body = [NSJSONSerialization dataWithJSONObject:json options:0 error:error];
  if (!body) return nil;
  NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:urlString] cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:kTimeout];
  request.HTTPMethod = @"POST";
  request.HTTPBody = body;
  [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];

  dispatch_semaphore_t done = dispatch_semaphore_create(0);
  __block NSData *result;
  __block NSError *failure;
  [[NSURLSession.sharedSession dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *taskError) {
    NSInteger status = [(NSHTTPURLResponse *)response statusCode];
    if (taskError) {
      failure = taskError;
    } else if (status < 200 || status > 299) {
      failure = OtaError([NSString stringWithFormat:@"%@ returned %ld", urlString, (long)status]);
    } else {
      result = data ?: [NSData data];
    }
    dispatch_semaphore_signal(done);
  }] resume];
  dispatch_semaphore_wait(done, DISPATCH_TIME_FOREVER);
  if (failure && error) *error = failure;
  return result;
}

#pragma mark - Storage

- (NSString *)patchDir:(NSNumber *)number
{
  return [_patches stringByAppendingPathComponent:number.stringValue];
}

- (BOOL)bundleExists:(NSNumber *)number
{
  return [NSFileManager.defaultManager fileExistsAtPath:[[self patchDir:number] stringByAppendingPathComponent:kBundleName]];
}

- (void)removeUnusedPatches
{
  NSFileManager *files = NSFileManager.defaultManager;
  NSMutableSet *keep = [NSMutableSet set];
  for (NSNumber *number in @[ _state[@"current"] ?: @(-1), _state[@"next"] ?: @(-1), _state[@"booting"] ?: @(-1), _bootedPatch ?: @(-1) ]) {
    [keep addObject:number.stringValue];
  }
  for (NSString *name in [files contentsOfDirectoryAtPath:_patches error:nil]) {
    if (![keep containsObject:name]) {
      [files removeItemAtPath:[_patches stringByAppendingPathComponent:name] error:nil];
    }
  }
}

- (NSMutableDictionary *)loadState
{
  NSData *data = [NSData dataWithContentsOfFile:_statePath];
  NSDictionary *loaded = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
  if ([loaded isKindOfClass:NSDictionary.class] && [loaded[@"release_version"] isEqual:_releaseVersion]) {
    return [loaded mutableCopy];
  }
  // Patches are built for one release. A store update starts clean.
  [NSFileManager.defaultManager removeItemAtPath:_patches error:nil];
  NSString *clientId = [loaded isKindOfClass:NSDictionary.class] ? loaded[@"client_id"] : nil;
  return [@{
    @"release_version" : _releaseVersion,
    @"client_id" : clientId ?: NSUUID.UUID.UUIDString,
    @"failed" : @[],
    @"events" : @[],
  } mutableCopy];
}

- (void)saveState
{
  NSFileManager *files = NSFileManager.defaultManager;
  [files createDirectoryAtPath:_patches withIntermediateDirectories:YES attributes:nil error:nil];
  // Patches come from the server, so a backup has no reason to carry them.
  NSURL *rootUrl = [NSURL fileURLWithPath:_root isDirectory:YES];
  [rootUrl setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:nil];
  NSData *data = [NSJSONSerialization dataWithJSONObject:_state options:0 error:nil];
  if (![data writeToFile:_statePath atomically:YES]) NSLog(@"ota: could not save update state");
}

/// Reads the flat `key: value` lines of `ota.yaml`.
- (NSDictionary<NSString *, NSString *> *)loadConfig
{
  NSString *path = [NSBundle.mainBundle pathForResource:@"ota" ofType:@"yaml"];
  NSString *text = path ? [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil] : nil;
  if (!text) {
    NSLog(@"ota: ota.yaml is not in this build, so updates are off. Run `ota init`, then `pod install`.");
    return nil;
  }
  NSMutableDictionary *values = [NSMutableDictionary dictionary];
  NSCharacterSet *trim = NSCharacterSet.whitespaceAndNewlineCharacterSet;
  NSCharacterSet *quotes = [NSCharacterSet characterSetWithCharactersInString:@"\"'"];
  for (NSString *rawLine in [text componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
    NSString *line = [[rawLine componentsSeparatedByString:@"#"].firstObject stringByTrimmingCharactersInSet:trim];
    NSRange colon = [line rangeOfString:@":"];
    if (colon.location == NSNotFound) continue;
    NSString *key = [[line substringToIndex:colon.location] stringByTrimmingCharactersInSet:trim];
    NSString *value = [[[line substringFromIndex:NSMaxRange(colon)] stringByTrimmingCharactersInSet:trim] stringByTrimmingCharactersInSet:quotes];
    if (value.length) values[key] = value;
  }
  if (!values[@"app_id"] || !values[@"base_url"]) return nil;
  while ([values[@"base_url"] hasSuffix:@"/"]) {
    values[@"base_url"] = [values[@"base_url"] substringToIndex:[values[@"base_url"] length] - 1];
  }
  return values;
}

@end

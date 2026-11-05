# React Native

Update the JavaScript and assets of a bare React Native app without a store release. Works on Android and iOS, on the New Architecture (React Native 0.76 and newer). Tested on 0.88.

Expo-managed apps are not supported yet.

## Set up

Run these from your app.

1. Register the app. This writes `ota.yaml`, which holds your app ID and server address.

   ```bash
   ota init
   ```

2. Install the SDK. It is not on npm yet, so install it from a clone of this repo.

   ```bash
   npm install /path/to/ota/react-native --install-links
   ```

3. Import it first in your entry file (`index.js`). The import is what confirms a patch works, so without it every patch rolls back.

   ```js
   import 'ota-react-native';
   import { AppRegistry } from 'react-native';
   ```

4. **Android:** pass the bundle path in `MainApplication.kt`.

   ```kotlin
   import dev.ota.reactnative.Ota

   override val reactHost: ReactHost by lazy {
     getDefaultReactHost(
       context = applicationContext,
       packageList = PackageList(this).packages,
       jsBundleFilePath = Ota.bundlePath(applicationContext),
     )
   }
   ```

5. **iOS:** use the patch in the release branch of `bundleURL()`, in `SceneDelegate.swift` (or `AppDelegate.swift` on older templates). Then run `pod install`.

   ```swift
   import OtaReactNative

   override func bundleURL() -> URL? {
     #if DEBUG
     RCTBundleURLProvider.sharedSettings().jsBundleURL(forBundleRoot: "index")
     #else
     Ota.bundleURL() ?? Bundle.main.url(forResource: "main", withExtension: "jsbundle")
     #endif
   }
   ```

   `pod install` copies `ota.yaml` into the app. Run it again whenever `ota.yaml` changes.

[`examples/react-native`](../examples/react-native) is a working app with all of this done.

## Ship

1. Record the release. Do this for every version you send to a store.

   ```bash
   ota release react-native
   ```

   It builds the bundle the way your release build does and reads the version from your native projects. Pick one platform with `--platforms=android`.

2. Build and ship the native app as usual.

3. When you have a fix, push it.

   ```bash
   ota patch react-native
   ```

   Patches target the release matching the version in your native projects. Target another one with `--release-version=1.0+1`.

Phones download the patch on their next launch and run it on the launch after.

## Roll back

```bash
ota patches rollback --release-version 1.0+1 --patch-number 3
```

Phones drop the patch at their next check and run the release, or the newest patch still live, on the launch after. Undo it with `--undo`. The console has the same buttons.

A patch that crashes the app in its first two seconds rolls itself back on the next launch, and that phone never runs it again.

## Channels

Patches go to the `stable` channel unless you pass `--track=beta` or `--track=staging`. A build follows the channel named in its `ota.yaml`:

```yaml
channel: beta
```

## JavaScript API

The import is all most apps need. To control the timing yourself, set `auto_update: false` in `ota.yaml` and call the API:

```ts
import { checkForUpdate, getState, markReady } from 'ota-react-native';

const { status, patchNumber } = await checkForUpdate(); // 'disabled' | 'up-to-date' | 'downloaded'
const { bootedPatch, nextPatch, releaseVersion } = await getState();
markReady(); // confirm the running patch sooner than the default two seconds
```

Debug builds load from Metro and never touch updates.

## Rules and limits

- **Native changes need a store release.** A patch can't add a native module or change native code. If patched JavaScript calls something missing, the app crashes and the patch rolls itself back.
- **React Native version is pinned.** Hermes bytecode only runs on the version that built it, so `ota patch` refuses a mismatch with the release.
- **Whole bundle, not a diff.** A patch contains the full bundle and assets, so size matches your bundle. Diffs are planned.
- **Updates apply at launch.** There is no restart API yet.
- **Use HTTPS in production.** Android and iOS block plain HTTP in release builds by default. The example allows it only to reach a local server.
- **Patches aren't signed yet.** Hashes catch corruption, but anyone who controls your server can publish code to your users. Protect it accordingly.

## Test it

`scripts/run_react_native_loop.sh android` (or `ios`) runs the whole flow on an emulator or simulator: release, patch, a crashing patch that rolls itself back, and a server rollback.

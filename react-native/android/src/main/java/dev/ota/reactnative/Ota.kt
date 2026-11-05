package dev.ota.reactnative

import android.content.Context

/** What the app calls while it starts. */
object Ota {
  /**
   * The bundle to load: the newest patch that hasn't failed, or null for the
   * bundle inside the app. Pass it as `jsBundleFilePath` to `getDefaultReactHost`.
   */
  @JvmStatic
  fun bundlePath(context: Context): String? = OtaUpdater.get(context).prepareBoot()
}

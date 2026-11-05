package dev.ota.reactnative

import com.facebook.react.bridge.Arguments
import com.facebook.react.bridge.Promise
import com.facebook.react.bridge.ReactApplicationContext
import java.util.concurrent.Executors

class OtaModule(context: ReactApplicationContext) : NativeOtaSpec(context) {
  private val updater = OtaUpdater.get(context)
  private val background = Executors.newSingleThreadExecutor()

  override fun getName() = NAME

  override fun getState(promise: Promise) {
    val state = updater.state()
    promise.resolve(
      Arguments.createMap().apply {
        putString("releaseVersion", state.releaseVersion)
        putNumberOrNull("bootedPatch", state.bootedPatch)
        putNumberOrNull("currentPatch", state.currentPatch)
        putNumberOrNull("nextPatch", state.nextPatch)
        putBoolean("configured", state.configured)
        putString("appId", state.appId)
        putString("channel", state.channel)
        putBoolean("autoUpdate", state.autoUpdate)
      },
    )
  }

  override fun checkForUpdate(promise: Promise) {
    background.execute {
      try {
        val result = updater.checkForUpdate()
        promise.resolve(
          Arguments.createMap().apply {
            putString("status", result.status)
            result.patchNumber?.let { putInt("patchNumber", it) }
          },
        )
      } catch (error: Exception) {
        promise.reject("ota_check_failed", error.message, error)
      }
    }
  }

  override fun markReady() {
    background.execute { updater.markReady() }
  }

  private fun com.facebook.react.bridge.WritableMap.putNumberOrNull(key: String, value: Int?) {
    if (value == null) putNull(key) else putInt(key, value)
  }

  companion object {
    const val NAME = "Ota"
  }
}

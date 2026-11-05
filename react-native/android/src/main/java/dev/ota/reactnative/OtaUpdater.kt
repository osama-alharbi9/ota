package dev.ota.reactnative

import android.content.Context
import android.os.Build
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.io.BufferedInputStream
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.InputStream
import java.net.HttpURLConnection
import java.net.URL
import java.security.DigestInputStream
import java.security.MessageDigest
import java.util.UUID
import java.util.zip.GZIPInputStream

private const val TAG = "ota"
private const val BUNDLE_NAME = "index.android.bundle"
private const val ARCH = "js"
private const val PLATFORM = "android"
private const val TIMEOUT_MS = 15_000

internal data class OtaStateSnapshot(
  val releaseVersion: String,
  val bootedPatch: Int?,
  val currentPatch: Int?,
  val nextPatch: Int?,
  val configured: Boolean,
  val appId: String?,
  val channel: String,
  val autoUpdate: Boolean,
)

internal data class OtaCheckResult(val status: String, val patchNumber: Int? = null)

/**
 * Downloads patches and decides which bundle boots.
 *
 * A patch moves through three slots: `next` when it is downloaded, `booting` while
 * its first launch is unproven, and `current` once the running app confirms it.
 * If the app starts and finds a patch still in `booting`, that launch crashed, so
 * the patch is marked failed and never boots again.
 *
 * state.json is the only source of truth. It is rewritten whole on every change.
 */
internal class OtaUpdater private constructor(private val context: Context) {
  private val root = File(context.filesDir, "ota")
  private val patches = File(root, "patches")
  private val stateFile = File(root, "state.json")
  private val config = OtaConfig.load(context)
  private val releaseVersion = readReleaseVersion()
  private var bootedPatch: Int? = null

  private var state = loadState()

  /** Picks the bundle for this launch. Returns null for the bundle inside the app. */
  @Synchronized
  fun prepareBoot(): String? {
    state.booting?.let { crashed ->
      Log.w(TAG, "Patch $crashed did not confirm its last launch. Removing it.")
      state.booting = null
      state.failed.add(crashed)
      if (state.next == crashed) state.next = null
      if (state.current == crashed) state.current = null
      patchDir(crashed).deleteRecursively()
      queueEvent("__patch_install_failure__", crashed)
    }

    var candidate = state.next ?: state.current
    if (candidate != null && (candidate in state.failed || !bundleFile(candidate).isFile)) {
      // A patch whose files vanished can't boot. Forget it and use what's left.
      if (state.next == candidate) state.next = null
      if (state.current == candidate) state.current = null
      candidate = state.current?.takeIf { bundleFile(it).isFile }
      if (candidate == null) state.current = null
    }

    bootedPatch = candidate
    if (candidate != null && candidate != state.current) state.booting = candidate
    saveState()
    removeUnusedPatches()

    if (candidate == null) return null
    Log.i(TAG, "Booting patch $candidate")
    return bundleFile(candidate).absolutePath
  }

  /** The running bundle works. Promotes it and clears out older patches. */
  @Synchronized
  fun markReady() {
    val confirmed = state.booting
    if (confirmed == null || confirmed != bootedPatch) return
    state.booting = null
    state.current = confirmed
    if (state.next == confirmed) state.next = null
    saveState()
    queueEvent("__patch_install__", confirmed)
    removeUnusedPatches()
  }

  /** Asks the server for a newer patch and downloads it. Blocks: call off the main thread. */
  fun checkForUpdate(): OtaCheckResult {
    val appId = config?.appId
    val baseUrl = config?.baseUrl
    if (appId == null || baseUrl == null) return OtaCheckResult("disabled")

    flushEvents()
    val body = JSONObject()
      .put("app_id", appId)
      .put("channel", config.channel)
      .put("release_version", releaseVersion)
      .put("platform", PLATFORM)
      .put("arch", ARCH)
      .put("client_id", synchronized(this) { state.clientId })
    synchronized(this) { state.current }?.let {
      body.put("patch_number", it)
      body.put("current_patch_number", it)
    }

    val response = JSONObject(post("$baseUrl/api/v1/patches/check", body.toString()))
    applyRollbacks(response.optJSONArray("rolled_back_patch_numbers"))

    if (!response.optBoolean("patch_available")) return OtaCheckResult("up-to-date")
    val patch = response.getJSONObject("patch")
    val number = patch.getInt("number")
    synchronized(this) {
      if (number == state.current || number == state.next || number in state.failed) {
        return OtaCheckResult("up-to-date")
      }
    }

    install(number, patch.getString("download_url"), patch.getString("hash"))
    synchronized(this) {
      state.next = number
      saveState()
    }
    queueEvent("__patch_download__", number)
    flushEvents()
    Log.i(TAG, "Patch $number is ready for the next launch")
    return OtaCheckResult("downloaded", number)
  }

  @Synchronized
  fun state() = OtaStateSnapshot(
    releaseVersion = releaseVersion,
    bootedPatch = bootedPatch,
    currentPatch = state.current,
    nextPatch = state.next?.takeIf { it != bootedPatch },
    configured = config != null,
    appId = config?.appId,
    channel = config?.channel ?: "stable",
    autoUpdate = config?.autoUpdate ?: false,
  )

  @Synchronized
  private fun applyRollbacks(numbers: JSONArray?) {
    if (numbers == null) return
    for (i in 0 until numbers.length()) {
      val number = numbers.getInt(i)
      if (state.next == number) {
        state.next = null
        patchDir(number).deleteRecursively()
      }
      // The running code stays until the app restarts, then the next boot skips it.
      // Its files are kept for now because this launch may still read its assets.
      if (state.current == number) state.current = null
    }
    saveState()
  }

  private fun install(number: Int, url: String, expectedHash: String) {
    val temp = File.createTempFile("patch", ".tar.gz", context.cacheDir)
    val staging = File(patches, "$number.staging")
    try {
      val digest = MessageDigest.getInstance("SHA-256")
      val connection = open(url)
      try {
        if (connection.responseCode != 200) {
          throw OtaException("Download failed with status ${connection.responseCode}")
        }
        DigestInputStream(connection.inputStream, digest).use { input ->
          FileOutputStream(temp).use { input.copyTo(it) }
        }
      } finally {
        connection.disconnect()
      }
      val actual = digest.digest().joinToString("") { "%02x".format(it) }
      if (!actual.equals(expectedHash, ignoreCase = true)) {
        throw OtaException("Hash mismatch for patch $number")
      }

      staging.deleteRecursively()
      staging.mkdirs()
      GZIPInputStream(BufferedInputStream(FileInputStream(temp))).use { untar(it, staging) }
      if (!File(staging, BUNDLE_NAME).isFile) throw OtaException("Patch $number has no bundle")

      val target = patchDir(number)
      target.deleteRecursively()
      if (!staging.renameTo(target)) throw OtaException("Could not install patch $number")
    } finally {
      temp.delete()
      staging.deleteRecursively()
    }
  }

  /** Reads a ustar stream. Regular files only, and nothing may escape [destination]. */
  private fun untar(input: InputStream, destination: File) {
    val base = destination.canonicalPath + File.separator
    val header = ByteArray(512)
    while (true) {
      if (!readFully(input, header)) return
      if (header.all { it == 0.toByte() }) return

      val name = field(header, 0, 100)
      val prefix = field(header, 345, 155)
      val path = if (prefix.isEmpty()) name else "$prefix/$name"
      val size = field(header, 124, 12).trim().ifEmpty { "0" }.toLong(8)
      val type = header[156].toInt()

      if (type == '0'.code || type == 0) {
        val file = File(destination, path)
        if (!file.canonicalPath.startsWith(base)) throw OtaException("Unsafe path in patch: $path")
        file.parentFile?.mkdirs()
        FileOutputStream(file).use { copyExactly(input, it, size) }
      } else {
        skipExactly(input, size)
      }
      skipExactly(input, (512 - size % 512) % 512)
    }
  }

  private fun field(header: ByteArray, offset: Int, length: Int): String {
    var end = offset
    while (end < offset + length && header[end] != 0.toByte()) end++
    return String(header, offset, end - offset, Charsets.UTF_8)
  }

  private fun readFully(input: InputStream, buffer: ByteArray): Boolean {
    var read = 0
    while (read < buffer.size) {
      val count = input.read(buffer, read, buffer.size - read)
      if (count < 0) return false
      read += count
    }
    return true
  }

  private fun copyExactly(input: InputStream, output: FileOutputStream, size: Long) {
    val buffer = ByteArray(64 * 1024)
    var remaining = size
    while (remaining > 0) {
      val count = input.read(buffer, 0, minOf(remaining, buffer.size.toLong()).toInt())
      if (count < 0) throw OtaException("Patch archive is truncated")
      output.write(buffer, 0, count)
      remaining -= count
    }
  }

  private fun skipExactly(input: InputStream, size: Long) {
    val buffer = ByteArray(4096)
    var remaining = size
    while (remaining > 0) {
      val count = input.read(buffer, 0, minOf(remaining, buffer.size.toLong()).toInt())
      if (count < 0) throw OtaException("Patch archive is truncated")
      remaining -= count
    }
  }

  private fun removeUnusedPatches() {
    val keep = setOfNotNull(state.current, state.next, state.booting, bootedPatch).map { it.toString() }
    patches.listFiles()?.filter { it.name !in keep }?.forEach { it.deleteRecursively() }
  }

  private fun patchDir(number: Int) = File(patches, number.toString())

  private fun bundleFile(number: Int) = File(patchDir(number), BUNDLE_NAME)

  @Synchronized
  private fun queueEvent(type: String, patchNumber: Int) {
    val appId = config?.appId ?: return
    state.events.put(
      JSONObject()
        .put("app_id", appId)
        .put("arch", ARCH)
        .put("client_id", state.clientId)
        .put("type", type)
        .put("patch_number", patchNumber)
        .put("platform", PLATFORM)
        .put("release_version", releaseVersion)
        .put("timestamp", System.currentTimeMillis() / 1000),
    )
    saveState()
  }

  /** Sends queued events. Failures keep them queued for the next check. */
  private fun flushEvents() {
    val baseUrl = config?.baseUrl ?: return
    val pending = synchronized(this) { JSONArray(state.events.toString()) }
    var sent = 0
    try {
      for (i in 0 until pending.length()) {
        post("$baseUrl/api/v1/patches/events", JSONObject().put("event", pending.get(i)).toString())
        sent++
      }
    } catch (error: Exception) {
      Log.w(TAG, "Could not send update events: ${error.message}")
    }
    if (sent > 0) {
      synchronized(this) {
        val remaining = JSONArray()
        for (i in sent until state.events.length()) remaining.put(state.events.get(i))
        state.events = remaining
        saveState()
      }
    }
  }

  private fun post(url: String, body: String): String {
    val connection = open(url)
    try {
      connection.requestMethod = "POST"
      connection.doOutput = true
      connection.setRequestProperty("Content-Type", "application/json")
      connection.outputStream.use { it.write(body.toByteArray()) }
      val status = connection.responseCode
      if (status !in 200..299) throw OtaException("$url returned $status")
      return connection.inputStream.bufferedReader().use { it.readText() }
    } finally {
      connection.disconnect()
    }
  }

  private fun open(url: String) = (URL(url).openConnection() as HttpURLConnection).apply {
    connectTimeout = TIMEOUT_MS
    readTimeout = TIMEOUT_MS
  }

  private fun readReleaseVersion(): String {
    val info = context.packageManager.getPackageInfo(context.packageName, 0)
    val code = if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else {
      @Suppress("DEPRECATION")
      info.versionCode.toLong()
    }
    return "${info.versionName}+$code"
  }

  private fun loadState(): PersistedState {
    val loaded = try {
      if (stateFile.isFile) PersistedState.fromJson(JSONObject(stateFile.readText())) else null
    } catch (error: Exception) {
      Log.w(TAG, "Ignoring unreadable state: ${error.message}")
      null
    }
    // Patches are built for one release. A store update starts clean.
    if (loaded != null && loaded.releaseVersion == releaseVersion) return loaded
    patches.deleteRecursively()
    return PersistedState(releaseVersion, loaded?.clientId ?: UUID.randomUUID().toString())
  }

  private fun saveState() {
    root.mkdirs()
    patches.mkdirs()
    val temp = File(root, "state.json.tmp")
    temp.writeText(state.toJson().toString())
    if (!temp.renameTo(stateFile)) Log.w(TAG, "Could not save update state")
  }

  private class OtaException(message: String) : Exception(message)

  companion object {
    @Volatile private var instance: OtaUpdater? = null

    fun get(context: Context): OtaUpdater = instance ?: synchronized(this) {
      instance ?: OtaUpdater(context.applicationContext).also { instance = it }
    }
  }
}

private class PersistedState(
  val releaseVersion: String,
  val clientId: String,
  var current: Int? = null,
  var next: Int? = null,
  var booting: Int? = null,
  val failed: MutableSet<Int> = mutableSetOf(),
  var events: JSONArray = JSONArray(),
) {
  fun toJson(): JSONObject = JSONObject()
    .put("release_version", releaseVersion)
    .put("client_id", clientId)
    .put("current", current ?: JSONObject.NULL)
    .put("next", next ?: JSONObject.NULL)
    .put("booting", booting ?: JSONObject.NULL)
    .put("failed", JSONArray(failed.toList()))
    .put("events", events)

  companion object {
    fun fromJson(json: JSONObject) = PersistedState(
      releaseVersion = json.getString("release_version"),
      clientId = json.getString("client_id"),
      current = json.optIntOrNull("current"),
      next = json.optIntOrNull("next"),
      booting = json.optIntOrNull("booting"),
      failed = json.optJSONArray("failed")?.let { list ->
        (0 until list.length()).map { list.getInt(it) }.toMutableSet()
      } ?: mutableSetOf(),
      events = json.optJSONArray("events") ?: JSONArray(),
    )

    private fun JSONObject.optIntOrNull(key: String): Int? = if (isNull(key)) null else optInt(key)
  }
}

private class OtaConfig(
  val appId: String,
  val baseUrl: String,
  val channel: String,
  val autoUpdate: Boolean,
) {
  companion object {
    /** Reads the flat `key: value` lines of `ota.yaml`. */
    fun load(context: Context): OtaConfig? {
      val text = try {
        context.assets.open("ota.yaml").bufferedReader().use { it.readText() }
      } catch (error: Exception) {
        Log.w(TAG, "ota.yaml is not in this build, so updates are off. Run `ota init`.")
        return null
      }
      val values = text.lineSequence()
        .map { it.substringBefore('#').trim() }
        .filter { it.contains(':') }
        .associate { line ->
          line.substringBefore(':').trim() to line.substringAfter(':').trim().trim('"', '\'')
        }
      val appId = values["app_id"]?.ifEmpty { null } ?: return null
      val baseUrl = values["base_url"]?.ifEmpty { null }?.trimEnd('/') ?: return null
      return OtaConfig(
        appId = appId,
        baseUrl = baseUrl,
        channel = values["channel"]?.ifEmpty { null } ?: "stable",
        autoUpdate = values["auto_update"] != "false",
      )
    }
  }
}

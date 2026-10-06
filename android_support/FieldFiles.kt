package app.bastion.bastion_meshtastic

import android.Manifest
import android.app.Activity
import android.content.*
import android.content.pm.PackageManager
import android.location.*
import android.os.*
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.io.*
import java.util.concurrent.Executors
import java.util.zip.ZipInputStream

/** Local, user-selected data only; no map tile downloads or background GPS. */
object FieldFiles {
    private lateinit var context: Context
    private val handler = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    private var importResult: MethodChannel.Result? = null
    private var locationResult: MethodChannel.Result? = null
    private var locationListener: LocationListener? = null
    private val root get() = File(context.filesDir, "offline_maps")
    fun bind(ctx: Context, channel: MethodChannel) {
        context = ctx
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "mapPack" -> result.success(readPack())
                "importMapPack" -> {
                    val host = FieldBridge.activity?.get()
                    if (host?.visible != true || importResult != null) result.error("busy", "Open the app to import one map pack at a time", null)
                    else {
                        importResult = result
                        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                            type = "application/zip"
                            addCategory(Intent.CATEGORY_OPENABLE)
                            putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("application/zip", "application/x-zip-compressed", "application/octet-stream"))
                        }
                        try { host.startActivityForResult(intent, 2402) }
                        catch (e: Exception) { importResult = null; result.error("picker", e.message, null) }
                    }
                }
                "clearMapPack" -> {
                    if (importResult != null) result.error("busy", "Import is in progress", null)
                    else worker.execute { root.deleteRecursively(); handler.post { result.success(null) } }
                }
                "locationFix" -> {
                    val host = FieldBridge.activity?.get()
                    if (host?.visible != true || locationResult != null) result.error("location", "Open the app to request a location fix", null)
                    else {
                        locationResult = result
                        if (context.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED && context.checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) != PackageManager.PERMISSION_GRANTED) {
                            host.requestPermissions(arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION), 2403)
                        } else requestFix()
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
    fun cancelFixOnBackground() { if (locationResult != null) finishFix(null, "Location capture cancelled when app left the foreground") }
    private fun readPack(): Map<String, Any>? {
        if (!File(root, "current").exists() && File(root, "old").exists()) File(root, "old").renameTo(File(root, "current"))
        val meta = File(root, "current/metadata.json")
        return try {
            val j = JSONObject(meta.readText())
            mapOf("path" to File(root, "current").absolutePath, "name" to j.getString("name"),
                "attribution" to j.getString("attribution"), "minZoom" to j.getInt("minZoom"),
                "maxZoom" to j.getInt("maxZoom"), "tiles" to j.getInt("tiles"),
                "latitude" to j.getDouble("latitude"), "longitude" to j.getDouble("longitude"))
        } catch (_: Exception) { null }
    }
    fun documentResult(code: Int, outcome: Int, data: Intent?) {
        if (code != 2402) return
        val result = importResult ?: return
        val uri = data?.data
        if (outcome != Activity.RESULT_OK || uri == null) { importResult = null; result.success(null); return }
        worker.execute {
            val staging = File(root, "staging")
            try {
                staging.deleteRecursively(); staging.mkdirs()
                var total = 0L
                var entries = 0
                var tiles = 0
                var metadata: JSONObject? = null
                val seen = HashSet<String>()
                val tilePattern = Regex("^(\\d{1,2})/(\\d{1,10})/(\\d{1,10})\\.png$")
                context.contentResolver.openInputStream(uri)!!.use { raw ->
                    // Bound compressed bytes as well as decompressed data.
                    val limited = object : FilterInputStream(raw) {
                        var count = 0L
                        override fun read(): Int { val n = super.read(); if (n >= 0 && ++count > 128L * 1024 * 1024) throw IOException("Map pack exceeds 128 MiB"); return n }
                        override fun read(b: ByteArray, off: Int, len: Int): Int {
                            val n = `in`.read(b, off, len); if (n > 0) count += n
                            if (count > 128L * 1024 * 1024) throw IOException("Map pack exceeds 128 MiB")
                            return n
                        }
                    }
                    ZipInputStream(limited).use { zip ->
                        while (true) {
                            val entry = zip.nextEntry ?: break
                            if (++entries > 12_000) throw IOException("Too many ZIP entries")
                            val name = entry.name
                            if (entry.isDirectory) {
                                if (!Regex("^\\d{1,2}(/\\d{1,10})?/$").matches(name)) throw IOException("Invalid directory in map pack")
                                if (zip.read() != -1) throw IOException("ZIP directory contains data")
                                continue
                            }
                            if (!seen.add(name)) throw IOException("Duplicate file in map pack")
                            val match = tilePattern.matchEntire(name)
                            if (name != "metadata.json" && match == null) throw IOException("Map packs need z/x/y.png tiles and metadata.json at the ZIP root")
                            if (match != null) {
                                val z = match.groupValues[1].toInt()
                                val x = match.groupValues[2].toLong()
                                val y = match.groupValues[3].toLong()
                                if (z !in 0..19 || x >= (1L shl z) || y >= (1L shl z)) throw IOException("Invalid tile coordinates")
                                if (++tiles > 10_000) throw IOException("Maximum 10,000 tiles")
                            }
                            val output = ByteArrayOutputStream()
                            val buffer = ByteArray(8192)
                            val limit = if (name == "metadata.json") 8192 else 1024 * 1024
                            while (true) {
                                val n = zip.read(buffer)
                                if (n < 0) break
                                total += n
                                if (output.size() + n > limit || total > 256L * 1024 * 1024) throw IOException("Expanded map pack is too large")
                                output.write(buffer, 0, n)
                            }
                            val bytes = output.toByteArray()
                            if (name == "metadata.json") metadata = JSONObject(String(bytes, Charsets.UTF_8))
                            else {
                                val signature = byteArrayOf(0x89.toByte(), 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a)
                                if (bytes.size < 24 || !bytes.take(8).toByteArray().contentEquals(signature)) throw IOException("Tiles must be PNG images")
                                val size = java.nio.ByteBuffer.wrap(bytes, 16, 8)
                                val width = size.int; val height = size.int
                                if (width !in listOf(256, 512) || height != width) throw IOException("Tiles must be 256 or 512 pixel squares")
                                val file = File(staging, name); file.parentFile!!.mkdirs(); file.writeBytes(bytes)
                            }
                        }
                    }
                }
                val j = metadata ?: throw IOException("metadata.json is required, including name, attribution, center and zoom range")
                val label = j.getString("name").trim(); val attribution = j.getString("attribution").trim()
                val lat = j.getDouble("latitude"); val lon = j.getDouble("longitude")
                val min = j.getInt("minZoom"); val max = j.getInt("maxZoom")
                if (tiles == 0 || label.isEmpty() || label.length > 80 || attribution.isEmpty() || attribution.length > 300 || !lat.isFinite() || !lon.isFinite() || lat !in -85.0..85.0 || lon !in -180.0..180.0 || min !in 0..19 || max !in min..19) throw IOException("Invalid map metadata")
                j.put("name", label); j.put("attribution", attribution); j.put("tiles", tiles)
                File(staging, "metadata.json").writeText(j.toString())
                val old = File(root, "old"); old.deleteRecursively()
                val current = File(root, "current")
                if (current.exists() && !current.renameTo(old)) throw IOException("Could not replace the existing map")
                if (!staging.renameTo(current)) { old.renameTo(current); throw IOException("Could not save the map pack") }
                old.deleteRecursively()
                val pack = readPack()
                handler.post { importResult = null; result.success(pack) }
            } catch (e: Exception) {
                staging.deleteRecursively()
                handler.post { importResult = null; result.error("mapPack", e.message ?: "Import failed", null) }
            }
        }
    }
    fun permissionsResult(code: Int, grants: IntArray) {
        if (code != 2403 || locationResult == null) return
        if (grants.any { it == PackageManager.PERMISSION_GRANTED }) requestFix() else finishFix(null, "Location permission was declined")
    }
    private fun requestFix() {
        if (FieldBridge.activity?.get()?.visible != true) { finishFix(null, "Open the app to capture a location"); return }
        val manager = context.getSystemService(Context.LOCATION_SERVICE) as LocationManager
        val provider = when {
            context.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED && manager.isProviderEnabled(LocationManager.GPS_PROVIDER) -> LocationManager.GPS_PROVIDER
            manager.isProviderEnabled(LocationManager.NETWORK_PROVIDER) -> LocationManager.NETWORK_PROVIDER
            else -> { finishFix(null, "Enable phone location services"); return }
        }
        val started = SystemClock.elapsedRealtimeNanos()
        val listener = object : LocationListener {
            override fun onLocationChanged(location: Location) {
                if (location.elapsedRealtimeNanos < started || !location.hasAccuracy() || location.accuracy > 100) return
                finishFix(mapOf("latitude" to location.latitude, "longitude" to location.longitude,
                    "accuracy" to location.accuracy.toDouble(), "time" to location.time), null)
            }
            @Deprecated("Legacy Android callback") override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}
            override fun onProviderEnabled(provider: String) {}
            override fun onProviderDisabled(provider: String) {}
        }
        locationListener = listener
        try {
            manager.requestLocationUpdates(provider, 1000L, 0f, listener, Looper.getMainLooper())
            handler.postDelayed({ if (locationListener === listener) finishFix(null, "No accurate fresh location arrived within 25 seconds") }, 25_000L)
        } catch (e: Exception) { finishFix(null, e.message ?: "Location request failed") }
    }
    private fun finishFix(value: Map<String, Any>?, error: String?) {
        locationListener?.let { (context.getSystemService(Context.LOCATION_SERVICE) as LocationManager).removeUpdates(it) }
        locationListener = null
        val result = locationResult; locationResult = null
        if (error != null) result?.error("location", error, null) else result?.success(value)
    }
}

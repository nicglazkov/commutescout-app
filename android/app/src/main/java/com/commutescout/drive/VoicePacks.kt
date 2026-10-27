package com.commutescout.drive

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.pm.ServiceInfo
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.Data
import androidx.work.ExistingWorkPolicy
import androidx.work.ForegroundInfo
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkInfo
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import androidx.work.workDataOf
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.isActive
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.security.MessageDigest
import java.util.concurrent.TimeUnit

/**
 * What the pack row shows. [done] and [total] are bytes.
 */
sealed class PackState {
    data object NotInstalled : PackState()
    /** Stopped with part of it on the phone; the next download resumes. */
    data class Paused(val done: Long, val total: Long) : PackState()
    /** Queued: waiting for Wi-Fi (or any network when [metered] is allowed). */
    data class Waiting(val metered: Boolean, val done: Long, val total: Long) : PackState()
    data class Downloading(val done: Long, val total: Long, val metered: Boolean) : PackState()
    data class Failed(val reason: String, val done: Long) : PackState()
    data class Installed(val bytes: Long) : PackState()
}

/**
 * Pure checks on a pack's files, so the download rules are tested
 * without a phone.
 */
object PackFiles {
    const val MARKER = "pack.ok"

    fun sha256(f: File): String {
        val md = MessageDigest.getInstance("SHA-256")
        f.inputStream().use { input ->
            val buf = ByteArray(1 shl 16)
            while (true) {
                val n = input.read(buf)
                if (n < 0) break
                md.update(buf, 0, n)
            }
        }
        return md.digest().joinToString("") { "%02x".format(it) }
    }

    /** A finished file is kept only when its size and sha256 match the catalog. */
    fun verify(f: File, expect: PackFile): Boolean = f.isFile && f.length() == expect.size && sha256(f).equals(expect.sha256, ignoreCase = true)

    /** Bytes already on disk for [pack]: finished files and partial ones. */
    fun bytesOnDisk(dir: File, pack: VoicePackInfo): Long = pack.files.sumOf { f ->
        val done = File(dir, f.name)
        val part = File(dir, f.name + ".part")
        when {
            done.isFile && done.length() == f.size -> f.size
            part.isFile -> minOf(part.length(), f.size)
            else -> 0L
        }
    }

    /** Space the download still needs, plus 10% (docs/voices.md). */
    fun spaceNeeded(dir: File, pack: VoicePackInfo): Long = ((pack.downloadSize - bytesOnDisk(dir, pack)).coerceAtLeast(0) * 1.1).toLong()

    /** Installed means the marker is there and every file has its catalog size. Hashes were checked before the marker was written. */
    fun installed(dir: File, pack: VoicePackInfo): Boolean =
        File(dir, MARKER).isFile && pack.files.all { File(dir, it.name).let { f -> f.isFile && f.length() == it.size } }

    /**
     * Files in the pack's folder that this catalog does not name, such as
     * a model an earlier release called something else. Parts of current
     * files stay.
     */
    fun stale(dir: File, pack: VoicePackInfo): List<String> {
        val keep = pack.files.flatMap { listOf(it.name, it.name + ".part") }.toSet() + MARKER
        return dir.list()?.filter { it !in keep }?.sorted() ?: emptyList()
    }

    /**
     * A pack that was installed and no longer matches the catalog: this
     * version of the app ships new model files, or a file was damaged.
     */
    fun needsUpdate(dir: File, pack: VoicePackInfo): Boolean = File(dir, MARKER).isFile && !installed(dir, pack)

    /** Where a partial file resumes: its length, or 0 when it is longer than it can be. */
    fun resumeFrom(part: File, expect: PackFile): Long {
        if (!part.isFile) return 0
        val n = part.length()
        if (n > expect.size) { part.delete(); return 0 }
        return n
    }
}

/**
 * The downloaded packs on this phone, under noBackupFilesDir/voices/<pack id>/:
 * 100 MB and more of model files have no place in a backup.
 */
class VoicePacks(context: Context) {
    private val app = context.applicationContext
    val catalog: VoiceCatalog = VoiceCatalog.load(app)
    private val root = File(app.noBackupFilesDir, "voices")
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private val work = WorkManager.getInstance(app)
    // The driver's last network choice per pack, so an update after an app
    // release follows it instead of waiting for Wi-Fi again.
    private val prefs = app.getSharedPreferences("cs.voices", Context.MODE_PRIVATE)

    init { updateChanged() }

    private val _installed = MutableStateFlow(scanInstalled())
    /** Pack ids that are fully downloaded and verified. */
    val installed: StateFlow<Set<String>> = _installed.asStateFlow()

    fun dir(packId: String) = File(root, packId)

    /**
     * At start: a pack installed by an earlier version whose files changed
     * fetches just those files again, on Wi-Fi unless the driver allowed
     * mobile data for that pack before. The chosen voice stays chosen; the
     * system voice speaks until the files are in.
     */
    private fun updateChanged() {
        for (pack in catalog.packs) {
            val d = dir(pack.id)
            if (!PackFiles.needsUpdate(d, pack)) continue
            val stale = PackFiles.stale(d, pack)
            stale.forEach { File(d, it).delete() }
            File(d, PackFiles.MARKER).delete()
            val metered = prefs.getBoolean(meteredKey(pack.id), false)
            Log.i(TAG, "${pack.id} changed (removed ${stale.joinToString()}); updating")
            enqueue(pack, metered, ExistingWorkPolicy.KEEP)
        }
    }

    private fun scanInstalled(): Set<String> = catalog.packs.filter { PackFiles.installed(dir(it.id), it) }.map { it.id }.toSet()

    /** Look at the disk again: a download finished or a pack was removed. */
    fun rescan() { _installed.value = scanInstalled() }

    fun bytes(packId: String): Long = dir(packId).listFiles()?.sumOf { it.length() } ?: 0L

    /** The row's state, from the download job and the disk. */
    fun state(pack: VoicePackInfo): StateFlow<PackState> =
        combine(work.getWorkInfosForUniqueWorkFlow(workName(pack.id)).map { it.firstOrNull() }, _installed) { info, installed ->
            if (pack.id in installed) return@combine PackState.Installed(bytes(pack.id))
            val onDisk = PackFiles.bytesOnDisk(dir(pack.id), pack)
            val metered = info?.tags?.contains(TAG_METERED) == true
            when (info?.state) {
                WorkInfo.State.RUNNING -> {
                    val done = info.progress.getLong(KEY_DONE, onDisk)
                    PackState.Downloading(done, pack.downloadSize, metered)
                }
                WorkInfo.State.ENQUEUED, WorkInfo.State.BLOCKED -> PackState.Waiting(metered, onDisk, pack.downloadSize)
                WorkInfo.State.FAILED -> PackState.Failed(info.outputData.getString(KEY_REASON) ?: "The download did not finish.", onDisk)
                WorkInfo.State.SUCCEEDED -> { rescan(); PackState.Installed(bytes(pack.id)) }
                else -> if (onDisk > 0) PackState.Paused(onDisk, pack.downloadSize) else PackState.NotInstalled
            }
        }.stateIn(scope, SharingStarted.WhileSubscribed(5000), PackState.NotInstalled)

    /**
     * Starts or resumes a pack. Wi-Fi only unless [metered]: then any
     * network, the driver having agreed to the size.
     */
    fun download(pack: VoicePackInfo, metered: Boolean) {
        prefs.edit().putBoolean(meteredKey(pack.id), metered).apply()
        enqueue(pack, metered, ExistingWorkPolicy.REPLACE)
    }

    private fun meteredKey(packId: String) = "metered.$packId"

    private fun enqueue(pack: VoicePackInfo, metered: Boolean, policy: ExistingWorkPolicy) {
        val req = OneTimeWorkRequestBuilder<VoicePackWorker>()
            .setConstraints(Constraints.Builder()
                .setRequiredNetworkType(if (metered) NetworkType.CONNECTED else NetworkType.UNMETERED)
                .build())
            .setInputData(workDataOf(KEY_PACK to pack.id))
            .addTag(if (metered) TAG_METERED else TAG_WIFI)
            .build()
        Log.i(TAG, "download ${pack.id}: ${if (metered) "any network" else "Wi-Fi only"}")
        work.enqueueUniqueWork(workName(pack.id), policy, req)
    }

    /** Stops the download and keeps the partial files, so the next one resumes. */
    fun cancel(packId: String) {
        Log.i(TAG, "download $packId cancelled")
        work.cancelUniqueWork(workName(packId))
    }

    /** Removes the pack and anything partial. A voice in it gives way to the system voice. */
    fun delete(packId: String) {
        work.cancelUniqueWork(workName(packId))
        Neural.forgetPack(packId)
        dir(packId).deleteRecursively()
        work.pruneWork()
        Log.i(TAG, "pack $packId deleted")
        rescan()
    }

    companion object {
        const val TAG = "VoicePacks"
        const val KEY_PACK = "pack"
        const val KEY_DONE = "done"
        const val KEY_REASON = "reason"
        const val TAG_METERED = "voice-metered"
        const val TAG_WIFI = "voice-wifi"
        fun workName(packId: String) = "voice-pack-$packId"
    }
}

/**
 * Downloads one pack, file by file, from the per-file release assets.
 * Each file goes to `<name>.part`, resumes with a Range request, and is
 * renamed only after its size and sha256 match the catalog. `pack.ok`
 * is written last. WorkManager runs it in the background and retries
 * when the network drops.
 */
class VoicePackWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    private val http = OkHttpClient.Builder()
        .connectTimeout(20, TimeUnit.SECONDS)
        .readTimeout(60, TimeUnit.SECONDS)
        .build()

    override suspend fun doWork(): Result = withContext(Dispatchers.IO) {
        val packId = inputData.getString(VoicePacks.KEY_PACK) ?: return@withContext Result.failure()
        val packs = Neural.packs(applicationContext)
        val pack = packs.catalog.pack(packId) ?: return@withContext fail("This voice pack is no longer offered.", 0)
        val dir = packs.dir(packId).apply { mkdirs() }
        val need = PackFiles.spaceNeeded(dir, pack)
        if (dir.usableSpace < need) {
            Log.w(VoicePacks.TAG, "$packId: needs ${need / 1_000_000} MB, ${dir.usableSpace / 1_000_000} MB free")
            return@withContext fail("Not enough space. Free up ${Units.bytes(need - dir.usableSpace)} and try again.", PackFiles.bytesOnDisk(dir, pack))
        }
        runCatching { setForeground(foreground(pack, PackFiles.bytesOnDisk(dir, pack))) }
            .onFailure { Log.w(VoicePacks.TAG, "no foreground notice for the download: $it") }
        val started = System.currentTimeMillis()
        try {
            for (f in pack.files) {
                if (!isActive) return@withContext Result.retry()
                val out = File(dir, f.name)
                if (out.isFile && out.length() == f.size) continue
                var ok = false
                for (attempt in 1..2) {
                    fetch(f, File(dir, f.name + ".part"), pack, dir)
                    val part = File(dir, f.name + ".part")
                    if (PackFiles.verify(part, f)) {
                        out.delete()
                        if (!part.renameTo(out)) throw IOException("could not rename ${part.name}")
                        ok = true
                        break
                    }
                    Log.w(VoicePacks.TAG, "$packId/${f.name}: size or sha256 mismatch, starting the file again")
                    part.delete()
                }
                if (!ok) return@withContext fail("A file did not pass its check. Try again later.", PackFiles.bytesOnDisk(dir, pack))
            }
            File(dir, PackFiles.MARKER).writeText("${pack.id} ${System.currentTimeMillis()}\n")
            PackFiles.stale(dir, pack).forEach { File(dir, it).delete() }
            Log.i(VoicePacks.TAG, "$packId installed in ${(System.currentTimeMillis() - started) / 1000} s")
            packs.rescan()
            Result.success()
        } catch (e: IOException) {
            Log.w(VoicePacks.TAG, "$packId: $e; retrying later")
            if (runAttemptCount >= 8) fail("The download keeps failing. Check your connection and try again.", PackFiles.bytesOnDisk(dir, pack))
            else Result.retry()
        }
    }

    private fun fail(reason: String, done: Long): Result =
        Result.failure(workDataOf(VoicePacks.KEY_REASON to reason, VoicePacks.KEY_DONE to done))

    private var lastReport = 0L

    private suspend fun fetch(f: PackFile, part: File, pack: VoicePackInfo, dir: File) {
        val from = PackFiles.resumeFrom(part, f)
        if (from == f.size) return
        val req = Request.Builder().url(f.url).apply { if (from > 0) header("Range", "bytes=$from-") }.build()
        http.newCall(req).execute().use { r ->
            val append = r.code == 206
            if (!r.isSuccessful) throw IOException("HTTP ${r.code} for ${f.name}")
            // A server that ignores the range sends the whole file: start over.
            FileOutputStream(part, append).use { out ->
                val input = r.body.byteStream()
                val buf = ByteArray(1 shl 16)
                var wrote = 0L
                while (true) {
                    if (isStopped) throw IOException("stopped")
                    val n = input.read(buf)
                    if (n < 0) break
                    out.write(buf, 0, n)
                    wrote += n
                    val now = System.currentTimeMillis()
                    if (now - lastReport > 500) {
                        lastReport = now
                        val done = PackFiles.bytesOnDisk(dir, pack)
                        setProgress(Data.Builder().putLong(VoicePacks.KEY_DONE, done).build())
                        runCatching { setForeground(foreground(pack, done)) }
                    }
                }
            }
        }
    }

    override suspend fun getForegroundInfo(): ForegroundInfo {
        val packId = inputData.getString(VoicePacks.KEY_PACK) ?: ""
        val pack = Neural.packs(applicationContext).catalog.pack(packId)
        return foreground(pack, 0)
    }

    private fun foreground(pack: VoicePackInfo?, done: Long): ForegroundInfo {
        val nm = applicationContext.getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && nm.getNotificationChannel(CHANNEL) == null) {
            nm.createNotificationChannel(NotificationChannel(CHANNEL, "Voice downloads", NotificationManager.IMPORTANCE_LOW))
        }
        val total = pack?.downloadSize ?: 0L
        val n = NotificationCompat.Builder(applicationContext, CHANNEL)
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setContentTitle("Downloading ${pack?.title?.lowercase() ?: "voices"}")
            .setContentText(if (total > 0) "${Units.bytes(done)} of ${Units.bytes(total)}" else "")
            .setProgress(100, if (total > 0) (done * 100 / total).toInt() else 0, total == 0L)
            .setOngoing(true)
            .setSilent(true)
            .build()
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) ForegroundInfo(NOTIFICATION_ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        else ForegroundInfo(NOTIFICATION_ID, n)
    }

    companion object {
        private const val CHANNEL = "voice-downloads"
        private const val NOTIFICATION_ID = 7301
    }
}

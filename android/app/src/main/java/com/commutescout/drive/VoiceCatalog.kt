package com.commutescout.drive

import android.content.Context
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/**
 * The neural voice packs the app can download, read from
 * `shared/voices.json`. The build copies that file into the app's
 * assets, so the list never needs the network. See docs/voices.md.
 */
@Serializable
data class VoiceCatalog(
    val schema: Int,
    val release: String,
    @SerialName("default_pack") val defaultPack: String,
    val packs: List<VoicePackInfo>,
) {
    /** The packs the app may show and use. */
    val listed: List<VoicePackInfo> get() = packs.filter { VoiceCatalogRules.isListed(it.id) }

    fun pack(id: String): VoicePackInfo? = packs.firstOrNull { it.id == id }

    /** A listed voice by its catalog id, such as "kokoro-en-v1_0.af_heart". */
    fun voice(id: String): NeuralVoice? {
        for (p in listed) p.voices.firstOrNull { it.id == id }?.let { return NeuralVoice(p, it) }
        return null
    }

    companion object {
        private val json = Json { ignoreUnknownKeys = true }

        fun parse(text: String): VoiceCatalog = json.decodeFromString(serializer(), text)

        @Volatile private var loaded: VoiceCatalog? = null

        /** The bundled catalog; an empty one if the asset is unreadable, so the app still runs on system voices. */
        fun load(context: Context): VoiceCatalog = loaded ?: synchronized(this) {
            loaded ?: runCatching {
                parse(context.assets.open("voices.json").bufferedReader().use { it.readText() })
            }.getOrElse {
                android.util.Log.e("Neural", "voice catalog unreadable: $it")
                VoiceCatalog(1, "", "", emptyList())
            }.also { loaded = it }
        }
    }
}

object VoiceCatalogRules {
    /**
     * Supertonic 2 is under BigScience OpenRAIL-M. Its use restrictions
     * (Attachment A) must be part of the app's terms before the pack
     * ships. Until then this stays false: the pack is not listed, not
     * offered for download and never picked by Automatic.
     */
    const val SUPERTONIC_CLEARED = false

    /** Packs held back until a condition is met, by id. */
    fun isListed(packId: String): Boolean = when (packId) {
        "supertonic2-en" -> SUPERTONIC_CLEARED
        else -> true
    }
}

@Serializable
data class VoicePackInfo(
    val id: String,
    val title: String,
    val engine: String,
    @SerialName("engine_version") val engineVersion: String = "",
    val language: String = "en",
    @SerialName("sample_rate") val sampleRate: Int,
    @SerialName("text_input") val textInput: String = "raw",
    val generation: Generation = Generation(),
    val lexicons: Map<String, List<String>> = emptyMap(),
    val license: License,
    val attribution: String,
    val voices: List<VoiceEntry>,
    val files: List<PackFile>,
    @SerialName("download_size") val downloadSize: Long,
) {
    val isKokoro: Boolean get() = engine == "kokoro"
    val isSupertonic: Boolean get() = engine == "supertonic"
    val defaultVoice: VoiceEntry? get() = voices.firstOrNull { it.default } ?: voices.firstOrNull()
    fun file(role: String): PackFile? = files.firstOrNull { it.role == role }

    @Serializable
    data class Generation(
        @SerialName("num_steps") val numSteps: Int = 0,
        val extra: Map<String, String> = emptyMap(),
        val speed: Float = 1f,
    )

    @Serializable
    data class License(
        val spdx: String,
        val name: String,
        @SerialName("commercial_use") val commercialUse: Boolean = false,
        val url: String = "",
        val obligations: List<String> = emptyList(),
    )
}

@Serializable
data class VoiceEntry(
    val id: String,
    val sid: Int,
    val upstream: String = "",
    val name: String,
    val accent: String,
    val gender: String,
    val default: Boolean = false,
    val preview: Preview? = null,
) {
    @Serializable
    data class Preview(val url: String, val size: Long = 0, val sha256: String = "", val format: String = "")
}

@Serializable
data class PackFile(val name: String, val role: String, val url: String, val sha256: String, val size: Long)

/** One voice and the pack it lives in. */
data class NeuralVoice(val pack: VoicePackInfo, val voice: VoiceEntry) {
    val id: String get() = voice.id
    val name: String get() = voice.name

    /** The engine this voice runs on: one per pack, and for Kokoro one per accent (each has its own lexicons). */
    val engineKey: String get() = if (pack.isKokoro) "${pack.id}/${voice.accent}" else pack.id

    /** "US English · Female" */
    val description: String get() = NeuralLabels.accent(voice.accent) + " · " + voice.gender.replaceFirstChar { it.uppercase() }
}

object NeuralLabels {
    /** Shown beside every neural voice: OpenRAIL-M asks for the disclosure, and it is true of them all. */
    const val GENERATED = "Computer-generated voice"

    fun accent(tag: String): String = when (tag) {
        "en-US" -> "US English"
        "en-GB" -> "UK English"
        else -> tag
    }
}

/**
 * Which neural voice speaks, if any. Pure, so it is tested without a
 * phone. [saved] is the stored voice name: a catalog id for a neural
 * voice, a system voice name, or empty for Automatic.
 */
object NeuralPick {
    /**
     * The neural voice for [saved], or null when a system voice speaks.
     * A saved neural voice speaks while its pack is installed. Automatic
     * uses the default voice of an installed pack, the catalog's default
     * pack first. A saved system voice keeps the system voice.
     */
    fun choose(saved: String, catalog: VoiceCatalog, installed: Set<String>): NeuralVoice? {
        if (saved.isNotEmpty()) {
            val v = catalog.voice(saved) ?: return null
            return v.takeIf { it.pack.id in installed }
        }
        return automatic(catalog, installed)
    }

    /** What Automatic uses when a neural pack is on the phone; null leaves the system pick. */
    fun automatic(catalog: VoiceCatalog, installed: Set<String>): NeuralVoice? {
        val packs = catalog.listed.filter { it.id in installed }
            .sortedBy { if (it.id == catalog.defaultPack) 0 else 1 }
        val p = packs.firstOrNull() ?: return null
        val v = p.defaultVoice ?: return null
        return NeuralVoice(p, v)
    }

    /** True when [saved] names a neural voice, whether or not its pack is installed. */
    fun isNeural(saved: String, catalog: VoiceCatalog): Boolean = saved.isNotEmpty() && catalog.packs.any { p -> p.voices.any { it.id == saved } }
}

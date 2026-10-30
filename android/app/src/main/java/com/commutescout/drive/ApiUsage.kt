package com.commutescout.drive

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.intOrNull
import java.text.NumberFormat
import java.util.Locale

/**
 * Today's API use for the signed-in account, from /api/keys: requests
 * against the account's daily limit (2,000 on a free key, 10,000 on a
 * pro key) and the limit for calls with no key, per address. [requests]
 * is null when the server did not say: never read that as nothing used.
 */
data class ApiUsage(val requests: Int?, val limit: Int, val tier: String, val keylessDaily: Int?, val activeKeys: Int) {
    /** How full the meter is, 0 to 1. */
    val fraction: Float get() = if (limit <= 0 || requests == null) 0f else (requests.toFloat() / limit).coerceIn(0f, 1f)
    val full: Boolean get() = requests != null && limit in 1..requests
    val usedText: String get() = requests?.let { n(it) } ?: UNAVAILABLE
    val limitText: String get() = if (requests == null) "" else "of ${n(limit)}"
    /** Under the account's limit: "a day with your free key". */
    val tierText: String get() = if (activeKeys == 0) "a day with a free key" else "a day with your $tier key"
    val keysText: String get() = when (activeKeys) { 0 -> "None"; 1 -> "1 key"; else -> "$activeKeys keys" }

    companion object {
        const val FREE_DAILY = 2_000
        const val UNAVAILABLE = "Unavailable"
        fun n(v: Int): String = NumberFormat.getIntegerInstance(Locale.US).format(v)

        /** The response body, or null when it is not one. Older servers leave out usage: then the tier's limit and no count. */
        fun parse(body: String): ApiUsage? {
            val root = runCatching { Backend.json.parseToJsonElement(body) }.getOrNull() as? JsonObject ?: return null
            val keys = (root["keys"] as? JsonArray)?.mapNotNull { it as? JsonObject } ?: return null
            val active = keys.filter { (it["revoked"] as? JsonPrimitive)?.booleanOrNull != true }
            val usage = root["usage"] as? JsonObject
            val tiers = root["tiers"] as? JsonObject
            fun JsonObject.str(k: String) = (this[k] as? JsonPrimitive)?.takeIf { it.isString }?.content
            fun JsonObject.int(k: String) = (this[k] as? JsonPrimitive)?.intOrNull
            val tier = usage?.str("tier") ?: if (active.any { it.str("tier") == "pro" }) "pro" else "free"
            val limit = usage?.int("limit") ?: tiers?.int(tier) ?: active.mapNotNull { it.int("daily_limit") }.maxOrNull() ?: FREE_DAILY
            return ApiUsage(usage?.int("requests"), limit, tier, root.int("keyless_daily"), active.size)
        }
    }
}

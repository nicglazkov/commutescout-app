package com.commutescout.drive

import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.asin
import kotlin.math.ceil
import kotlin.math.cos
import kotlin.math.ln
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * The math behind watch areas and area downloads, kept free of Android
 * so it is unit tested. Areas and lengths follow the backend's own
 * formulas (planar shoelace on a locally scaled grid, haversine), so
 * what the app says an area covers is what the server will check.
 */
object WatchGeo {
    const val MI_M = 1609.344
    const val MIN_RADIUS_MI = 1
    const val MAX_RADIUS_MI = 25
    /** The free limits the backend enforces (watch.py FREE_MAX_*). */
    const val FREE_RADIUS_KM = 40.2
    const val FREE_POLYGON_SQ_KM = 5180.0
    const val FREE_ROUTE_KM = 402.0
    /** 2 mi is 3.22 km, just over the free 3.2 km buffer: send the limit itself. */
    const val ROUTE_BUFFER_KM = 3.2
    const val MAX_POLY_POINTS = 20
    const val SQ_KM_PER_SQ_MI = 2.589988

    fun clampRadius(mi: Int): Int = mi.coerceIn(MIN_RADIUS_MI, MAX_RADIUS_MI)

    /** "8 mi", and at the top "25 mi, the most". */
    fun radiusLabel(mi: Int): String = if (clampRadius(mi) >= MAX_RADIUS_MI) "$MAX_RADIUS_MI mi, the most" else "${clampRadius(mi)} mi"

    /** A radius in whole miles as the km the backend takes, never past the free limit. */
    fun radiusKm(mi: Int): Double = min(clampRadius(mi) * MI_M / 1000.0, FREE_RADIUS_KM)

    /** A stored radius back to whole miles. */
    fun radiusMi(km: Double?): Int = clampRadius(((km ?: 8 * MI_M / 1000) * 1000 / MI_M).roundToInt())

    /** The circle's area, rounded to tens of sq mi as the mockup says it ("about 200 sq mi"). */
    fun circleSqMi(mi: Int): Int = (PI * mi * mi / 10).roundToInt() * 10

    /**
     * The drag: up to 12 mi the handle moves 10 dp a mile on a fixed
     * map; past it the handle stops and the map zooms out instead, a
     * mile per 4 dp of further pull. [scale] is the screen's width over
     * the mockup's 390.
     */
    fun radiusFromDrag(distanceDp: Float, scale: Float = 1f): Int {
        val d = distanceDp / scale
        val r = if (d <= 120f) d / 10f else 12f + (d - 120f) / 4f
        return clampRadius(r.roundToInt())
    }

    /** Where the handle sits from the centre, in dp. */
    fun handleDp(mi: Int, scale: Float = 1f): Float = min(clampRadius(mi) * 10f, 120f) * scale

    /** Meters per dp the map needs so [mi] draws as [handleDp]. */
    fun metersPerDp(mi: Int, scale: Float = 1f): Double = clampRadius(mi) * MI_M / handleDp(mi, scale)

    /** The zoom that turns [current] meters per dp at [zoom] into [wanted]. */
    fun zoomFor(zoom: Double, current: Double, wanted: Double): Double = zoom + ln(current / wanted) / ln(2.0)

    /** MapLibre's zoom for [mpd] meters per dp at [lat] (512 dp tiles, Web Mercator). */
    fun zoomForMpd(mpd: Double, lat: Double): Double = ln(EARTH_M * cos(Math.toRadians(lat)) / (512 * mpd)) / ln(2.0)

    /** And back: meters per dp at [zoom] and [lat]. */
    fun mpdAt(zoom: Double, lat: Double): Double = EARTH_M * cos(Math.toRadians(lat)) / (512 * Math.pow(2.0, zoom))

    const val EARTH_M = 40_075_016.686
    /** A new shape starts this small (a downtown), drawn at [SHAPE_DP_PER_MI]. */
    const val SHAPE_START_MI = 0.4
    const val SHAPE_DP_PER_MI = 25.0

    fun haversineKm(a: LatLon, b: LatLon): Double {
        val r = 6371.0
        val p1 = Math.toRadians(a.lat); val p2 = Math.toRadians(b.lat)
        val dp = Math.toRadians(b.lat - a.lat); val dl = Math.toRadians(b.lon - a.lon)
        val h = sin(dp / 2) * sin(dp / 2) + cos(p1) * cos(p2) * sin(dl / 2) * sin(dl / 2)
        return 2 * r * asin(sqrt(h))
    }

    fun lengthKm(path: List<LatLon>): Double = path.zipWithNext { a, b -> haversineKm(a, b) }.sum()

    /** The backend's polygon_area_sq_km, point for point. */
    fun polygonSqKm(points: List<LatLon>): Double {
        if (points.size < 3) return 0.0
        val lat0 = points.sumOf { it.lat } / points.size
        val kx = 111.32 * cos(Math.toRadians(lat0)); val ky = 110.57
        var s = 0.0
        for (i in points.indices) {
            val a = points[i]; val b = points[(i + 1) % points.size]
            s += (a.lon * kx) * (b.lat * ky) - (b.lon * kx) * (a.lat * ky)
        }
        return abs(s) / 2.0
    }

    fun polygonSqMi(points: List<LatLon>): Int = (polygonSqKm(points) / SQ_KM_PER_SQ_MI).roundToInt()

    /** A point [northM] and [eastM] meters from [from]. */
    fun offset(from: LatLon, northM: Double, eastM: Double): LatLon =
        LatLon(from.lat + northM / 110_540.0, from.lon + eastM / (111_320.0 * cos(Math.toRadians(from.lat))))

    /** A circle as a closed ring, for drawing it on the map. */
    fun circleRing(center: LatLon, radiusM: Double, n: Int = 72): List<LatLon> =
        (0..n).map { i -> val a = 2 * PI * i / n; offset(center, radiusM * cos(a), radiusM * sin(a)) }

    /**
     * The shape a new polygon starts as: the mockup's five corners
     * (dp from the centre at 10 dp a mile, y down), times [scaleMi].
     */
    fun startPolygon(center: LatLon, scaleMi: Double = SHAPE_START_MI): List<LatLon> =
        listOf(-85.0 to -102.0, 67.0 to -124.0, 123.0 to -16.0, 63.0 to 84.0, -87.0 to 62.0)
            .map { (x, y) -> offset(center, -y / 10 * MI_M * scaleMi, x / 10 * MI_M * scaleMi) }

    /** The route as at most [max] points, keeping both ends. */
    fun thin(path: List<LatLon>, max: Int = 400): List<LatLon> {
        if (path.size <= max) return path
        val step = ceil(path.size / max.toDouble()).toInt()
        val out = path.filterIndexed { i, _ -> i % step == 0 }.toMutableList()
        if (out.last() != path.last()) out += path.last()
        return out
    }

    /** "A 24 mi drive" from a route's length. */
    fun miles(km: Double): Int = max(1, (km * 1000 / MI_M).roundToInt())

    fun grouped(n: Int): String = "%,d".format(n)
}

/** What a picked download area costs: its size on the phone and the path the map server cuts along. */
object AreaMath {
    /** The server cuts squares this far either side of the path (mapfiles.MAX_BUFFER_M). */
    const val BUFFER_M = 6000.0
    /** And refuses paths longer than this (MAX_ROUTE_M), with some room. */
    const val MAX_PATH_KM = 780.0
    /** Without a state to learn from: a suburban square kilometer of full detail. */
    const val FALLBACK_BYTES_PER_SQ_KM = 250_000.0

    fun widthKm(south: Double, west: Double, north: Double, east: Double): Double =
        WatchGeo.haversineKm(LatLon((south + north) / 2, west), LatLon((south + north) / 2, east))
    fun heightKm(south: Double, north: Double): Double = (north - south) * 110.54

    /**
     * A back and forth path whose squares cover the box: rows
     * 2 buffers apart, from one side to the other. The server takes
     * corridors only, so an area is a corridor that folds.
     */
    fun serpentine(south: Double, west: Double, north: Double, east: Double): List<LatLon> {
        val rowStep = 2 * BUFFER_M / 110_540.0
        val rows = max(1, ceil((north - south) / rowStep).toInt())
        val inset = min(BUFFER_M / 110_540.0, (north - south) / 2)
        val out = ArrayList<LatLon>()
        for (i in 0 until rows) {
            val lat = min(south + inset + i * rowStep, north - inset).coerceAtLeast(south + inset)
            if (i % 2 == 0) { out += LatLon(lat, west); out += LatLon(lat, east) } else { out += LatLon(lat, east); out += LatLon(lat, west) }
        }
        // Points every few km, so the server's samples land on the line.
        val dense = ArrayList<LatLon>()
        out.zipWithNext { a, b ->
            val n = max(1, ceil(WatchGeo.haversineKm(a, b) / 4.0).toInt())
            for (k in 0 until n) dense += LatLon(a.lat + (b.lat - a.lat) * k / n, a.lon + (b.lon - a.lon) * k / n)
        }
        dense += out.last()
        return dense
    }

    fun fits(south: Double, west: Double, north: Double, east: Double): Boolean =
        WatchGeo.lengthKm(serpentine(south, west, north, east)) <= MAX_PATH_KM

    /** Bytes per square km, learned from a whole state's file and its box; null when unknown. */
    fun density(stateBytes: Long?, bounds: DoubleArray?): Double? {
        if (stateBytes == null || stateBytes <= 0 || bounds == null) return null
        val km2 = widthKm(bounds[0], bounds[1], bounds[2], bounds[3]) * heightKm(bounds[0], bounds[2])
        return if (km2 <= 0) null else stateBytes / km2
    }

    fun estimateBytes(widthKm: Double, heightKm: Double, bytesPerSqKm: Double?): Long =
        (widthKm * heightKm * (bytesPerSqKm ?: FALLBACK_BYTES_PER_SQ_KM)).toLong()

    /** "About 312 MB", rounded so it never claims more precision than it has. */
    fun aboutText(bytes: Long): String = when {
        bytes >= 1_000_000_000L -> "About %.1f GB".format(bytes / 1e9)
        bytes >= 10_000_000L -> "About ${((bytes / 1e6) / 5).roundToInt() * 5} MB"
        else -> "About ${max(1, (bytes / 1e6).roundToInt())} MB"
    }

    /** "22 by 16 mi". */
    fun spanText(widthKm: Double, heightKm: Double): String =
        "${WatchGeo.miles(widthKm)} by ${WatchGeo.miles(heightKm)} mi"
}

/** How the storage bar splits what is saved: states, areas and trips, as fractions of everything saved. */
data class StorageSplit(val states: Float, val areas: Float, val trips: Float) {
    companion object {
        fun of(states: Long, areas: Long, trips: Long): StorageSplit {
            val total = (states + areas + trips).toFloat()
            if (total <= 0f) return StorageSplit(0f, 0f, 0f)
            // A sliver too thin to see still shows.
            fun f(v: Long) = if (v <= 0) 0f else max(v / total, 0.03f)
            val raw = listOf(f(states), f(areas), f(trips)); val sum = raw.sum()
            return StorageSplit(raw[0] / sum, raw[1] / sum, raw[2] / sum)
        }
    }
}

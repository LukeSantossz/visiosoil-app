package com.visiosoil.app

/**
 * The arithmetic behind MainActivity's camera channels (SPEC 0238), kept free
 * of Android types so JVM tests reach it without a device (SPEC 0263). Each
 * function answers null for an input that is not a measurement, which Dart
 * reads as "not known".
 */
internal object CameraReadings {
    /** The first focal length the lens lists, in millimetres. */
    fun focalLengthMm(focals: FloatArray?): Double? {
        val focal = focals?.firstOrNull() ?: return null
        return if (focal.isFinite() && focal > 0f) focal.toDouble() else null
    }

    /**
     * The long side of the active array, in millimetres: the physical long
     * side's share that the active pixels span. The active array is the part
     * of the sensor the frames come from.
     */
    fun activeLongSideMm(physicalLongMm: Float, activeLongPx: Int, pixelLongPx: Int): Double? {
        if (!physicalLongMm.isFinite() || physicalLongMm <= 0f) return null
        if (activeLongPx <= 0 || pixelLongPx <= 0) return null
        return physicalLongMm.toDouble() * activeLongPx / pixelLongPx
    }

    /** The illuminance, in lux, a light sensor event reports. */
    fun luxOf(values: FloatArray): Double? {
        val lux = values.firstOrNull() ?: return null
        return if (lux.isFinite() && lux >= 0f) lux.toDouble() else null
    }
}

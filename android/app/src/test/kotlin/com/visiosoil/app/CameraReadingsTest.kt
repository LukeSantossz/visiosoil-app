package com.visiosoil.app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** The arithmetic behind MainActivity's camera channels (SPEC 0238, SPEC 0263). */
class CameraReadingsTest {
    @Test
    fun active_long_side_is_the_physical_side_share_of_the_active_array() {
        val side = CameraReadings.activeLongSideMm(7.3f, 4000, 4032)!!
        assertEquals(7.3 * 4000 / 4032, side, 1e-6)
    }

    @Test
    fun active_long_side_is_unknown_for_a_size_that_is_not_a_measurement() {
        for (physical in floatArrayOf(0f, -1f, Float.NaN, Float.POSITIVE_INFINITY)) {
            assertNull("physical $physical", CameraReadings.activeLongSideMm(physical, 4000, 4032))
        }
        assertNull(CameraReadings.activeLongSideMm(7.3f, 0, 4032))
        assertNull(CameraReadings.activeLongSideMm(7.3f, 4000, 0))
        assertNull(CameraReadings.activeLongSideMm(7.3f, 4000, -1))
    }

    @Test
    fun focal_length_is_the_first_one_the_lens_lists() {
        assertEquals(5.6, CameraReadings.focalLengthMm(floatArrayOf(5.6f, 7.0f))!!, 1e-6)
    }

    @Test
    fun focal_length_is_unknown_for_a_list_that_holds_no_measurement() {
        assertNull(CameraReadings.focalLengthMm(null))
        assertNull(CameraReadings.focalLengthMm(floatArrayOf()))
        assertNull(CameraReadings.focalLengthMm(floatArrayOf(0f)))
        assertNull(CameraReadings.focalLengthMm(floatArrayOf(Float.NaN)))
        assertNull(CameraReadings.focalLengthMm(floatArrayOf(Float.POSITIVE_INFINITY)))
    }

    @Test
    fun lux_is_the_first_value_of_a_light_event() {
        assertEquals(1480.0, CameraReadings.luxOf(floatArrayOf(1480f))!!, 1e-6)
        assertEquals(0.0, CameraReadings.luxOf(floatArrayOf(0f))!!, 1e-6)
    }

    @Test
    fun lux_is_unknown_for_a_value_that_is_not_an_illuminance() {
        assertNull(CameraReadings.luxOf(floatArrayOf()))
        assertNull(CameraReadings.luxOf(floatArrayOf(Float.NaN)))
        assertNull(CameraReadings.luxOf(floatArrayOf(Float.POSITIVE_INFINITY)))
        assertNull(CameraReadings.luxOf(floatArrayOf(-1f)))
    }
}

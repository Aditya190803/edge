package wtf.openstrap.openstrap_edge

import java.time.Duration
import java.time.ZoneId
import java.time.ZonedDateTime
import org.junit.Assert.assertEquals
import org.junit.Test

class BridgeHealthWriterTest {
    private val zone = ZoneId.of("Europe/Berlin")
    private fun local(y: Int, m: Int, d: Int, h: Int) = ZonedDateTime.of(y,m,d,h,0,0,0,zone).toInstant()
    @Test fun legacyCleanupUsesLocalNoonAcrossDst() {
        val range = bridgeCleanupRange(local(2026,10,25,9),local(2026,10,25,1),zone)
        assertEquals(local(2026,10,24,12), range.start)
        assertEquals(local(2026,10,25,12), range.end)
        assertEquals(25L, Duration.between(range.start,range.end).toHours())
    }
    @Test fun cleanupRetainsEarlierSessionBoundary() {
        val start = local(2026,8,4,10)
        assertEquals(start, bridgeCleanupRange(local(2026,8,5,8), start,zone).start)
    }
    @Test fun legacyMinuteMergesEverySample() {
        assertEquals(80L, bridgeAverageBpm(listOf(60L,100L)))
    }
    @Test(expected = IllegalArgumentException::class) fun emptyMinuteIsNeverFabricated() {
        bridgeAverageBpm(emptyList())
    }
}

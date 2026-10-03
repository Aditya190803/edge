package wtf.openstrap.openstrap_edge

import android.content.Context
import android.util.Log
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.records.*
import androidx.health.connect.client.records.metadata.Metadata
import androidx.health.connect.client.request.ReadRecordsRequest
import androidx.health.connect.client.time.TimeRangeFilter
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.time.Instant
import java.time.ZoneId
import kotlinx.coroutines.*
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

internal data class BridgeCleanupRange(val start: Instant, val end: Instant)
internal fun bridgeCleanupRange(anchor: Instant, sessionStart: Instant?, zone: ZoneId): BridgeCleanupRange {
    val localEnd = anchor.atZone(zone)
    val wakeDate = if (localEnd.hour < 12) localEnd.toLocalDate() else localEnd.toLocalDate().plusDays(1)
    val calculatedStart = wakeDate.minusDays(1).atTime(12, 0).atZone(zone).toInstant()
    val start = if (sessionStart != null && sessionStart.isBefore(calculatedStart)) sessionStart else calculatedStart
    return BridgeCleanupRange(start, wakeDate.atTime(12, 0).atZone(zone).toInstant())
}
internal fun bridgeAverageBpm(samples: List<Long>): Long {
    require(samples.isNotEmpty() && samples.all { it in 1..300 })
    return samples.average().toLong()
}

/** Stable IDs and durable SQLite versions make retries safe after process death. */
object BridgeHeartRateWriter {
    private data class LegacyConfig(val cutoff: Long = 0, val allowRead: Boolean = false)
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val mutex = Mutex()
    fun register(engine: FlutterEngine, context: Context) {
        val app = context.applicationContext
        var legacy = LegacyConfig()
        MethodChannel(engine.dartExecutor.binaryMessenger, "openstrap/bridge_health")
            .setMethodCallHandler { call, result ->
                if (call.method == "configureLegacy") {
                    legacy = LegacyConfig((call.argument<Any>("cutoff") as? Number)?.toLong() ?: 0,
                        call.argument<Boolean>("allowRead") == true)
                    result.success(true)
                } else if (call.method !in listOf("upsertMinutes", "upsertNight")) {
                    result.notImplemented()
                } else {
                  val config = legacy
                  scope.launch {
                    val success = withContext(Dispatchers.IO) {
                        mutex.withLock {
                            try {
                                val client = HealthConnectClient.getOrCreate(app)
                                when (call.method) {
                                    "upsertMinutes" -> minutes(client, call, app, config)
                                    else -> night(client, call, app, config)
                                }
                                true
                            } catch (cancelled: CancellationException) { throw cancelled }
                            catch (error: Exception) {
                                Log.e("OpenStrapBridge", "Export failed", error)
                                false
                            }
                        }
                    }
                    result.success(success)
                  }
                }
            }
    }
    private fun metadata(id: String, version: Long) = Metadata(
        clientRecordId = id, clientRecordVersion = version,
        recordingMethod = Metadata.RECORDING_METHOD_AUTOMATICALLY_RECORDED,
    )
    private suspend fun minutes(client: HealthConnectClient, call: MethodCall, context: Context, config: LegacyConfig) {
        val rows = requireNotNull(call.argument<List<Map<String, Any?>>>("minutes"))
        val records = ArrayList<HeartRateRecord>()
        val deleted = ArrayList<String>()
        val prefs = context.getSharedPreferences("bridge_health_migration", Context.MODE_PRIVATE)
        for (row in rows) {
            val minute = (row["minute"] as Number).toLong()
            val version = (row["generation"] as Number).toLong()
            val start = Instant.ofEpochSecond(minute)
            val end = start.plusSeconds(60)
            val id = "whoop4:hr:$minute"
            // Old exports used one anonymous record per local day. Remove only
            // those old records, never a newly inserted minute, once per day.
            val date = start.atZone(ZoneId.systemDefault()).toLocalDate()
            val migrationKey = "hr:$date"
            if (config.cutoff > 0 && start.toEpochMilli() < config.cutoff && !prefs.getBoolean(migrationKey, false)) {
                check(config.allowRead) { "Legacy export requires foreground migration" }
                val dayStart = date.atStartOfDay(ZoneId.systemDefault()).toInstant()
                val dayEnd = date.plusDays(1).atStartOfDay(ZoneId.systemDefault()).toInstant()
                var token: String? = null
                val legacy = ArrayList<HeartRateRecord>()
                do {
                    val response = client.readRecords(ReadRecordsRequest(
                        HeartRateRecord::class, TimeRangeFilter.between(dayStart, dayEnd),
                        pageToken = token,
                    ))
                    legacy.addAll(response.records.filter {
                        it.metadata.dataOrigin.packageName == context.packageName &&
                            it.metadata.clientRecordId == null
                    })
                    token = response.pageToken?.takeIf { it.isNotEmpty() }
                } while (token != null)
                    // Preserve samples outside raw retention before retiring a
                    // legacy full-day record. Epoch-version bridge corrections
                    // outrank version zero, so replay cannot overwrite them.
                    val copied = legacy.flatMap { it.samples }.groupBy { (it.time.epochSecond / 60) * 60 }.map { (sampleMinute, samples) ->
                        val sampleStart = Instant.ofEpochSecond(sampleMinute)
                        HeartRateRecord(startTime = sampleStart, startZoneOffset = null,
                            endTime = sampleStart.plusSeconds(60), endZoneOffset = null,
                            samples = listOf(HeartRateRecord.Sample(sampleStart, bridgeAverageBpm(samples.map { it.beatsPerMinute }))),
                            metadata = metadata("whoop4:hr:$sampleMinute", 0))
                    }
                    for (batch in copied.chunked(500)) client.insertRecords(batch)
                    if (legacy.isNotEmpty()) client.deleteRecords(HeartRateRecord::class, legacy.map { it.metadata.id }, emptyList())
                check(prefs.edit().putBoolean(migrationKey, true).commit())
            }
            val bpm = (row["bpm"] as? Number)?.toLong()
            if (bpm == null) deleted.add(id)
            else {
                require(bpm in 1..300)
                records.add(HeartRateRecord(startTime = start, startZoneOffset = null,
                    endTime = end, endZoneOffset = null,
                    samples = listOf(HeartRateRecord.Sample(start, bpm)), metadata = metadata(id, version)))
            }
        }
        if (deleted.isNotEmpty()) client.deleteRecords(HeartRateRecord::class, emptyList(), deleted)
        if (records.isNotEmpty()) client.insertRecords(records)
    }
    private suspend fun night(client: HealthConnectClient, call: MethodCall, context: Context, config: LegacyConfig) {
        val day = requireNotNull(call.argument<String>("day"))
        val version = (call.argument<Any>("version") as Number).toLong()
        val session = call.argument<Map<String, Any?>>("session")
        val records = ArrayList<Record>()
        val stages = (session?.get("stages") as? List<*>)?.map { raw ->
            val stage = raw as Map<*, *>
            val type = when (stage["stage"]) {
                "awake" -> SleepSessionRecord.STAGE_TYPE_AWAKE
                "rem" -> SleepSessionRecord.STAGE_TYPE_REM
                "light" -> SleepSessionRecord.STAGE_TYPE_LIGHT
                "deep" -> SleepSessionRecord.STAGE_TYPE_DEEP
                else -> error("Unknown sleep stage")
            }
            SleepSessionRecord.Stage(Instant.ofEpochMilli((stage["startTime"] as Number).toLong()),
                Instant.ofEpochMilli((stage["endTime"] as Number).toLong()), type)
        }.orEmpty()
        if (session != null && stages.isNotEmpty()) {
            records.add(SleepSessionRecord(
                startTime = Instant.ofEpochMilli((session["startTime"] as Number).toLong()),
                endTime = Instant.ofEpochMilli((session["endTime"] as Number).toLong()),
                startZoneOffset = null, endZoneOffset = null, stages = stages,
                title = "OpenStrap sleep", metadata = metadata("whoop4:sleep:$day", version)))
        } else client.deleteRecords(SleepSessionRecord::class, emptyList(), listOf("whoop4:sleep:$day"))
        val values = call.argument<Map<String, Number>>("scalars").orEmpty()
        val time = (call.argument<Any>("time") as? Number)?.toLong()?.let(Instant::ofEpochMilli)
        val rhr = values["rhr"]?.toLong()
        val hrv = values["rmssd"]?.toDouble()
        val resp = values["resp_rate"]?.toDouble()
        if (time != null && rhr != null) records.add(RestingHeartRateRecord(time = time, zoneOffset = null, beatsPerMinute = rhr, metadata = metadata("whoop4:rhr:$day", version)))
        else client.deleteRecords(RestingHeartRateRecord::class, emptyList(), listOf("whoop4:rhr:$day"))
        if (time != null && hrv != null) records.add(HeartRateVariabilityRmssdRecord(time = time, zoneOffset = null, heartRateVariabilityMillis = hrv, metadata = metadata("whoop4:rmssd:$day", version)))
        else client.deleteRecords(HeartRateVariabilityRmssdRecord::class, emptyList(), listOf("whoop4:rmssd:$day"))
        if (time != null && resp != null) records.add(RespiratoryRateRecord(time = time, zoneOffset = null, rate = resp, metadata = metadata("whoop4:resp_rate:$day", version)))
        else client.deleteRecords(RespiratoryRateRecord::class, emptyList(), listOf("whoop4:resp_rate:$day"))
        // Read legacy IDs first, write the authoritative replacement, then
        // remove ONLY those IDs. A failed insert preserves all old history.
        val cleanup = ArrayList<suspend () -> Unit>()
        if (config.cutoff > 0 && java.time.LocalDate.parse(day).atStartOfDay(ZoneId.systemDefault()).toInstant().toEpochMilli() < config.cutoff) {
            check(config.allowRead) { "Legacy night requires foreground migration" }
            val anchor = if (session != null) Instant.ofEpochMilli((session["endTime"] as Number).toLong()) else time
            if (anchor != null) {
                val sessionStart = session?.get("startTime")?.let { Instant.ofEpochMilli((it as Number).toLong()) }
                val (start, end) = bridgeCleanupRange(anchor, sessionStart, ZoneId.systemDefault())
                if (stages.isNotEmpty()) cleanup.add(legacyCleanup(client, SleepSessionRecord::class, context, "sleep:$day", start, end))
                if (rhr != null) cleanup.add(legacyCleanup(client, RestingHeartRateRecord::class, context, "rhr:$day", start, end))
                if (hrv != null) cleanup.add(legacyCleanup(client, HeartRateVariabilityRmssdRecord::class, context, "rmssd:$day", start, end))
                if (resp != null) cleanup.add(legacyCleanup(client, RespiratoryRateRecord::class, context, "resp_rate:$day", start, end))
            }
        }
        if (records.isNotEmpty()) client.insertRecords(records)
        for (finish in cleanup) finish()
    }

    private suspend fun <T : Record> legacyCleanup(client: HealthConnectClient, type: kotlin.reflect.KClass<T>, context: Context,
        key: String, start: Instant, end: Instant): suspend () -> Unit {
        val prefs = context.getSharedPreferences("bridge_health_migration", Context.MODE_PRIVATE)
        if (prefs.getBoolean(key, false)) return {}
        val ids = ArrayList<String>()
        var token: String? = null
        do {
            val response = client.readRecords(ReadRecordsRequest(type, TimeRangeFilter.between(start, end), pageToken = token))
            ids.addAll(response.records.filter {
                it.metadata.dataOrigin.packageName == context.packageName && it.metadata.clientRecordId == null
            }.map { it.metadata.id })
            token = response.pageToken?.takeIf { it.isNotEmpty() }
        } while (token != null)
        return {
            if (ids.isNotEmpty()) client.deleteRecords(type, ids, emptyList())
            check(prefs.edit().putBoolean(key, true).commit())
        }
    }
}

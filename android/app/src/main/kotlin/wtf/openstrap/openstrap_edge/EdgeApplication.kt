package wtf.openstrap.openstrap_edge

import android.app.Application
import android.content.Context
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor

/** Lazily caches one Flutter engine shared by Activity and Bluetooth service. */
class EdgeApplication : Application() {
    companion object {
        const val ENGINE_ID = "openstrap_main_engine"

        /**
         * Create, register, run and cache the shared engine if it doesn't exist
         * yet; return the cached one otherwise. Idempotent. Main-thread only —
         * every caller (Activity/Service onCreate) already is.
         */
        @JvmStatic
        fun ensureEngine(context: Context): FlutterEngine {
            FlutterEngineCache.getInstance().get(ENGINE_ID)?.let { return it }
            val app = context.applicationContext
            // Constructor auto-registers plugins (GeneratedPluginRegistrant) →
            // flutter_blue_plus, health, shared_preferences,
            // etc. are all available headless.
            val engine = FlutterEngine(app)
            // Register platform channels on the engine BEFORE Dart starts, so they
            // exist even when no Activity is attached (headless calls like
            // EdgeTracking.start must work).
            NativeChannels.register(engine, app)
            engine.dartExecutor.executeDartEntrypoint(
                DartExecutor.DartEntrypoint.createDefault()
            )
            FlutterEngineCache.getInstance().put(ENGINE_ID, engine)
            return engine
        }
    }

    override fun onCreate() {
        super.onCreate()
        // Periodic watchdog: restart the tracking foreground service if the OS
        // killed it while a band is paired (START_STICKY backup). Idempotent (KEEP
        // policy). Paired-gated: unconditional scheduling gave even a never-paired
        // install a persisted 15-min periodic wake forever. Pairing (re-)arms it
        // via EdgeTrackingService.onCreate, and the worker cancels its own chain
        // if it ever runs unpaired.
        if (KeepAliveWorker.hasPairedDevice(this)) {
            KeepAliveWorker.schedule(this)
        }
    }
}

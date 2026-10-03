package wtf.openstrap.openstrap_edge

import android.Manifest
import android.app.ActivityManager
import android.bluetooth.BluetoothManager
import android.content.ActivityNotFoundException
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/** Registered on the retained engine, including boots without an Activity. */
object NativeChannels {
    fun register(engine: FlutterEngine, context: Context) {
        val app = context.applicationContext
        BridgeHeartRateWriter.register(engine, app)
        MethodChannel(engine.dartExecutor.binaryMessenger, "openstrap/edge_tracking")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> {
                        try {
                            EdgeTrackingService.start(app)
                            result.success(null)
                        } catch (error: Exception) {
                            result.error("BACKGROUND_START", error.message, null)
                        }
                    }
                    "stop" -> {
                        app.stopService(Intent(app, EdgeTrackingService::class.java))
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(engine.dartExecutor.binaryMessenger, "openstrap/ble_native")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "remoteDeviceName" -> remoteDeviceName(app, call.argument<String>("mac") ?: "", result)
                    else -> result.notImplemented()
                }
            }
        MethodChannel(engine.dartExecutor.binaryMessenger, "openstrap/android_background")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "associateCompanion" -> CompanionBridge.associate(app, call.arguments as? String ?: "", result)
                    "isIgnoringBatteryOptimizations" -> result.success(
                        (app.getSystemService(Context.POWER_SERVICE) as PowerManager)
                            .isIgnoringBatteryOptimizations(app.packageName))
                    "requestIgnoreBatteryOptimizations" -> result.success(requestIgnoreBatteryOptimizations(app))
                    "manufacturerHint" -> result.success(Build.MANUFACTURER.lowercase())
                    "isBackgroundRestricted" -> result.success(isBackgroundRestricted(app))
                    "openOemAutostartSettings" -> result.success(openOemAutostartSettings(app))
                    else -> result.notImplemented()
                }
            }
    }

    private fun remoteDeviceName(app: Context, mac: String, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
            app.checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) !=
                android.content.pm.PackageManager.PERMISSION_GRANTED
        ) {
            result.error("name_unavailable", "BLUETOOTH_CONNECT not granted", null)
            return
        }
        try {
            val mgr = app.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
            result.success(mgr?.adapter?.getRemoteDevice(mac)?.name)
        } catch (e: Exception) {
            result.error("name_unavailable", e.toString(), null)
        }
    }

    private fun requestIgnoreBatteryOptimizations(ctx: Context): Boolean {
        return try {
            val pm = ctx.getSystemService(Context.POWER_SERVICE) as PowerManager
            if (pm.isIgnoringBatteryOptimizations(ctx.packageName)) return true
            val intent = Intent(
                Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                Uri.parse("package:${ctx.packageName}"),
            )
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            ctx.startActivity(intent)
            true
        } catch (e: Exception) {
            false
        }
    }

    /**
     * Whether the OS is CURRENTLY restricting this app's background work —
     * the one official, CTS-tested, documented signal for this situation
     * (`ActivityManager.isBackgroundRestricted`, API 28+): "if true, any work
     * that the app tries to do will be aggressively restricted while it is in
     * the background... jobs and alarms will not execute and foreground
     * services cannot be started." This is what actually gates whether the
     * OEM-autostart entry point below should even be surfaced to the user —
     * NOT a manufacturer-name guess, which can't tell whether the OS is
     * presently restricting anything at all. False on API <28 (unsupported,
     * so we can't tell — callers fall back to the manufacturer hint alone in
     * that case, same as before).
     */
    private fun isBackgroundRestricted(ctx: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) return false
        val am = ctx.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        return am.isBackgroundRestricted
    }

    /**
     * OEM autostart/battery-manager allowlist deep link — a second, stronger
     * line of defense than [requestIgnoreBatteryOptimizations]. The stock
     * Android Doze exemption is well-known to be INSUFFICIENT on Xiaomi
     * (MIUI)/Huawei/Honor/Oppo (ColorOS)/Vivo (FuntouchOS)/OnePlus — these
     * OEMs layer their own aggressive process killers on top of stock Doze
     * and gate survival behind a separate "autostart"/"protected apps" list
     * that stock APIs cannot toggle. There is NO official Android API for
     * this specific mechanism (confirmed against developer.android.com's
     * Doze/App-Standby guide, which never mentions OEM autostart screens);
     * the settings-activity ComponentNames below are long-standing
     * community-documented ones (the "autostarter" pattern), not a Google
     * source, and can change across OEM software versions — every attempt
     * is wrapped so a missing/renamed activity on some device just falls
     * through to the next candidate, never crashes. Falls back to this app's
     * standard "App info" settings page (always resolvable) if no
     * OEM-specific screen exists on this device — so the user always lands
     * somewhere useful, never a silent no-op. Dart gates whether to even
     * OFFER this (via [isBackgroundRestricted]) rather than firing it
     * unconditionally off the manufacturer string — see
     * AndroidBackground.needsOemAutostartSettings.
     */
    private fun openOemAutostartSettings(ctx: Context): String {
        val manufacturer = Build.MANUFACTURER.lowercase()
        val candidates: List<ComponentName> = when {
            manufacturer.contains("xiaomi") -> listOf(
                ComponentName(
                    "com.miui.securitycenter",
                    "com.miui.permcenter.autostart.AutoStartManagementActivity",
                ),
                ComponentName(
                    "com.miui.securitycenter",
                    "com.miui.powercenter.PowerSettings",
                ),
            )
            manufacturer.contains("huawei") || manufacturer.contains("honor") -> listOf(
                ComponentName(
                    "com.huawei.systemmanager",
                    "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity",
                ),
                ComponentName(
                    "com.huawei.systemmanager",
                    "com.huawei.systemmanager.optimize.process.ProtectActivity",
                ),
            )
            manufacturer.contains("oppo") || manufacturer.contains("realme") -> listOf(
                ComponentName(
                    "com.coloros.safecenter",
                    "com.coloros.safecenter.permission.startup.StartupAppListActivity",
                ),
                ComponentName(
                    "com.coloros.safecenter",
                    "com.coloros.safecenter.startupapp.StartupAppListActivity",
                ),
            )
            manufacturer.contains("vivo") -> listOf(
                ComponentName(
                    "com.vivo.permissionmanager",
                    "com.vivo.permissionmanager.activity.BgStartUpManagerActivity",
                ),
                ComponentName(
                    "com.iqoo.secure",
                    "com.iqoo.secure.ui.phoneoptimize.AddWhiteListActivity",
                ),
            )
            manufacturer.contains("oneplus") -> listOf(
                ComponentName(
                    "com.oneplus.security",
                    "com.oneplus.security.chainlaunch.view.ChainLaunchAppListActivity",
                ),
            )
            else -> emptyList()
        }

        for (component in candidates) {
            try {
                val intent = Intent().apply {
                    setComponent(component)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                ctx.startActivity(intent)
                return "opened_oem_autostart"
            } catch (e: ActivityNotFoundException) {
                continue // try the next candidate / fall through to app-info
            } catch (e: SecurityException) {
                continue
            }
        }

        return try {
            val fallback = Intent(
                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                Uri.parse("package:${ctx.packageName}"),
            ).apply { addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) }
            ctx.startActivity(fallback)
            "opened_app_info_fallback"
        } catch (e: Exception) {
            "failed"
        }
    }

}

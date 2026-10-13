package com.sujay.taskme

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private var pending: MethodChannel.Result? = null
    private val localNetwork = "android.permission.ACCESS_LOCAL_NETWORK"

    private var quickChannel: MethodChannel? = null
    private var pendingQuick: HashMap<String, String>? = null

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        pendingQuick = readQuick(intent)
    }

    /** A widget button or app-icon shortcut asked to add something (expense, journal, ...). */
    private fun readQuick(i: Intent?): HashMap<String, String>? {
        if (i == null) return null
        // Do not replay the request when Android restores the app from the recent-apps list.
        if (i.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY != 0) return null
        val action = i.getStringExtra("quick") ?: return null
        val m = hashMapOf("action" to action)
        i.getStringExtra("when")?.let { m["when"] = it }
        i.removeExtra("quick")
        i.removeExtra("when")
        return m
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        readQuick(intent)?.let { quickChannel?.invokeMethod("quick", it) }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Newer Android versions ask permission before an app may talk to other
        // devices on the home Wi-Fi (needed to sync with the computer).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "myday/perm")
            .setMethodCallHandler { call, result ->
                if (call.method == "requestLocalNetwork") {
                    if (Build.VERSION.SDK_INT < 36 ||
                        checkSelfPermission(localNetwork) == PackageManager.PERMISSION_GRANTED
                    ) {
                        result.success(true)
                    } else {
                        pending?.success(false)
                        pending = result
                        requestPermissions(arrayOf(localNetwork), 4242)
                    }
                } else {
                    result.notImplemented()
                }
            }

        // Widgets and shortcuts talk to the app through this channel.
        quickChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "myday/quick").also { ch ->
            ch.setMethodCallHandler { call, result ->
                when (call.method) {
                    "initial" -> {
                        result.success(pendingQuick)
                        pendingQuick = null
                    }
                    "pinWidget" -> {
                        val name = call.arguments as? String
                        val mgr = AppWidgetManager.getInstance(this)
                        if (name == null || Build.VERSION.SDK_INT < Build.VERSION_CODES.O || !mgr.isRequestPinAppWidgetSupported) {
                            result.success(false)
                        } else {
                            try {
                                val cls = Class.forName("com.sujay.taskme.widgets.$name")
                                result.success(mgr.requestPinAppWidget(ComponentName(this, cls), null, null))
                            } catch (e: Exception) {
                                result.success(false)
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 4242) {
            pending?.success(grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED)
            pending = null
        }
    }
}

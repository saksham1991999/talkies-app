package `in`.talkies.talkies

import android.content.ComponentName
import android.content.pm.PackageManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val icons = listOf("default", "yellow", "green", "blue", "night")

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Launcher icon variants are activity-aliases; exactly one is enabled.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "talkies/app_icon").setMethodCallHandler { call, result ->
            if (call.method != "set") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val name = call.argument<String>("name")
            if (name !in icons) {
                result.success(false)
                return@setMethodCallHandler
            }
            for (n in icons) {
                val alias = ComponentName(this, "$packageName.Icon${n.replaceFirstChar { it.uppercase() }}")
                val state = if (n == name) PackageManager.COMPONENT_ENABLED_STATE_ENABLED else PackageManager.COMPONENT_ENABLED_STATE_DISABLED
                packageManager.setComponentEnabledSetting(alias, state, PackageManager.DONT_KILL_APP)
            }
            result.success(true)
        }
    }
}

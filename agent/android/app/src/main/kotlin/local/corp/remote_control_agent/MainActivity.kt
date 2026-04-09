package local.corp.remote_control_agent

/**
 * MainActivity
 *
 * Flutter + MethodChannel 통합:
 *   - "remote_control/service" → 포그라운드 서비스 시작/중지
 *   - "remote_control/projection" → MediaProjection 권한 요청 (화면 캡처)
 *
 * 화면 캡처 흐름 (Android):
 *   1. Flutter → "requestProjection" MethodChannel 호출
 *   2. MainActivity → MediaProjectionManager.createScreenCaptureIntent() 시작
 *   3. 사용자 승인 → onActivityResult → Dart에 결과 전달
 *   4. Rust JNI 레이어에서 MediaProjection API 사용
 */

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.media.projection.MediaProjectionManager
import android.os.Build
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        private const val SERVICE_CHANNEL    = "remote_control/service"
        private const val PROJECTION_CHANNEL = "remote_control/projection"
        private const val REQUEST_PROJECTION = 1001
    }

    private var projectionResult: MethodChannel.Result? = null

    // ──────────────────────────────────────────────
    // FlutterEngine 설정
    // ──────────────────────────────────────────────

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // ── 포그라운드 서비스 채널 ──
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SERVICE_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "start"  -> {
                    startRemoteControlService()
                    result.success(null)
                }
                "stop"   -> {
                    stopRemoteControlService()
                    result.success(null)
                }
                "update" -> {
                    val status = call.argument<String>("status") ?: "idle"
                    updateServiceStatus(status)
                    result.success(null)
                }
                else     -> result.notImplemented()
            }
        }

        // ── MediaProjection 채널 ──
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            PROJECTION_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "requestProjection" -> {
                    projectionResult = result
                    requestMediaProjection()
                }
                else -> result.notImplemented()
            }
        }
    }

    // ──────────────────────────────────────────────
    // 포그라운드 서비스
    // ──────────────────────────────────────────────

    private fun startRemoteControlService() {
        val intent = Intent(this, RemoteControlService::class.java).apply {
            action = RemoteControlService.ACTION_START
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }

    private fun stopRemoteControlService() {
        val intent = Intent(this, RemoteControlService::class.java).apply {
            action = RemoteControlService.ACTION_STOP
        }
        startService(intent)
    }

    private fun updateServiceStatus(status: String) {
        val intent = Intent(this, RemoteControlService::class.java).apply {
            action = RemoteControlService.ACTION_UPDATE
            putExtra(RemoteControlService.EXTRA_STATUS, status)
        }
        startService(intent)
    }

    // ──────────────────────────────────────────────
    // MediaProjection 권한 요청
    // ──────────────────────────────────────────────

    private fun requestMediaProjection() {
        val mgr = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        startActivityForResult(mgr.createScreenCaptureIntent(), REQUEST_PROJECTION)
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)

        if (requestCode == REQUEST_PROJECTION) {
            val result = projectionResult ?: return
            projectionResult = null

            if (resultCode == Activity.RESULT_OK && data != null) {
                // 성공: resultCode + data를 Dart로 전달 (JNI에서 사용)
                result.success(mapOf(
                    "resultCode" to resultCode,
                    "granted"    to true,
                ))
            } else {
                result.success(mapOf("granted" to false))
            }
        }
    }
}

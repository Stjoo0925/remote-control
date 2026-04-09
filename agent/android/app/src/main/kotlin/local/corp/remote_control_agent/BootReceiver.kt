package local.corp.remote_control_agent

/**
 * BootReceiver — 부팅 완료 시 에이전트 자동 시작
 *
 * 기기 재부팅 후 사용자가 앱을 수동으로 실행하지 않아도
 * 에이전트가 백그라운드에서 자동으로 시작됩니다.
 *
 * 동작:
 *   1. BOOT_COMPLETED / MY_PACKAGE_REPLACED 브로드캐스트 수신
 *   2. FlutterEngine 워밍업 (dart:main 실행) — 선택적
 *   3. RemoteControlService 포그라운드 서비스 시작
 *
 * 참고:
 *   - Android 10+에서 백그라운드 시작 제한으로 직접 Activity 시작 불가.
 *   - 포그라운드 서비스는 허용됩니다.
 */

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log

class BootReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "RC_BootReceiver"
    }

    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED -> {
                Log.i(TAG, "부팅 완료 — 에이전트 서비스 시작")
                startService(context)
            }
        }
    }

    private fun startService(context: Context) {
        val serviceIntent = Intent(context, RemoteControlService::class.java).apply {
            action = RemoteControlService.ACTION_START
        }
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(serviceIntent)
            } else {
                context.startService(serviceIntent)
            }
        } catch (e: Exception) {
            Log.e(TAG, "서비스 시작 실패: ${e.message}")
        }
    }
}

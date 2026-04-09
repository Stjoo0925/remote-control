package local.corp.remote_control_agent

/**
 * RemoteControlService — 포그라운드 서비스
 *
 * Android에서 앱이 백그라운드로 이동해도 Signaling 서버 연결과
 * WebRTC 세션을 유지하기 위한 포그라운드 서비스입니다.
 *
 * Flutter 측에서 MethodChannel "remote_control/service"를 통해
 * start / stop 명령을 전달합니다.
 *
 * 알림:
 *   - 채널: "remote_control_channel" (중요도: DEFAULT)
 *   - 세션 상태(대기/진행)를 알림 텍스트로 표시
 *   - 알림 탭 → 앱 포그라운드 복귀
 */

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

class RemoteControlService : Service() {

    companion object {
        const val CHANNEL_ID      = "remote_control_channel"
        const val NOTIFICATION_ID = 1001
        const val ACTION_START    = "ACTION_START"
        const val ACTION_STOP     = "ACTION_STOP"
        const val ACTION_UPDATE   = "ACTION_UPDATE_STATUS"
        const val EXTRA_STATUS    = "status"
    }

    // ──────────────────────────────────────────────
    // 생명주기
    // ──────────────────────────────────────────────

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                val notification = buildNotification("대기 중", "연결 요청을 기다리고 있습니다.")
                startForeground(NOTIFICATION_ID, notification)
            }
            ACTION_UPDATE -> {
                val status = intent.getStringExtra(EXTRA_STATUS) ?: "idle"
                updateNotification(status)
            }
            ACTION_STOP -> {
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
            }
        }
        // 시스템이 서비스를 강제 종료하면 자동 재시작
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        super.onDestroy()
        // Flutter 엔진에 서비스 종료 알림 (필요 시 MethodChannel로 전달)
    }

    // ──────────────────────────────────────────────
    // 알림
    // ──────────────────────────────────────────────

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "원격 제어 에이전트",
                NotificationManager.IMPORTANCE_LOW  // 소리 없음
            ).apply {
                description = "원격 연결 상태를 표시합니다."
                setShowBadge(false)
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(title: String, text: String): Notification {
        val tapIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            this, 0, tapIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(text)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentIntent(pendingIntent)
            .setOngoing(true)           // 스와이프 삭제 불가
            .setShowWhen(false)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }

    private fun updateNotification(status: String) {
        val (title, text) = when (status) {
            "idle"    -> Pair("원격 제어 에이전트", "대기 중 — 연결 요청을 기다립니다.")
            "pending" -> Pair("원격 제어 에이전트", "⚠️ 연결 요청 수신 — 앱을 열어 승인하세요.")
            "active"  -> Pair("원격 제어 에이전트", "🔴 세션 진행 중 — 원격 제어를 받고 있습니다.")
            else      -> Pair("원격 제어 에이전트", "대기 중")
        }
        val manager = getSystemService(NotificationManager::class.java)
        manager.notify(NOTIFICATION_ID, buildNotification(title, text))
    }
}

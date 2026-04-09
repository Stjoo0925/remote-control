// 세션 관리자
// SignalingClient와 ScreenStreamer를 조율해 세션 생명주기를 관리합니다.
//
// 책임:
//   - 연결 요청 수신 → ConsentDialog → 승인/거부
//   - 승인 시 ScreenStreamer에 Offer 전달 → Answer 반환 → Signaling
//   - 긴급 종료 (Ctrl+Alt+F12)

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:logger/logger.dart';

import '../clipboard/clipboard_manager.dart';
import '../consent/consent_dialog.dart';
import '../file_transfer/file_transfer_manager.dart';
import '../platform/android_service.dart';
import '../stream/screen_streamer.dart';
import '../tray/tray_app.dart';
import 'signaling_client.dart';

final sessionManagerProvider = Provider((ref) => SessionManager());

// ─────────────────────────────────────────────────────────────
// 상태 모델
// ─────────────────────────────────────────────────────────────

enum SessionStatus { idle, pending, active, ended }

class SessionState {
  final SessionStatus status;
  final String? sessionId;
  final String? controllerName;

  const SessionState({
    this.status = SessionStatus.idle,
    this.sessionId,
    this.controllerName,
  });

  SessionState copyWith({
    SessionStatus? status,
    String? sessionId,
    String? controllerName,
  }) =>
      SessionState(
        status: status ?? this.status,
        sessionId: sessionId ?? this.sessionId,
        controllerName: controllerName ?? this.controllerName,
      );
}

// ─────────────────────────────────────────────────────────────
// SessionManager
// ─────────────────────────────────────────────────────────────

class SessionManager {
  final _logger = Logger();
  final _storage = const FlutterSecureStorage();

  final _signaling = SignalingClient();
  final _streamer  = ScreenStreamer();

  ClipboardManager? _clipboardMgr;
  FileTransferManager? _fileMgr;

  SessionStatus _status = SessionStatus.idle;
  String? _sessionId;
  String? _controllerUsername;

  bool get _isDesktop => !Platform.isAndroid && !Platform.isIOS;

  void _updateStatus(SessionStatus newStatus) {
    _status = newStatus;
    if (_isDesktop) {
      TrayApp.instance.updateStatus(newStatus);
    } else if (Platform.isAndroid) {
      final statusStr = switch (newStatus) {
        SessionStatus.idle    => 'idle',
        SessionStatus.pending => 'pending',
        SessionStatus.active  => 'active',
        SessionStatus.ended   => 'idle',
      };
      AndroidService.instance.updateStatus(statusStr);
    }
  }

  // ──────────────────────────────────────────────
  // 초기화 & 연결
  // ──────────────────────────────────────────────

  /// 앱 시작 시 호출 — Rust Core + Signaling 서버 초기화
  Future<void> initialize() async {
    // Android: 포그라운드 서비스 시작 (백그라운드 유지)
    if (Platform.isAndroid) {
      await AndroidService.instance.start();
    }

    await _streamer.init();

    await _signaling.connect(
      callbacks: SignalingCallbacks(
        onConnectionRequest: _onConnectionRequest,
        onOffer: _onOffer,
        onIceCandidate: _onIceCandidate,
        onSessionEnded: _onSessionEnded,
        onSwitchMonitor: _onSwitchMonitor,
      ),
      platform: _getPlatform(),
    );

    // ScreenStreamer ICE Candidate → Signaling
    _streamer.onLocalIceCandidate = (candidate) {
      if (_sessionId != null && _controllerUsername != null) {
        _signaling.sendIceCandidate(
          sessionId: _sessionId!,
          targetOrControllerUsername: _controllerUsername!,
          candidate: candidate,
        );
      }
    };
  }

  // ──────────────────────────────────────────────
  // 이벤트 핸들러
  // ──────────────────────────────────────────────

  /// 연결 요청 수신 → 사용자에게 승인/거부 묻기
  void _onConnectionRequest(String controllerName, String sessionId) async {
    _logger.i('연결 요청: $controllerName (session=$sessionId)');
    _updateStatus(SessionStatus.pending);
    _controllerUsername = controllerName;

    final approved = await ConsentDialog.show(
      controllerName: controllerName,
      sessionId: sessionId,
    );

    if (approved) {
      _sessionId = sessionId;
      _updateStatus(SessionStatus.active);
      _signaling.approveSession(sessionId);
      _signaling.joinRoom(sessionId);
      _logger.i('세션 승인: $sessionId');

      // 클립보드 동기화 + 파일 수신 관리자 시작
      await _startAuxManagers(sessionId, controllerName);
    } else {
      _updateStatus(SessionStatus.idle);
      _controllerUsername = null;
      _signaling.rejectSession(sessionId);
      _logger.i('세션 거부: $sessionId');
    }
  }

  /// SDP Offer 수신 → ScreenStreamer로 처리 → Answer 반환
  Future<String> _onOffer(String offerJson) async {
    _logger.d('SDP Offer 처리 시작');
    // coturn STUN/TURN 서버 주소는 환경변수 또는 서버 설정에서 가져옵니다.
    const iceServers = [
      {'urls': 'stun:stun.corp.local:3478'},
      // TURN 서버가 있는 경우:
      // {'urls': 'turn:turn.corp.local:3478', 'username': 'rc', 'credential': 'rc-secret'},
    ];

    final answer = await _streamer.handleOffer(
      offerJson: offerJson,
      iceServers: iceServers,
    );
    _logger.d('SDP Answer 생성 완료');
    return answer;
  }

  /// 상대방의 ICE Candidate 수신
  Future<void> _onIceCandidate(String candidateJson) async {
    await _streamer.addIceCandidate(candidateJson);
  }

  /// 모니터 전환 요청 수신 (Controller → Agent)
  Future<void> _onSwitchMonitor(int monitorIndex) async {
    _logger.i('모니터 전환 요청: $monitorIndex번');
    await _streamer.switchMonitor(monitorIndex);
  }

  /// 세션 종료 이벤트
  void _onSessionEnded(String sessionId) {
    _logger.i('세션 종료: $sessionId');
    _streamer.stop();
    _stopAuxManagers();
    _sessionId = null;
    _controllerUsername = null;
    _updateStatus(SessionStatus.idle);
  }

  // ──────────────────────────────────────────────
  // 보조 관리자 (클립보드 / 파일 전송)
  // ──────────────────────────────────────────────

  Future<void> _startAuxManagers(String sessionId, String peerUsername) async {
    final serverUrl  = await _storage.read(key: 'server_url') ?? '';
    final token      = await _storage.read(key: 'access_token') ?? '';
    final socket     = _signaling.socket;
    if (socket == null) return;

    _clipboardMgr = ClipboardManager(
      socket: socket,
      sessionId: sessionId,
      peerUsername: peerUsername,
      isController: false, // Agent는 피제어측
    );
    _clipboardMgr!.start();

    _fileMgr = FileTransferManager(
      socket: socket,
      sessionId: sessionId,
      serverBaseUrl: '$serverUrl/api',
      accessToken: token,
      onTransferStarted: (info) {
        _logger.i('파일 수신 시작: ${info.filename}');
      },
      onTransferCompleted: (info) {
        _logger.i('파일 저장 완료: ${info.savedPath}');
      },
      onTransferFailed: (id) {
        _logger.w('파일 수신 실패: $id');
      },
    );
    _fileMgr!.start();
  }

  void _stopAuxManagers() {
    _clipboardMgr?.stop();
    _clipboardMgr = null;
    _fileMgr?.stop();
    _fileMgr = null;
  }

  // ──────────────────────────────────────────────
  // 긴급 종료 (Ctrl+Alt+F12)
  // ──────────────────────────────────────────────

  void forceEnd() {
    if (_sessionId != null) {
      _signaling.endSession(_sessionId!, reason: 'user_force_end');
      _streamer.stop();
      _stopAuxManagers();
      _sessionId = null;
      _controllerUsername = null;
      _updateStatus(SessionStatus.idle);
      _logger.w('세션 강제 종료');
    }
  }

  // ──────────────────────────────────────────────
  // 정리
  // ──────────────────────────────────────────────

  Future<void> dispose() async {
    _stopAuxManagers();
    await _streamer.stop();
    _signaling.disconnect();
  }

  // ──────────────────────────────────────────────
  // 유틸리티
  // ──────────────────────────────────────────────

  String _getPlatform() {
    // dart:io 없이 플랫폼 판별 (Flutter 방식)
    return 'desktop';
  }

  SessionStatus get status => _status;
  String? get sessionId => _sessionId;
  bool get isConnected => _signaling.isConnected;
}

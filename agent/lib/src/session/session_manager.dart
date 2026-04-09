// 세션 관리자
// SignalingClient와 ScreenStreamer를 조율해 세션 생명주기를 관리합니다.
//
// 책임:
//   - 연결 요청 수신 → ConsentDialog → 승인/거부
//   - 승인 시 ScreenStreamer에 Offer 전달 → Answer 반환 → Signaling
//   - 긴급 종료 (Ctrl+Alt+F12)

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';

import '../consent/consent_dialog.dart';
import '../stream/screen_streamer.dart';
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

  final _signaling = SignalingClient();
  final _streamer = ScreenStreamer();

  SessionStatus _status = SessionStatus.idle;
  String? _sessionId;
  String? _controllerUsername;

  // ──────────────────────────────────────────────
  // 초기화 & 연결
  // ──────────────────────────────────────────────

  /// 앱 시작 시 호출 — Rust Core + Signaling 서버 초기화
  Future<void> initialize() async {
    await _streamer.init();

    await _signaling.connect(
      callbacks: SignalingCallbacks(
        onConnectionRequest: _onConnectionRequest,
        onOffer: _onOffer,
        onIceCandidate: _onIceCandidate,
        onSessionEnded: _onSessionEnded,
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
    _status = SessionStatus.pending;
    _controllerUsername = controllerName;

    final approved = await ConsentDialog.show(
      controllerName: controllerName,
      sessionId: sessionId,
    );

    if (approved) {
      _sessionId = sessionId;
      _status = SessionStatus.active;
      _signaling.approveSession(sessionId);
      _signaling.joinRoom(sessionId);
      _logger.i('세션 승인: $sessionId');
    } else {
      _status = SessionStatus.idle;
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

  /// 세션 종료 이벤트
  void _onSessionEnded(String sessionId) {
    _logger.i('세션 종료: $sessionId');
    _streamer.stop();
    _sessionId = null;
    _controllerUsername = null;
    _status = SessionStatus.idle;
  }

  // ──────────────────────────────────────────────
  // 긴급 종료 (Ctrl+Alt+F12)
  // ──────────────────────────────────────────────

  void forceEnd() {
    if (_sessionId != null) {
      _signaling.endSession(_sessionId!, reason: 'user_force_end');
      _streamer.stop();
      _sessionId = null;
      _controllerUsername = null;
      _status = SessionStatus.idle;
      _logger.w('세션 강제 종료');
    }
  }

  // ──────────────────────────────────────────────
  // 정리
  // ──────────────────────────────────────────────

  Future<void> dispose() async {
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

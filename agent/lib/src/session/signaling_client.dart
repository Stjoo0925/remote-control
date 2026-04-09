// Signaling 클라이언트
// Socket.IO 연결 + WebRTC SDP/ICE 메시지 중계를 담당합니다.
// SessionManager에서 분리해 단일 책임 원칙을 적용했습니다.
//
// 역할:
//   - Signaling 서버 연결/재연결
//   - offer / answer / ice_candidate 이벤트 라우팅
//   - session_approved / session_rejected / session_ended 이벤트 발송

import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:logger/logger.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

/// Signaling 이벤트 콜백 정의
class SignalingCallbacks {
  /// SDP Offer 수신 (Agent 측)
  final Future<String> Function(String offerJson)? onOffer;

  /// SDP Answer 수신 (Controller 측)
  final Future<void> Function(String answerJson)? onAnswer;

  /// ICE Candidate 수신
  final Future<void> Function(String candidateJson)? onIceCandidate;

  /// 연결 요청 수신 (controller_name, session_id)
  final void Function(String controllerName, String sessionId)? onConnectionRequest;

  /// 세션 종료
  final void Function(String sessionId)? onSessionEnded;

  const SignalingCallbacks({
    this.onOffer,
    this.onAnswer,
    this.onIceCandidate,
    this.onConnectionRequest,
    this.onSessionEnded,
  });
}

class SignalingClient {
  final _logger = Logger();
  final _storage = const FlutterSecureStorage();

  io.Socket? _socket;
  SignalingCallbacks? _callbacks;

  bool _connected = false;
  String? _myUsername;

  // ──────────────────────────────────────────────
  // 연결
  // ──────────────────────────────────────────────

  /// Signaling 서버에 연결
  Future<void> connect({
    required SignalingCallbacks callbacks,
    String? platform,
  }) async {
    _callbacks = callbacks;

    final serverUrl =
        await _storage.read(key: 'server_url') ?? 'https://remote.corp.local';
    final token = await _storage.read(key: 'access_token');
    _myUsername = await _storage.read(key: 'username');

    _socket = io.io(serverUrl, <String, dynamic>{
      'transports': ['websocket'],
      'auth': {'token': token},
      'autoConnect': false,
      'reconnection': true,
      'reconnectionAttempts': 10,
      'reconnectionDelay': 2000,
    });

    _socket!
      ..onConnect((_) {
        _connected = true;
        _logger.i('Signaling 서버 연결됨');
        _socket!.emit('agent_ready', {
          'platform': platform ?? _detectPlatform(),
        });
      })
      ..onDisconnect((_) {
        _connected = false;
        _logger.w('Signaling 서버 연결 끊김');
      })
      ..onConnectError((err) {
        _logger.e('연결 오류: $err');
      })
      ..on('connection_request', _handleConnectionRequest)
      ..on('offer', _handleOffer)
      ..on('answer', _handleAnswer)
      ..on('ice_candidate', _handleIceCandidate)
      ..on('session_ended', _handleSessionEnded)
      ..connect();
  }

  /// 서버 연결 해제
  void disconnect() {
    _socket?.disconnect();
    _socket = null;
    _connected = false;
  }

  // ──────────────────────────────────────────────
  // 수신 이벤트 핸들러
  // ──────────────────────────────────────────────

  void _handleConnectionRequest(dynamic data) {
    final map = _toMap(data);
    final controllerName = map['controller_name'] as String? ?? '알 수 없음';
    final sessionId = map['session_id'] as String? ?? '';
    _logger.i('연결 요청 수신 — controller=$controllerName session=$sessionId');
    _callbacks?.onConnectionRequest?.call(controllerName, sessionId);
  }

  void _handleOffer(dynamic data) async {
    final map = _toMap(data);
    final offerJson = map['sdp'] as String?;
    if (offerJson == null) return;

    _logger.d('SDP Offer 수신');

    final answerJson = await _callbacks?.onOffer?.call(offerJson);
    if (answerJson == null) return;

    // Answer 반환
    final controllerUsername = map['controller_username'] as String?;
    _socket?.emit('answer', {
      'sdp': answerJson,
      'session_id': map['session_id'],
      'controller_username': controllerUsername,
    });
    _logger.d('SDP Answer 전송 완료');
  }

  void _handleAnswer(dynamic data) async {
    final map = _toMap(data);
    final answerJson = map['sdp'] as String?;
    if (answerJson != null) {
      _logger.d('SDP Answer 수신');
      await _callbacks?.onAnswer?.call(answerJson);
    }
  }

  void _handleIceCandidate(dynamic data) async {
    final map = _toMap(data);
    final candidateJson = map['candidate'] as String?;
    if (candidateJson != null) {
      _logger.d('ICE Candidate 수신');
      await _callbacks?.onIceCandidate?.call(candidateJson);
    }
  }

  void _handleSessionEnded(dynamic data) {
    final map = _toMap(data);
    final sessionId = map['session_id'] as String? ?? '';
    _logger.i('세션 종료 수신: $sessionId');
    _callbacks?.onSessionEnded?.call(sessionId);
  }

  // ──────────────────────────────────────────────
  // 발신 이벤트
  // ──────────────────────────────────────────────

  /// ICE Candidate 전송 (로컬 수집 → Signaling 서버 → 상대방)
  void sendIceCandidate({
    required String sessionId,
    required String targetOrControllerUsername,
    required RTCIceCandidate candidate,
  }) {
    _socket?.emit('ice_candidate', {
      'session_id': sessionId,
      'target_username': targetOrControllerUsername,
      'controller_username': targetOrControllerUsername,
      'candidate': jsonEncode({
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      }),
    });
  }

  /// 세션 승인
  void approveSession(String sessionId) {
    _socket?.emit('session_approved', {'session_id': sessionId});
    _logger.i('세션 승인 전송: $sessionId');
  }

  /// 세션 거부
  void rejectSession(String sessionId) {
    _socket?.emit('session_rejected', {'session_id': sessionId});
    _logger.i('세션 거부 전송: $sessionId');
  }

  /// 세션 강제 종료
  void endSession(String sessionId, {String reason = 'user_ended'}) {
    _socket?.emit('session_ended', {
      'session_id': sessionId,
      'reason': reason,
    });
    _logger.i('세션 종료 전송: $sessionId ($reason)');
  }

  /// 세션 룸 참가
  void joinRoom(String sessionId) {
    _socket?.emit('join_session', {'session_id': sessionId});
  }

  // ──────────────────────────────────────────────
  // 유틸리티
  // ──────────────────────────────────────────────

  Map<String, dynamic> _toMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return {};
  }

  String _detectPlatform() {
    // dart:io 없이 Flutter 방식으로 판별
    if (identical(0, 0.0)) return 'web'; // never true — placeholder
    return 'desktop';
  }

  bool get isConnected => _connected;
  String? get username => _myUsername;
}

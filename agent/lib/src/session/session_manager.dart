// 세션 관리자
// Signaling 서버와 WebSocket으로 연결하고 세션 생명주기를 관리합니다.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:logger/logger.dart';

import '../consent/consent_dialog.dart';

final sessionManagerProvider = Provider((ref) => SessionManager());

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
  }) => SessionState(
    status: status ?? this.status,
    sessionId: sessionId ?? this.sessionId,
    controllerName: controllerName ?? this.controllerName,
  );
}

class SessionManager {
  final _logger = Logger();
  final _storage = const FlutterSecureStorage();
  io.Socket? _socket;

  SessionStatus _status = SessionStatus.idle;
  String? _sessionId;

  /// Signaling 서버에 연결
  Future<void> connect() async {
    final serverUrl = await _storage.read(key: 'server_url') ?? 'https://remote.corp.local';
    final token = await _storage.read(key: 'access_token');

    _socket = io.io(serverUrl, <String, dynamic>{
      'transports': ['websocket'],
      'auth': {'token': token},
      'autoConnect': false,
    });

    _socket!
      ..onConnect((_) {
        _logger.i('Signaling 서버 연결됨');
        _socket!.emit('agent_ready', {'platform': _getPlatform()});
      })
      ..onDisconnect((_) {
        _logger.w('Signaling 서버 연결 끊김 — 재연결 시도');
        _status = SessionStatus.idle;
      })
      ..on('connection_request', _onConnectionRequest)
      ..on('session_ended', _onSessionEnded)
      ..on('offer', _onOffer)
      ..on('ice_candidate', _onIceCandidate)
      ..connect();
  }

  /// 연결 요청 수신 → 사용자에게 승인/거부 묻기
  void _onConnectionRequest(dynamic data) async {
    _logger.i('연결 요청: ${data['controller_name']}');
    _status = SessionStatus.pending;

    final approved = await ConsentDialog.show(
      controllerName: data['controller_name'] as String,
      sessionId: data['session_id'] as String,
    );

    if (approved) {
      _sessionId = data['session_id'] as String;
      _status = SessionStatus.active;
      _socket!.emit('session_approved', {'session_id': _sessionId});
      _logger.i('세션 승인: $_sessionId');
    } else {
      _status = SessionStatus.idle;
      _socket!.emit('session_rejected', {'session_id': data['session_id']});
      _logger.i('세션 거부');
    }
  }

  void _onSessionEnded(dynamic data) {
    _logger.i('세션 종료: $_sessionId');
    _sessionId = null;
    _status = SessionStatus.idle;
  }

  void _onOffer(dynamic data) {
    // TODO: WebRTC offer 처리 (Phase 2)
    _logger.d('SDP Offer 수신');
  }

  void _onIceCandidate(dynamic data) {
    // TODO: ICE Candidate 처리 (Phase 2)
    _logger.d('ICE Candidate 수신');
  }

  /// 긴급 세션 강제 종료 (Ctrl+Alt+F12)
  void forceEnd() {
    if (_sessionId != null) {
      _socket?.emit('session_ended', {'session_id': _sessionId, 'reason': 'user_force_end'});
      _sessionId = null;
      _status = SessionStatus.idle;
      _logger.w('세션 강제 종료');
    }
  }

  String _getPlatform() {
    // dart:io Platform으로 판별
    return 'desktop'; // TODO: Android 분기
  }

  SessionStatus get status => _status;
  String? get sessionId => _sessionId;
}

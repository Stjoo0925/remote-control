// ClipboardManager — 세션 내 클립보드 양방향 동기화
//
// 동작:
//   - 수신: Socket.IO 'clipboard_sync' 이벤트 → Flutter Clipboard에 쓰기
//   - 송신: 1초 폴링으로 로컬 클립보드 변경 감지 → 'clipboard_sync' 이벤트 전송
//
// 사용 방법:
//   final mgr = ClipboardManager(socket: socket, sessionId: sid, peerUsername: username);
//   mgr.start();
//   // 세션 종료 시
//   mgr.stop();

import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:logger/logger.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

class ClipboardManager {
  ClipboardManager({
    required io.Socket socket,
    required String sessionId,
    required String peerUsername,   // 수신 대상 (target_username 또는 controller_username)
    required bool isController,     // Controller면 true, Agent면 false
  })  : _socket = socket,
        _sessionId = sessionId,
        _peerUsername = peerUsername,
        _isController = isController;

  final io.Socket _socket;
  final String _sessionId;
  final String _peerUsername;
  final bool _isController;
  final _logger = Logger();

  Timer? _pollTimer;
  String _lastClipboard = '';
  bool _ignoreNext = false; // 수신 직후 루프 방지

  // ──────────────────────────────────────────────
  // 시작 / 정지
  // ──────────────────────────────────────────────

  void start() {
    _socket.on('clipboard_sync', _onClipboardSync);

    // 1초마다 로컬 클립보드 감지
    _pollTimer = Timer.periodic(const Duration(seconds: 1), (_) => _poll());
    _logger.i('ClipboardManager 시작 — session=$_sessionId');
  }

  void stop() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _socket.off('clipboard_sync', _onClipboardSync);
    _logger.i('ClipboardManager 정지');
  }

  // ──────────────────────────────────────────────
  // 수신 처리
  // ──────────────────────────────────────────────

  void _onClipboardSync(dynamic data) async {
    final map = _toMap(data);
    if (map['session_id'] != _sessionId) return;

    final text = map['text'] as String?;
    if (text == null || text == _lastClipboard) return;

    _logger.d('클립보드 수신: ${text.length}자');
    _ignoreNext = true;
    _lastClipboard = text;

    try {
      await Clipboard.setData(ClipboardData(text: text));
    } catch (e) {
      _logger.e('클립보드 쓰기 실패: $e');
    }
  }

  // ──────────────────────────────────────────────
  // 송신 처리 (폴링)
  // ──────────────────────────────────────────────

  Future<void> _poll() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text ?? '';

      if (text.isEmpty || text == _lastClipboard) return;

      if (_ignoreNext) {
        // 수신으로 인한 변경 — 루프 방지
        _ignoreNext = false;
        return;
      }

      _lastClipboard = text;
      _send(text);
    } catch (_) {
      // 클립보드 접근 실패 — 무시
    }
  }

  void _send(String text) {
    final payload = <String, dynamic>{
      'session_id': _sessionId,
      'text': text,
    };

    // 수신 대상 필드명은 역할에 따라 다름
    if (_isController) {
      payload['target_username'] = _peerUsername;
    } else {
      payload['controller_username'] = _peerUsername;
    }

    _socket.emit('clipboard_sync', jsonEncode(payload));
    _logger.d('클립보드 송신: ${text.length}자');
  }

  // ──────────────────────────────────────────────
  // 유틸
  // ──────────────────────────────────────────────

  Map<String, dynamic> _toMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    if (data is String) {
      try {
        return jsonDecode(data) as Map<String, dynamic>;
      } catch (_) {}
    }
    return {};
  }
}

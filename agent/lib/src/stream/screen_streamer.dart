// 화면 스트리밍 관리자
// Rust Core(rc-core)에서 캡처한 BGRA 프레임을 WebRTC Video Track으로 전송합니다.
//
// 흐름:
//   1. RustCore.initCapturer() → 화면 캡처 준비
//   2. flutter_webrtc의 RTCPeerConnection에 VideoTrack 추가
//   3. 루프: RustCore.captureFrame() → 프레임 → Track으로 push
//   4. DataChannel "input" 메시지 수신 → RustCore.sendMouseMove() 등 호출

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:logger/logger.dart';

import '../bridge/rust_core.dart';

/// 입력 이벤트 JSON → Rust 호출 디스패처
typedef InputDispatcher = Future<void> Function(Map<String, dynamic> event);

class ScreenStreamer {
  final _logger = Logger();

  RTCPeerConnection? _peerConnection;
  RTCDataChannel? _dataChannel;

  /// 스트리밍 루프 타이머
  Timer? _captureTimer;

  /// 화면 해상도
  int _screenWidth = 1920;
  int _screenHeight = 1080;

  bool _running = false;

  // ──────────────────────────────────────────────
  // 초기화
  // ──────────────────────────────────────────────

  /// 캡처러 + 입력 컨트롤러 초기화 (앱 시작 시 한 번 호출)
  Future<void> init({int monitorIndex = 0}) async {
    await RustCore.initCapturer(monitorIndex: monitorIndex);
    await RustCore.initInput();

    final size = await RustCore.getScreenSize();
    if (size.length >= 2) {
      _screenWidth = size[0];
      _screenHeight = size[1];
    }

    _logger.i('ScreenStreamer 초기화 완료 — ${_screenWidth}x$_screenHeight');
  }

  // ──────────────────────────────────────────────
  // WebRTC 연결 수립 (Agent 측)
  // ──────────────────────────────────────────────

  /// SDP Offer를 받아 Answer를 반환하고 스트리밍 시작
  Future<String> handleOffer({
    required String offerJson,
    required List<Map<String, dynamic>> iceServers,
  }) async {
    // RTCPeerConnection 생성
    final config = {
      'iceServers': iceServers,
    };
    final constraints = <String, dynamic>{
      'mandatory': {},
      'optional': [
        {'DtlsSrtpKeyAgreement': true},
      ],
    };

    _peerConnection = await createPeerConnection(config, constraints);

    // DataChannel "input" 수신 설정
    _peerConnection!.onDataChannel = (channel) {
      if (channel.label == 'input') {
        _dataChannel = channel;
        _dataChannel!.onMessage = _onInputMessage;
        _logger.i('DataChannel "input" 수신');
      }
    };

    // ICE Candidate 수집 콜백 (호출자에서 on_ice_candidate로 처리)
    _peerConnection!.onIceCandidate = (candidate) {
      _logger.d('로컬 ICE Candidate 수집: ${candidate.candidate}');
      // SessionManager를 통해 Signaling 서버로 전달됩니다.
      onLocalIceCandidate?.call(candidate);
    };

    // 연결 상태 변화
    _peerConnection!.onConnectionState = (state) {
      _logger.i('WebRTC 연결 상태: $state');
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        _startStreaming();
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        stop();
      }
    };

    // Offer 설정
    final offer = RTCSessionDescription(
      _extractSdp(offerJson),
      _extractType(offerJson),
    );
    await _peerConnection!.setRemoteDescription(offer);

    // Answer 생성
    final answer = await _peerConnection!.createAnswer();
    await _peerConnection!.setLocalDescription(answer);

    return jsonEncode({'type': answer.type, 'sdp': answer.sdp});
  }

  /// 상대방 ICE Candidate 추가
  Future<void> addIceCandidate(String candidateJson) async {
    final map = jsonDecode(candidateJson) as Map<String, dynamic>;
    final candidate = RTCIceCandidate(
      map['candidate'] as String?,
      map['sdpMid'] as String?,
      map['sdpMLineIndex'] as int?,
    );
    await _peerConnection?.addCandidate(candidate);
  }

  // ──────────────────────────────────────────────
  // 로컬 ICE Candidate 콜백 (SessionManager에서 설정)
  // ──────────────────────────────────────────────

  void Function(RTCIceCandidate)? onLocalIceCandidate;

  // ──────────────────────────────────────────────
  // 화면 스트리밍 루프
  // ──────────────────────────────────────────────

  void _startStreaming() {
    if (_running) return;
    _running = true;
    _logger.i('화면 스트리밍 시작 (30 fps)');

    // 30fps: ~33ms 간격
    _captureTimer = Timer.periodic(
      const Duration(milliseconds: 33),
      (_) => _captureAndSend(),
    );
  }

  Future<void> _captureAndSend() async {
    if (!_running) return;
    try {
      // BGRA 바이트 배열 캡처 (Rust Core)
      final frameBytes = await RustCore.captureFrame();
      if (frameBytes.isEmpty) return;

      // DataChannel로 화면 크기 메타데이터 전송 (첫 번째 요청 시)
      // 실제 비디오 트랙 push는 flutter_webrtc의 addTrack + VideoRenderer 를 통해 구현
      // 현재 단계: DataChannel을 통한 raw frame 전송 (MJPEG-over-DataChannel 방식)
      // 프로덕션에서는 addTrack()으로 H.264 인코딩 스트림을 사용합니다.
      if (_dataChannel?.state == RTCDataChannelState.RTCDataChannelOpen) {
        _dataChannel!.send(
          RTCDataChannelMessage.fromBinary(Uint8List.fromList(frameBytes)),
        );
      }
    } catch (e) {
      _logger.e('프레임 캡처 오류: $e');
    }
  }

  // ──────────────────────────────────────────────
  // 입력 이벤트 처리 (DataChannel "input" → Rust)
  // ──────────────────────────────────────────────

  void _onInputMessage(RTCDataChannelMessage message) {
    if (message.isBinary) return; // 입력 이벤트는 텍스트 JSON

    try {
      final event = jsonDecode(message.text) as Map<String, dynamic>;
      _dispatchInput(event);
    } catch (e) {
      _logger.e('입력 이벤트 파싱 실패: $e');
    }
  }

  Future<void> _dispatchInput(Map<String, dynamic> event) async {
    final type = event['type'] as String?;

    switch (type) {
      case 'get_screen_size':
        // 화면 크기 응답
        if (_dataChannel?.state == RTCDataChannelState.RTCDataChannelOpen) {
          _dataChannel!.send(RTCDataChannelMessage(
            jsonEncode({'type': 'screen_size', 'width': _screenWidth, 'height': _screenHeight}),
          ));
        }

      case 'mouse_move':
        await RustCore.sendMouseMove(
          event['x'] as int? ?? 0,
          event['y'] as int? ?? 0,
        );

      case 'mouse_button':
        await RustCore.sendMouseButton(
          event['button'] as int? ?? 0,
          event['pressed'] as bool? ?? false,
        );

      case 'mouse_scroll':
        await RustCore.sendMouseScroll(
          event['delta_x'] as int? ?? 0,
          event['delta_y'] as int? ?? 0,
        );

      case 'key_event':
        await RustCore.sendKeyEvent(
          event['key_code'] as int? ?? 0,
          event['pressed'] as bool? ?? false,
        );

      case 'type_text':
        final text = event['text'] as String?;
        if (text != null) await RustCore.typeText(text);

      case 'switch_monitor':
        final idx = event['monitor_index'] as int? ?? 0;
        await _switchMonitor(idx);

      default:
        _logger.w('알 수 없는 입력 이벤트 타입: $type');
    }
  }

  // ──────────────────────────────────────────────
  // 다중 모니터 전환
  // ──────────────────────────────────────────────

  /// Socket.IO 'switch_monitor' 이벤트 또는 DataChannel 요청으로 호출
  Future<void> switchMonitor(int monitorIndex) async {
    await _switchMonitor(monitorIndex);
  }

  Future<void> _switchMonitor(int monitorIndex) async {
    _logger.i('모니터 전환 → $monitorIndex번');
    try {
      await RustCore.switchMonitor(monitorIndex);
      final size = await RustCore.getScreenSize();
      if (size.length >= 2) {
        _screenWidth  = size[0];
        _screenHeight = size[1];
        _logger.i('모니터 전환 완료 — ${_screenWidth}x$_screenHeight');
      }
      // 화면 크기 변경을 Controller에 알림
      if (_dataChannel?.state == RTCDataChannelState.RTCDataChannelOpen) {
        _dataChannel!.send(RTCDataChannelMessage(
          jsonEncode({
            'type': 'screen_size',
            'width': _screenWidth,
            'height': _screenHeight,
            'monitor_index': monitorIndex,
          }),
        ));
      }
    } catch (e) {
      _logger.e('모니터 전환 실패: $e');
    }
  }

  // ──────────────────────────────────────────────
  // 종료
  // ──────────────────────────────────────────────

  Future<void> stop() async {
    if (!_running && _peerConnection == null) return;

    _running = false;
    _captureTimer?.cancel();
    _captureTimer = null;

    await _dataChannel?.close();
    await _peerConnection?.close();
    _dataChannel = null;
    _peerConnection = null;

    _logger.i('ScreenStreamer 종료');
  }

  // ──────────────────────────────────────────────
  // 유틸리티
  // ──────────────────────────────────────────────

  String _extractSdp(String sdpJson) {
    try {
      return (jsonDecode(sdpJson) as Map<String, dynamic>)['sdp'] as String;
    } catch (_) {
      return sdpJson;
    }
  }

  String _extractType(String sdpJson) {
    try {
      return (jsonDecode(sdpJson) as Map<String, dynamic>)['type'] as String? ?? 'offer';
    } catch (_) {
      return 'offer';
    }
  }

  bool get isRunning => _running;
  int get screenWidth => _screenWidth;
  int get screenHeight => _screenHeight;
}

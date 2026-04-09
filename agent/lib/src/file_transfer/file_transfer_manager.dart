// FileTransferManager — 세션 내 파일 수신 관리
//
// 역할:
//   - Socket.IO 'file_transfer_notify' 이벤트 수신
//   - event=started  : UI에 수신 대기 항목 추가 (onTransferStarted 콜백)
//   - event=completed: REST API에서 파일 다운로드 → 기기 저장소 저장
//                      (onTransferCompleted 콜백 — 저장 경로 포함)
//   - event=failed   : 실패 상태 전파 (onTransferFailed 콜백)
//
// 사용 방법:
//   final mgr = FileTransferManager(
//     socket: _socket,
//     sessionId: _sessionId,
//     serverBaseUrl: 'https://remote.corp.local/api',
//     accessToken: token,
//     onTransferStarted: (info) { ... },
//     onTransferCompleted: (info) { ... },
//     onTransferFailed: (transferId) { ... },
//   );
//   mgr.start();
//   mgr.stop();

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';
import 'package:path_provider/path_provider.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

// ─────────────────────────────────────────────────────────────
// 모델
// ─────────────────────────────────────────────────────────────

class TransferInfo {
  final String transferId;
  final String filename;
  final int fileSize;
  final String? savedPath;

  const TransferInfo({
    required this.transferId,
    required this.filename,
    required this.fileSize,
    this.savedPath,
  });

  TransferInfo copyWith({String? savedPath}) => TransferInfo(
        transferId: transferId,
        filename: filename,
        fileSize: fileSize,
        savedPath: savedPath ?? this.savedPath,
      );
}

// ─────────────────────────────────────────────────────────────
// FileTransferManager
// ─────────────────────────────────────────────────────────────

class FileTransferManager {
  FileTransferManager({
    required io.Socket socket,
    required String sessionId,
    required String serverBaseUrl,
    required String accessToken,
    void Function(TransferInfo info)? onTransferStarted,
    void Function(TransferInfo info)? onTransferCompleted,
    void Function(String transferId)? onTransferFailed,
  })  : _socket = socket,
        _sessionId = sessionId,
        _serverBaseUrl = serverBaseUrl.replaceAll(RegExp(r'/$'), ''),
        _accessToken = accessToken,
        _onStarted = onTransferStarted,
        _onCompleted = onTransferCompleted,
        _onFailed = onTransferFailed;

  final io.Socket _socket;
  final String _sessionId;
  final String _serverBaseUrl;
  final String _accessToken;

  final void Function(TransferInfo)? _onStarted;
  final void Function(TransferInfo)? _onCompleted;
  final void Function(String)? _onFailed;

  final _logger = Logger();

  // ──────────────────────────────────────────────
  // 시작 / 정지
  // ──────────────────────────────────────────────

  void start() {
    _socket.on('file_transfer_notify', _onNotify);
    _logger.i('FileTransferManager 시작 — session=$_sessionId');
  }

  void stop() {
    _socket.off('file_transfer_notify', _onNotify);
    _logger.i('FileTransferManager 정지');
  }

  // ──────────────────────────────────────────────
  // 이벤트 처리
  // ──────────────────────────────────────────────

  void _onNotify(dynamic data) async {
    final map = _toMap(data);
    if (map['session_id'] != _sessionId) return;

    final event      = map['event'] as String? ?? '';
    final transferId = map['transfer_id'] as String? ?? '';
    final filename   = map['filename'] as String? ?? 'unknown';
    final fileSize   = (map['file_size'] as num?)?.toInt() ?? 0;

    _logger.d('파일 전송 알림: event=$event file=$filename');

    switch (event) {
      case 'started':
        final info = TransferInfo(
          transferId: transferId,
          filename: filename,
          fileSize: fileSize,
        );
        _onStarted?.call(info);

      case 'completed':
        await _downloadFile(
          transferId: transferId,
          filename: filename,
          fileSize: fileSize,
        );

      case 'failed':
        _onFailed?.call(transferId);
    }
  }

  // ──────────────────────────────────────────────
  // 파일 다운로드
  // ──────────────────────────────────────────────

  Future<void> _downloadFile({
    required String transferId,
    required String filename,
    required int fileSize,
  }) async {
    try {
      final url = Uri.parse('$_serverBaseUrl/file-transfers/$transferId/download');
      final response = await http.get(url, headers: {
        'Authorization': 'Bearer $_accessToken',
      });

      if (response.statusCode != 200) {
        _logger.e('파일 다운로드 실패: HTTP ${response.statusCode}');
        _onFailed?.call(transferId);
        return;
      }

      // 저장 디렉토리 결정
      final dir = await _getDownloadDirectory();
      final savedFile = await _resolveUniquePath(dir, filename);
      await savedFile.writeAsBytes(response.bodyBytes);

      _logger.i('파일 저장 완료: ${savedFile.path} (${response.bodyBytes.length} bytes)');

      final info = TransferInfo(
        transferId: transferId,
        filename: filename,
        fileSize: fileSize,
        savedPath: savedFile.path,
      );
      _onCompleted?.call(info);
    } catch (e) {
      _logger.e('파일 다운로드 예외: $e');
      _onFailed?.call(transferId);
    }
  }

  // ──────────────────────────────────────────────
  // 저장 경로 유틸
  // ──────────────────────────────────────────────

  Future<Directory> _getDownloadDirectory() async {
    if (Platform.isAndroid) {
      // Android: 외부 저장소 Downloads
      final extDir = await getExternalStorageDirectory();
      if (extDir != null) {
        final downloads = Directory('${extDir.path}/RCTransfers');
        await downloads.create(recursive: true);
        return downloads;
      }
    } else if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      // Desktop: Documents/RCTransfers
      final docsDir = await getApplicationDocumentsDirectory();
      final rcDir = Directory('${docsDir.path}/RCTransfers');
      await rcDir.create(recursive: true);
      return rcDir;
    }

    // 폴백: 앱 문서 디렉토리
    final appDir = await getApplicationDocumentsDirectory();
    final fallback = Directory('${appDir.path}/RCTransfers');
    await fallback.create(recursive: true);
    return fallback;
  }

  /// 파일명 충돌 시 (1), (2) … 붙여 고유 경로 반환
  Future<File> _resolveUniquePath(Directory dir, String filename) async {
    var file = File('${dir.path}/$filename');
    if (!await file.exists()) return file;

    final dot = filename.lastIndexOf('.');
    final name = dot >= 0 ? filename.substring(0, dot) : filename;
    final ext  = dot >= 0 ? filename.substring(dot) : '';

    var counter = 1;
    while (true) {
      file = File('${dir.path}/$name ($counter)$ext');
      if (!await file.exists()) return file;
      counter++;
    }
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

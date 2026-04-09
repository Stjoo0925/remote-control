// 연결 승인 다이얼로그
// 원격 연결 요청이 들어오면 이 다이얼로그를 띄워 사용자 동의를 받습니다.
// 60초 타임아웃 시 자동 거부합니다.

import 'dart:async';
import 'package:flutter/material.dart';

class ConsentDialog {
  /// 연결 요청 승인 다이얼로그 표시
  /// 반환값: true = 승인, false = 거부 또는 타임아웃
  static Future<bool> show({
    required String controllerName,
    required String sessionId,
  }) async {
    // 현재 컨텍스트 가져오기 (navigatorKey 통해)
    final context = _navigatorKey.currentContext;
    if (context == null) return false;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ConsentDialogWidget(controllerName: controllerName),
    );

    return result ?? false;
  }

  static final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  static GlobalKey<NavigatorState> get navigatorKey => _navigatorKey;
}

class _ConsentDialogWidget extends StatefulWidget {
  final String controllerName;
  const _ConsentDialogWidget({required this.controllerName});

  @override
  State<_ConsentDialogWidget> createState() => _ConsentDialogWidgetState();
}

class _ConsentDialogWidgetState extends State<_ConsentDialogWidget> {
  static const _timeout = 60;
  int _remaining = _timeout;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      setState(() => _remaining--);
      if (_remaining <= 0) {
        t.cancel();
        if (mounted) Navigator.of(context).pop(false);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = _remaining / _timeout;
    final urgentColor = _remaining <= 10 ? Colors.red : Colors.blue;

    return AlertDialog(
      backgroundColor: const Color(0xFF1E293B), // slate-800
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          const Icon(Icons.computer, color: Colors.blue, size: 28),
          const SizedBox(width: 12),
          const Text('원격 연결 요청', style: TextStyle(color: Colors.white, fontSize: 18)),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${widget.controllerName}님이 이 기기에 원격으로 접속하려 합니다.',
            style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 14),
          ),
          const SizedBox(height: 8),
          const Text(
            '승인하면 상대방이 화면을 보고 제어할 수 있습니다.',
            style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
          ),
          const SizedBox(height: 20),
          // 타임아웃 진행바
          LinearProgressIndicator(
            value: progress,
            backgroundColor: const Color(0xFF334155),
            valueColor: AlwaysStoppedAnimation(urgentColor),
          ),
          const SizedBox(height: 6),
          Text(
            '자동 거부까지 $_remaining초',
            style: TextStyle(color: urgentColor, fontSize: 12),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('거부', style: TextStyle(color: Colors.red)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('승인'),
        ),
      ],
    );
  }
}

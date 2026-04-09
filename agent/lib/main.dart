// 원격 제어 Agent 앱 진입점
// 피제어측(Target) 기기에 설치되는 앱입니다.
// 데스크탑: 시스템 트레이에서 실행 (창 기본 숨김)
// Android: 포그라운드 서비스로 실행

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'src/tray/tray_app.dart';
import 'src/settings/settings_page.dart';
import 'src/session/session_manager.dart';
import 'src/consent/consent_dialog.dart';
import 'src/bridge/rust_core.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (_isDesktop) {
    await windowManager.ensureInitialized();
    const windowOptions = WindowOptions(
      size: Size(440, 520),
      minimumSize: Size(360, 420),
      center: true,
      title: '원격 제어 에이전트',
      skipTaskbar: false,
    );
    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      // 처음에는 트레이에 숨김 (설정 미완료면 설정 창 표시는 AgentHome에서)
      await windowManager.hide();
    });
  }

  // Rust Core 초기화 (화면 캡처 + 입력 제어 준비)
  await RustCore.init();

  runApp(
    const ProviderScope(
      child: AgentApp(),
    ),
  );
}

bool get _isDesktop =>
    !Platform.isAndroid && !Platform.isIOS;

// ─────────────────────────────────────────────────────────────
// AgentApp
// ─────────────────────────────────────────────────────────────

class AgentApp extends ConsumerWidget {
  const AgentApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: '원격 제어 에이전트',
      debugShowCheckedModeBanner: false,
      // ConsentDialog.show()에서 컨텍스트를 가져오기 위한 navigatorKey
      navigatorKey: ConsentDialog.navigatorKey,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF3B82F6),
          brightness: Brightness.dark,
        ),
      ),
      home: const AgentHome(),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// AgentHome — 앱 전역 초기화 + 단축키 리스너
// ─────────────────────────────────────────────────────────────

class AgentHome extends ConsumerStatefulWidget {
  const AgentHome({super.key});

  @override
  ConsumerState<AgentHome> createState() => _AgentHomeState();
}

class _AgentHomeState extends ConsumerState<AgentHome> with WindowListener {
  @override
  void initState() {
    super.initState();

    // 데스크탑: 트레이 + 창 이벤트 리스너
    if (_isDesktop) {
      windowManager.addListener(this);
      TrayApp.instance.init(ref: ref);
    }

    // Signaling 서버 연결 + Rust Core 스트리머 초기화
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await ref.read(sessionManagerProvider).initialize();
    });
  }

  @override
  void dispose() {
    if (_isDesktop) windowManager.removeListener(this);
    super.dispose();
  }

  // 창 닫기 버튼 → 트레이로 최소화 (앱 종료 아님)
  @override
  void onWindowClose() async {
    await windowManager.hide();
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: FocusNode()..requestFocus(),
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: const SettingsPage(),
    );
  }

  // ──────────────────────────────────────────────
  // Ctrl+Alt+F12 긴급 종료 단축키
  // ──────────────────────────────────────────────

  final _pressedKeys = <LogicalKeyboardKey>{};

  void _handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent) {
      _pressedKeys.add(event.logicalKey);
      _checkEmergencyHotkey();
    } else if (event is KeyUpEvent) {
      _pressedKeys.remove(event.logicalKey);
    }
  }

  void _checkEmergencyHotkey() {
    final ctrl = _pressedKeys.contains(LogicalKeyboardKey.controlLeft) ||
        _pressedKeys.contains(LogicalKeyboardKey.controlRight);
    final alt = _pressedKeys.contains(LogicalKeyboardKey.altLeft) ||
        _pressedKeys.contains(LogicalKeyboardKey.altRight);
    final f12 = _pressedKeys.contains(LogicalKeyboardKey.f12);

    if (ctrl && alt && f12) {
      ref.read(sessionManagerProvider).forceEnd();
      _showSnackBar('세션이 강제 종료됐습니다 (Ctrl+Alt+F12)');
    }
  }

  void _showSnackBar(String message) {
    final ctx = ConsentDialog.navigatorKey.currentContext;
    if (ctx != null) {
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: const Color(0xFF334155),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }
}

// 원격 제어 Agent 앱 진입점
// 피제어측(Target) 기기에 설치되는 앱입니다.
// 데스크탑: 시스템 트레이에서 실행
// Android: 백그라운드 서비스로 실행

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'src/tray/tray_app.dart';
import 'src/settings/settings_page.dart';
import 'src/session/session_manager.dart';
import 'src/bridge/rust_core.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 데스크탑 환경에서 창 설정
  if (!Platform.isAndroid && !Platform.isIOS) {
    await windowManager.ensureInitialized();
    const windowOptions = WindowOptions(
      size: Size(400, 300),
      center: true,
      title: '원격 제어 에이전트',
      skipTaskbar: false,
    );
    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      // 설정이 완료되면 트레이로 최소화
      await windowManager.hide();
    });
  }

  // Rust Core 초기화
  await RustCore.init();

  runApp(
    const ProviderScope(
      child: AgentApp(),
    ),
  );
}

class AgentApp extends ConsumerWidget {
  const AgentApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: '원격 제어 에이전트',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF3B82F6), // blue-500
          brightness: Brightness.dark,
        ),
      ),
      home: const AgentHome(),
    );
  }
}

class AgentHome extends ConsumerStatefulWidget {
  const AgentHome({super.key});

  @override
  ConsumerState<AgentHome> createState() => _AgentHomeState();
}

class _AgentHomeState extends ConsumerState<AgentHome> {
  @override
  void initState() {
    super.initState();
    // 데스크탑: 트레이 앱 초기화
    if (!Platform.isAndroid && !Platform.isIOS) {
      TrayApp.instance.init();
    }
    // Signaling 서버 연결
    ref.read(sessionManagerProvider).connect();
  }

  @override
  Widget build(BuildContext context) {
    // 메인 UI는 설정 페이지 (트레이에서 열릴 때 표시)
    return const SettingsPage();
  }
}

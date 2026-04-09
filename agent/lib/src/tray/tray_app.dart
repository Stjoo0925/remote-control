// 시스템 트레이 앱 (데스크탑 전용)
// 에이전트가 백그라운드에서 실행되며 트레이 아이콘으로 상태를 표시합니다.

import 'package:system_tray/system_tray.dart';
import 'package:window_manager/window_manager.dart';

import '../session/session_manager.dart';

class TrayApp {
  TrayApp._();
  static final instance = TrayApp._();

  final _systemTray = SystemTray();
  final _menu = Menu();

  Future<void> init() async {
    await _systemTray.initSystemTray(
      title: '원격 제어',
      iconPath: 'assets/tray_idle.png',
      toolTip: '원격 제어 에이전트 — 대기 중',
    );

    await _menu.buildFrom([
      MenuItemLabel(label: '원격 제어 에이전트', enabled: false),
      MenuSeparator(),
      MenuItemLabel(
        label: '설정 열기',
        onClicked: (_) => windowManager.show(),
      ),
      MenuItemLabel(
        label: '세션 강제 종료',
        onClicked: (_) => _forceEndSession(),
      ),
      MenuSeparator(),
      MenuItemLabel(
        label: '종료',
        onClicked: (_) => _quit(),
      ),
    ]);

    await _systemTray.setContextMenu(_menu);
    _systemTray.registerSystemTrayEventHandler((eventName) {
      if (eventName == kSystemTrayEventClick) {
        windowManager.show();
      } else if (eventName == kSystemTrayEventRightClick) {
        _systemTray.popUpContextMenu();
      }
    });
  }

  /// 세션 상태에 따라 트레이 아이콘 업데이트
  Future<void> updateStatus(SessionStatus status) async {
    switch (status) {
      case SessionStatus.idle:
        await _systemTray.setImage('assets/tray_idle.png');
        await _systemTray.setToolTip('원격 제어 에이전트 — 대기 중');
      case SessionStatus.pending:
        await _systemTray.setImage('assets/tray_pending.png');
        await _systemTray.setToolTip('원격 제어 에이전트 — 연결 요청 수신');
      case SessionStatus.active:
        await _systemTray.setImage('assets/tray_active.png');
        await _systemTray.setToolTip('원격 제어 에이전트 — 세션 진행 중');
      case SessionStatus.ended:
        await _systemTray.setImage('assets/tray_idle.png');
        await _systemTray.setToolTip('원격 제어 에이전트 — 대기 중');
    }
  }

  void _forceEndSession() {
    // TODO: sessionManager.forceEnd() 연결
  }

  void _quit() {
    _systemTray.destroy();
    windowManager.destroy();
  }
}

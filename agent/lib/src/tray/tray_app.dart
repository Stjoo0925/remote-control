// 시스템 트레이 앱 (데스크탑 전용)
// 에이전트가 백그라운드에서 실행되며 트레이 아이콘으로 연결 상태를 표시합니다.
//
// 아이콘 의미:
//   tray_idle.png   → 대기 중 (Signaling 서버 연결됨)
//   tray_pending.png → 연결 요청 수신 (사용자 응답 대기)
//   tray_active.png  → 원격 세션 진행 중

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:system_tray/system_tray.dart';
import 'package:window_manager/window_manager.dart';

import '../session/session_manager.dart';

class TrayApp {
  TrayApp._();
  static final instance = TrayApp._();

  final _systemTray = SystemTray();
  final _menu = Menu();

  WidgetRef? _ref;

  // ──────────────────────────────────────────────
  // 초기화
  // ──────────────────────────────────────────────

  Future<void> init({required WidgetRef ref}) async {
    _ref = ref;

    await _systemTray.initSystemTray(
      title: '',
      iconPath: _iconPath(SessionStatus.idle),
      toolTip: '원격 제어 에이전트 — 대기 중',
    );

    await _buildMenu();

    _systemTray.registerSystemTrayEventHandler((eventName) {
      switch (eventName) {
        case kSystemTrayEventClick:
          // 좌클릭: 설정 창 토글
          windowManager.isVisible().then((visible) {
            if (visible) {
              windowManager.hide();
            } else {
              windowManager.show();
              windowManager.focus();
            }
          });
        case kSystemTrayEventRightClick:
          _systemTray.popUpContextMenu();
      }
    });
  }

  Future<void> _buildMenu() async {
    final sessionId = _ref?.read(sessionManagerProvider).sessionId;
    final hasActiveSession = sessionId != null;

    await _menu.buildFrom([
      MenuItemLabel(
        label: '원격 제어 에이전트',
        enabled: false,
      ),
      MenuSeparator(),
      MenuItemLabel(
        label: '설정 열기',
        onClicked: (_) async {
          await windowManager.show();
          await windowManager.focus();
        },
      ),
      MenuSeparator(),
      MenuItemLabel(
        label: hasActiveSession ? '세션 강제 종료 (Ctrl+Alt+F12)' : '진행 중인 세션 없음',
        enabled: hasActiveSession,
        onClicked: hasActiveSession ? (_) => _forceEndSession() : null,
      ),
      MenuSeparator(),
      MenuItemLabel(
        label: '에이전트 종료',
        onClicked: (_) => _quit(),
      ),
    ]);

    await _systemTray.setContextMenu(_menu);
  }

  // ──────────────────────────────────────────────
  // 상태 업데이트 (SessionManager에서 호출)
  // ──────────────────────────────────────────────

  Future<void> updateStatus(SessionStatus status) async {
    await _systemTray.setImage(_iconPath(status));
    await _systemTray.setToolTip(_tooltip(status));
    // 세션 상태 변경 시 컨텍스트 메뉴 재구성 (강제 종료 활성화/비활성화)
    await _buildMenu();
  }

  // ──────────────────────────────────────────────
  // 액션
  // ──────────────────────────────────────────────

  void _forceEndSession() {
    _ref?.read(sessionManagerProvider).forceEnd();
  }

  void _quit() {
    _systemTray.destroy();
    windowManager.destroy();
  }

  // ──────────────────────────────────────────────
  // 유틸리티
  // ──────────────────────────────────────────────

  String _iconPath(SessionStatus status) {
    switch (status) {
      case SessionStatus.idle:
      case SessionStatus.ended:
        return 'assets/icons/tray_idle.png';
      case SessionStatus.pending:
        return 'assets/icons/tray_pending.png';
      case SessionStatus.active:
        return 'assets/icons/tray_active.png';
    }
  }

  String _tooltip(SessionStatus status) {
    switch (status) {
      case SessionStatus.idle:
        return '원격 제어 에이전트 — 대기 중';
      case SessionStatus.pending:
        return '원격 제어 에이전트 — 연결 요청 수신';
      case SessionStatus.active:
        return '원격 제어 에이전트 — 세션 진행 중';
      case SessionStatus.ended:
        return '원격 제어 에이전트 — 대기 중';
    }
  }
}

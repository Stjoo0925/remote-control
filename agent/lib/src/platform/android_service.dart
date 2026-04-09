// Android 포그라운드 서비스 브릿지 (Flutter → Kotlin MethodChannel)
// 데스크탑에서는 no-op이므로 플랫폼 분기 없이 호출해도 안전합니다.

import 'dart:io';
import 'package:flutter/services.dart';
import 'package:logger/logger.dart';

class AndroidService {
  AndroidService._();
  static final instance = AndroidService._();

  static const _channel = MethodChannel('remote_control/service');
  final _logger = Logger();

  bool get _isAndroid => Platform.isAndroid;

  /// 포그라운드 서비스 시작 (앱 최초 실행 / 부팅 후 재시작 시)
  Future<void> start() async {
    if (!_isAndroid) return;
    try {
      await _channel.invokeMethod('start');
      _logger.i('Android 포그라운드 서비스 시작');
    } on PlatformException catch (e) {
      _logger.e('서비스 시작 실패: ${e.message}');
    }
  }

  /// 포그라운드 서비스 중지 (앱 종료 시)
  Future<void> stop() async {
    if (!_isAndroid) return;
    try {
      await _channel.invokeMethod('stop');
      _logger.i('Android 포그라운드 서비스 중지');
    } on PlatformException catch (e) {
      _logger.e('서비스 중지 실패: ${e.message}');
    }
  }

  /// 알림 상태 업데이트 (세션 상태 변경 시)
  /// status: 'idle' | 'pending' | 'active'
  Future<void> updateStatus(String status) async {
    if (!_isAndroid) return;
    try {
      await _channel.invokeMethod('update', {'status': status});
    } on PlatformException catch (e) {
      _logger.e('상태 업데이트 실패: ${e.message}');
    }
  }
}

// 설정 페이지
// 서버 주소·계정 입력 + 로그인 API 호출 + Signaling 연결 상태 표시
//
// 흐름:
//   1. 서버 주소 / 사번 / 비밀번호 입력
//   2. '저장 및 연결' → POST /api/auth/login → JWT 저장
//   3. SessionManager.initialize() 재호출 → Signaling 서버 연결
//   4. 연결 상태(idle/connected/active) 표시

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';

import '../session/session_manager.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  final _logger = Logger();
  final _storage = const FlutterSecureStorage();

  final _serverCtrl   = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  bool _saving = false;
  bool _obscurePassword = true;
  _Status _status = _Status.notConnected;
  String? _errorMsg;

  @override
  void initState() {
    super.initState();
    _loadSaved();
  }

  Future<void> _loadSaved() async {
    _serverCtrl.text =
        await _storage.read(key: 'server_url') ?? 'https://remote.corp.local';
    _usernameCtrl.text = await _storage.read(key: 'username') ?? '';

    // 저장된 토큰이 있으면 이미 연결 시도 중
    final token = await _storage.read(key: 'access_token');
    if (token != null) {
      setState(() => _status = _Status.connecting);
    }
  }

  // ──────────────────────────────────────────────
  // 저장 + 로그인
  // ──────────────────────────────────────────────

  Future<void> _saveAndConnect() async {
    final server   = _serverCtrl.text.trim();
    final username = _usernameCtrl.text.trim();
    final password = _passwordCtrl.text;

    if (server.isEmpty || username.isEmpty || password.isEmpty) {
      setState(() => _errorMsg = '서버 주소, 사번, 비밀번호를 모두 입력해 주세요.');
      return;
    }

    setState(() {
      _saving   = true;
      _errorMsg = null;
      _status   = _Status.connecting;
    });

    try {
      // 1. 로그인 API 호출
      final uri = Uri.parse('$server/api/auth/login');
      final res = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'username': username, 'password': password}),
          )
          .timeout(const Duration(seconds: 10));

      if (res.statusCode != 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final detail = body['detail'] as String? ?? '로그인에 실패했습니다.';
        throw Exception(detail);
      }

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final accessToken  = data['access_token']  as String;
      final refreshToken = data['refresh_token'] as String;

      // 2. 토큰 + 설정 저장
      await Future.wait([
        _storage.write(key: 'server_url',     value: server),
        _storage.write(key: 'username',       value: username),
        _storage.write(key: 'access_token',   value: accessToken),
        _storage.write(key: 'refresh_token',  value: refreshToken),
      ]);
      // 비밀번호는 저장하지 않음 (토큰만 사용)

      // 3. SessionManager 재초기화 → Signaling 서버 연결
      await ref.read(sessionManagerProvider).initialize();

      setState(() {
        _status   = _Status.connected;
        _errorMsg = null;
      });
    } on SocketException {
      setState(() {
        _status   = _Status.notConnected;
        _errorMsg = '서버에 연결할 수 없습니다. 서버 주소를 확인해 주세요.';
      });
    } on Exception catch (e) {
      setState(() {
        _status   = _Status.notConnected;
        _errorMsg = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      setState(() => _saving = false);
    }
  }

  // ──────────────────────────────────────────────
  // 빌드
  // ──────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final sessionMgr = ref.watch(sessionManagerProvider);

    // SessionManager 상태로 _status 동기화
    final liveStatus = switch (sessionMgr.status) {
      SessionStatus.active  => _Status.active,
      SessionStatus.pending => _Status.pending,
      _ => _status,
    };

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('원격 제어 에이전트', style: TextStyle(fontSize: 16)),
        centerTitle: false,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: _StatusChip(status: liveStatus),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── 연결 안내 카드 ──
            _InfoCard(status: liveStatus, sessionId: sessionMgr.sessionId),
            const SizedBox(height: 24),

            // ── 서버 설정 ──
            _sectionLabel('서버 설정'),
            _textField(
              controller: _serverCtrl,
              hint: 'https://remote.corp.local',
              label: '서버 주소',
              icon: Icons.dns_outlined,
            ),
            const SizedBox(height: 20),

            // ── 계정 ──
            _sectionLabel('계정'),
            _textField(
              controller: _usernameCtrl,
              hint: 'hong.gildong',
              label: '사번 / 아이디',
              icon: Icons.person_outline,
            ),
            const SizedBox(height: 12),
            _textField(
              controller: _passwordCtrl,
              hint: '사내 LDAP 비밀번호',
              label: '비밀번호',
              icon: Icons.lock_outline,
              obscure: _obscurePassword,
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword ? Icons.visibility_off : Icons.visibility,
                  color: const Color(0xFF64748B),
                  size: 20,
                ),
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
              ),
            ),
            const SizedBox(height: 24),

            // ── 저장 버튼 ──
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF3B82F6),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: _saving ? null : _saveAndConnect,
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('저장 및 연결',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              ),
            ),

            // ── 오류 메시지 ──
            if (_errorMsg != null) ...[
              const SizedBox(height: 12),
              _ErrorBanner(message: _errorMsg!),
            ],

            const SizedBox(height: 32),

            // ── 안내 ──
            const _HintText(),
          ],
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────
  // 위젯 헬퍼
  // ──────────────────────────────────────────────

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(
          text,
          style: const TextStyle(
              color: Color(0xFF94A3B8),
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8),
        ),
      );

  Widget _textField({
    required TextEditingController controller,
    required String hint,
    required String label,
    required IconData icon,
    bool obscure = false,
    Widget? suffixIcon,
  }) {
    const border = OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(10)),
      borderSide: BorderSide(color: Color(0xFF334155)),
    );
    return TextField(
      controller: controller,
      obscureText: obscure,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFF475569)),
        prefixIcon: Icon(icon, color: const Color(0xFF475569), size: 20),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: const Color(0xFF1E293B),
        border: border,
        enabledBorder: border,
        focusedBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(10)),
          borderSide: BorderSide(color: Color(0xFF3B82F6)),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
    );
  }

  @override
  void dispose() {
    _serverCtrl.dispose();
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }
}

// ─────────────────────────────────────────────────────────────
// 상태 열거형
// ─────────────────────────────────────────────────────────────

enum _Status { notConnected, connecting, connected, pending, active }

// ─────────────────────────────────────────────────────────────
// 서브 위젯
// ─────────────────────────────────────────────────────────────

class _StatusChip extends StatelessWidget {
  final _Status status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      _Status.notConnected => ('미연결', const Color(0xFF64748B)),
      _Status.connecting   => ('연결 중', const Color(0xFFFACC15)),
      _Status.connected    => ('대기 중', const Color(0xFF22C55E)),
      _Status.pending      => ('요청 수신', const Color(0xFFF97316)),
      _Status.active       => ('세션 중', const Color(0xFF3B82F6)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(
                  color: color, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final _Status status;
  final String? sessionId;
  const _InfoCard({required this.status, this.sessionId});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: switch (status) {
        _Status.notConnected => const _CardContent(
            icon: Icons.link_off,
            iconColor: Color(0xFF64748B),
            title: '서버 미연결',
            subtitle: '아래에서 서버 주소와 계정을 입력하고 연결하세요.',
          ),
        _Status.connecting => const _CardContent(
            icon: Icons.sync,
            iconColor: Color(0xFFFACC15),
            title: '연결 중…',
            subtitle: 'Signaling 서버에 연결하고 있습니다.',
          ),
        _Status.connected => const _CardContent(
            icon: Icons.check_circle_outline,
            iconColor: Color(0xFF22C55E),
            title: '대기 중',
            subtitle: '연결 요청이 오면 승인/거부 팝업이 표시됩니다.',
          ),
        _Status.pending => const _CardContent(
            icon: Icons.notifications_active,
            iconColor: Color(0xFFF97316),
            title: '연결 요청 수신',
            subtitle: '승인 팝업을 확인해 주세요.',
          ),
        _Status.active => _CardContent(
            icon: Icons.monitor,
            iconColor: const Color(0xFF3B82F6),
            title: '세션 진행 중',
            subtitle: sessionId != null
                ? '세션 ID: ${sessionId!.substring(0, 8)}…\nCtrl+Alt+F12로 즉시 종료할 수 있습니다.'
                : 'Ctrl+Alt+F12로 즉시 종료할 수 있습니다.',
          ),
      },
    );
  }
}

class _CardContent extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  const _CardContent({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: iconColor, size: 24),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 14)),
              const SizedBox(height: 4),
              Text(subtitle,
                  style: const TextStyle(
                      color: Color(0xFF94A3B8), fontSize: 12, height: 1.5)),
            ],
          ),
        ),
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF7F1D1D).withOpacity(0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFDC2626).withOpacity(0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Color(0xFFF87171), size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Color(0xFFFCA5A5), fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _HintText extends StatelessWidget {
  const _HintText();

  @override
  Widget build(BuildContext context) {
    return const Text(
      '이 기기가 원격 연결 대상(피제어측)입니다.\n'
      '사내 LDAP 계정으로 로그인하면 IT 지원팀이 원격으로 접속을 요청할 수 있습니다.\n'
      '연결 전 반드시 사용자의 승인이 필요합니다.',
      style: TextStyle(
          color: Color(0xFF475569), fontSize: 12, height: 1.6),
    );
  }
}

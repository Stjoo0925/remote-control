// 설정 페이지
// 서버 주소, 사용자 계정 등을 입력하는 UI입니다.
// 트레이 아이콘 클릭 또는 최초 실행 시 표시됩니다.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  final _storage = const FlutterSecureStorage();
  final _serverController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _saving = false;
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    _loadSavedSettings();
  }

  Future<void> _loadSavedSettings() async {
    _serverController.text =
        await _storage.read(key: 'server_url') ?? 'https://remote.corp.local';
    _usernameController.text = await _storage.read(key: 'username') ?? '';
  }

  Future<void> _save() async {
    setState(() { _saving = true; _statusMessage = null; });

    await _storage.write(key: 'server_url', value: _serverController.text.trim());
    await _storage.write(key: 'username', value: _usernameController.text.trim());
    if (_passwordController.text.isNotEmpty) {
      await _storage.write(key: 'password', value: _passwordController.text);
    }

    setState(() {
      _saving = false;
      _statusMessage = '설정이 저장됐습니다.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A), // slate-900
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('원격 제어 에이전트 설정', style: TextStyle(fontSize: 16)),
        centerTitle: false,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _label('서버 주소'),
            _textField(_serverController, 'https://remote.corp.local'),
            const SizedBox(height: 16),

            _label('사번 / 아이디'),
            _textField(_usernameController, 'hong.gildong'),
            const SizedBox(height: 16),

            _label('비밀번호'),
            _textField(_passwordController, '••••••••', obscure: true),
            const SizedBox(height: 24),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF3B82F6),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('저장 및 연결', style: TextStyle(color: Colors.white)),
              ),
            ),

            if (_statusMessage != null) ...[
              const SizedBox(height: 12),
              Text(_statusMessage!, style: const TextStyle(color: Colors.green, fontSize: 13)),
            ],

            const Spacer(),
            const Text(
              '이 기기가 원격 연결 대상입니다.\n연결 요청이 오면 승인/거부 팝업이 표시됩니다.',
              style: TextStyle(color: Color(0xFF64748B), fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(text, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
  );

  Widget _textField(TextEditingController ctrl, String hint, {bool obscure = false}) =>
    TextField(
      controller: ctrl,
      obscureText: obscure,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFF475569)),
        filled: true,
        fillColor: const Color(0xFF1E293B),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF334155)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF334155)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF3B82F6)),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );

  @override
  void dispose() {
    _serverController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}

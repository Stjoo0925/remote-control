// Rust Core 래퍼
// flutter_rust_bridge가 자동 생성하는 코드를 감싸는 편의 클래스입니다.
// 실제 자동 생성 파일은 빌드 시 생성됩니다 (flutter_rust_bridge generate).
//
// Rust 모르는 개발자는 이 클래스의 메서드만 호출하면 됩니다.

class RustCore {
  RustCore._();

  /// Rust 엔진 초기화 (앱 시작 시 호출)
  static Future<void> init() async {
    // TODO: flutter_rust_bridge 초기화
    // await RustLib.init();
  }

  // ──────────────────────────────────────────
  // 화면 캡처
  // ──────────────────────────────────────────

  /// 캡처러 초기화 (모니터 인덱스: 0 = 주 모니터)
  static Future<void> initCapturer({int monitorIndex = 0}) async {
    // await initCapturer(monitorIndex: monitorIndex);
  }

  /// 현재 화면 프레임 캡처 (BGRA 바이트 배열)
  static Future<List<int>> captureFrame() async {
    // return await captureFrame();
    return [];
  }

  /// 화면 해상도 반환 [width, height]
  static Future<List<int>> getScreenSize() async {
    // return await getScreenSize();
    return [1920, 1080];
  }

  /// 모니터 수 반환
  static Future<int> getMonitorCount() async {
    // return await getMonitorCount();
    return 1;
  }

  // ──────────────────────────────────────────
  // 입력 제어
  // ──────────────────────────────────────────

  /// 입력 컨트롤러 초기화
  static Future<void> initInput() async {
    // await initInput();
  }

  /// 마우스 절대 좌표 이동
  static Future<void> sendMouseMove(int x, int y) async {
    // await sendMouseMove(x: x, y: y);
  }

  /// 마우스 버튼 이벤트 (button: 0=왼쪽, 1=오른쪽, 2=가운데)
  static Future<void> sendMouseButton(int button, bool pressed) async {
    // await sendMouseButton(button: button, pressed: pressed);
  }

  /// 마우스 스크롤
  static Future<void> sendMouseScroll(int deltaX, int deltaY) async {
    // await sendMouseScroll(deltaX: deltaX, deltaY: deltaY);
  }

  /// 키보드 이벤트
  static Future<void> sendKeyEvent(int keyCode, bool pressed) async {
    // await sendKeyEvent(keyCode: keyCode, pressed: pressed);
  }

  /// 텍스트 직접 입력
  static Future<void> typeText(String text) async {
    // await typeText(text: text);
  }

  // ──────────────────────────────────────────
  // 암호화
  // ──────────────────────────────────────────

  /// 새 AES-256-GCM 키 생성
  static Future<List<int>> generateEncryptionKey() async {
    // return await generateEncryptionKey();
    return [];
  }

  /// 데이터 암호화
  static Future<List<int>> encryptData(List<int> keyBytes, List<int> plaintext) async {
    // return await encryptData(keyBytes: keyBytes, plaintext: plaintext);
    return [];
  }

  /// 데이터 복호화
  static Future<List<int>> decryptData(List<int> keyBytes, List<int> ciphertext) async {
    // return await decryptData(keyBytes: keyBytes, ciphertext: ciphertext);
    return [];
  }
}

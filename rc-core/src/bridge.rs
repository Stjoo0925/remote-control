// Flutter ↔ Rust 브릿지 공개 API
// flutter_rust_bridge가 이 파일을 읽어 Dart 코드를 자동 생성합니다.
// Dart에서는 생성된 bridge/rust_core.dart 를 import해서 사용합니다.
//
// 사용 예 (Dart):
//   final frame = await captureScreen(monitorIndex: 0);
//   await sendMouseMove(x: 100, y: 200);

use crate::capture::ScreenCapturer;
use crate::input::InputController;
use crate::crypto::AesGcmCipher;
use std::sync::Mutex;

// --- 전역 상태 (싱글턴) ---

static CAPTURER: Mutex<Option<ScreenCapturer>> = Mutex::new(None);
static INPUT: Mutex<Option<InputController>> = Mutex::new(None);

// --- 초기화 ---

/// 화면 캡처 초기화. 앱 시작 시 한 번 호출.
pub fn init_capturer(monitor_index: usize) -> Result<(), String> {
    let capturer = ScreenCapturer::new(monitor_index).map_err(|e| e.to_string())?;
    *CAPTURER.lock().unwrap() = Some(capturer);
    Ok(())
}

/// 입력 제어 초기화. 앱 시작 시 한 번 호출.
pub fn init_input() -> Result<(), String> {
    let input = InputController::new().map_err(|e| e.to_string())?;
    *INPUT.lock().unwrap() = Some(input);
    Ok(())
}

// --- 화면 캡처 ---

/// 현재 프레임 캡처 → BGRA 바이트 배열 반환
pub fn capture_frame() -> Result<Vec<u8>, String> {
    CAPTURER
        .lock()
        .unwrap()
        .as_mut()
        .ok_or_else(|| "캡처러 미초기화. init_capturer() 먼저 호출하세요.".into())?
        .capture_frame()
        .map_err(|e| e.to_string())
}

/// 화면 해상도 반환 [width, height]
pub fn get_screen_size() -> Result<Vec<u32>, String> {
    let guard = CAPTURER.lock().unwrap();
    let c = guard.as_ref()
        .ok_or_else(|| "캡처러 미초기화".to_string())?;
    Ok(vec![c.width(), c.height()])
}

/// 연결된 모니터 수 반환
pub fn get_monitor_count() -> Result<usize, String> {
    ScreenCapturer::monitor_count().map_err(|e| e.to_string())
}

// --- 입력 제어 ---

/// 마우스 절대 좌표 이동
pub fn send_mouse_move(x: i32, y: i32) -> Result<(), String> {
    INPUT
        .lock()
        .unwrap()
        .as_mut()
        .ok_or_else(|| "입력 컨트롤러 미초기화".to_string())?
        .mouse_move(x, y)
        .map_err(|e| e.to_string())
}

/// 마우스 버튼 이벤트 (button: 0=왼쪽, 1=오른쪽, 2=가운데)
pub fn send_mouse_button(button: u8, pressed: bool) -> Result<(), String> {
    INPUT
        .lock()
        .unwrap()
        .as_mut()
        .ok_or_else(|| "입력 컨트롤러 미초기화".to_string())?
        .mouse_click(button, pressed)
        .map_err(|e| e.to_string())
}

/// 마우스 스크롤
pub fn send_mouse_scroll(delta_x: i32, delta_y: i32) -> Result<(), String> {
    INPUT
        .lock()
        .unwrap()
        .as_mut()
        .ok_or_else(|| "입력 컨트롤러 미초기화".to_string())?
        .mouse_scroll(delta_x, delta_y)
        .map_err(|e| e.to_string())
}

/// 키보드 이벤트
pub fn send_key_event(key_code: u32, pressed: bool) -> Result<(), String> {
    INPUT
        .lock()
        .unwrap()
        .as_mut()
        .ok_or_else(|| "입력 컨트롤러 미초기화".to_string())?
        .key_event(key_code, pressed)
        .map_err(|e| e.to_string())
}

/// 텍스트 직접 입력
pub fn type_text(text: String) -> Result<(), String> {
    INPUT
        .lock()
        .unwrap()
        .as_mut()
        .ok_or_else(|| "입력 컨트롤러 미초기화".to_string())?
        .type_text(&text)
        .map_err(|e| e.to_string())
}

// --- 암호화 ---

/// 새 AES-256-GCM 키 생성 → 키 바이트 반환
pub fn generate_encryption_key() -> Result<Vec<u8>, String> {
    AesGcmCipher::generate()
        .map(|c| c.key_bytes())
        .map_err(|e| e.to_string())
}

/// 데이터 암호화
pub fn encrypt_data(key_bytes: Vec<u8>, plaintext: Vec<u8>) -> Result<Vec<u8>, String> {
    AesGcmCipher::from_bytes(key_bytes)
        .and_then(|c| c.encrypt(&plaintext))
        .map_err(|e| e.to_string())
}

/// 데이터 복호화
pub fn decrypt_data(key_bytes: Vec<u8>, ciphertext: Vec<u8>) -> Result<Vec<u8>, String> {
    AesGcmCipher::from_bytes(key_bytes)
        .and_then(|c| c.decrypt(&ciphertext))
        .map_err(|e| e.to_string())
}

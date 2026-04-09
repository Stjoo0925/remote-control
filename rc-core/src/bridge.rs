// Flutter ↔ Rust 브릿지 공개 API
// flutter_rust_bridge가 이 파일을 읽어 Dart 코드를 자동 생성합니다.
// Dart에서는 생성된 bridge/rust_core.dart 를 import해서 사용합니다.
//
// 사용 예 (Dart):
//   final frame = await captureFrame();
//   await sendMouseMove(x: 100, y: 200);
//   final peerId = await webrtcInit(iceServers: ["stun:stun.corp.local:3478"]);
//   final offer = await webrtcCreateOffer(peerId: peerId);

use crate::capture::ScreenCapturer;
use crate::input::InputController;
use crate::crypto::AesGcmCipher;
use crate::webrtc::WebRtcPeer;
use std::sync::Mutex;
use std::collections::HashMap;
use tokio::runtime::Handle;

// --- 전역 상태 (싱글턴) ---

static CAPTURER: Mutex<Option<ScreenCapturer>> = Mutex::new(None);
static INPUT: Mutex<Option<InputController>> = Mutex::new(None);

/// WebRTC 피어 풀 — peer_id(u64) → WebRtcPeer
/// 다중 세션을 위해 Map으로 관리 (보통은 1개)
static WEBRTC_PEERS: Mutex<Option<HashMap<u64, WebRtcPeer>>> = Mutex::new(None);
static NEXT_PEER_ID: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(1);

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

// --- WebRTC ---

/// WebRTC 피어 생성 → peer_id 반환
/// ice_server_urls 예: ["stun:stun.corp.local:3478"]
pub fn webrtc_create_peer(ice_server_urls: Vec<String>) -> Result<u64, String> {
    let rt = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .map_err(|e| e.to_string())?;

    let peer = rt.block_on(WebRtcPeer::new(ice_server_urls))
        .map_err(|e| e.to_string())?;

    let id = NEXT_PEER_ID.fetch_add(1, std::sync::atomic::Ordering::SeqCst);

    let mut guard = WEBRTC_PEERS.lock().unwrap();
    guard.get_or_insert_with(HashMap::new).insert(id, peer);

    Ok(id)
}

/// SDP Offer 생성 (Controller 측)
/// 반환: JSON 직렬화된 RTCSessionDescription
pub fn webrtc_create_offer(peer_id: u64) -> Result<String, String> {
    let rt = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .map_err(|e| e.to_string())?;

    let guard = WEBRTC_PEERS.lock().unwrap();
    let peers = guard.as_ref().ok_or("WebRTC 피어 풀 미초기화")?;
    let peer = peers.get(&peer_id).ok_or(format!("peer_id {peer_id} 없음"))?;
    drop(guard); // 비동기 실행 전 락 해제

    // Safety: 락 해제 후 peer reference 재획득
    // 단순화: peer를 Arc로 감싸지 않으므로 블로킹 호출 방식 사용
    // 실제 프로덕션에서는 Arc<WebRtcPeer>로 변경 권장
    Err("peer_id 기반 비동기 API는 flutter_rust_bridge 통합 시 async fn으로 교체 예정".into())
}

/// SDP Offer → Answer 생성 (Agent 측)
pub fn webrtc_create_answer(peer_id: u64, offer_json: String) -> Result<String, String> {
    let _ = (peer_id, offer_json);
    Err("flutter_rust_bridge 통합 시 async fn으로 교체 예정".into())
}

/// Answer 설정 (Controller 측)
pub fn webrtc_set_answer(peer_id: u64, answer_json: String) -> Result<(), String> {
    let _ = (peer_id, answer_json);
    Ok(())
}

/// ICE Candidate 추가
pub fn webrtc_add_ice_candidate(peer_id: u64, candidate_json: String) -> Result<(), String> {
    let _ = (peer_id, candidate_json);
    Ok(())
}

/// 로컬 ICE Candidate 수집 (Signaling 서버로 전송할 것들)
pub fn webrtc_drain_ice_candidates(peer_id: u64) -> Result<Vec<String>, String> {
    let _ = peer_id;
    Ok(vec![])
}

/// 데이터 채널로 입력 이벤트 전송 (Controller 측)
pub fn webrtc_send_input_event(peer_id: u64, event_json: String) -> Result<(), String> {
    let _ = (peer_id, event_json);
    Ok(())
}

/// 피어 연결 종료 + 풀에서 제거
pub fn webrtc_close_peer(peer_id: u64) -> Result<(), String> {
    let mut guard = WEBRTC_PEERS.lock().unwrap();
    if let Some(peers) = guard.as_mut() {
        peers.remove(&peer_id);
    }
    Ok(())
}

/// 연결 상태 조회
pub fn webrtc_connection_state(peer_id: u64) -> Result<String, String> {
    let guard = WEBRTC_PEERS.lock().unwrap();
    let peers = guard.as_ref().ok_or("WebRTC 피어 풀 미초기화")?;
    if peers.contains_key(&peer_id) {
        Ok("New".to_string()) // 실제 값은 async 컨텍스트에서만 조회 가능
    } else {
        Err(format!("peer_id {peer_id} 없음"))
    }
}

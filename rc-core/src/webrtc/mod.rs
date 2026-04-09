// WebRTC 연결 관리 모듈
// webrtc-rs 크레이트 기반 피어 연결 생성, SDP Offer/Answer 처리, ICE Candidate 교환
//
// 흐름:
//   Controller(브라우저) ──Offer──► Agent(Rust) ──Answer──► Controller
//   양측 ICE Candidate 교환 후 P2P 연결 확립
//   연결 후 DataChannel "input" 으로 마우스/키보드 이벤트 수신

use std::sync::Arc;

use tokio::sync::Mutex;
use webrtc::api::interceptor_registry::register_default_interceptors;
use webrtc::api::media_engine::MediaEngine;
use webrtc::api::APIBuilder;
use webrtc::data_channel::data_channel_init::RTCDataChannelInit;
use webrtc::data_channel::RTCDataChannel;
use webrtc::ice_transport::ice_candidate::RTCIceCandidateInit;
use webrtc::ice_transport::ice_server::RTCIceServer;
use webrtc::interceptor::registry::Registry;
use webrtc::peer_connection::configuration::RTCConfiguration;
use webrtc::peer_connection::sdp::session_description::RTCSessionDescription;
use webrtc::peer_connection::RTCPeerConnection;

use crate::error::{RcError, Result};

// ─────────────────────────────────────────────────────────────
// WebRtcPeer — 피어 연결 + 데이터 채널 래퍼
// ─────────────────────────────────────────────────────────────

pub struct WebRtcPeer {
    peer_connection: Arc<RTCPeerConnection>,
    /// Controller 측이 생성하는 데이터 채널 (입력 이벤트 전송)
    data_channel: Arc<Mutex<Option<Arc<RTCDataChannel>>>>,
    /// ICE Candidate 버퍼 (로컬 생성 즉시 Signaling 서버로 보내야 함)
    ice_candidates: Arc<Mutex<Vec<String>>>,
}

impl WebRtcPeer {
    // ─────────────────────────────────────────────────────────
    // 생성
    // ─────────────────────────────────────────────────────────

    /// ICE 서버 URL 목록으로 피어 연결 초기화
    /// ice_server_urls 예시: vec!["stun:stun.corp.local:3478", "turn:turn.corp.local:3478"]
    pub async fn new(ice_server_urls: Vec<String>) -> Result<Self> {
        // MediaEngine — 기본 코덱 등록 (데이터 채널만 사용하지만 필수)
        let mut m = MediaEngine::default();
        m.register_default_codecs()
            .map_err(|e| RcError::WebRtcError(format!("MediaEngine 초기화 실패: {e}")))?;

        // Interceptor 레지스트리 (RTCP, NACK, TWCC 등)
        let mut registry = Registry::new();
        registry = register_default_interceptors(registry, &mut m)
            .map_err(|e| RcError::WebRtcError(format!("Interceptor 등록 실패: {e}")))?;

        let api = APIBuilder::new()
            .with_media_engine(m)
            .with_interceptor_registry(registry)
            .build();

        let ice_servers = ice_server_urls
            .into_iter()
            .map(|url| RTCIceServer {
                urls: vec![url],
                ..Default::default()
            })
            .collect();

        let config = RTCConfiguration {
            ice_servers,
            ..Default::default()
        };

        let peer_connection = Arc::new(
            api.new_peer_connection(config)
                .await
                .map_err(|e| RcError::WebRtcError(format!("피어 연결 생성 실패: {e}")))?,
        );

        let ice_candidates = Arc::new(Mutex::new(Vec::<String>::new()));
        let ice_buf = Arc::clone(&ice_candidates);

        // ICE Candidate 로컬 수집 → 버퍼에 저장
        peer_connection.on_ice_candidate(Box::new(move |c| {
            let buf = Arc::clone(&ice_buf);
            Box::pin(async move {
                if let Some(candidate) = c {
                    if let Ok(json) = candidate.to_json() {
                        if let Ok(s) = serde_json::to_string(&json) {
                            buf.lock().await.push(s);
                        }
                    }
                }
            })
        }));

        Ok(Self {
            peer_connection,
            data_channel: Arc::new(Mutex::new(None)),
            ice_candidates,
        })
    }

    // ─────────────────────────────────────────────────────────
    // Controller 측 (Offer)
    // ─────────────────────────────────────────────────────────

    /// SDP Offer 생성 (Controller 측에서 호출)
    /// 반환값: JSON 직렬화된 RTCSessionDescription
    pub async fn create_offer(&self) -> Result<String> {
        // 입력 이벤트 전송용 데이터 채널 생성
        let dc = self
            .peer_connection
            .create_data_channel(
                "input",
                Some(RTCDataChannelInit {
                    ordered: Some(true),
                    ..Default::default()
                }),
            )
            .await
            .map_err(|e| RcError::WebRtcError(format!("DataChannel 생성 실패: {e}")))?;

        *self.data_channel.lock().await = Some(dc);

        let offer = self
            .peer_connection
            .create_offer(None)
            .await
            .map_err(|e| RcError::WebRtcError(format!("Offer 생성 실패: {e}")))?;

        self.peer_connection
            .set_local_description(offer.clone())
            .await
            .map_err(|e| RcError::WebRtcError(format!("LocalDescription 설정 실패: {e}")))?;

        serde_json::to_string(&offer)
            .map_err(|e| RcError::WebRtcError(format!("Offer 직렬화 실패: {e}")))
    }

    // ─────────────────────────────────────────────────────────
    // Agent 측 (Answer)
    // ─────────────────────────────────────────────────────────

    /// SDP Offer 수신 후 Answer 생성 (Agent 측에서 호출)
    /// offer_json: create_offer()가 반환한 JSON 문자열
    /// 반환값: JSON 직렬화된 RTCSessionDescription (Answer)
    pub async fn create_answer(&self, offer_json: String) -> Result<String> {
        let offer: RTCSessionDescription = serde_json::from_str(&offer_json)
            .map_err(|e| RcError::WebRtcError(format!("Offer 파싱 실패: {e}")))?;

        self.peer_connection
            .set_remote_description(offer)
            .await
            .map_err(|e| RcError::WebRtcError(format!("RemoteDescription(offer) 설정 실패: {e}")))?;

        let answer = self
            .peer_connection
            .create_answer(None)
            .await
            .map_err(|e| RcError::WebRtcError(format!("Answer 생성 실패: {e}")))?;

        self.peer_connection
            .set_local_description(answer.clone())
            .await
            .map_err(|e| RcError::WebRtcError(format!("LocalDescription(answer) 설정 실패: {e}")))?;

        serde_json::to_string(&answer)
            .map_err(|e| RcError::WebRtcError(format!("Answer 직렬화 실패: {e}")))
    }

    // ─────────────────────────────────────────────────────────
    // Controller 측 — Answer 수신
    // ─────────────────────────────────────────────────────────

    /// Agent가 반환한 Answer를 Controller 측에서 설정
    pub async fn set_answer(&self, answer_json: String) -> Result<()> {
        let answer: RTCSessionDescription = serde_json::from_str(&answer_json)
            .map_err(|e| RcError::WebRtcError(format!("Answer 파싱 실패: {e}")))?;

        self.peer_connection
            .set_remote_description(answer)
            .await
            .map_err(|e| RcError::WebRtcError(format!("RemoteDescription(answer) 설정 실패: {e}")))
    }

    // ─────────────────────────────────────────────────────────
    // ICE Candidate
    // ─────────────────────────────────────────────────────────

    /// 상대방의 ICE Candidate 추가
    /// candidate_json: RTCIceCandidateInit JSON 문자열
    pub async fn add_ice_candidate(&self, candidate_json: String) -> Result<()> {
        let candidate: RTCIceCandidateInit = serde_json::from_str(&candidate_json)
            .map_err(|e| RcError::WebRtcError(format!("ICE Candidate 파싱 실패: {e}")))?;

        self.peer_connection
            .add_ice_candidate(candidate)
            .await
            .map_err(|e| RcError::WebRtcError(format!("ICE Candidate 추가 실패: {e}")))
    }

    /// 로컬에서 수집된 ICE Candidate를 모두 꺼냄 (Signaling 서버로 전송 후 삭제)
    pub async fn drain_ice_candidates(&self) -> Vec<String> {
        let mut buf = self.ice_candidates.lock().await;
        std::mem::take(&mut *buf)
    }

    // ─────────────────────────────────────────────────────────
    // 데이터 채널 (입력 이벤트)
    // ─────────────────────────────────────────────────────────

    /// 데이터 채널로 입력 이벤트 JSON 전송 (Controller 측에서 호출)
    /// event_json 형식: {"type":"mouse_move","x":100,"y":200}
    pub async fn send_input_event(&self, event_json: String) -> Result<()> {
        let dc_guard = self.data_channel.lock().await;
        let dc = dc_guard
            .as_ref()
            .ok_or_else(|| RcError::WebRtcError("데이터 채널 미초기화 — create_offer() 먼저 호출".into()))?;

        dc.send_text(event_json)
            .await
            .map_err(|e| RcError::WebRtcError(format!("DataChannel 전송 실패: {e}")))
    }

    // ─────────────────────────────────────────────────────────
    // 종료
    // ─────────────────────────────────────────────────────────

    /// 피어 연결 종료
    pub async fn close(&self) -> Result<()> {
        self.peer_connection
            .close()
            .await
            .map_err(|e| RcError::WebRtcError(format!("연결 종료 실패: {e}")))
    }

    /// 현재 연결 상태 문자열 반환
    pub async fn connection_state(&self) -> String {
        format!("{:?}", self.peer_connection.connection_state())
    }
}

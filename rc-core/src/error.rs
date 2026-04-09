// 공통 에러 타입

use thiserror::Error;

#[derive(Error, Debug)]
pub enum RcError {
    #[error("화면 캡처 실패: {0}")]
    CaptureError(String),

    #[error("입력 제어 실패: {0}")]
    InputError(String),

    #[error("WebRTC 오류: {0}")]
    WebRtcError(String),

    #[error("암호화 오류: {0}")]
    CryptoError(String),

    #[error("초기화되지 않음: {0}")]
    NotInitialized(String),
}

pub type Result<T> = std::result::Result<T, RcError>;

// 화면 캡처 모듈
// scrap 크레이트로 플랫폼별 화면 캡처를 통일된 인터페이스로 제공합니다.
// Windows: DXGI Desktop Duplication API (GPU 가속)
// macOS: CGDisplayStream
// Linux: X11 / PipeWire

use scrap::{Capturer, Display};
use crate::error::{RcError, Result};

pub struct ScreenCapturer {
    capturer: Capturer,
    width: u32,
    height: u32,
}

impl ScreenCapturer {
    /// 지정한 모니터 인덱스로 캡처러 초기화
    pub fn new(monitor_index: usize) -> Result<Self> {
        let displays = Display::all()
            .map_err(|e| RcError::CaptureError(e.to_string()))?;

        let display = displays
            .into_iter()
            .nth(monitor_index)
            .ok_or_else(|| RcError::CaptureError(format!("모니터 {}번 없음", monitor_index)))?;

        let width = display.width() as u32;
        let height = display.height() as u32;

        let capturer = Capturer::new(display)
            .map_err(|e| RcError::CaptureError(e.to_string()))?;

        Ok(Self { capturer, width, height })
    }

    /// 현재 프레임 캡처 (BGRA 바이트 배열 반환)
    pub fn capture_frame(&mut self) -> Result<Vec<u8>> {
        use std::io::ErrorKind;

        loop {
            match self.capturer.frame() {
                Ok(frame) => return Ok(frame.to_vec()),
                Err(e) if e.kind() == ErrorKind::WouldBlock => {
                    // 아직 프레임 준비 안 됨 — 재시도
                    std::thread::sleep(std::time::Duration::from_millis(1));
                    continue;
                }
                Err(e) => return Err(RcError::CaptureError(e.to_string())),
            }
        }
    }

    pub fn width(&self) -> u32 { self.width }
    pub fn height(&self) -> u32 { self.height }

    /// 연결된 모니터 수 반환
    pub fn monitor_count() -> Result<usize> {
        Display::all()
            .map(|d| d.len())
            .map_err(|e| RcError::CaptureError(e.to_string()))
    }
}

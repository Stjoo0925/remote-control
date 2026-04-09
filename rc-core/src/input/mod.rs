// 입력 제어 모듈
// enigo 크레이트로 플랫폼별 마우스/키보드 이벤트를 통일된 인터페이스로 제공합니다.
// Windows: SendInput API
// macOS: CGEvent
// Linux: uinput / X11 XTest

use enigo::{Enigo, Mouse, Keyboard, Settings, Button, Direction, Key, Coordinate};
use crate::error::{RcError, Result};

pub struct InputController {
    enigo: Enigo,
}

impl InputController {
    pub fn new() -> Result<Self> {
        let enigo = Enigo::new(&Settings::default())
            .map_err(|e| RcError::InputError(e.to_string()))?;
        Ok(Self { enigo })
    }

    /// 절대 좌표로 마우스 이동
    pub fn mouse_move(&mut self, x: i32, y: i32) -> Result<()> {
        self.enigo.move_mouse(x, y, Coordinate::Abs)
            .map_err(|e| RcError::InputError(e.to_string()))
    }

    /// 마우스 버튼 클릭
    /// button: 0=왼쪽, 1=오른쪽, 2=가운데
    pub fn mouse_click(&mut self, button: u8, pressed: bool) -> Result<()> {
        let btn = match button {
            0 => Button::Left,
            1 => Button::Right,
            2 => Button::Middle,
            _ => Button::Left,
        };
        let dir = if pressed { Direction::Press } else { Direction::Release };
        self.enigo.button(btn, dir)
            .map_err(|e| RcError::InputError(e.to_string()))
    }

    /// 마우스 스크롤
    pub fn mouse_scroll(&mut self, delta_x: i32, delta_y: i32) -> Result<()> {
        if delta_y != 0 {
            self.enigo.scroll(delta_y, enigo::Axis::Vertical)
                .map_err(|e| RcError::InputError(e.to_string()))?;
        }
        if delta_x != 0 {
            self.enigo.scroll(delta_x, enigo::Axis::Horizontal)
                .map_err(|e| RcError::InputError(e.to_string()))?;
        }
        Ok(())
    }

    /// 키보드 이벤트
    /// key_code: USB HID 키코드
    pub fn key_event(&mut self, key_code: u32, pressed: bool) -> Result<()> {
        let key = Key::Other(key_code);
        let dir = if pressed { Direction::Press } else { Direction::Release };
        self.enigo.key(key, dir)
            .map_err(|e| RcError::InputError(e.to_string()))
    }

    /// 텍스트 직접 입력 (클립보드 붙여넣기 방식)
    pub fn type_text(&mut self, text: &str) -> Result<()> {
        self.enigo.text(text)
            .map_err(|e| RcError::InputError(e.to_string()))
    }
}

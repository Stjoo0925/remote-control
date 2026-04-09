// 암호화 모듈
// ring 크레이트 기반 AES-256-GCM 암호화/복호화
// 파일 전송 시 추가 레이어 암호화에 사용됩니다.

use ring::aead::{self, BoundKey, Aad, NONCE_LEN};
use ring::rand::{self, SecureRandom};
use crate::error::{RcError, Result};

const KEY_LEN: usize = 32; // AES-256

pub struct AesGcmCipher {
    key_bytes: [u8; KEY_LEN],
}

impl AesGcmCipher {
    /// 새 랜덤 키 생성
    pub fn generate() -> Result<Self> {
        let rng = rand::SystemRandom::new();
        let mut key_bytes = [0u8; KEY_LEN];
        rng.fill(&mut key_bytes)
            .map_err(|_| RcError::CryptoError("키 생성 실패".into()))?;
        Ok(Self { key_bytes })
    }

    /// 기존 키로 초기화 (bytes 길이는 32여야 함)
    pub fn from_bytes(key_bytes: Vec<u8>) -> Result<Self> {
        let key_bytes: [u8; KEY_LEN] = key_bytes
            .try_into()
            .map_err(|_| RcError::CryptoError("키 길이가 32바이트여야 합니다".into()))?;
        Ok(Self { key_bytes })
    }

    pub fn key_bytes(&self) -> Vec<u8> {
        self.key_bytes.to_vec()
    }

    /// 데이터 암호화 → nonce(12) + ciphertext + tag(16) 반환
    pub fn encrypt(&self, plaintext: &[u8]) -> Result<Vec<u8>> {
        let rng = rand::SystemRandom::new();
        let mut nonce_bytes = [0u8; NONCE_LEN];
        rng.fill(&mut nonce_bytes)
            .map_err(|_| RcError::CryptoError("nonce 생성 실패".into()))?;

        let unbound_key = aead::UnboundKey::new(&aead::AES_256_GCM, &self.key_bytes)
            .map_err(|_| RcError::CryptoError("키 초기화 실패".into()))?;

        let nonce_seq = OneNonce(Some(aead::Nonce::assume_unique_for_key(nonce_bytes)));
        let mut sealing_key = aead::SealingKey::new(unbound_key, nonce_seq);

        let mut in_out = plaintext.to_vec();
        sealing_key
            .seal_in_place_append_tag(Aad::empty(), &mut in_out)
            .map_err(|_| RcError::CryptoError("암호화 실패".into()))?;

        // nonce + ciphertext+tag
        let mut result = nonce_bytes.to_vec();
        result.extend_from_slice(&in_out);
        Ok(result)
    }

    /// 데이터 복호화 (nonce(12) + ciphertext + tag(16) 형식)
    pub fn decrypt(&self, data: &[u8]) -> Result<Vec<u8>> {
        if data.len() < NONCE_LEN {
            return Err(RcError::CryptoError("데이터가 너무 짧습니다".into()));
        }

        let (nonce_bytes, ciphertext) = data.split_at(NONCE_LEN);
        let nonce = aead::Nonce::try_assume_unique_for_key(nonce_bytes)
            .map_err(|_| RcError::CryptoError("nonce 변환 실패".into()))?;

        let unbound_key = aead::UnboundKey::new(&aead::AES_256_GCM, &self.key_bytes)
            .map_err(|_| RcError::CryptoError("키 초기화 실패".into()))?;

        let nonce_seq = OneNonce(Some(nonce));
        let mut opening_key = aead::OpeningKey::new(unbound_key, nonce_seq);

        let mut in_out = ciphertext.to_vec();
        let plaintext = opening_key
            .open_in_place(Aad::empty(), &mut in_out)
            .map_err(|_| RcError::CryptoError("복호화 실패 (키 불일치 또는 데이터 손상)".into()))?;

        Ok(plaintext.to_vec())
    }
}

/// 단일 nonce 제공자
struct OneNonce(Option<aead::Nonce>);

impl aead::NonceSequence for OneNonce {
    fn advance(&mut self) -> std::result::Result<aead::Nonce, ring::error::Unspecified> {
        self.0.take().ok_or(ring::error::Unspecified)
    }
}

# 로컬 인증 제공자
# LDAP 없이 이메일/비밀번호로 사용자 인증합니다.
# bcrypt 해시로 비밀번호를 저장하며 LDAP이 없는 외부 사용자에 사용됩니다.

import logging
from typing import Optional

import bcrypt

logger = logging.getLogger(__name__)


class LocalAuthProvider:
    def hash_password(self, password: str) -> str:
        """bcrypt로 비밀번호 해시 생성"""
        return bcrypt.hashpw(password.encode(), bcrypt.gensalt(rounds=12)).decode()

    def verify_password(self, password: str, password_hash: str) -> bool:
        """비밀번호와 저장된 해시 비교"""
        try:
            return bcrypt.checkpw(password.encode(), password_hash.encode())
        except Exception:
            return False

    def validate_password_strength(self, password: str) -> Optional[str]:
        """비밀번호 강도 검사. 통과 시 None, 실패 시 오류 메시지 반환."""
        if len(password) < 8:
            return "비밀번호는 8자 이상이어야 합니다."
        if not any(c.isupper() for c in password):
            return "비밀번호에 대문자가 포함되어야 합니다."
        if not any(c.islower() for c in password):
            return "비밀번호에 소문자가 포함되어야 합니다."
        if not any(c.isdigit() for c in password):
            return "비밀번호에 숫자가 포함되어야 합니다."
        return None


local_provider = LocalAuthProvider()

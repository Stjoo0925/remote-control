# LDAP/AD 인증 제공자
# 사내 Active Directory 또는 LDAP 서버로 사용자 인증을 처리합니다.

import logging
from typing import Optional
from ldap3 import Server, Connection, ALL, SUBTREE
from ldap3.core.exceptions import LDAPException

from app.config import settings

logger = logging.getLogger(__name__)


class LDAPAuthProvider:
    def __init__(self):
        self._server = Server(settings.LDAP_SERVER, get_info=ALL)

    def authenticate(self, username: str, password: str) -> Optional[dict]:
        """
        LDAP 바인딩으로 사용자 인증.
        성공 시 사용자 정보 dict 반환, 실패 시 None 반환.
        """
        if not username or not password:
            return None

        # 사용자 DN 조회를 위해 서비스 계정으로 먼저 바인딩
        user_dn = self._find_user_dn(username)
        if not user_dn:
            logger.warning("LDAP: 사용자 '%s' 를 찾을 수 없음", username)
            return None

        # 실제 사용자 자격증명으로 바인딩 (비밀번호 검증)
        try:
            conn = Connection(
                self._server,
                user=user_dn,
                password=password,
                auto_bind=True,
            )
            conn.unbind()

            user_info = self.get_user_info(username)
            logger.info("LDAP: 인증 성공 — %s", username)
            return user_info

        except LDAPException as e:
            logger.warning("LDAP: 인증 실패 — %s (%s)", username, type(e).__name__)
            return None

    def get_user_info(self, username: str) -> Optional[dict]:
        """사용자 속성 조회 (메일, 표시이름, 그룹)"""
        try:
            conn = Connection(
                self._server,
                user=settings.LDAP_BIND_DN,
                password=settings.LDAP_BIND_PASSWORD,
                auto_bind=True,
            )
            conn.search(
                search_base=settings.LDAP_BASE_DN,
                search_filter=f"(sAMAccountName={username})",
                search_scope=SUBTREE,
                attributes=["mail", "displayName", "sAMAccountName", "memberOf"],
            )
            if not conn.entries:
                return None

            entry = conn.entries[0]
            conn.unbind()

            return {
                "username": str(entry.sAMAccountName),
                "email": str(entry.mail) if entry.mail else f"{username}@corp.local",
                "display_name": str(entry.displayName) if entry.displayName else username,
                "groups": [str(g) for g in entry.memberOf] if entry.memberOf else [],
            }
        except LDAPException as e:
            logger.error("LDAP: 사용자 정보 조회 실패 — %s", e)
            return None

    def _find_user_dn(self, username: str) -> Optional[str]:
        """서비스 계정으로 사용자 DN 조회"""
        try:
            conn = Connection(
                self._server,
                user=settings.LDAP_BIND_DN,
                password=settings.LDAP_BIND_PASSWORD,
                auto_bind=True,
            )
            conn.search(
                search_base=settings.LDAP_BASE_DN,
                search_filter=f"(sAMAccountName={username})",
                search_scope=SUBTREE,
                attributes=["distinguishedName"],
            )
            if not conn.entries:
                return None
            dn = conn.entries[0].entry_dn
            conn.unbind()
            return dn
        except LDAPException:
            return None


ldap_provider = LDAPAuthProvider()

# LDAP/AD 인증 제공자
# AUTH_MODE=ldap 또는 both 일 때만 사용됩니다.
# LDAP_SERVER가 설정되지 않으면 항상 None을 반환해 앱이 정상 동작합니다.

import logging
from typing import Optional

from app.config import settings

logger = logging.getLogger(__name__)


class LDAPAuthProvider:
    @property
    def _enabled(self) -> bool:
        return bool(settings.LDAP_SERVER)

    def authenticate(self, username: str, password: str) -> Optional[dict]:
        """
        LDAP 바인딩으로 사용자 인증.
        LDAP_SERVER가 설정되지 않았거나 연결 실패 시 None 반환 (앱은 계속 동작).
        """
        if not self._enabled:
            return None
        if not username or not password:
            return None

        try:
            from ldap3 import Server, Connection, ALL, SUBTREE
            from ldap3.core.exceptions import LDAPException

            server = Server(settings.LDAP_SERVER, get_info=ALL)
            user_dn = self._find_user_dn(server, username)
            if not user_dn:
                logger.warning("LDAP: 사용자 '%s' 를 찾을 수 없음", username)
                return None

            conn = Connection(server, user=user_dn, password=password, auto_bind=True)
            conn.unbind()
            user_info = self._get_user_info(server, username)
            logger.info("LDAP: 인증 성공 — %s", username)
            return user_info

        except ImportError:
            logger.warning("LDAP: ldap3 패키지가 설치되지 않았습니다.")
            return None
        except Exception as e:
            logger.warning("LDAP: 인증 실패 — %s (%s)", username, type(e).__name__)
            return None

    def _get_user_info(self, server, username: str) -> Optional[dict]:
        try:
            from ldap3 import Connection, SUBTREE
            conn = Connection(
                server,
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
                "email": str(entry.mail) if entry.mail else f"{username}@example.com",
                "display_name": str(entry.displayName) if entry.displayName else username,
                "groups": [str(g) for g in entry.memberOf] if entry.memberOf else [],
            }
        except Exception as e:
            logger.error("LDAP: 사용자 정보 조회 실패 — %s", e)
            return None

    def _find_user_dn(self, server, username: str) -> Optional[str]:
        try:
            from ldap3 import Connection, SUBTREE
            conn = Connection(
                server,
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
        except Exception:
            return None


ldap_provider = LDAPAuthProvider()

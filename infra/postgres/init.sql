-- 원격 제어 시스템 초기 DB 설정

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- 역할 enum
CREATE TYPE user_role AS ENUM ('admin', 'support', 'user');

-- 세션 상태 enum
CREATE TYPE session_status AS ENUM ('pending', 'active', 'ended', 'rejected');

-- 기본 관리자 계정 (LDAP 없는 로컬 테스트용)
-- 실제 운영 시 LDAP으로 대체
INSERT INTO users (id, username, email, display_name, role, is_active, created_at)
VALUES (
    uuid_generate_v4(),
    'admin',
    'admin@corp.local',
    '시스템 관리자',
    'admin',
    true,
    NOW()
) ON CONFLICT DO NOTHING;

// 공통 TypeScript 타입 정의

export type Role = "admin" | "support" | "user";

export interface UserInfo {
  id: string;
  username: string;
  email: string;
  display_name: string;
  role: Role;
}

export interface TokenResponse {
  access_token: string;
  refresh_token: string;
  token_type: string;
  expires_in: number;
}

export interface Session {
  id: string;
  controller_id: string;
  target_id: string;
  status: "pending" | "active" | "ended" | "rejected";
  started_at: string | null;
  created_at: string;
}

export interface AuditLog {
  id: string;
  user_id: string | null;
  action: string;
  target: string | null;
  ip_address: string | null;
  details: Record<string, unknown> | null;
  created_at: string;
}

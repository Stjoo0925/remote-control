/**
 * AdminDashboard — 관리자 전용 대시보드
 * 탭: 세션 현황 | 사용자 관리 | 감사 로그
 */

import { useEffect, useState, useCallback } from "react";
import {
  Monitor, Users, Shield, RefreshCw, Trash2, ChevronLeft, ChevronRight,
  CheckCircle, Clock, XCircle, User, Crown,
} from "lucide-react";
import client from "@/shared/api/client";
import type { Session, UserInfo, AuditLog } from "@/shared/types";

type Tab = "sessions" | "users" | "logs";
type Role = "admin" | "support" | "user";

// ─────────────────────────────────────────────────────────────
// 메인 컴포넌트
// ─────────────────────────────────────────────────────────────

export default function AdminDashboard() {
  const [tab, setTab] = useState<Tab>("sessions");

  return (
    <div className="min-h-screen bg-slate-900 text-white">
      <header className="bg-slate-800 border-b border-slate-700 px-6 py-4 flex items-center gap-3">
        <div className="bg-purple-600 p-1.5 rounded-lg">
          <Shield className="w-5 h-5" />
        </div>
        <span className="font-semibold">관리자 대시보드</span>
      </header>

      {/* 탭 */}
      <div className="bg-slate-800 border-b border-slate-700 px-6 flex gap-1">
        {([
          { id: "sessions", label: "세션 현황", icon: Monitor },
          { id: "users",    label: "사용자 관리", icon: Users },
          { id: "logs",     label: "감사 로그",   icon: Shield },
        ] as { id: Tab; label: string; icon: React.ElementType }[]).map(({ id, label, icon: Icon }) => (
          <button
            key={id}
            onClick={() => setTab(id)}
            className={`flex items-center gap-2 px-4 py-3 text-sm border-b-2 transition-colors ${
              tab === id
                ? "border-blue-500 text-white"
                : "border-transparent text-slate-400 hover:text-white"
            }`}
          >
            <Icon className="w-4 h-4" />
            {label}
          </button>
        ))}
      </div>

      <div className="max-w-6xl mx-auto px-6 py-8">
        {tab === "sessions" && <SessionsTab />}
        {tab === "users"    && <UsersTab />}
        {tab === "logs"     && <AuditLogsTab />}
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// 세션 현황 탭
// ─────────────────────────────────────────────────────────────

function SessionsTab() {
  const [sessions, setSessions] = useState<Session[]>([]);
  const [loading, setLoading]   = useState(false);
  const [filter, setFilter]     = useState<string>("");

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const { data } = await client.get<Session[]>("/admin/sessions", {
        params: filter ? { status_filter: filter } : {},
      });
      setSessions(data);
    } finally {
      setLoading(false);
    }
  }, [filter]);

  useEffect(() => { load(); }, [load]);

  const forceEnd = async (id: string) => {
    await client.delete(`/admin/sessions/${id}`);
    setSessions((prev) => prev.map((s) => s.id === id ? { ...s, status: "ended" } : s));
  };

  const statusBadge = (status: Session["status"]) => {
    const map = {
      pending:  { label: "대기",   cls: "text-yellow-400 bg-yellow-400/10", Icon: Clock },
      active:   { label: "진행",   cls: "text-green-400 bg-green-400/10",   Icon: CheckCircle },
      ended:    { label: "종료",   cls: "text-slate-400 bg-slate-400/10",   Icon: XCircle },
      rejected: { label: "거부",   cls: "text-red-400 bg-red-400/10",       Icon: XCircle },
    };
    const { label, cls, Icon } = map[status];
    return (
      <span className={`inline-flex items-center gap-1 text-xs px-2 py-0.5 rounded-full font-medium ${cls}`}>
        <Icon className="w-3 h-3" />{label}
      </span>
    );
  };

  return (
    <div>
      <div className="flex items-center justify-between mb-5">
        <h2 className="text-lg font-medium">세션 현황</h2>
        <div className="flex items-center gap-3">
          <select
            value={filter}
            onChange={(e) => setFilter(e.target.value)}
            className="bg-slate-800 border border-slate-600 text-sm rounded-lg px-3 py-1.5 text-white"
          >
            <option value="">전체</option>
            <option value="pending">대기</option>
            <option value="active">진행 중</option>
            <option value="ended">종료</option>
          </select>
          <button
            onClick={load}
            className="flex items-center gap-1.5 text-slate-400 hover:text-white text-sm transition-colors"
          >
            <RefreshCw className={`w-4 h-4 ${loading ? "animate-spin" : ""}`} />
            새로고침
          </button>
        </div>
      </div>

      {sessions.length === 0 ? (
        <div className="bg-slate-800 rounded-xl p-12 text-center text-slate-500">
          세션이 없습니다
        </div>
      ) : (
        <div className="bg-slate-800 rounded-xl overflow-hidden">
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b border-slate-700 text-slate-400 text-xs uppercase">
                <th className="text-left px-4 py-3">세션 ID</th>
                <th className="text-left px-4 py-3">상태</th>
                <th className="text-left px-4 py-3">시작 시각</th>
                <th className="text-right px-4 py-3">액션</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-700">
              {sessions.map((s) => (
                <tr key={s.id} className="hover:bg-slate-750 transition-colors">
                  <td className="px-4 py-3 font-mono text-xs text-slate-300">
                    {s.id.slice(0, 8)}…
                  </td>
                  <td className="px-4 py-3">{statusBadge(s.status)}</td>
                  <td className="px-4 py-3 text-slate-400 text-xs">
                    {new Date(s.created_at).toLocaleString("ko-KR")}
                  </td>
                  <td className="px-4 py-3 text-right">
                    {s.status === "active" && (
                      <button
                        onClick={() => forceEnd(s.id)}
                        className="text-red-400 hover:text-red-300 text-xs flex items-center gap-1 ml-auto transition-colors"
                      >
                        <Trash2 className="w-3.5 h-3.5" /> 강제 종료
                      </button>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// 사용자 관리 탭
// ─────────────────────────────────────────────────────────────

function UsersTab() {
  const [users, setUsers]     = useState<UserInfo[]>([]);
  const [loading, setLoading] = useState(false);

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const { data } = await client.get<UserInfo[]>("/admin/users");
      setUsers(data);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => { load(); }, [load]);

  const updateRole = async (userId: string, role: Role) => {
    await client.patch(`/admin/users/${userId}/role`, { role });
    setUsers((prev) =>
      prev.map((u) => (u.id === userId ? { ...u, role } : u))
    );
  };

  const roleIcon = (role: Role) => {
    if (role === "admin")   return <Crown className="w-3.5 h-3.5 text-yellow-400" />;
    if (role === "support") return <Shield className="w-3.5 h-3.5 text-blue-400" />;
    return <User className="w-3.5 h-3.5 text-slate-400" />;
  };

  return (
    <div>
      <div className="flex items-center justify-between mb-5">
        <h2 className="text-lg font-medium">사용자 관리</h2>
        <button
          onClick={load}
          className="flex items-center gap-1.5 text-slate-400 hover:text-white text-sm transition-colors"
        >
          <RefreshCw className={`w-4 h-4 ${loading ? "animate-spin" : ""}`} />
          새로고침
        </button>
      </div>

      <div className="bg-slate-800 rounded-xl overflow-hidden">
        <table className="w-full text-sm">
          <thead>
            <tr className="border-b border-slate-700 text-slate-400 text-xs uppercase">
              <th className="text-left px-4 py-3">사용자</th>
              <th className="text-left px-4 py-3">이메일</th>
              <th className="text-left px-4 py-3">현재 역할</th>
              <th className="text-right px-4 py-3">역할 변경</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-slate-700">
            {users.map((u) => (
              <tr key={u.id} className="hover:bg-slate-750 transition-colors">
                <td className="px-4 py-3">
                  <div className="flex items-center gap-2">
                    {roleIcon(u.role as Role)}
                    <div>
                      <p className="text-white font-medium">{u.display_name}</p>
                      <p className="text-xs text-slate-500">{u.username}</p>
                    </div>
                  </div>
                </td>
                <td className="px-4 py-3 text-slate-400 text-xs">{u.email}</td>
                <td className="px-4 py-3">
                  <RoleBadge role={u.role as Role} />
                </td>
                <td className="px-4 py-3 text-right">
                  <select
                    value={u.role}
                    onChange={(e) => updateRole(u.id, e.target.value as Role)}
                    className="bg-slate-700 border border-slate-600 text-xs rounded-lg px-2 py-1 text-white cursor-pointer"
                  >
                    <option value="user">user</option>
                    <option value="support">support</option>
                    <option value="admin">admin</option>
                  </select>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}

function RoleBadge({ role }: { role: Role }) {
  const map: Record<Role, { label: string; cls: string }> = {
    admin:   { label: "관리자",    cls: "text-yellow-400 bg-yellow-400/10" },
    support: { label: "지원 담당자", cls: "text-blue-400 bg-blue-400/10" },
    user:    { label: "일반 사용자", cls: "text-slate-400 bg-slate-400/10" },
  };
  const { label, cls } = map[role];
  return (
    <span className={`inline-block text-xs px-2 py-0.5 rounded-full font-medium ${cls}`}>
      {label}
    </span>
  );
}

// ─────────────────────────────────────────────────────────────
// 감사 로그 탭
// ─────────────────────────────────────────────────────────────

interface AuditLogsResponse {
  page: number;
  size: number;
  items: AuditLog[];
}

function AuditLogsTab() {
  const [logs, setLogs]       = useState<AuditLog[]>([]);
  const [page, setPage]       = useState(1);
  const [hasMore, setHasMore] = useState(true);
  const [loading, setLoading] = useState(false);
  const PAGE_SIZE = 50;

  const load = useCallback(async (p: number) => {
    setLoading(true);
    try {
      const { data } = await client.get<AuditLogsResponse>("/admin/audit-logs", {
        params: { page: p, size: PAGE_SIZE },
      });
      setLogs(data.items);
      setHasMore(data.items.length === PAGE_SIZE);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => { load(page); }, [load, page]);

  return (
    <div>
      <div className="flex items-center justify-between mb-5">
        <h2 className="text-lg font-medium">감사 로그</h2>
        <button
          onClick={() => load(page)}
          className="flex items-center gap-1.5 text-slate-400 hover:text-white text-sm transition-colors"
        >
          <RefreshCw className={`w-4 h-4 ${loading ? "animate-spin" : ""}`} />
          새로고침
        </button>
      </div>

      <div className="bg-slate-800 rounded-xl overflow-hidden">
        <table className="w-full text-sm">
          <thead>
            <tr className="border-b border-slate-700 text-slate-400 text-xs uppercase">
              <th className="text-left px-4 py-3">시각</th>
              <th className="text-left px-4 py-3">액션</th>
              <th className="text-left px-4 py-3">대상</th>
              <th className="text-left px-4 py-3">IP</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-slate-700">
            {logs.map((log) => (
              <tr key={log.id} className="hover:bg-slate-750 transition-colors">
                <td className="px-4 py-2.5 text-slate-500 text-xs whitespace-nowrap">
                  {new Date(log.created_at).toLocaleString("ko-KR")}
                </td>
                <td className="px-4 py-2.5">
                  <ActionBadge action={log.action} />
                </td>
                <td className="px-4 py-2.5 text-slate-400 text-xs font-mono">
                  {log.target ?? "—"}
                </td>
                <td className="px-4 py-2.5 text-slate-500 text-xs">
                  {log.ip_address ?? "—"}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      {/* 페이지네이션 */}
      <div className="flex items-center justify-between mt-4">
        <button
          disabled={page === 1}
          onClick={() => setPage((p) => p - 1)}
          className="flex items-center gap-1 text-sm text-slate-400 hover:text-white disabled:opacity-30 disabled:cursor-not-allowed transition-colors"
        >
          <ChevronLeft className="w-4 h-4" /> 이전
        </button>
        <span className="text-sm text-slate-500">페이지 {page}</span>
        <button
          disabled={!hasMore}
          onClick={() => setPage((p) => p + 1)}
          className="flex items-center gap-1 text-sm text-slate-400 hover:text-white disabled:opacity-30 disabled:cursor-not-allowed transition-colors"
        >
          다음 <ChevronRight className="w-4 h-4" />
        </button>
      </div>
    </div>
  );
}

function ActionBadge({ action }: { action: string }) {
  const colorMap: Record<string, string> = {
    login:          "text-green-400 bg-green-400/10",
    logout:         "text-slate-400 bg-slate-400/10",
    session_start:  "text-blue-400 bg-blue-400/10",
    session_end:    "text-slate-400 bg-slate-400/10",
    session_reject: "text-red-400 bg-red-400/10",
    file_transfer:  "text-purple-400 bg-purple-400/10",
    role_change:    "text-yellow-400 bg-yellow-400/10",
  };
  const cls = colorMap[action] ?? "text-slate-300 bg-slate-300/10";
  return (
    <span className={`inline-block text-xs px-2 py-0.5 rounded-full font-medium ${cls}`}>
      {action}
    </span>
  );
}

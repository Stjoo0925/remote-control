/**
 * SessionDashboard — 세션 목록 & 세션 워크스페이스 통합 뷰
 *
 * 레이아웃:
 *   - 세션을 선택하지 않은 상태 → 세션 목록 카드
 *   - 세션 선택(active) → 전체 화면 워크스페이스
 *       ┌────────────────────────────┬────────────┐
 *       │  RemoteViewer (WebRTC)     │  ChatPanel │
 *       │                            ├────────────┤
 *       │                            │  File-     │
 *       │                            │  Transfer  │
 *       └────────────────────────────┴────────────┘
 *
 * 새 세션:
 *   - support/admin 역할만 "새 세션" 버튼 표시
 *   - 대상 username 입력 → POST /api/sessions
 */

import { useEffect, useState, useCallback } from "react";
import {
  Monitor, LogOut, Plus, Clock, CheckCircle, XCircle,
  ArrowLeft, MessageSquare, FolderOpen, X, RefreshCw, Users,
} from "lucide-react";
import { useAuth } from "@/features/auth/useAuth";
import client from "@/shared/api/client";
import type { Session } from "@/shared/types";
import RemoteViewer from "@/features/viewer/RemoteViewer";
import ChatPanel from "@/features/chat/ChatPanel";
import FileTransferPanel from "@/features/file-transfer/FileTransferPanel";
import ConnectionRequestModal from "./ConnectionRequestModal";

// ─────────────────────────────────────────────────────────────
// 타입
// ─────────────────────────────────────────────────────────────

type SidePanel = "chat" | "files";

// ─────────────────────────────────────────────────────────────
// 메인 컴포넌트
// ─────────────────────────────────────────────────────────────

export default function SessionDashboard() {
  const { user, logout } = useAuth();
  const [sessions, setSessions]       = useState<Session[]>([]);
  const [activeSession, setActive]    = useState<Session | null>(null);
  const [sidePanel, setSidePanel]     = useState<SidePanel>("chat");
  const [showNewModal, setShowNewModal] = useState(false);
  const [loading, setLoading]         = useState(false);
  const [incomingRequest, setIncoming] = useState<{
    sessionId: string;
    controllerName: string;
  } | null>(null);

  // ── 세션 목록 로드 ──
  const loadSessions = useCallback(async () => {
    setLoading(true);
    try {
      const { data } = await client.get<Session[]>("/sessions");
      setSessions(data);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => { loadSessions(); }, [loadSessions]);

  // ── 세션 선택: active 세션만 워크스페이스 진입 가능 ──
  const openSession = (s: Session) => {
    if (s.status === "active") setActive(s);
  };

  const closeSession = () => setActive(null);

  // ── 워크스페이스 뷰 ──
  if (activeSession) {
    const targetId    = activeSession.target_id;
    const myUsername  = user?.username ?? "";
    const myDisplay   = user?.display_name ?? "";

    return (
      <div className="flex flex-col h-screen bg-slate-900 text-white overflow-hidden">
        {/* 워크스페이스 헤더 */}
        <header className="flex items-center justify-between bg-slate-800 border-b border-slate-700 px-4 py-2 shrink-0">
          <div className="flex items-center gap-3">
            <button
              onClick={closeSession}
              className="flex items-center gap-1.5 text-slate-400 hover:text-white text-sm transition-colors"
            >
              <ArrowLeft className="w-4 h-4" /> 목록으로
            </button>
            <span className="text-slate-600">|</span>
            <div className="flex items-center gap-2 text-sm">
              <Monitor className="w-4 h-4 text-blue-400" />
              <span className="text-slate-300 font-mono text-xs">
                {activeSession.id.slice(0, 8)}…
              </span>
            </div>
          </div>

          {/* 사이드 패널 전환 버튼 */}
          <div className="flex items-center gap-1 bg-slate-700 rounded-lg p-1">
            <button
              onClick={() => setSidePanel("chat")}
              className={`flex items-center gap-1.5 px-3 py-1.5 rounded-md text-xs transition-colors ${
                sidePanel === "chat"
                  ? "bg-blue-600 text-white"
                  : "text-slate-400 hover:text-white"
              }`}
            >
              <MessageSquare className="w-3.5 h-3.5" /> 채팅
            </button>
            <button
              onClick={() => setSidePanel("files")}
              className={`flex items-center gap-1.5 px-3 py-1.5 rounded-md text-xs transition-colors ${
                sidePanel === "files"
                  ? "bg-blue-600 text-white"
                  : "text-slate-400 hover:text-white"
              }`}
            >
              <FolderOpen className="w-3.5 h-3.5" /> 파일
            </button>
          </div>
        </header>

        {/* 워크스페이스 본문 */}
        <div className="flex flex-1 overflow-hidden">
          {/* 원격 뷰어 */}
          <div className="flex-1 overflow-hidden">
            <RemoteViewer
              sessionId={activeSession.id}
              targetUsername={targetId}   // target_id는 username으로 사용
              onClose={closeSession}
            />
          </div>

          {/* 사이드 패널 (320px 고정) */}
          <div className="w-80 border-l border-slate-700 flex flex-col shrink-0">
            {sidePanel === "chat" ? (
              <ChatPanel
                sessionId={activeSession.id}
                myUsername={myUsername}
                myDisplayName={myDisplay}
              />
            ) : (
              <FileTransferPanel
                sessionId={activeSession.id}
                targetUsername={targetId}
                myUsername={myUsername}
              />
            )}
          </div>
        </div>
      </div>
    );
  }

  // ── 세션 목록 뷰 ──
  return (
    <div className="min-h-screen bg-slate-900 text-white">
      {/* 헤더 */}
      <header className="bg-slate-800 border-b border-slate-700 px-6 py-4 flex items-center justify-between">
        <div className="flex items-center gap-3">
          <div className="bg-blue-600 p-1.5 rounded-lg">
            <Monitor className="w-5 h-5" />
          </div>
          <span className="font-semibold">원격 제어</span>
        </div>
        <div className="flex items-center gap-4">
          <span className="text-slate-400 text-sm">
            {user?.display_name}
            <span className="ml-1 text-xs text-slate-600">({user?.role})</span>
          </span>
          <button
            onClick={logout}
            className="flex items-center gap-1.5 text-slate-400 hover:text-white text-sm transition-colors"
          >
            <LogOut className="w-4 h-4" /> 로그아웃
          </button>
        </div>
      </header>

      <main className="max-w-4xl mx-auto px-6 py-8">
        {/* 툴바 */}
        <div className="flex items-center justify-between mb-6">
          <h2 className="text-lg font-medium">세션 목록</h2>
          <div className="flex items-center gap-3">
            <button
              onClick={loadSessions}
              className="flex items-center gap-1.5 text-slate-400 hover:text-white text-sm transition-colors"
            >
              <RefreshCw className={`w-4 h-4 ${loading ? "animate-spin" : ""}`} />
              새로고침
            </button>
            {(user?.role === "admin" || user?.role === "support") && (
              <button
                onClick={() => setShowNewModal(true)}
                className="flex items-center gap-2 bg-blue-600 hover:bg-blue-500 text-white text-sm px-4 py-2 rounded-lg transition-colors"
              >
                <Plus className="w-4 h-4" /> 새 세션
              </button>
            )}
          </div>
        </div>

        {/* 세션 카드 목록 */}
        {sessions.length === 0 ? (
          <div className="bg-slate-800 rounded-xl p-12 text-center text-slate-500">
            <Monitor className="w-12 h-12 mx-auto mb-3 opacity-30" />
            <p>진행 중인 세션이 없습니다</p>
          </div>
        ) : (
          <div className="space-y-3">
            {sessions.map((s) => (
              <SessionCard
                key={s.id}
                session={s}
                onClick={() => openSession(s)}
              />
            ))}
          </div>
        )}
      </main>

      {/* 새 세션 모달 */}
      {showNewModal && (
        <NewSessionModal
          onClose={() => setShowNewModal(false)}
          onCreated={(s) => {
            setSessions((prev) => [s, ...prev]);
            setShowNewModal(false);
          }}
        />
      )}

      {/* 연결 요청 모달 (피제어측) */}
      {incomingRequest && (
        <ConnectionRequestModal
          controllerName={incomingRequest.controllerName}
          sessionId={incomingRequest.sessionId}
          onApprove={() => setIncoming(null)}
          onReject={() => setIncoming(null)}
        />
      )}
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// SessionCard
// ─────────────────────────────────────────────────────────────

function SessionCard({ session: s, onClick }: { session: Session; onClick: () => void }) {
  const statusMap = {
    pending:  { label: "대기 중",  cls: "text-yellow-400 bg-yellow-400/10", Icon: Clock },
    active:   { label: "진행 중",  cls: "text-green-400 bg-green-400/10",   Icon: CheckCircle },
    ended:    { label: "종료",     cls: "text-slate-400 bg-slate-400/10",   Icon: XCircle },
    rejected: { label: "거부됨",   cls: "text-red-400 bg-red-400/10",       Icon: XCircle },
  };
  const { label, cls, Icon } = statusMap[s.status];
  const clickable = s.status === "active";

  return (
    <div
      onClick={clickable ? onClick : undefined}
      className={`bg-slate-800 rounded-xl px-5 py-4 flex items-center justify-between transition-colors ${
        clickable ? "hover:bg-slate-750 cursor-pointer" : "opacity-60 cursor-default"
      }`}
    >
      <div className="flex items-center gap-3">
        <div className={`p-2 rounded-lg ${clickable ? "bg-blue-600/20" : "bg-slate-700"}`}>
          <Monitor className={`w-4 h-4 ${clickable ? "text-blue-400" : "text-slate-500"}`} />
        </div>
        <div>
          <p className="text-sm font-medium">
            세션 <span className="font-mono">{s.id.slice(0, 8)}…</span>
          </p>
          <p className="text-xs text-slate-500 mt-0.5 flex items-center gap-1">
            <Users className="w-3 h-3" />
            {new Date(s.created_at).toLocaleString("ko-KR")}
          </p>
        </div>
      </div>

      <div className="flex items-center gap-3">
        <span className={`inline-flex items-center gap-1 text-xs px-2 py-0.5 rounded-full font-medium ${cls}`}>
          <Icon className="w-3 h-3" />{label}
        </span>
        {clickable && (
          <span className="text-xs text-blue-400 hover:text-blue-300">
            열기 →
          </span>
        )}
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// NewSessionModal — 새 세션 생성 (support/admin)
// ─────────────────────────────────────────────────────────────

function NewSessionModal({
  onClose,
  onCreated,
}: {
  onClose: () => void;
  onCreated: (s: Session) => void;
}) {
  const [targetUsername, setTarget] = useState("");
  const [loading, setLoading]       = useState(false);
  const [error, setError]           = useState("");

  const create = async () => {
    if (!targetUsername.trim()) return;
    setLoading(true);
    setError("");
    try {
      const { data } = await client.post<Session>("/sessions", {
        target_username: targetUsername.trim(),
      });
      onCreated(data);
    } catch (e: unknown) {
      const msg =
        (e as { response?: { data?: { detail?: string } } })?.response?.data?.detail ??
        "세션 생성에 실패했습니다.";
      setError(msg);
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="fixed inset-0 bg-black/60 backdrop-blur-sm flex items-center justify-center z-50 px-4">
      <div className="bg-slate-800 rounded-2xl p-6 w-full max-w-sm shadow-2xl border border-slate-700">
        {/* 제목 */}
        <div className="flex items-center justify-between mb-5">
          <div className="flex items-center gap-2">
            <div className="bg-blue-600/20 p-2 rounded-xl">
              <Monitor className="w-5 h-5 text-blue-400" />
            </div>
            <h2 className="text-white font-semibold">새 원격 세션</h2>
          </div>
          <button onClick={onClose} className="text-slate-500 hover:text-white transition-colors">
            <X className="w-5 h-5" />
          </button>
        </div>

        {/* 입력 */}
        <label className="block text-xs text-slate-400 mb-1.5">대상 사용자 (username)</label>
        <input
          autoFocus
          type="text"
          value={targetUsername}
          onChange={(e) => setTarget(e.target.value)}
          onKeyDown={(e) => e.key === "Enter" && create()}
          placeholder="예: hong.gildong"
          className="w-full bg-slate-700 border border-slate-600 rounded-lg px-3 py-2.5 text-sm text-white placeholder-slate-500 focus:outline-none focus:border-blue-500 transition-colors"
        />

        {error && (
          <p className="mt-2 text-xs text-red-400">{error}</p>
        )}

        {/* 버튼 */}
        <div className="flex gap-3 mt-5">
          <button
            onClick={onClose}
            className="flex-1 bg-slate-700 hover:bg-slate-600 text-white text-sm py-2.5 rounded-xl transition-colors"
          >
            취소
          </button>
          <button
            onClick={create}
            disabled={loading || !targetUsername.trim()}
            className="flex-1 flex items-center justify-center gap-2 bg-blue-600 hover:bg-blue-500 disabled:opacity-40 disabled:cursor-not-allowed text-white text-sm py-2.5 rounded-xl transition-colors"
          >
            {loading ? (
              <RefreshCw className="w-4 h-4 animate-spin" />
            ) : (
              <Plus className="w-4 h-4" />
            )}
            {loading ? "생성 중…" : "세션 시작"}
          </button>
        </div>
      </div>
    </div>
  );
}
 
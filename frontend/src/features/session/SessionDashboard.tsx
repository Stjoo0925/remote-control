import { useEffect, useState } from "react";
import { Monitor, LogOut, Plus, Clock, CheckCircle, XCircle } from "lucide-react";
import { useAuth } from "@/features/auth/useAuth";
import client from "@/shared/api/client";
import type { Session } from "@/shared/types";
import ConnectionRequestModal from "./ConnectionRequestModal";

export default function SessionDashboard() {
  const { user, logout } = useAuth();
  const [sessions, setSessions] = useState<Session[]>([]);
  const [incomingRequest, setIncomingRequest] = useState<{ sessionId: string; controllerName: string } | null>(null);

  useEffect(() => {
    client.get<Session[]>("/sessions").then((r) => setSessions(r.data)).catch(() => {});
  }, []);

  const statusBadge = (status: Session["status"]) => {
    const map = {
      pending:  { label: "대기 중",   color: "text-yellow-400 bg-yellow-400/10", icon: Clock },
      active:   { label: "진행 중",   color: "text-green-400 bg-green-400/10",   icon: CheckCircle },
      ended:    { label: "종료",      color: "text-slate-400 bg-slate-400/10",   icon: XCircle },
      rejected: { label: "거부됨",    color: "text-red-400 bg-red-400/10",       icon: XCircle },
    };
    const { label, color, icon: Icon } = map[status];
    return (
      <span className={`inline-flex items-center gap-1 text-xs px-2 py-0.5 rounded-full font-medium ${color}`}>
        <Icon className="w-3 h-3" />{label}
      </span>
    );
  };

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
          <span className="text-slate-400 text-sm">{user?.display_name} ({user?.role})</span>
          <button onClick={logout} className="flex items-center gap-1.5 text-slate-400 hover:text-white text-sm transition-colors">
            <LogOut className="w-4 h-4" /> 로그아웃
          </button>
        </div>
      </header>

      <main className="max-w-4xl mx-auto px-6 py-8">
        <div className="flex items-center justify-between mb-6">
          <h2 className="text-lg font-medium">세션 목록</h2>
          {(user?.role === "admin" || user?.role === "support") && (
            <button className="flex items-center gap-2 bg-blue-600 hover:bg-blue-500 text-white text-sm px-4 py-2 rounded-lg transition-colors">
              <Plus className="w-4 h-4" /> 새 세션
            </button>
          )}
        </div>

        {sessions.length === 0 ? (
          <div className="bg-slate-800 rounded-xl p-12 text-center text-slate-500">
            <Monitor className="w-12 h-12 mx-auto mb-3 opacity-30" />
            <p>진행 중인 세션이 없습니다</p>
          </div>
        ) : (
          <div className="space-y-3">
            {sessions.map((s) => (
              <div key={s.id} className="bg-slate-800 rounded-xl px-5 py-4 flex items-center justify-between hover:bg-slate-750 transition-colors">
                <div>
                  <p className="text-sm font-medium">세션 {s.id.slice(0, 8)}...</p>
                  <p className="text-xs text-slate-500 mt-0.5">{new Date(s.created_at).toLocaleString("ko-KR")}</p>
                </div>
                {statusBadge(s.status)}
              </div>
            ))}
          </div>
        )}
      </main>

      {incomingRequest && (
        <ConnectionRequestModal
          controllerName={incomingRequest.controllerName}
          sessionId={incomingRequest.sessionId}
          onApprove={() => setIncomingRequest(null)}
          onReject={() => setIncomingRequest(null)}
        />
      )}
    </div>
  );
}

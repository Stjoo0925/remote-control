import { useState } from "react";
import { useAuth } from "./useAuth";
import { Monitor } from "lucide-react";

export default function LoginPage() {
  const { login } = useAuth();
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError(null);
    setLoading(true);
    try {
      await login(username, password);
    } catch {
      setError("아이디 또는 비밀번호가 올바르지 않습니다.");
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="min-h-screen bg-slate-900 flex items-center justify-center px-4">
      <div className="w-full max-w-sm">
        {/* 로고 */}
        <div className="flex items-center justify-center gap-3 mb-8">
          <div className="bg-blue-600 p-2.5 rounded-xl">
            <Monitor className="w-6 h-6 text-white" />
          </div>
          <span className="text-white text-xl font-semibold">원격 제어</span>
        </div>

        <form onSubmit={handleSubmit} className="bg-slate-800 rounded-2xl p-8 space-y-5 shadow-xl">
          <h1 className="text-white text-lg font-medium mb-1">로그인</h1>

          <div className="space-y-1">
            <label className="text-slate-400 text-sm">사번 / 아이디</label>
            <input
              type="text"
              value={username}
              onChange={(e) => setUsername(e.target.value)}
              placeholder="hong.gildong"
              required
              className="w-full bg-slate-700 text-white rounded-lg px-4 py-2.5 text-sm border border-slate-600 focus:border-blue-500 focus:outline-none placeholder:text-slate-500"
            />
          </div>

          <div className="space-y-1">
            <label className="text-slate-400 text-sm">비밀번호</label>
            <input
              type="password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              placeholder="••••••••"
              required
              className="w-full bg-slate-700 text-white rounded-lg px-4 py-2.5 text-sm border border-slate-600 focus:border-blue-500 focus:outline-none placeholder:text-slate-500"
            />
          </div>

          {error && (
            <p className="text-red-400 text-sm bg-red-400/10 rounded-lg px-3 py-2">{error}</p>
          )}

          <button
            type="submit"
            disabled={loading}
            className="w-full bg-blue-600 hover:bg-blue-500 disabled:opacity-50 text-white font-medium rounded-lg py-2.5 text-sm transition-colors"
          >
            {loading ? "로그인 중..." : "로그인"}
          </button>
        </form>

        <p className="text-slate-600 text-xs text-center mt-6">
          사내 계정(LDAP)으로 로그인합니다
        </p>
      </div>
    </div>
  );
}

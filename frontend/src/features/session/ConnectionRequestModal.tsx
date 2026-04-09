import { useEffect, useState } from "react";
import { Monitor, ShieldCheck, X } from "lucide-react";

interface Props {
  controllerName: string;
  sessionId: string;
  onApprove: () => void;
  onReject: () => void;
}

const TIMEOUT = 60;

export default function ConnectionRequestModal({ controllerName, sessionId, onApprove, onReject }: Props) {
  const [remaining, setRemaining] = useState(TIMEOUT);

  useEffect(() => {
    const timer = setInterval(() => {
      setRemaining((r) => {
        if (r <= 1) { clearInterval(timer); onReject(); }
        return r - 1;
      });
    }, 1000);
    return () => clearInterval(timer);
  }, [onReject]);

  const progress = (remaining / TIMEOUT) * 100;
  const urgent = remaining <= 10;

  return (
    <div className="fixed inset-0 bg-black/60 backdrop-blur-sm flex items-center justify-center z-50 px-4">
      <div className="bg-slate-800 rounded-2xl p-6 w-full max-w-sm shadow-2xl border border-slate-700">
        <div className="flex items-center gap-3 mb-4">
          <div className="bg-blue-600/20 p-2 rounded-xl">
            <Monitor className="w-6 h-6 text-blue-400" />
          </div>
          <h2 className="text-white font-semibold text-base">원격 연결 요청</h2>
        </div>

        <p className="text-slate-300 text-sm mb-1">
          <span className="text-white font-medium">{controllerName}</span>님이 이 기기에 접속하려 합니다.
        </p>
        <p className="text-slate-500 text-xs mb-5">승인하면 상대방이 화면을 보고 제어할 수 있습니다.</p>

        {/* 타임아웃 진행바 */}
        <div className="mb-2 h-1.5 bg-slate-700 rounded-full overflow-hidden">
          <div
            className={`h-full rounded-full transition-all ${urgent ? "bg-red-500" : "bg-blue-500"}`}
            style={{ width: `${progress}%` }}
          />
        </div>
        <p className={`text-xs mb-5 ${urgent ? "text-red-400" : "text-slate-500"}`}>
          자동 거부까지 {remaining}초
        </p>

        <div className="flex gap-3">
          <button
            onClick={onReject}
            className="flex-1 flex items-center justify-center gap-2 bg-slate-700 hover:bg-slate-600 text-white text-sm py-2.5 rounded-xl transition-colors"
          >
            <X className="w-4 h-4" /> 거부
          </button>
          <button
            onClick={onApprove}
            className="flex-1 flex items-center justify-center gap-2 bg-blue-600 hover:bg-blue-500 text-white text-sm py-2.5 rounded-xl transition-colors"
          >
            <ShieldCheck className="w-4 h-4" /> 승인
          </button>
        </div>
      </div>
    </div>
  );
}

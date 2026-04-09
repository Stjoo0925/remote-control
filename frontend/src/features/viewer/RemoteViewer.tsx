/**
 * RemoteViewer — WebRTC 기반 원격 화면 뷰어 (Controller 측)
 *
 * 흐름:
 *   1. Socket.IO로 Signaling 서버에 연결
 *   2. RTCPeerConnection 생성 → Offer SDP 생성 → 서버에 전송
 *   3. Agent로부터 Answer SDP, ICE Candidate 수신 → 연결 확립
 *   4. Agent가 보내는 Video Track(화면) → <video> 태그로 렌더링
 *   5. Canvas mousemove/mousedown/keydown → DataChannel "input" 으로 전송
 */

import {
  useEffect,
  useRef,
  useCallback,
  useState,
} from "react";
import { Maximize2, Minimize2, X, Wifi, WifiOff, Loader2 } from "lucide-react";
import { getSocket, connectSocket } from "@/shared/socket";

// ─────────────────────────────────────────────────────────────
// 타입
// ─────────────────────────────────────────────────────────────

type ConnectionState = "idle" | "connecting" | "connected" | "failed" | "closed";

interface RemoteViewerProps {
  sessionId: string;
  targetUsername: string;
  onClose: () => void;
}

interface InputEvent {
  type: "mouse_move" | "mouse_button" | "mouse_scroll" | "key_event" | "type_text";
  [key: string]: unknown;
}

// ─────────────────────────────────────────────────────────────
// STUN/TURN 서버 설정 (환경변수에서 주입)
// ─────────────────────────────────────────────────────────────

const ICE_SERVERS: RTCIceServer[] = [
  { urls: import.meta.env.VITE_STUN_URL ?? "stun:stun.corp.local:3478" },
  ...(import.meta.env.VITE_TURN_URL
    ? [
        {
          urls: import.meta.env.VITE_TURN_URL as string,
          username: import.meta.env.VITE_TURN_USER ?? "rc",
          credential: import.meta.env.VITE_TURN_PASS ?? "rc-secret",
        },
      ]
    : []),
];

// ─────────────────────────────────────────────────────────────
// 컴포넌트
// ─────────────────────────────────────────────────────────────

export default function RemoteViewer({
  sessionId,
  targetUsername,
  onClose,
}: RemoteViewerProps) {
  const videoRef = useRef<HTMLVideoElement>(null);
  const pcRef = useRef<RTCPeerConnection | null>(null);
  const dcRef = useRef<RTCDataChannel | null>(null);

  const [connState, setConnState] = useState<ConnectionState>("idle");
  const [fullscreen, setFullscreen] = useState(false);
  const [remoteSize, setRemoteSize] = useState<{ w: number; h: number } | null>(null);

  // ──────────────────────────────────────────────
  // 입력 이벤트 → DataChannel 전송
  // ──────────────────────────────────────────────

  const sendInput = useCallback((event: InputEvent) => {
    const dc = dcRef.current;
    if (dc?.readyState === "open") {
      dc.send(JSON.stringify(event));
    }
  }, []);

  // ──────────────────────────────────────────────
  // 마우스 이벤트 핸들러
  // ──────────────────────────────────────────────

  const handleMouseMove = useCallback(
    (e: React.MouseEvent<HTMLVideoElement>) => {
      if (!remoteSize) return;
      const rect = e.currentTarget.getBoundingClientRect();
      const x = Math.round(((e.clientX - rect.left) / rect.width) * remoteSize.w);
      const y = Math.round(((e.clientY - rect.top) / rect.height) * remoteSize.h);
      sendInput({ type: "mouse_move", x, y });
    },
    [remoteSize, sendInput]
  );

  const handleMouseButton = useCallback(
    (e: React.MouseEvent<HTMLVideoElement>, pressed: boolean) => {
      e.preventDefault();
      // button: 0=왼쪽, 1=가운데(e.button==1), 2=오른쪽(e.button==2)
      const buttonMap: Record<number, number> = { 0: 0, 1: 2, 2: 1 };
      const button = buttonMap[e.button] ?? 0;
      sendInput({ type: "mouse_button", button, pressed });
    },
    [sendInput]
  );

  const handleWheel = useCallback(
    (e: React.WheelEvent<HTMLVideoElement>) => {
      e.preventDefault();
      sendInput({
        type: "mouse_scroll",
        delta_x: Math.round(e.deltaX),
        delta_y: Math.round(e.deltaY),
      });
    },
    [sendInput]
  );

  // ──────────────────────────────────────────────
  // 키보드 이벤트 핸들러
  // ──────────────────────────────────────────────

  const handleKeyDown = useCallback(
    (e: React.KeyboardEvent<HTMLVideoElement>) => {
      e.preventDefault();
      sendInput({ type: "key_event", key_code: e.keyCode, pressed: true });
    },
    [sendInput]
  );

  const handleKeyUp = useCallback(
    (e: React.KeyboardEvent<HTMLVideoElement>) => {
      e.preventDefault();
      sendInput({ type: "key_event", key_code: e.keyCode, pressed: false });
    },
    [sendInput]
  );

  // ──────────────────────────────────────────────
  // WebRTC 연결 수립
  // ──────────────────────────────────────────────

  useEffect(() => {
    const socket = getSocket();
    connectSocket();
    setConnState("connecting");

    // RTCPeerConnection 생성
    const pc = new RTCPeerConnection({ iceServers: ICE_SERVERS });
    pcRef.current = pc;

    // 연결 상태 모니터링
    pc.onconnectionstatechange = () => {
      const state = pc.connectionState;
      if (state === "connected") setConnState("connected");
      else if (state === "failed" || state === "disconnected") setConnState("failed");
      else if (state === "closed") setConnState("closed");
    };

    // Agent가 보내는 Video Track 수신
    pc.ontrack = (event) => {
      if (videoRef.current && event.streams[0]) {
        videoRef.current.srcObject = event.streams[0];
      }
    };

    // DataChannel "input" 생성 (Controller → Agent 입력 이벤트)
    const dc = pc.createDataChannel("input", { ordered: true });
    dcRef.current = dc;

    dc.onopen = () => {
      // Agent에 화면 크기 요청
      dc.send(JSON.stringify({ type: "get_screen_size" }));
    };

    dc.onmessage = (e) => {
      try {
        const msg = JSON.parse(e.data as string);
        if (msg.type === "screen_size") {
          setRemoteSize({ w: msg.width, h: msg.height });
        }
      } catch {
        /* ignore */
      }
    };

    // 로컬 ICE Candidate → Signaling 서버로 전달
    pc.onicecandidate = (event) => {
      if (event.candidate) {
        socket.emit("ice_candidate", {
          session_id: sessionId,
          target_username: targetUsername,
          candidate: JSON.stringify(event.candidate),
        });
      }
    };

    // SDP Offer 생성 & 서버로 전송
    (async () => {
      try {
        const offer = await pc.createOffer();
        await pc.setLocalDescription(offer);
        socket.emit("offer", {
          session_id: sessionId,
          target_username: targetUsername,
          sdp: JSON.stringify(offer),
        });
      } catch (err) {
        console.error("Offer 생성 실패", err);
        setConnState("failed");
      }
    })();

    // ── Signaling 이벤트 수신 ──

    // Agent의 SDP Answer 수신
    const onAnswer = async (data: { sdp: string }) => {
      try {
        const answer: RTCSessionDescriptionInit = JSON.parse(data.sdp);
        await pc.setRemoteDescription(new RTCSessionDescription(answer));
      } catch (err) {
        console.error("Answer 처리 실패", err);
        setConnState("failed");
      }
    };

    // 상대방의 ICE Candidate 수신
    const onIceCandidate = async (data: { candidate: string; target_username?: string; controller_username?: string }) => {
      try {
        const candidate = JSON.parse(data.candidate);
        await pc.addIceCandidate(new RTCIceCandidate(candidate));
      } catch (err) {
        console.error("ICE Candidate 추가 실패", err);
      }
    };

    // 세션 종료 이벤트
    const onSessionEnded = () => {
      setConnState("closed");
      onClose();
    };

    socket.on("answer", onAnswer);
    socket.on("ice_candidate", onIceCandidate);
    socket.on("session_ended", onSessionEnded);

    // 세션 룸 참가
    socket.emit("join_session", { session_id: sessionId });

    // ── 정리 ──
    return () => {
      socket.off("answer", onAnswer);
      socket.off("ice_candidate", onIceCandidate);
      socket.off("session_ended", onSessionEnded);
      dc.close();
      pc.close();
      pcRef.current = null;
      dcRef.current = null;
    };
  }, [sessionId, targetUsername, onClose]);

  // ──────────────────────────────────────────────
  // 세션 강제 종료
  // ──────────────────────────────────────────────

  const handleForceEnd = useCallback(() => {
    const socket = getSocket();
    socket.emit("session_ended", { session_id: sessionId, reason: "controller_closed" });
    onClose();
  }, [sessionId, onClose]);

  // ──────────────────────────────────────────────
  // 렌더링
  // ──────────────────────────────────────────────

  const stateLabel: Record<ConnectionState, string> = {
    idle: "대기 중",
    connecting: "연결 중…",
    connected: "연결됨",
    failed: "연결 실패",
    closed: "종료됨",
  };

  return (
    <div
      className={`${
        fullscreen
          ? "fixed inset-0 z-50 bg-black"
          : "fixed inset-4 z-40 rounded-2xl overflow-hidden shadow-2xl bg-black"
      } flex flex-col`}
    >
      {/* 툴바 */}
      <header className="flex items-center justify-between bg-slate-900/90 backdrop-blur-sm px-4 py-2 shrink-0">
        <div className="flex items-center gap-3">
          {connState === "connected" ? (
            <Wifi className="w-4 h-4 text-green-400" />
          ) : connState === "connecting" ? (
            <Loader2 className="w-4 h-4 text-yellow-400 animate-spin" />
          ) : (
            <WifiOff className="w-4 h-4 text-red-400" />
          )}
          <span className="text-sm text-white font-medium">{targetUsername}</span>
          <span
            className={`text-xs px-2 py-0.5 rounded-full ${
              connState === "connected"
                ? "bg-green-500/20 text-green-400"
                : connState === "connecting"
                ? "bg-yellow-500/20 text-yellow-400"
                : "bg-red-500/20 text-red-400"
            }`}
          >
            {stateLabel[connState]}
          </span>
          {remoteSize && (
            <span className="text-xs text-slate-500">
              {remoteSize.w} × {remoteSize.h}
            </span>
          )}
        </div>

        <div className="flex items-center gap-2">
          <button
            onClick={() => setFullscreen((f) => !f)}
            className="text-slate-400 hover:text-white p-1.5 rounded-lg hover:bg-slate-700 transition-colors"
            title={fullscreen ? "전체화면 해제" : "전체화면"}
          >
            {fullscreen ? (
              <Minimize2 className="w-4 h-4" />
            ) : (
              <Maximize2 className="w-4 h-4" />
            )}
          </button>
          <button
            onClick={handleForceEnd}
            className="text-slate-400 hover:text-red-400 p-1.5 rounded-lg hover:bg-red-500/10 transition-colors"
            title="세션 종료 (Ctrl+Alt+F12)"
          >
            <X className="w-4 h-4" />
          </button>
        </div>
      </header>

      {/* 화면 뷰어 */}
      <div className="flex-1 relative flex items-center justify-center bg-black min-h-0">
        {connState === "connecting" && (
          <div className="absolute inset-0 flex flex-col items-center justify-center gap-3 text-slate-400 z-10">
            <Loader2 className="w-10 h-10 animate-spin" />
            <p className="text-sm">원격 화면에 연결하는 중…</p>
          </div>
        )}

        {connState === "failed" && (
          <div className="absolute inset-0 flex flex-col items-center justify-center gap-3 text-red-400 z-10">
            <WifiOff className="w-10 h-10" />
            <p className="text-sm">연결에 실패했습니다.</p>
            <button
              onClick={onClose}
              className="mt-2 text-xs bg-slate-700 hover:bg-slate-600 text-white px-4 py-1.5 rounded-lg transition-colors"
            >
              닫기
            </button>
          </div>
        )}

        {/* eslint-disable-next-line jsx-a11y/media-has-caption */}
        <video
          ref={videoRef}
          autoPlay
          playsInline
          className="w-full h-full object-contain cursor-crosshair outline-none"
          tabIndex={0}
          onMouseMove={handleMouseMove}
          onMouseDown={(e) => handleMouseButton(e, true)}
          onMouseUp={(e) => handleMouseButton(e, false)}
          onContextMenu={(e) => e.preventDefault()}
          onWheel={handleWheel}
          onKeyDown={handleKeyDown}
          onKeyUp={handleKeyUp}
          style={{ display: connState === "connected" ? "block" : "none" }}
        />
      </div>
    </div>
  );
}

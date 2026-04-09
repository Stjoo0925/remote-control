/**
 * ChatPanel — 세션 내 실시간 채팅
 * Socket.IO chat_message 이벤트를 통해 메시지를 송수신합니다.
 */

import { useEffect, useRef, useState, useCallback, KeyboardEvent } from "react";
import { Send } from "lucide-react";
import { getSocket } from "@/shared/socket";

// ─────────────────────────────────────────────────────────────
// 타입
// ─────────────────────────────────────────────────────────────

interface ChatMessage {
  id: string;
  senderId: string;
  senderName: string;
  text: string;
  timestamp: string;
  isMine: boolean;
}

interface Props {
  sessionId: string;
  myUsername: string;
  myDisplayName: string;
}

// ─────────────────────────────────────────────────────────────
// 컴포넌트
// ─────────────────────────────────────────────────────────────

export default function ChatPanel({ sessionId, myUsername, myDisplayName }: Props) {
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [input, setInput] = useState("");
  const bottomRef = useRef<HTMLDivElement>(null);

  // ── 메시지 수신 ──
  useEffect(() => {
    const socket = getSocket();

    const onMessage = (data: {
      session_id: string;
      sender_id: string;
      sender_name: string;
      text: string;
      timestamp: string;
    }) => {
      if (data.session_id !== sessionId) return;

      setMessages((prev) => [
        ...prev,
        {
          id: `${data.timestamp}-${data.sender_id}`,
          senderId: data.sender_id,
          senderName: data.sender_name,
          text: data.text,
          timestamp: data.timestamp,
          isMine: data.sender_name === myUsername,
        },
      ]);
    };

    socket.on("chat_message", onMessage);
    return () => { socket.off("chat_message", onMessage); };
  }, [sessionId, myUsername]);

  // 새 메시지 시 자동 스크롤
  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [messages]);

  // ── 메시지 전송 ──
  const sendMessage = useCallback(() => {
    const text = input.trim();
    if (!text) return;

    const socket = getSocket();
    const timestamp = new Date().toISOString();

    socket.emit("chat_message", {
      session_id: sessionId,
      text,
      timestamp,
    });

    setInput("");
  }, [input, sessionId]);

  const handleKeyDown = (e: KeyboardEvent<HTMLTextAreaElement>) => {
    if (e.key === "Enter" && !e.shiftKey) {
      e.preventDefault();
      sendMessage();
    }
  };

  // ── 렌더링 ──
  return (
    <div className="flex flex-col h-full bg-slate-900 text-white">
      <div className="px-4 py-3 border-b border-slate-700 text-sm font-medium text-slate-300">
        채팅
      </div>

      {/* 메시지 목록 */}
      <div className="flex-1 overflow-y-auto px-3 py-3 space-y-3">
        {messages.length === 0 && (
          <p className="text-center text-slate-600 text-sm py-8">
            메시지를 입력해 대화를 시작하세요
          </p>
        )}
        {messages.map((msg) => (
          <MessageBubble key={msg.id} msg={msg} />
        ))}
        <div ref={bottomRef} />
      </div>

      {/* 입력창 */}
      <div className="border-t border-slate-700 p-3 flex items-end gap-2">
        <textarea
          value={input}
          onChange={(e) => setInput(e.target.value)}
          onKeyDown={handleKeyDown}
          placeholder="메시지 입력 (Enter 전송, Shift+Enter 줄바꿈)"
          rows={2}
          className="flex-1 bg-slate-800 text-white text-sm rounded-lg px-3 py-2 resize-none outline-none border border-slate-600 focus:border-blue-500 placeholder-slate-500 transition-colors"
        />
        <button
          onClick={sendMessage}
          disabled={!input.trim()}
          className="bg-blue-600 hover:bg-blue-500 disabled:opacity-40 disabled:cursor-not-allowed text-white p-2.5 rounded-lg transition-colors shrink-0"
        >
          <Send className="w-4 h-4" />
        </button>
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// MessageBubble
// ─────────────────────────────────────────────────────────────

function MessageBubble({ msg }: { msg: ChatMessage }) {
  const time = new Date(msg.timestamp).toLocaleTimeString("ko-KR", {
    hour: "2-digit",
    minute: "2-digit",
  });

  if (msg.isMine) {
    return (
      <div className="flex flex-col items-end gap-1">
        <div className="bg-blue-600 text-white text-sm rounded-2xl rounded-br-sm px-3 py-2 max-w-[85%] whitespace-pre-wrap break-words">
          {msg.text}
        </div>
        <span className="text-xs text-slate-600">{time}</span>
      </div>
    );
  }

  return (
    <div className="flex flex-col items-start gap-1">
      <span className="text-xs text-slate-500 px-1">{msg.senderName}</span>
      <div className="bg-slate-700 text-white text-sm rounded-2xl rounded-bl-sm px-3 py-2 max-w-[85%] whitespace-pre-wrap break-words">
        {msg.text}
      </div>
      <span className="text-xs text-slate-600">{time}</span>
    </div>
  );
}

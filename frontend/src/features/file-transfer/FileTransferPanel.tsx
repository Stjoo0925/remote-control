/**
 * FileTransferPanel — 세션 내 양방향 파일 전송 패널
 *
 * 송신:
 *   1. 드래그앤드롭 또는 클릭으로 파일 선택
 *   2. POST /api/file-transfers → transfer_id 발급
 *   3. 1 MB 청크로 분할 → PUT /api/file-transfers/{id}/chunk
 *   4. POST /api/file-transfers/{id}/complete
 *   5. Socket.IO file_transfer_notify로 상대방에게 알림
 *
 * 수신:
 *   - Socket.IO file_transfer_notify(completed) 수신 → 다운로드 버튼 표시
 */

import { useCallback, useEffect, useRef, useState } from "react";
import { Upload, Download, X, FileText, CheckCircle, AlertCircle, Loader2 } from "lucide-react";
import client from "@/shared/api/client";
import { getSocket } from "@/shared/socket";

const CHUNK_SIZE = 1 * 1024 * 1024; // 1 MB

// ─────────────────────────────────────────────────────────────
// 타입
// ─────────────────────────────────────────────────────────────

type TransferStatus = "pending" | "uploading" | "completed" | "failed" | "received";

interface TransferItem {
  id: string;
  filename: string;
  fileSize: number;
  transferred: number;
  status: TransferStatus;
  direction: "send" | "receive";
  downloadUrl?: string;
}

interface Props {
  sessionId: string;
  targetUsername: string;
  myUsername: string;
}

// ─────────────────────────────────────────────────────────────
// 컴포넌트
// ─────────────────────────────────────────────────────────────

export default function FileTransferPanel({ sessionId, targetUsername, myUsername }: Props) {
  const [transfers, setTransfers] = useState<TransferItem[]>([]);
  const [dragging, setDragging] = useState(false);
  const fileInputRef = useRef<HTMLInputElement>(null);

  // ── 소켓 이벤트 수신 ──
  useEffect(() => {
    const socket = getSocket();

    const onNotify = (data: {
      event: string;
      transfer_id: string;
      filename: string;
      file_size: number;
      session_id: string;
    }) => {
      if (data.session_id !== sessionId) return;

      if (data.event === "started") {
        setTransfers((prev) => [
          {
            id: data.transfer_id,
            filename: data.filename,
            fileSize: data.file_size,
            transferred: 0,
            status: "pending",
            direction: "receive",
          },
          ...prev,
        ]);
      } else if (data.event === "completed") {
        setTransfers((prev) =>
          prev.map((t) =>
            t.id === data.transfer_id
              ? {
                  ...t,
                  status: "received",
                  transferred: data.file_size,
                  downloadUrl: `/api/file-transfers/${data.transfer_id}/download`,
                }
              : t
          )
        );
      } else if (data.event === "failed") {
        setTransfers((prev) =>
          prev.map((t) =>
            t.id === data.transfer_id ? { ...t, status: "failed" } : t
          )
        );
      }
    };

    socket.on("file_transfer_notify", onNotify);
    return () => { socket.off("file_transfer_notify", onNotify); };
  }, [sessionId]);

  // ── 파일 업로드 처리 ──
  const uploadFile = useCallback(
    async (file: File) => {
      const socket = getSocket();
      let transferId = "";

      // 1. 전송 초기화
      try {
        const { data } = await client.post("/file-transfers", {
          session_id: sessionId,
          filename: file.name,
          mime_type: file.type || "application/octet-stream",
          file_size: file.size,
          direction: "controller_to_target",
        });
        transferId = data.id;
      } catch {
        return;
      }

      const item: TransferItem = {
        id: transferId,
        filename: file.name,
        fileSize: file.size,
        transferred: 0,
        status: "uploading",
        direction: "send",
      };
      setTransfers((prev) => [item, ...prev]);

      // 상대방에게 시작 알림
      socket.emit("file_transfer_notify", {
        session_id: sessionId,
        event: "started",
        transfer_id: transferId,
        filename: file.name,
        file_size: file.size,
      });

      // 2. 청크 업로드
      try {
        let offset = 0;
        while (offset < file.size) {
          const end = Math.min(offset + CHUNK_SIZE - 1, file.size - 1);
          const chunk = file.slice(offset, end + 1);

          await client.put(`/file-transfers/${transferId}/chunk`, chunk, {
            headers: {
              "Content-Type": "application/octet-stream",
              "Content-Range": `bytes ${offset}-${end}/${file.size}`,
            },
          });

          offset = end + 1;
          setTransfers((prev) =>
            prev.map((t) =>
              t.id === transferId ? { ...t, transferred: offset } : t
            )
          );
        }

        // 3. 완료
        await client.post(`/file-transfers/${transferId}/complete`);

        setTransfers((prev) =>
          prev.map((t) =>
            t.id === transferId
              ? { ...t, status: "completed", transferred: file.size }
              : t
          )
        );

        socket.emit("file_transfer_notify", {
          session_id: sessionId,
          event: "completed",
          transfer_id: transferId,
          filename: file.name,
          file_size: file.size,
        });
      } catch {
        setTransfers((prev) =>
          prev.map((t) =>
            t.id === transferId ? { ...t, status: "failed" } : t
          )
        );
        socket.emit("file_transfer_notify", {
          session_id: sessionId,
          event: "failed",
          transfer_id: transferId,
          filename: file.name,
          file_size: file.size,
        });
      }
    },
    [sessionId]
  );

  const handleFiles = useCallback(
    (files: FileList | null) => {
      if (!files) return;
      Array.from(files).forEach(uploadFile);
    },
    [uploadFile]
  );

  const handleDrop = useCallback(
    (e: React.DragEvent) => {
      e.preventDefault();
      setDragging(false);
      handleFiles(e.dataTransfer.files);
    },
    [handleFiles]
  );

  const removeTransfer = (id: string) =>
    setTransfers((prev) => prev.filter((t) => t.id !== id));

  // ── 렌더링 ──
  return (
    <div className="flex flex-col h-full bg-slate-900 text-white">
      <div className="px-4 py-3 border-b border-slate-700 text-sm font-medium text-slate-300">
        파일 전송
      </div>

      {/* 드래그앤드롭 영역 */}
      <div
        className={`m-3 border-2 border-dashed rounded-xl p-6 text-center cursor-pointer transition-colors ${
          dragging
            ? "border-blue-500 bg-blue-500/10"
            : "border-slate-600 hover:border-slate-500"
        }`}
        onDragOver={(e) => { e.preventDefault(); setDragging(true); }}
        onDragLeave={() => setDragging(false)}
        onDrop={handleDrop}
        onClick={() => fileInputRef.current?.click()}
      >
        <Upload className="w-8 h-8 mx-auto mb-2 text-slate-500" />
        <p className="text-sm text-slate-400">
          파일을 드래그하거나 클릭해서 선택
        </p>
        <p className="text-xs text-slate-600 mt-1">최대 512 MB</p>
        <input
          ref={fileInputRef}
          type="file"
          multiple
          className="hidden"
          onChange={(e) => handleFiles(e.target.files)}
        />
      </div>

      {/* 전송 목록 */}
      <div className="flex-1 overflow-y-auto px-3 space-y-2 pb-3">
        {transfers.length === 0 && (
          <p className="text-center text-slate-600 text-sm py-8">
            전송 내역이 없습니다
          </p>
        )}
        {transfers.map((t) => (
          <TransferRow key={t.id} item={t} onRemove={() => removeTransfer(t.id)} />
        ))}
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// TransferRow
// ─────────────────────────────────────────────────────────────

function TransferRow({ item, onRemove }: { item: TransferItem; onRemove: () => void }) {
  const progress = item.fileSize > 0 ? Math.round((item.transferred / item.fileSize) * 100) : 0;

  const statusIcon = {
    pending:   <Loader2 className="w-4 h-4 text-slate-400 animate-spin" />,
    uploading: <Loader2 className="w-4 h-4 text-blue-400 animate-spin" />,
    completed: <CheckCircle className="w-4 h-4 text-green-400" />,
    failed:    <AlertCircle className="w-4 h-4 text-red-400" />,
    received:  <Download className="w-4 h-4 text-blue-400" />,
  }[item.status];

  return (
    <div className="bg-slate-800 rounded-lg p-3">
      <div className="flex items-start justify-between gap-2">
        <div className="flex items-center gap-2 min-w-0">
          <FileText className="w-4 h-4 text-slate-400 shrink-0" />
          <div className="min-w-0">
            <p className="text-sm text-white truncate">{item.filename}</p>
            <p className="text-xs text-slate-500">
              {formatBytes(item.fileSize)} · {item.direction === "send" ? "송신" : "수신"}
            </p>
          </div>
        </div>
        <div className="flex items-center gap-1.5 shrink-0">
          {statusIcon}
          {(item.status === "completed" || item.status === "failed") && (
            <button onClick={onRemove} className="text-slate-500 hover:text-white">
              <X className="w-3.5 h-3.5" />
            </button>
          )}
        </div>
      </div>

      {/* 진행률 바 */}
      {(item.status === "uploading" || item.status === "pending") && (
        <div className="mt-2">
          <div className="w-full bg-slate-700 rounded-full h-1.5">
            <div
              className="bg-blue-500 h-1.5 rounded-full transition-all"
              style={{ width: `${progress}%` }}
            />
          </div>
          <p className="text-xs text-slate-500 mt-1">{progress}%</p>
        </div>
      )}

      {/* 다운로드 버튼 */}
      {item.status === "received" && item.downloadUrl && (
        <a
          href={item.downloadUrl}
          download={item.filename}
          className="mt-2 flex items-center gap-1.5 text-xs text-blue-400 hover:text-blue-300"
        >
          <Download className="w-3 h-3" /> 다운로드
        </a>
      )}
    </div>
  );
}

function formatBytes(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 ** 2) return `${(bytes / 1024).toFixed(1)} KB`;
  if (bytes < 1024 ** 3) return `${(bytes / 1024 ** 2).toFixed(1)} MB`;
  return `${(bytes / 1024 ** 3).toFixed(1)} GB`;
}

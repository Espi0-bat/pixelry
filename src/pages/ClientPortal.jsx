import { useState, useCallback, useEffect } from "react";
import {
  Home,
  FolderOpen,
  Files,
  MessageCircle,
  Bell,
  CheckCircle2,
  XCircle,
  Clock,
  Zap,
  ChevronRight,
  X,
  FileText,
  Palette,
  Film,
  BarChart2,
  LogOut,
  Upload,
  Download,
  Image,
  Paperclip,
  Send,
} from "lucide-react";
import pixelryLogo from "../components/images/pixelryicone.jpeg";
import { isSupabaseConfigured, supabase } from "../config/supabase";
import styles from "./ClientPortal.module.css";

/* ─────────────────────────────────────────────
   DESIGN TOKENS
───────────────────────────────────────────── */
const C = {
  bg:          "#070710",
  sidebar:     "#0c0c1c",
  card:        "#141430",
  cardHover:   "#1a1a3a",
  border:      "rgba(255, 255, 255, 0.08)",
  borderGlow:  "rgba(128, 64, 245, 0.3)",
  text:        "#f0f0fa",
  textSub:     "rgba(240, 240, 250, 0.55)",
  textMuted:   "rgba(240, 240, 250, 0.32)",
  purple:      "#8040F5",
  indigo:      "#8040F5",
  cyan:        "#00D8FF",
  grad:        "linear-gradient(135deg, #8040F5 0%, #00D8FF 100%)",
  success:     "#25D366",
  amber:       "#f59e0b",
  red:         "#f43f5e",
};

const FONT_DISPLAY = "'Inter', sans-serif";
const FONT_BODY = "'DM Sans', sans-serif";
const FONT_MONO = "'JetBrains Mono', monospace";

const STATUS = {
  pending:    { label: "Aguardando revisão", color: C.amber,   bg: "rgba(245,158,11,0.09)",  border: "rgba(245,158,11,0.22)"  },
  approved:   { label: "Aprovado",           color: C.success, bg: "rgba(37,211,102,0.09)",   border: "rgba(37,211,102,0.22)"  },
  revision:   { label: "Ajuste solicitado",  color: C.red,     bg: "rgba(244,63,94,0.09)",   border: "rgba(244,63,94,0.22)"   },
  production: { label: "Em produção",        color: C.cyan,    bg: "rgba(0,216,255,0.07)",   border: "rgba(0,216,255,0.2)"    },
};

const PIXELRY_FILES = [
  { id: 1, name: "Manual_da_Marca_v2.pdf",      type: "PDF",    size: "4.2 MB",  date: "08 Mai 2026", icon: FileText },
  { id: 2, name: "Landing_Page_Desktop.fig",     type: "Design", size: "18.7 MB", date: "12 Mai 2026", icon: Palette  },
  { id: 3, name: "Relatorio_Trafego_Abril.pdf",  type: "PDF",    size: "2.1 MB",  date: "30 Abr 2026", icon: BarChart2},
  { id: 4, name: "Logo_Pack_Completo.zip",       type: "ZIP",    size: "9.8 MB",  date: "20 Abr 2026", icon: Image   },
];

const TYPE_ICON = {
  Design:    Palette,
  Documento: FileText,
  Vídeo:     Film,
  Relatório: BarChart2,
};

const STATUS_ALIASES = {
  pending: "pending",
  aguardando_revisao: "pending",
  aguardando: "pending",
  approved: "approved",
  aprovado: "approved",
  revision: "revision",
  ajuste_solicitado: "revision",
  in_revision: "revision",
  production: "production",
  em_producao: "production",
  in_production: "production",
};

function normalizeStatus(status) {
  return STATUS_ALIASES[String(status || "").toLowerCase()] || "production";
}

function formatPortalDate(value) {
  if (!value) return "Sem data";

  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return String(value);

  return new Intl.DateTimeFormat("pt-BR", {
    day: "2-digit",
    month: "short",
    year: "numeric",
  })
    .format(date)
    .replace(".", "");
}

function getDeliverySortDate(row) {
  const rawDate = row.due_date || row.delivery_date || row.created_at || row.updated_at;
  const date = new Date(rawDate);
  return Number.isNaN(date.getTime()) ? 0 : date.getTime();
}

function mapDelivery(row) {
  const type = row.type || row.category || row.file_type || "Documento";

  return {
    id: row.id,
    title: row.title || row.name || "Entrega sem título",
    date: formatPortalDate(row.due_date || row.delivery_date || row.created_at || row.updated_at),
    rawDate: row.due_date || row.delivery_date || row.created_at || row.updated_at,
    type,
    status: normalizeStatus(row.status),
    description: row.description || row.notes || row.summary || "Entrega disponível para acompanhamento no portal.",
    source: row,
  };
}

function downloadPortalFile(file) {
  const content = [
    "PIXELRY - Portal do Cliente",
    `Arquivo: ${file.name}`,
    `Tipo: ${file.type}`,
    `Tamanho: ${file.size}`,
    `Data: ${file.date}`,
    "",
    "Este download simula o arquivo dentro do protótipo do portal.",
  ].join("\n");
  const blob = new Blob([content], { type: "text/plain;charset=utf-8" });
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = file.name.replace(/\.[^.]+$/, ".txt");
  document.body.appendChild(link);
  link.click();
  link.remove();
  URL.revokeObjectURL(url);
}

/* ─────────────────────────────────────────────
   SUB-COMPONENTS
───────────────────────────────────────────── */

/** PIXELRY logotipo */
function Logo({ onClick }) {
  return (
    <button
      type="button"
      onClick={onClick}
      aria-label="Voltar para o site da PIXELRY"
      title="Voltar para o site"
      style={{
        display: "flex",
        alignItems: "center",
        gap: 12,
        padding: 0,
        border: "none",
        background: "transparent",
        cursor: "pointer",
        textAlign: "left",
      }}
    >
      <img 
        src={pixelryLogo} 
        alt="PIXELRY" 
        style={{ width: 32, height: 32, borderRadius: 8, objectFit: "cover" }} 
      />
      <div>
        <div style={{
          fontFamily: FONT_DISPLAY,
          fontWeight: 800, fontSize: 15,
          letterSpacing: 1.5, color: C.text,
          lineHeight: 1,
        }}>
          PIXELRY
        </div>
        <div style={{ 
          fontSize: 10, 
          color: C.textSub, 
          letterSpacing: 0.5,
          fontFamily: FONT_BODY,
          marginTop: 2
        }}>
          Portal do Cliente
        </div>
      </div>
    </button>
  );
}

/** Circular progress SVG */
function CircularProgress({ percent, size = 110, stroke = 7, className }) {
  const r   = (size - stroke) / 2;
  const c   = 2 * Math.PI * r;
  const arc = (percent / 100) * c;
  const cx  = size / 2;
  return (
    <svg className={className} width={size} height={size} viewBox={`0 0 ${size} ${size}`} style={{ transform: "rotate(-90deg)" }} aria-hidden="true">
      <defs>
        <linearGradient id="pg" x1="0%" y1="0%" x2="100%" y2="0%">
          <stop offset="0%"   stopColor="#8040F5" />
          <stop offset="100%" stopColor="#00D8FF" />
        </linearGradient>
      </defs>
      <circle cx={cx} cy={cx} r={r} fill="none" stroke="rgba(148,163,184,0.07)" strokeWidth={stroke} />
      <circle
        cx={cx} cy={cx} r={r} fill="none"
        stroke="url(#pg)"
        strokeWidth={stroke}
        strokeLinecap="round"
        strokeDasharray={`${arc} ${c - arc}`}
        style={{ transition: "stroke-dasharray 0.8s ease" }}
      />
    </svg>
  );
}

/** Nav link */
function NavLink({ icon: Icon, label, active, onClick }) {
  return (
    <button
      onClick={onClick}
      style={{
        width: "100%",
        display: "flex", alignItems: "center", gap: 10,
        padding: "9px 11px",
        borderRadius: 9,
        border: "none",
        background: active ? "rgba(128, 64, 245, 0.13)" : "transparent",
        cursor: "pointer",
        color: active ? C.purple : C.textSub,
        fontFamily: FONT_BODY,
        fontSize: 13.5,
        fontWeight: active ? 600 : 400,
        transition: "background 0.15s, color 0.15s",
        textAlign: "left",
      }}
    >
      <Icon size={16} strokeWidth={active ? 2 : 1.5} />
      {label}
      {active && (
        <div style={{
          marginLeft: "auto",
          width: 5, height: 5, borderRadius: "50%",
          background: C.purple,
          boxShadow: `0 0 6px ${C.purple}`,
        }} />
      )}
    </button>
  );
}

/** Metric card */
function MetricCard({ label, value, sub, accent }) {
  return (
    <div className={styles.metricTile}>
      <div style={{
        fontSize: 10, color: C.cyan,
        letterSpacing: 0.15, textTransform: "uppercase",
        fontFamily: FONT_MONO,
        fontWeight: 500,
        marginBottom: 8,
      }}>
        {label}
      </div>
      <div style={{
        fontFamily: FONT_DISPLAY,
        fontWeight: 800, fontSize: 28,
        color: accent || C.text,
        lineHeight: 1,
        marginBottom: 6,
      }}>
        {value}
      </div>
      {sub && (
        <div style={{ fontSize: 11, color: C.textSub, fontFamily: FONT_BODY }}>
          {sub}
        </div>
      )}
    </div>
  );
}

/** Delivery card row */
function DeliveryRow({ item, onClick }) {
  const [hovered, setHovered] = useState(false);
  const s   = STATUS[item.status] || STATUS.production;
  const Icon = TYPE_ICON[item.type] || FileText;

  return (
    <div
      className={styles.deliveryTile}
      onClick={() => onClick(item)}
      onMouseEnter={() => setHovered(true)}
      onMouseLeave={() => setHovered(false)}
      style={{
        display: "flex", alignItems: "center", gap: 14,
        background: hovered ? C.cardHover : C.card,
        border: `1px solid ${hovered ? C.borderGlow : C.border}`,
        borderRadius: 12,
        padding: "14px 18px",
        cursor: "pointer",
        transition: "background 0.18s, border-color 0.18s",
      }}
    >
      {/* Type icon */}
      <div style={{
        width: 38, height: 38, borderRadius: 9, flexShrink: 0,
        background: hovered ? "rgba(128, 64, 245, 0.16)" : "rgba(128, 64, 245, 0.08)",
        display: "flex", alignItems: "center", justifyContent: "center",
        transition: "background 0.18s",
      }}>
        <Icon size={16} color={C.purple} strokeWidth={1.5} />
      </div>

      {/* Info */}
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{
          fontFamily: FONT_BODY,
          fontWeight: 600, fontSize: 14,
          color: C.text, marginBottom: 3,
          whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis",
        }}>
          {item.title}
        </div>
        <div style={{ fontSize: 11, color: C.textSub, fontFamily: FONT_BODY }}>
          {item.date} · {item.type}
        </div>
      </div>

      {/* Status badge */}
      <div style={{
        background: s.bg,
        border: `1px solid ${s.border}`,
        color: s.color,
        fontSize: 11.5, fontWeight: 500,
        padding: "5px 12px", borderRadius: 20,
        fontFamily: FONT_BODY,
        whiteSpace: "nowrap", flexShrink: 0,
      }}>
        {s.label}
      </div>

      <ChevronRight size={14} color={C.textSub} strokeWidth={1.5} style={{ flexShrink: 0 }} />
    </div>
  );
}

/** Delivery modal */
function Modal({ item, onClose, onApprove, onRequestRevision, actionStatus }) {
  useEffect(() => {
    if (!item) return;
    const handler = (e) => { if (e.key === "Escape") onClose(); };
    window.addEventListener("keydown", handler);
    return () => window.removeEventListener("keydown", handler);
  }, [item, onClose]);

  if (!item) return null;

  const s    = STATUS[item.status] || STATUS.production;
  const Icon = TYPE_ICON[item.type] || FileText;
  const isUpdating = actionStatus?.id === item.id;
  const actionLabel =
    actionStatus?.status === "approved"
      ? "Aprovando..."
      : actionStatus?.status === "revision"
        ? "Solicitando ajuste..."
        : "";

  return (
    <div
      className={styles.deliveryModalOverlay}
      onClick={onClose}
      style={{
        position: "fixed", inset: 0,
        background: "rgba(2, 6, 23, 0.88)",
        backdropFilter: "blur(10px)",
        WebkitBackdropFilter: "blur(10px)",
        display: "flex", alignItems: "center", justifyContent: "center",
        zIndex: 100, padding: 24,
      }}
    >
      <div
        className={styles.deliveryModalContent}
        onClick={(e) => e.stopPropagation()}
        style={{
          background: "#0b1628",
          border: `1px solid ${C.borderGlow}`,
          borderRadius: 18,
          padding: "28px 30px",
          maxWidth: 500, width: "100%",
          boxShadow: `0 0 60px rgba(128, 64, 245, 0.12)`,
        }}
      >
        {/* Modal header */}
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-start", marginBottom: 22 }}>
          <div style={{ display: "flex", alignItems: "center", gap: 12 }}>
            <div style={{
              width: 40, height: 40, borderRadius: 9,
              background: "rgba(128, 64, 245, 0.1)",
              display: "flex", alignItems: "center", justifyContent: "center",
            }}>
              <Icon size={18} color={C.purple} strokeWidth={1.5} />
            </div>
            <div>
              <div style={{
                fontFamily: FONT_DISPLAY,
                fontWeight: 700, fontSize: 15,
                color: C.text, marginBottom: 2,
              }}>
                {item.title}
              </div>
              <div style={{ fontSize: 12, color: C.textSub, fontFamily: FONT_BODY }}>
                {item.date} · {item.type}
              </div>
            </div>
          </div>
          <button
            onClick={onClose}
            style={{
              background: "rgba(148,163,184,0.06)",
              border: `1px solid ${C.border}`,
              borderRadius: 8,
              width: 30, height: 30,
              display: "flex", alignItems: "center", justifyContent: "center",
              cursor: "pointer", color: C.textSub,
            }}
          >
            <X size={14} />
          </button>
        </div>

        {/* Status info */}
        <div style={{
          background: s.bg,
          border: `1px solid ${s.border}`,
          borderRadius: 10,
          padding: "14px 16px",
          marginBottom: 18,
        }}>
          <div style={{
            fontSize: 10, color: s.color, fontWeight: 700,
            letterSpacing: 1.2, textTransform: "uppercase",
            fontFamily: FONT_DISPLAY,
            marginBottom: 5,
          }}>
            Status · {s.label}
          </div>
          <div style={{ fontSize: 13.5, color: C.text, fontFamily: FONT_BODY, lineHeight: 1.6 }}>
            {item.description}
          </div>
        </div>

        {/* Preview area */}
        <div style={{
          background: "rgba(128, 64, 245, 0.03)",
          border: `1px dashed rgba(128, 64, 245, 0.15)`,
          borderRadius: 11,
          height: 150,
          display: "flex", alignItems: "center", justifyContent: "center",
          flexDirection: "column", gap: 8,
          marginBottom: 20,
          color: C.textSub,
          fontFamily: FONT_BODY,
        }}>
          <Icon size={28} strokeWidth={1} color="rgba(128, 64, 245, 0.3)" />
          <span style={{ fontSize: 12 }}>Pré-visualização do arquivo</span>
        </div>

        {/* Action buttons — only for pending items */}
        {item.status === "pending" ? (
          <div style={{ display: "flex", flexDirection: "column", gap: 12 }}>
            <p style={{
              margin: 0,
              color: C.textSub,
              fontFamily: FONT_BODY,
              fontSize: 12.5,
              lineHeight: 1.6,
            }}>
              Ao aprovar esta entrega, você confirma que o layout está em conformidade com o planejado.
            </p>
            {isUpdating && (
              <div style={{ fontSize: 12, color: C.cyan, fontFamily: FONT_BODY }}>
                {actionLabel}
              </div>
            )}
            <div style={{ display: "flex", gap: 10 }}>
              <button
                onClick={() => onApprove(item.id)}
                disabled={isUpdating}
                style={{
                  flex: 1, padding: "13px",
                  borderRadius: 10, border: "none",
                  background: C.grad,
                  color: "#fff",
                  fontFamily: FONT_DISPLAY,
                  fontWeight: 700, fontSize: 13.5,
                  cursor: isUpdating ? "not-allowed" : "pointer",
                  opacity: isUpdating ? 0.7 : 1,
                  display: "flex", alignItems: "center", justifyContent: "center", gap: 7,
                }}
              >
                <CheckCircle2 size={15} /> Aprovar
              </button>
              <button
                onClick={() => onRequestRevision(item.id)}
                disabled={isUpdating}
                style={{
                  flex: 1, padding: "13px",
                  borderRadius: 10,
                  background: "rgba(244,63,94,0.08)",
                  border: `1px solid rgba(244,63,94,0.22)`,
                  color: C.red,
                  fontFamily: FONT_BODY,
                  fontWeight: 600, fontSize: 13.5,
                  cursor: isUpdating ? "not-allowed" : "pointer",
                  opacity: isUpdating ? 0.7 : 1,
                  display: "flex", alignItems: "center", justifyContent: "center", gap: 7,
                }}
              >
                <XCircle size={15} /> Solicitar Ajuste
              </button>
            </div>
          </div>
        ) : (
          <div style={{
            textAlign: "center", fontSize: 12.5, color: C.textSub,
            fontFamily: FONT_BODY,
            padding: "10px 0 2px",
          }}>
            {item.status === "approved" && "✓ Entrega aprovada — nenhuma ação necessária."}
            {item.status === "revision" && "Aguardando nossa equipe aplicar os ajustes solicitados."}
            {item.status === "production" && "Em produção — em breve disponível para revisão."}
          </div>
        )}
      </div>
    </div>
  );
}

/* ─────────────────────────────────────────────
   UPLOAD ZONE
───────────────────────────────────────────── */
function UploadZone({ uploads, setUploads }) {
  const [dragging, setDragging] = useState(false);

  const processFiles = useCallback((files) => {
    const newUploads = Array.from(files).map((f, i) => ({
      id: Date.now() + i,
      name: f.name,
      size: (f.size / 1024 / 1024).toFixed(1) + " MB",
      progress: 0,
      done: false,
    }));
    setUploads((prev) => [...prev, ...newUploads]);
    newUploads.forEach((u) => {
      let p = 0;
      const iv = setInterval(() => {
        p += Math.random() * 18 + 8;
        if (p >= 100) { p = 100; clearInterval(iv); }
        setUploads((prev) =>
          prev.map((x) => x.id === u.id ? { ...x, progress: Math.floor(p), done: p >= 100 } : x)
        );
      }, 200);
    });
  }, [setUploads]);

  const onDrop = useCallback((e) => {
    e.preventDefault(); setDragging(false);
    processFiles(e.dataTransfer.files);
  }, [processFiles]);

  const typeIcon = (name) => {
    const ext = name.split(".").pop().toLowerCase();
    if (["jpg","jpeg","png","gif","webp","svg"].includes(ext)) return Image;
    if (["pdf"].includes(ext)) return FileText;
    if (["fig","psd","ai","sketch"].includes(ext)) return Palette;
    return Paperclip;
  };

  return (
    <div>
      {/* Drop area */}
      <div
        className={styles.uploadDropzone}
        onDragOver={(e) => { e.preventDefault(); setDragging(true); }}
        onDragLeave={() => setDragging(false)}
        onDrop={onDrop}
        onClick={() => document.getElementById("px-file-input").click()}
        style={{
          border: `2px dashed ${dragging ? C.cyan : "rgba(128,64,245,0.4)"}`,
          borderRadius: 16,
          padding: "36px 24px",
          textAlign: "center",
          cursor: "pointer",
          background: dragging
            ? "rgba(0,216,255,0.05)"
            : "rgba(128,64,245,0.04)",
          backdropFilter: "blur(12px)",
          WebkitBackdropFilter: "blur(12px)",
          transition: "all 0.2s ease",
          boxShadow: dragging ? `0 0 40px rgba(0,216,255,0.12)` : "none",
        }}
      >
        <input
          id="px-file-input"
          type="file"
          multiple
          style={{ display: "none" }}
          onChange={(e) => processFiles(e.target.files)}
        />
        <div style={{
          width: 52, height: 52, borderRadius: "50%",
          background: C.grad,
          display: "flex", alignItems: "center", justifyContent: "center",
          margin: "0 auto 14px",
          boxShadow: "0 0 24px rgba(128,64,245,0.35)",
        }}>
          <Upload size={22} color="#fff" />
        </div>
        <div style={{ fontFamily: FONT_DISPLAY, fontWeight: 700, fontSize: 15, color: C.text, marginBottom: 6 }}>
          {dragging ? "Solte o arquivo aqui" : "Arraste arquivos ou clique"}
        </div>
        <div style={{ fontFamily: FONT_BODY, fontSize: 12, color: C.textSub }}>
          PDF, Imagens, Figma, ZIP — Máx. 50 MB
        </div>
      </div>

      {/* Upload list */}
      {uploads.length > 0 && (
        <div style={{ marginTop: 18, display: "flex", flexDirection: "column", gap: 10 }}>
          {uploads.map((u) => {
            const Icon = typeIcon(u.name);
            return (
              <div key={u.id} style={{
                background: C.card,
                border: `1px solid ${u.done ? "rgba(37,211,102,0.25)" : C.border}`,
                borderRadius: 12,
                padding: "12px 14px",
                display: "flex", alignItems: "center", gap: 12,
              }}>
                <div style={{
                  width: 34, height: 34, borderRadius: 8, flexShrink: 0,
                  background: u.done ? "rgba(37,211,102,0.1)" : "rgba(128, 64, 245, 0.1)",
                  display: "flex", alignItems: "center", justifyContent: "center",
                }}>
                  <Icon size={15} color={u.done ? C.success : C.purple} strokeWidth={1.5} />
                </div>
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div style={{
                    fontFamily: FONT_BODY, fontWeight: 500, fontSize: 13,
                    color: C.text, marginBottom: 4,
                    whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis",
                  }}>{u.name}</div>
                  {!u.done ? (
                    <div style={{ background: "rgba(255,255,255,0.06)", borderRadius: 4, height: 4 }}>
                      <div style={{
                        height: "100%", borderRadius: 4,
                        background: C.grad,
                        width: `${u.progress}%`,
                        transition: "width 0.15s ease",
                      }} />
                    </div>
                  ) : (
                    <div style={{ fontSize: 11, color: C.success, fontFamily: FONT_MONO }}>✓ Enviado — {u.size}</div>
                  )}
                </div>
                {!u.done && (
                  <div style={{ fontSize: 11, fontFamily: FONT_MONO, color: C.textSub, flexShrink: 0 }}>
                    {u.progress}%
                  </div>
                )}
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}

/* ─────────────────────────────────────────────
   FILE ROW (needs its own component for hover state)
───────────────────────────────────────────── */
function FileRow({ f, onDownload }) {
  const [hov, setHov] = useState(false);
  const Icon = f.icon;
  return (
    <div
      className={styles.fileTile}
      role="button"
      tabIndex={0}
      onClick={() => onDownload(f)}
      onKeyDown={(e) => {
        if (e.key === "Enter" || e.key === " ") {
          e.preventDefault();
          onDownload(f);
        }
      }}
      onMouseEnter={() => setHov(true)}
      onMouseLeave={() => setHov(false)}
      style={{
        display: "flex", alignItems: "center", gap: 14,
        background: hov ? C.cardHover : C.card,
        border: `1px solid ${hov ? C.borderGlow : C.border}`,
        borderRadius: 13, padding: "14px 18px", cursor: "pointer",
        transition: "all 0.18s ease",
        backdropFilter: "blur(8px)", WebkitBackdropFilter: "blur(8px)",
      }}
    >
      <div style={{
        width: 40, height: 40, borderRadius: 10, flexShrink: 0,
        background: hov ? "rgba(128, 64, 245, 0.18)" : "rgba(128, 64, 245, 0.08)",
        display: "flex", alignItems: "center", justifyContent: "center",
        transition: "background 0.18s",
      }}>
        <Icon size={17} color={C.purple} strokeWidth={1.5} />
      </div>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ fontFamily: FONT_BODY, fontWeight: 600, fontSize: 14, color: C.text, marginBottom: 3 }}>{f.name}</div>
        <div style={{ fontSize: 11, color: C.textSub, fontFamily: FONT_BODY }}>{f.type} · {f.size} · {f.date}</div>
      </div>
      <div style={{
        display: "flex", alignItems: "center", gap: 8,
        padding: "7px 14px", borderRadius: 20,
        background: hov ? "rgba(0,216,255,0.1)" : "transparent",
        border: `1px solid ${hov ? C.cyan : "transparent"}`,
        color: hov ? C.cyan : C.textSub,
        fontSize: 11, fontFamily: FONT_MONO, flexShrink: 0,
        transition: "all 0.18s ease",
      }}>
        <Download size={12} strokeWidth={1.5} /> Baixar
      </div>
    </div>
  );
}

/* ─────────────────────────────────────────────
   FILES VIEW
───────────────────────────────────────────── */
function FilesView() {
  const [uploads, setUploads] = useState([]);

  return (
    <div className={styles.filesGrid}>
      {/* Left — Pixelry files */}
      <div>
        <div style={{ marginBottom: 20 }}>
          <div style={{ fontSize: 10, color: C.cyan, letterSpacing: 2, textTransform: "uppercase", fontFamily: FONT_MONO, fontWeight: 500, marginBottom: 6 }}>
            Operação Pixelry
          </div>
          <h2 style={{ fontFamily: FONT_DISPLAY, fontWeight: 700, fontSize: 22, color: C.text, letterSpacing: "-0.01em", margin: 0 }}>
            Documentos e Entregas
          </h2>
        </div>
        <div style={{ display: "flex", flexDirection: "column", gap: 8 }}>
          {PIXELRY_FILES.map((f) => <FileRow key={f.id} f={f} onDownload={downloadPortalFile} />)}
        </div>
      </div>

      {/* Right — Upload */}
      <div className={styles.uploadPanel} style={{
        background: "rgba(20,20,48,0.5)",
        backdropFilter: "blur(20px)",
        WebkitBackdropFilter: "blur(20px)",
        border: `1px solid ${C.border}`,
        borderRadius: 18,
        padding: "24px",
        boxShadow: "0 0 60px rgba(128, 64, 245, 0.06)",
      }}>
        <div style={{ marginBottom: 18 }}>
          <div style={{ fontSize: 10, color: C.cyan, letterSpacing: 2, textTransform: "uppercase", fontFamily: FONT_MONO, fontWeight: 500, marginBottom: 6 }}>
            Enviar Material
          </div>
          <h2 style={{ fontFamily: FONT_DISPLAY, fontWeight: 700, fontSize: 18, color: C.text, margin: 0, letterSpacing: "-0.01em" }}>
            Ativos e Documentação
          </h2>
          <p style={{ fontFamily: FONT_BODY, fontSize: 12, color: C.textSub, marginTop: 6, lineHeight: 1.6 }}>
            Compartilhe materiais de referência, logos ou briefings com a equipe.
          </p>
        </div>
        <UploadZone uploads={uploads} setUploads={setUploads} />
      </div>
    </div>
  );
}

/* ─────────────────────────────────────────────
   PROJECTS VIEW (placeholder)
───────────────────────────────────────────── */
function ProjectsView() {
  return (
    <div className={styles.emptyState}>
      <div style={{
        width: 64, height: 64, borderRadius: "50%",
        background: "rgba(128, 64, 245, 0.08)",
        border: `1px solid rgba(128, 64, 245, 0.2)`,
        display: "flex", alignItems: "center", justifyContent: "center",
      }}>
        <FolderOpen size={26} color={C.purple} strokeWidth={1.2} />
      </div>
      <div style={{ fontFamily: FONT_DISPLAY, fontWeight: 700, fontSize: 18, color: C.text }}>Projetos</div>
      <div style={{ fontFamily: FONT_BODY, fontSize: 13, color: C.textSub, textAlign: "center", maxWidth: 300, lineHeight: 1.65 }}>
        Todos os seus projetos ativos e histórico de trabalhos realizados aparecerão aqui.
      </div>
      <div style={{
        marginTop: 8, padding: "8px 20px", borderRadius: 20,
        background: "rgba(128, 64, 245, 0.1)", border: `1px solid rgba(128, 64, 245, 0.25)`,
        color: C.purple, fontSize: 12, fontFamily: FONT_MONO,
      }}>Em breve</div>
    </div>
  );
}

/* ─────────────────────────────────────────────
   SUPPORT VIEW (placeholder)
───────────────────────────────────────────── */
function SupportView() {
  const [msg, setMsg] = useState("");
  return (
    <div className={styles.supportView}>
      <div style={{ marginBottom: 24 }}>
        <div style={{ fontSize: 10, color: C.cyan, letterSpacing: 2, textTransform: "uppercase", fontFamily: FONT_MONO, fontWeight: 500, marginBottom: 6 }}>Central de Atendimento</div>
        <h2 style={{ fontFamily: FONT_DISPLAY, fontWeight: 700, fontSize: 22, color: C.text, margin: 0, letterSpacing: "-0.01em" }}>Fale com a equipe</h2>
        <p style={{ fontFamily: FONT_BODY, fontSize: 13, color: C.textSub, marginTop: 8, lineHeight: 1.65 }}>Dúvidas, feedback ou solicitações — respondemos em até 24h.</p>
      </div>
      <div style={{
        background: "rgba(20,20,48,0.5)",
        backdropFilter: "blur(16px)",
        WebkitBackdropFilter: "blur(16px)",
        border: `1px solid ${C.border}`,
        borderRadius: 16,
        padding: 24,
      }}>
        <textarea
          value={msg}
          onChange={(e) => setMsg(e.target.value)}
          placeholder="Descreva sua dúvida ou solicitação..."
          rows={5}
          style={{
            width: "100%", resize: "none",
            background: "rgba(255,255,255,0.04)",
            border: `1px solid ${C.border}`,
            borderRadius: 10,
            padding: "14px 16px",
            color: C.text,
            fontFamily: FONT_BODY,
            fontSize: 14,
            lineHeight: 1.65,
            outline: "none",
            boxSizing: "border-box",
          }}
        />
        <div style={{ marginTop: 12, display: "flex", justifyContent: "flex-end" }}>
          <button
            onClick={() => { alert("Mensagem enviada! Responderemos em breve."); setMsg(""); }}
            style={{
              display: "flex", alignItems: "center", gap: 8,
              padding: "11px 24px", borderRadius: 10,
              background: C.grad,
              border: "none", color: "#fff",
              fontFamily: FONT_DISPLAY, fontWeight: 700, fontSize: 13,
              cursor: "pointer",
              boxShadow: "0 0 20px rgba(128, 64, 245, 0.3)",
            }}
          >
            <Send size={14} /> Enviar mensagem
          </button>
        </div>
      </div>
    </div>
  );
}

/* ─────────────────────────────────────────────
   MAIN COMPONENT
───────────────────────────────────────────── */
export default function ClientPortal({ user, onLogout }) {
  const [activeNav,        setActiveNav]        = useState("Início");
  const [selectedDelivery, setSelectedDelivery] = useState(null);
  const [deliveries,       setDeliveries]       = useState([]);
  const [loadingDeliveries, setLoadingDeliveries] = useState(true);
  const [deliveriesError, setDeliveriesError] = useState("");
  const [actionStatus, setActionStatus] = useState(null);
  const clientName =
    user?.user_metadata?.name ||
    user?.user_metadata?.full_name ||
    user?.email?.split("@")[0] ||
    "Cliente";
  const clientInitials = clientName
    .split(/\s+/)
    .filter(Boolean)
    .slice(0, 2)
    .map((part) => part[0])
    .join("")
    .toUpperCase();

  const NAV = [
    { icon: Home,          label: "Início"   },
    { icon: FolderOpen,    label: "Projetos" },
    { icon: Files,         label: "Ativos e Documentação" },
    { icon: MessageCircle, label: "Central de Atendimento"  },
  ];

  const pendingCount = deliveries.filter((d) => d.status === "pending").length;
  const firstPending = deliveries.find((d) => d.status === "pending");
  const approvedCount = deliveries.filter((d) => d.status === "approved").length;
  const activeCount = deliveries.filter((d) => d.status !== "approved").length;
  const nextDelivery = deliveries
    .filter((d) => d.rawDate && d.status !== "approved")
    .sort((a, b) => getDeliverySortDate(a.source) - getDeliverySortDate(b.source))[0];
  const progressPercent = deliveries.length ? Math.round((approvedCount / deliveries.length) * 100) : 0;
  const currentPhase = pendingCount > 0 ? "Revisão" : activeCount > 0 ? "Implementação" : "Sem entregas";

  const loadDeliveries = useCallback(async () => {
    if (!isSupabaseConfigured || !supabase || !user?.id) {
      setDeliveries([]);
      setLoadingDeliveries(false);
      return;
    }

    setLoadingDeliveries(true);
    setDeliveriesError("");

    const { data, error } = await supabase
      .from("deliveries")
      .select("*");

    if (error) {
      setDeliveries([]);
      setDeliveriesError("Não foi possível carregar suas entregas agora.");
      setLoadingDeliveries(false);
      return;
    }

    setDeliveries((data || []).map(mapDelivery).sort((a, b) => getDeliverySortDate(b.source) - getDeliverySortDate(a.source)));
    setLoadingDeliveries(false);
  }, [user?.id]);

  useEffect(() => {
    loadDeliveries();
  }, [loadDeliveries]);

  const PAGE_TITLES = {
    "Início":   { supra: "Bem-vindo de volta",      h1: "Olá, Ezer 👋"  },
    "Projetos": { supra: "Operação Pixelry",         h1: "Seus Projetos"  },
    "Ativos e Documentação": { supra: "Operação Pixelry",         h1: "Ativos e Documentação" },
    "Central de Atendimento": { supra: "Estamos aqui para ajudar", h1: "Central de Atendimento" },
  };

  const page =
    activeNav === NAV[0].label
      ? { ...PAGE_TITLES[activeNav], h1: `Olá, ${clientName}` }
      : PAGE_TITLES[activeNav];

  const updateDeliveryStatus = async (id, status) => {
    if (!isSupabaseConfigured || !supabase) {
      setDeliveriesError("O portal ainda não está conectado ao Supabase neste deploy.");
      return;
    }

    const previousDeliveries = deliveries;
    setActionStatus({ id, status });
    setDeliveriesError("");
    setDeliveries((current) =>
      current.map((delivery) =>
        delivery.id === id
          ? {
              ...delivery,
              status,
              description:
                status === "approved"
                  ? "Entrega aprovada pelo cliente no portal."
                  : "Ajuste solicitado pelo cliente no portal. Nossa equipe vai revisar os pontos enviados.",
            }
          : delivery
      )
    );
    const { error } = await supabase
      .from("deliveries")
      .update({ status })
      .eq("id", id);

    if (error) {
      setDeliveries(previousDeliveries);
      setDeliveriesError("Não foi possível atualizar o status da entrega. Tente novamente.");
      setActionStatus(null);
      return;
    }
    setActionStatus(null);
    setSelectedDelivery(null);
    setActiveNav("Início");
  };

  const handleNotificationClick = () => {
    setActiveNav("Início");
    if (firstPending) {
      setSelectedDelivery(firstPending);
    }
  };

  return (
    <div className={styles.dashboardContainer} style={{
      display: "flex", height: "100vh",
      background: C.bg,
      fontFamily: FONT_BODY,
      color: C.text,
      overflow: "hidden",
    }}>
      {/* ── SIDEBAR ── */}
      <aside className={styles.portalSidebar} style={{
        width: 228, flexShrink: 0,
        background: "rgba(12,12,28,0.85)",
        backdropFilter: "blur(20px)",
        WebkitBackdropFilter: "blur(20px)",
        borderRight: `1px solid ${C.border}`,
        display: "flex", flexDirection: "column",
        padding: "22px 14px",
        boxShadow: "4px 0 40px rgba(0,0,0,0.3)",
      }}>
        <div className={styles.sidebarBrand}>
          <Logo onClick={onLogout} />
        </div>

        <nav className={styles.sidebarNav} style={{ flex: 1, display: "flex", flexDirection: "column", gap: 3 }}>
          {NAV.map(({ icon, label }) => (
            <NavLink key={label} icon={icon} label={label}
              active={activeNav === label} onClick={() => setActiveNav(label)} />
          ))}
        </nav>

        <div className={styles.sidebarDivider} style={{ borderTop: `1px solid ${C.border}`, marginBottom: 14 }} />

        <div className={styles.sidebarProfile} style={{ display: "flex", alignItems: "center", gap: 10 }}>
          <div style={{
            width: 34, height: 34, borderRadius: "50%",
            background: C.grad,
            display: "flex", alignItems: "center", justifyContent: "center",
            fontFamily: FONT_DISPLAY, fontWeight: 800, fontSize: 12, color: "#fff",
            flexShrink: 0, letterSpacing: 0.5,
            boxShadow: "0 0 14px rgba(128, 64, 245, 0.4)",
          }}>{clientInitials || "CL"}</div>
          <div style={{ flex: 1, minWidth: 0 }}>
            <div style={{ fontSize: 13, fontWeight: 600, color: C.text }}>{clientName}</div>
            <div style={{ fontSize: 11, color: C.textSub }}>Plano Premium</div>
          </div>
          <button
            type="button"
            onClick={onLogout}
            aria-label="Sair do portal"
            title="Sair do portal"
            style={{
              width: 30,
              height: 30,
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
              border: "none",
              borderRadius: 8,
              background: "transparent",
              cursor: "pointer",
              flexShrink: 0,
            }}
          >
            <LogOut size={14} color={C.textSub} strokeWidth={1.5} />
          </button>
        </div>
      </aside>

      {/* ── MAIN CONTENT ── */}
      <main className={styles.portalMain} style={{ flex: 1, overflow: "auto", padding: "32px 36px" }}>

        {/* Header */}
        <div className={styles.portalHeader} style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-start", marginBottom: 32 }}>
          <div>
            <div style={{
              fontSize: 10, color: C.cyan,
              letterSpacing: 2, textTransform: "uppercase",
              fontFamily: FONT_MONO, marginBottom: 5, fontWeight: 500,
            }}>{page.supra}</div>
            <h1 style={{
              fontFamily: FONT_DISPLAY, fontWeight: 800, fontSize: 32,
              margin: 0, color: C.text, letterSpacing: "-0.02em",
            }}>{page.h1}</h1>
          </div>

          <div className={styles.notificationWrap} style={{ position: "relative" }}>
            <button
              type="button"
              onClick={handleNotificationClick}
              aria-label={pendingCount > 0 ? `Abrir ${pendingCount} entrega pendente` : "Sem notificações pendentes"}
              title={pendingCount > 0 ? "Abrir pendência" : "Sem pendências"}
              style={{
              width: 40, height: 40, borderRadius: 11,
              background: "rgba(20,20,48,0.6)",
              backdropFilter: "blur(12px)", WebkitBackdropFilter: "blur(12px)",
              border: `1px solid ${C.border}`,
              display: "flex", alignItems: "center", justifyContent: "center",
              cursor: "pointer",
            }}>
              <Bell size={16} color={C.textSub} strokeWidth={1.5} />
            </button>
            {pendingCount > 0 && (
              <div style={{
                position: "absolute", top: -3, right: -3,
                width: 16, height: 16, borderRadius: "50%",
                background: C.red,
                display: "flex", alignItems: "center", justifyContent: "center",
                fontSize: 9, fontWeight: 700, color: "#fff",
                border: `2px solid ${C.bg}`,
              }}>{pendingCount}</div>
            )}
          </div>
        </div>

        {/* ── PER-TAB CONTENT ── */}
        {activeNav === "Início" && (
          <>
            <div className={styles.metricGrid} style={{ display: "grid", gridTemplateColumns: "1fr 1fr 1fr 1fr", gap: 14, marginBottom: 32 }}>
              <div className={styles.progressTile} style={{
                background: "rgba(20,20,48,0.6)",
                backdropFilter: "blur(16px)", WebkitBackdropFilter: "blur(16px)",
                border: `1px solid ${C.border}`, borderRadius: 14,
                padding: "22px 20px", display: "flex", alignItems: "center", gap: 18,
                boxShadow: "0 8px 32px rgba(0,0,0,0.2)",
              }}>
                <div className={styles.progressRingWrap}>
                  <CircularProgress percent={progressPercent} className={styles.progressRing} />
                  <div className={styles.progressPercentWrap}>
                    <span className={styles.progressPercent} style={{ color: C.text }}>{progressPercent}%</span>
                  </div>
                </div>
                <div className={styles.progressTileText}>
                  <div className={styles.progressEyebrow} style={{ color: C.cyan }}>Fase Atual</div>
                  <div className={styles.progressPhase} style={{ color: C.text }}>{currentPhase}</div>
                  <div className={styles.progressMeta} style={{ color: C.textSub }}>{approvedCount} de {deliveries.length} entregas aprovadas</div>
                </div>
              </div>
              <MetricCard label="Entregas Ativas" value={String(activeCount)} sub={`${pendingCount} aguardando revisão`} accent={C.cyan} />
              <MetricCard label="Documentos Prontos" value={String(approvedCount)} sub="Aprovados no portal" />
              <MetricCard label="Próxima Entrega" value={nextDelivery ? nextDelivery.date : "--"} sub={nextDelivery ? nextDelivery.title : "Sem entregas agendadas"} accent={C.purple} />
            </div>

            <div className={styles.deliverySection}>
              <div className={styles.deliverySectionHeader} style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 14 }}>
                <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
                  <h2 style={{ fontFamily: FONT_DISPLAY, fontWeight: 700, fontSize: 18, margin: 0, color: C.text, letterSpacing: "-0.01em" }}>
                    Entregas &amp; Aprovações
                  </h2>
                  {pendingCount > 0 && (
                    <div style={{
                      background: "rgba(245,158,11,0.1)", border: "1px solid rgba(245,158,11,0.22)",
                      color: C.amber, fontSize: 11, fontWeight: 500,
                      padding: "3px 9px", borderRadius: 20, fontFamily: FONT_BODY,
                      display: "flex", alignItems: "center", gap: 4,
                    }}>
                      <Clock size={11} /> {pendingCount} aguardando
                    </div>
                  )}
                </div>
                <button
                  type="button"
                  onClick={() => setActiveNav("Ativos e Documentação")}
                  style={{
                    display: "flex",
                    alignItems: "center",
                    gap: 4,
                    padding: 0,
                    border: "none",
                    background: "transparent",
                    fontSize: 12,
                    color: C.textSub,
                    cursor: "pointer",
                    fontFamily: FONT_BODY,
                  }}
                >
                  Ver todas <Zap size={12} strokeWidth={1.5} />
                </button>
              </div>
              <div className={styles.deliveryStack} style={{ display: "flex", flexDirection: "column", gap: 8 }}>
                {loadingDeliveries && (
                  <div className={styles.emptyState} style={{ minHeight: 180 }}>
                    <Clock size={24} color={C.cyan} strokeWidth={1.5} />
                    <div style={{ fontFamily: FONT_DISPLAY, fontWeight: 700, fontSize: 18, color: C.text }}>Carregando entregas</div>
                    <div style={{ fontFamily: FONT_BODY, fontSize: 13, color: C.textSub }}>Buscando seus dados no Supabase.</div>
                  </div>
                )}

                {!loadingDeliveries && deliveriesError && (
                  <div className={styles.emptyState} style={{ minHeight: 180 }}>
                    <XCircle size={24} color={C.red} strokeWidth={1.5} />
                    <div style={{ fontFamily: FONT_DISPLAY, fontWeight: 700, fontSize: 18, color: C.text }}>Erro ao carregar</div>
                    <div style={{ fontFamily: FONT_BODY, fontSize: 13, color: C.textSub }}>{deliveriesError}</div>
                    <button
                      type="button"
                      onClick={loadDeliveries}
                      style={{
                        marginTop: 8,
                        padding: "9px 18px",
                        borderRadius: 10,
                        border: `1px solid ${C.borderGlow}`,
                        background: "rgba(128, 64, 245, 0.12)",
                        color: C.text,
                        fontFamily: FONT_BODY,
                        fontSize: 12,
                        cursor: "pointer",
                      }}
                    >
                      Tentar novamente
                    </button>
                  </div>
                )}

                {!loadingDeliveries && !deliveriesError && deliveries.length === 0 && (
                  <div className={styles.emptyState} style={{ minHeight: 180 }}>
                    <FolderOpen size={24} color={C.purple} strokeWidth={1.5} />
                    <div style={{ fontFamily: FONT_DISPLAY, fontWeight: 700, fontSize: 18, color: C.text }}>Nenhuma entrega por aqui</div>
                    <div style={{ fontFamily: FONT_BODY, fontSize: 13, color: C.textSub }}>Quando a equipe publicar uma entrega para este cliente, ela aparecerá aqui.</div>
                  </div>
                )}

                {!loadingDeliveries && !deliveriesError && deliveries.map((d) => (
                  <DeliveryRow key={d.id} item={d} onClick={setSelectedDelivery} />
                ))}
              </div>
            </div>
          </>
        )}

        {activeNav === "Projetos" && <ProjectsView />}
        {activeNav === "Ativos e Documentação" && <FilesView />}
        {activeNav === "Central de Atendimento"  && <SupportView />}

      </main>

      <Modal
        item={selectedDelivery}
        onClose={() => setSelectedDelivery(null)}
        onApprove={(id) => updateDeliveryStatus(id, "approved")}
        onRequestRevision={(id) => updateDeliveryStatus(id, "revision")}
        actionStatus={actionStatus}
      />
      <nav className={styles.mobileBottomNav} aria-label="Navegação do portal">
        {NAV.map(({ icon: Icon, label }) => (
          <button
            key={label}
            type="button"
            className={`${styles.mobileNavButton} ${activeNav === label ? styles.mobileNavButtonActive : ""}`}
            onClick={() => setActiveNav(label)}
            aria-current={activeNav === label ? "page" : undefined}
          >
            <Icon size={18} strokeWidth={activeNav === label ? 2.2 : 1.7} />
            <span>{label}</span>
          </button>
        ))}
      </nav>
    </div>
  );
}

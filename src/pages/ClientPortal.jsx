import { useState, useCallback, useEffect, useRef } from "react";
import { useNavigate } from "react-router-dom";
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
  Eye,
  Users,
  TrendingUp,
  ArrowRight,
  Filter,
  CheckSquare,
  Circle,
} from "lucide-react";
import { motion, AnimatePresence } from "framer-motion";
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


const TYPE_ICON = {
  Design:    Palette,
  Documento: FileText,
  Vídeo:     Film,
  Relatório: BarChart2,
};

const ICON_TONES = {
  design: {
    color: "#8040F5",
    bg: "rgba(128, 64, 245, 0.12)",
    bgHover: "rgba(128, 64, 245, 0.2)",
    border: "rgba(128, 64, 245, 0.32)",
    glow: "rgba(128, 64, 245, 0.42)",
  },
  document: {
    color: "#00D8FF",
    bg: "rgba(0, 216, 255, 0.1)",
    bgHover: "rgba(0, 216, 255, 0.18)",
    border: "rgba(0, 216, 255, 0.3)",
    glow: "rgba(0, 216, 255, 0.38)",
  },
  report: {
    color: "#10B981",
    bg: "rgba(16, 185, 129, 0.1)",
    bgHover: "rgba(16, 185, 129, 0.18)",
    border: "rgba(16, 185, 129, 0.3)",
    glow: "rgba(16, 185, 129, 0.36)",
  },
  warning: {
    color: "#F59E0B",
    bg: "rgba(245, 158, 11, 0.1)",
    bgHover: "rgba(245, 158, 11, 0.18)",
    border: "rgba(245, 158, 11, 0.32)",
    glow: "rgba(245, 158, 11, 0.36)",
  },
  media: {
    color: "#EC4899",
    bg: "rgba(236, 72, 153, 0.1)",
    bgHover: "rgba(236, 72, 153, 0.18)",
    border: "rgba(236, 72, 153, 0.3)",
    glow: "rgba(236, 72, 153, 0.35)",
  },
};

function getIconTone(item = {}) {
  const type = String(item.type || "").toLowerCase();
  const name = String(item.name || item.title || "").toLowerCase();
  const status = String(item.status || "").toLowerCase();
  const signal = `${type} ${name}`;

  if (status.includes("pending") || status.includes("revision") || status.includes("ajuste")) return ICON_TONES.warning;
  if (signal.includes("relat") || signal.includes("trafego") || signal.includes("tráfego") || signal.includes("chart")) return ICON_TONES.report;
  if (signal.includes("design") || signal.includes("fig") || signal.includes("psd") || signal.includes("sketch")) return ICON_TONES.design;
  if (signal.includes("image") || signal.includes("logo") || signal.includes("zip") || signal.includes("pack")) return ICON_TONES.media;
  return ICON_TONES.document;
}

function IconFrame({ icon: Icon, tone, hovered, size = 17 }) {
  return (
    <div
      className={styles.semanticIconFrame}
      data-active={hovered ? "true" : "false"}
      style={{
        "--icon-color": tone.color,
        "--icon-bg": hovered ? tone.bgHover : tone.bg,
        "--icon-border": tone.border,
        "--icon-glow": tone.glow,
      }}
    >
      <Icon size={size} strokeWidth={1.65} />
    </div>
  );
}

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

const DELIVERY_SELECT_FIELDS = "id,title,created_at,updated_at,due_date,type,status,description,file_url";
const CLIENT_MUTABLE_STATUSES = new Set(["approved", "revision"]);

function getFileTypeName(name) {
  const ext = String(name || "").split(".").pop().toLowerCase();
  if (["jpg","jpeg","png","gif","webp","svg"].includes(ext)) return "Imagem";
  if (ext === "pdf") return "PDF";
  if (["fig","psd","ai","sketch"].includes(ext)) return "Design";
  if (ext === "zip") return "ZIP";
  return "Documento";
}

function mapAsset(row) {
  const typeLower = String(row.file_type || "").toLowerCase();
  const nameLower = String(row.name || "").toLowerCase();
  let icon = FileText;
  if (typeLower.includes("design") || nameLower.includes(".fig") || nameLower.includes(".psd")) icon = Palette;
  else if (typeLower.includes("relat") || typeLower.includes("report") || nameLower.includes("relat")) icon = BarChart2;
  else if (["imagem","zip","media"].some(t => typeLower.includes(t)) || nameLower.includes(".zip")) icon = Image;
  return {
    id: row.id,
    name: row.name,
    type: row.file_type || "Documento",
    size: row.size || "—",
    date: formatPortalDate(row.created_at),
    icon,
    url: row.url,
  };
}

function mapClientFile(row) {
  const nameLower = String(row.name || "").toLowerCase();
  let icon = FileText;
  if (nameLower.match(/\.(jpg|jpeg|png|gif|webp|svg)$/)) icon = Image;
  else if (nameLower.match(/\.(fig|psd|ai|sketch)$/)) icon = Palette;
  return {
    id: row.id,
    name: row.name,
    type: row.type || "Documento",
    size: row.size_label || "—",
    date: formatPortalDate(row.created_at),
    icon,
    url: row.file_url,
    fromClient: true,
  };
}

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
  if (file.url) {
    window.open(file.url, "_blank", "noopener,noreferrer");
    return;
  }
  // fallback para arquivos sem URL (não deve ocorrer em produção)
  const link = document.createElement("a");
  link.href = "#";
  link.download = file.name;
  document.body.appendChild(link);
  link.click();
  link.remove();
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
  const [hov, setHov] = useState(false);
  return (
    <div
      className={styles.metricTile}
      onMouseEnter={() => setHov(true)}
      onMouseLeave={() => setHov(false)}
      style={{
        transition: "transform 0.2s ease, box-shadow 0.2s ease, border-color 0.2s ease",
        transform: hov ? "translateY(-3px) scale(1.015)" : "none",
        boxShadow: hov ? `0 20px 48px rgba(128,64,245,0.18)` : undefined,
        borderColor: hov ? C.borderGlow : undefined,
      }}
    >
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
        transition: "color 0.2s",
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

/** Quick action button */
function QuickActionBtn({ icon: Icon, label, color, onClick }) {
  const [hov, setHov] = useState(false);
  return (
    <button
      type="button"
      onClick={onClick}
      onMouseEnter={() => setHov(true)}
      onMouseLeave={() => setHov(false)}
      style={{
        display: "flex", flexDirection: "column", alignItems: "center", gap: 10,
        padding: "18px 12px",
        borderRadius: 14,
        border: `1px solid ${hov ? color + "55" : C.border}`,
        background: hov ? `${color}14` : C.card,
        cursor: "pointer",
        flex: 1,
        transition: "all 0.18s ease",
        transform: hov ? "translateY(-2px)" : "none",
        boxShadow: hov ? `0 12px 32px ${color}28` : "none",
      }}
    >
      <div style={{
        width: 40, height: 40, borderRadius: 12,
        background: hov ? `${color}22` : `${color}14`,
        border: `1px solid ${color}30`,
        display: "flex", alignItems: "center", justifyContent: "center",
        transition: "all 0.18s ease",
      }}>
        <Icon size={18} color={color} strokeWidth={1.6} />
      </div>
      <span style={{
        fontFamily: FONT_BODY, fontSize: 12, fontWeight: 600,
        color: hov ? color : C.textSub,
        transition: "color 0.18s",
        textAlign: "center",
      }}>{label}</span>
    </button>
  );
}

/** Project phase timeline */
function ProjectTimeline({ deliveries }) {
  const approved = deliveries.filter(d => d.status === "approved").length;
  const total = deliveries.length;
  const hasPending = deliveries.some(d => d.status === "pending");
  const hasRevision = deliveries.some(d => d.status === "revision");

  const STAGES = [
    { label: "Briefing",       key: "briefing"    },
    { label: "Design",         key: "design"      },
    { label: "Aprovação",      key: "aprovacao"   },
    { label: "Implementação",  key: "implementacao" },
    { label: "Entrega",        key: "entrega"     },
  ];

  let activeStage = 0;
  if (total === 0) activeStage = 0;
  else if (hasPending || hasRevision) activeStage = 2;
  else if (approved > 0 && approved < total) activeStage = 3;
  else if (approved === total && total > 0) activeStage = 4;
  else activeStage = 1;

  return (
    <div style={{
      background: "rgba(20,20,48,0.5)",
      backdropFilter: "blur(16px)",
      WebkitBackdropFilter: "blur(16px)",
      border: `1px solid ${C.border}`,
      borderRadius: 16,
      padding: "20px 24px",
      marginBottom: 28,
    }}>
      <div style={{ marginBottom: 16, display: "flex", alignItems: "center", gap: 8 }}>
        <TrendingUp size={14} color={C.cyan} strokeWidth={1.5} />
        <span style={{ fontSize: 10, color: C.cyan, letterSpacing: 2, textTransform: "uppercase", fontFamily: FONT_MONO, fontWeight: 500 }}>
          Progresso do Projeto
        </span>
      </div>
      <div style={{ display: "flex", alignItems: "center", gap: 0 }}>
        {STAGES.map((stage, idx) => {
          const done = idx < activeStage;
          const current = idx === activeStage;
          return (
            <div key={stage.key} style={{ display: "flex", alignItems: "center", flex: idx < STAGES.length - 1 ? 1 : undefined }}>
              <div style={{ display: "flex", flexDirection: "column", alignItems: "center", gap: 6 }}>
                <div style={{
                  width: 32, height: 32, borderRadius: "50%",
                  background: done ? C.grad : current ? "rgba(128,64,245,0.15)" : "rgba(255,255,255,0.04)",
                  border: `2px solid ${done ? "transparent" : current ? C.purple : "rgba(255,255,255,0.1)"}`,
                  display: "flex", alignItems: "center", justifyContent: "center",
                  boxShadow: current ? `0 0 16px rgba(128,64,245,0.5)` : "none",
                  flexShrink: 0,
                  transition: "all 0.3s ease",
                }}>
                  {done
                    ? <CheckCircle2 size={14} color="#fff" strokeWidth={2} />
                    : current
                      ? <Circle size={10} color={C.purple} strokeWidth={3} />
                      : <Circle size={8} color="rgba(255,255,255,0.2)" strokeWidth={2} />
                  }
                </div>
                <span style={{
                  fontSize: 10, fontFamily: FONT_BODY, fontWeight: current ? 700 : 400,
                  color: done ? C.success : current ? C.purple : C.textMuted,
                  whiteSpace: "nowrap",
                  transition: "color 0.3s",
                }}>{stage.label}</span>
              </div>
              {idx < STAGES.length - 1 && (
                <div style={{
                  flex: 1, height: 2, marginBottom: 20,
                  background: done ? C.grad : "rgba(255,255,255,0.06)",
                  transition: "background 0.5s ease",
                }} />
              )}
            </div>
          );
        })}
      </div>
    </div>
  );
}

/** Delivery card row */
function DeliveryRow({ item, onClick }) {
  const [hovered, setHovered] = useState(false);
  const s   = STATUS[item.status] || STATUS.production;
  const Icon = TYPE_ICON[item.type] || FileText;
  const tone = getIconTone(item);

  return (
    <div
      className={styles.deliveryTile}
      onClick={() => onClick(item)}
      onMouseEnter={() => setHovered(true)}
      onMouseLeave={() => setHovered(false)}
      style={{
        display: "flex", alignItems: "center", gap: 14,
        background: hovered ? C.cardHover : C.card,
        border: `1px solid ${hovered ? tone.border : C.border}`,
        borderRadius: 12,
        padding: "14px 18px",
        cursor: "pointer",
        transition: "background 0.18s, border-color 0.18s, box-shadow 0.18s, transform 0.18s",
        boxShadow: hovered ? `0 16px 36px ${tone.glow}` : "none",
      }}
    >
      {/* Type icon */}
      <IconFrame icon={Icon} tone={tone} hovered={hovered} size={16} />

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
function UploadZone({ uploads, setUploads, user, onUploadComplete }) {
  const [dragging, setDragging] = useState(false);

  const processFiles = useCallback(async (files) => {
    if (!isSupabaseConfigured || !supabase || !user?.id) return;
    const MAX_MB = 50;
    const fileArray = Array.from(files).filter(f => {
      if (f.size > MAX_MB * 1024 * 1024) {
        setUploads(prev => [...prev, {
          id: Date.now(),
          name: f.name,
          size: (f.size / 1024 / 1024).toFixed(1) + " MB",
          progress: 0, done: false, error: true,
          errorMsg: `Arquivo excede o limite de ${MAX_MB} MB`,
        }]);
        return false;
      }
      return true;
    });
    if (!fileArray.length) return;
    const newUploads = fileArray.map((f, i) => ({
      id: Date.now() + i,
      name: f.name,
      size: (f.size / 1024 / 1024).toFixed(1) + " MB",
      progress: 0,
      done: false,
      error: false,
    }));
    setUploads((prev) => [...prev, ...newUploads]);

    for (let i = 0; i < fileArray.length; i++) {
      const f = fileArray[i];
      const entry = newUploads[i];
      const path = `${user.id}/${Date.now()}_${f.name}`;

      // Progresso otimista enquanto o upload ocorre
      let p = 0;
      const iv = setInterval(() => {
        p = Math.min(p + Math.random() * 12 + 4, 85);
        setUploads((prev) => prev.map((x) => x.id === entry.id ? { ...x, progress: Math.floor(p) } : x));
      }, 300);

      const { error: storageError } = await supabase.storage
        .from("client-uploads")
        .upload(path, f, {
          upsert: false,
          contentType: f.type || "application/octet-stream",
        });

      clearInterval(iv);

      if (storageError) {
        console.error("[Upload] Falha no storage:", storageError.message);
        setUploads((prev) => prev.map((x) => x.id === entry.id ? { ...x, progress: 0, error: true, errorMsg: storageError.message } : x));
        continue;
      }

      const { data: { publicUrl } } = supabase.storage.from("client-uploads").getPublicUrl(path);

      const { error: insertError } = await supabase.from("client_files").insert({
        client_id: user.id,
        name: f.name,
        type: getFileTypeName(f.name),
        file_url: publicUrl,
        size_label: (f.size / 1024 / 1024).toFixed(1) + " MB",
      });

      if (insertError) {
        console.error("[Upload] Falha ao salvar no banco:", insertError.message);
        setUploads((prev) => prev.map((x) => x.id === entry.id ? { ...x, progress: 0, error: true, errorMsg: insertError.message } : x));
        continue;
      }

      setUploads((prev) => prev.map((x) => x.id === entry.id ? { ...x, progress: 100, done: true } : x));
      if (onUploadComplete) onUploadComplete();
    }
  }, [setUploads, user, onUploadComplete]);

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
                border: `1px solid ${u.error ? "rgba(239,68,68,0.35)" : u.done ? "rgba(37,211,102,0.25)" : C.border}`,
                borderRadius: 12,
                padding: "12px 14px",
                display: "flex", alignItems: "center", gap: 12,
              }}>
                <div style={{
                  width: 34, height: 34, borderRadius: 8, flexShrink: 0,
                  background: u.error ? "rgba(239,68,68,0.1)" : u.done ? "rgba(37,211,102,0.1)" : "rgba(128, 64, 245, 0.1)",
                  display: "flex", alignItems: "center", justifyContent: "center",
                }}>
                  <Icon size={15} color={u.error ? "#ef4444" : u.done ? C.success : C.purple} strokeWidth={1.5} />
                </div>
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div style={{
                    fontFamily: FONT_BODY, fontWeight: 500, fontSize: 13,
                    color: C.text, marginBottom: 4,
                    whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis",
                  }}>{u.name}</div>
                  {u.error ? (
                    <div style={{ fontSize: 11, color: "#ef4444", fontFamily: FONT_MONO }}>
                      ✕ Falha no envio — tente novamente
                    </div>
                  ) : !u.done ? (
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
                {!u.done && !u.error && (
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
function FileRow({ f, onDownload, isImage }) {
  const [hov, setHov] = useState(false);
  const Icon = f.icon;
  const tone = getIconTone(f);
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
        border: `1px solid ${hov ? tone.border : C.border}`,
        borderRadius: 13, padding: "14px 18px", cursor: "pointer",
        transition: "all 0.18s ease",
        boxShadow: hov ? `0 16px 36px ${tone.glow}` : "none",
        backdropFilter: "blur(8px)", WebkitBackdropFilter: "blur(8px)",
      }}
    >
      <IconFrame icon={Icon} tone={tone} hovered={hov} />
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ fontFamily: FONT_BODY, fontWeight: 600, fontSize: 14, color: C.text, marginBottom: 3 }}>{f.name}</div>
        <div style={{ fontSize: 11, color: C.textSub, fontFamily: FONT_BODY }}>{f.type} · {f.size} · {f.date}</div>
      </div>
      <div style={{
        display: "flex", alignItems: "center", gap: 8,
        padding: "7px 14px", borderRadius: 20,
        background: hov ? (isImage ? "rgba(128,64,245,0.12)" : "rgba(0,216,255,0.1)") : "transparent",
        border: `1px solid ${hov ? (isImage ? C.purple : C.cyan) : "transparent"}`,
        color: hov ? (isImage ? C.purple : C.cyan) : C.textSub,
        fontSize: 11, fontFamily: FONT_MONO, flexShrink: 0,
        transition: "all 0.18s ease",
      }}>
        {isImage ? <Eye size={12} strokeWidth={1.5} /> : <Download size={12} strokeWidth={1.5} />}
        {isImage ? "Visualizar" : "Baixar"}
      </div>
    </div>
  );
}

/* ─────────────────────────────────────────────
   IMAGE PREVIEW MODAL
───────────────────────────────────────────── */
function ImagePreviewModal({ file, onClose }) {
  useEffect(() => {
    if (!file) return;
    const handler = (e) => { if (e.key === "Escape") onClose(); };
    window.addEventListener("keydown", handler);
    return () => window.removeEventListener("keydown", handler);
  }, [file, onClose]);

  if (!file) return null;

  return (
    <div
      onClick={onClose}
      style={{
        position: "fixed", inset: 0, zIndex: 200,
        background: "rgba(2,6,23,0.92)",
        backdropFilter: "blur(16px)", WebkitBackdropFilter: "blur(16px)",
        display: "flex", alignItems: "center", justifyContent: "center",
        padding: 24,
      }}
    >
      <div onClick={e => e.stopPropagation()} style={{ maxWidth: 800, width: "100%", position: "relative" }}>
        <button
          type="button"
          onClick={onClose}
          style={{
            position: "absolute", top: -44, right: 0,
            background: "rgba(255,255,255,0.08)", border: `1px solid ${C.border}`,
            borderRadius: 8, width: 34, height: 34,
            display: "flex", alignItems: "center", justifyContent: "center",
            cursor: "pointer", color: C.textSub,
          }}
        >
          <X size={16} />
        </button>
        <img
          src={file.url}
          alt={file.name}
          style={{
            width: "100%", maxHeight: "75vh",
            objectFit: "contain",
            borderRadius: 14,
            border: `1px solid ${C.border}`,
            boxShadow: "0 0 80px rgba(0,0,0,0.5)",
          }}
        />
        <div style={{
          marginTop: 12, textAlign: "center",
          fontFamily: FONT_BODY, fontSize: 13, color: C.textSub,
        }}>{file.name}</div>
      </div>
    </div>
  );
}

/* ─────────────────────────────────────────────
   FILES VIEW
───────────────────────────────────────────── */
const FILE_FILTERS = ["Todos", "Designs", "Imagens", "Relatórios", "Documentos"];

function FilesView({ user }) {
  const [uploads, setUploads] = useState([]);
  const [assets, setAssets] = useState([]);
  const [clientFiles, setClientFiles] = useState([]);
  const [loadingAssets, setLoadingAssets] = useState(true);
  const [activeFilter, setActiveFilter] = useState("Todos");
  const [previewFile, setPreviewFile] = useState(null);

  useEffect(() => {
    if (!isSupabaseConfigured || !supabase || !user?.id) {
      setLoadingAssets(false);
      return;
    }
    // Busca projetos do cliente, depois assets de cada projeto
    supabase
      .from("projects")
      .select("id")
      .eq("client_id", user.id)
      .then(async ({ data: projects }) => {
        if (!projects?.length) { setLoadingAssets(false); return; }
        const projectIds = projects.map((p) => p.id);
        const { data } = await supabase
          .from("assets")
          .select("id, name, file_type, size, url, created_at")
          .in("project_id", projectIds)
          .order("created_at", { ascending: false });
        setAssets((data || []).map(mapAsset));
        setLoadingAssets(false);
      });
  }, [user?.id]);

  const fetchClientFiles = useCallback(() => {
    if (!isSupabaseConfigured || !supabase || !user?.id) return;
    supabase
      .from("client_files")
      .select("id, name, type, file_url, size_label, created_at")
      .eq("client_id", user.id)
      .order("created_at", { ascending: false })
      .then(({ data }) => setClientFiles((data || []).map(mapClientFile)));
  }, [user?.id]);

  useEffect(() => { fetchClientFiles(); }, [fetchClientFiles]);

  const allFiles = [...assets, ...clientFiles];

  const filteredAssets = activeFilter === "Todos" ? allFiles : allFiles.filter(a => {
    const t = String(a.type).toLowerCase();
    const n = String(a.name).toLowerCase();
    if (activeFilter === "Designs") return t.includes("design") || n.match(/\.(fig|psd|ai|sketch)$/);
    if (activeFilter === "Imagens") return t.includes("imagem") || n.match(/\.(jpg|jpeg|png|gif|webp|svg)$/);
    if (activeFilter === "Relatórios") return t.includes("relat") || n.includes("relat");
    if (activeFilter === "Documentos") return t.includes("pdf") || t.includes("doc") || t === "documento";
    return true;
  });

  const isImageFile = (f) => {
    const name = String(f.name || "").toLowerCase();
    return name.match(/\.(jpg|jpeg|png|gif|webp|svg)$/) || String(f.type || "").toLowerCase().includes("imagem");
  };

  const handleFileClick = (f) => {
    if (isImageFile(f) && f.url) {
      setPreviewFile(f);
    } else {
      downloadPortalFile(f);
    }
  };

  return (
    <>
      <ImagePreviewModal file={previewFile} onClose={() => setPreviewFile(null)} />
      <div className={styles.filesGrid}>
        {/* Left — Pixelry files */}
        <div>
          <div style={{ marginBottom: 16 }}>
            <div style={{ fontSize: 10, color: C.cyan, letterSpacing: 2, textTransform: "uppercase", fontFamily: FONT_MONO, fontWeight: 500, marginBottom: 6 }}>
              Operação Pixelry
            </div>
            <h2 style={{ fontFamily: FONT_DISPLAY, fontWeight: 700, fontSize: 22, color: C.text, letterSpacing: "-0.01em", margin: 0 }}>
              Documentos e Entregas
            </h2>
          </div>

          {/* Filter pills */}
          <div style={{ display: "flex", gap: 8, flexWrap: "wrap", marginBottom: 16 }}>
            {FILE_FILTERS.map(f => (
              <button
                key={f}
                type="button"
                onClick={() => setActiveFilter(f)}
                style={{
                  padding: "5px 14px", borderRadius: 20,
                  border: `1px solid ${activeFilter === f ? C.purple : C.border}`,
                  background: activeFilter === f ? "rgba(128,64,245,0.12)" : "transparent",
                  color: activeFilter === f ? C.purple : C.textSub,
                  fontSize: 12, fontFamily: FONT_BODY, fontWeight: activeFilter === f ? 600 : 400,
                  cursor: "pointer", transition: "all 0.15s",
                }}
              >{f}</button>
            ))}
          </div>

          <div style={{ display: "flex", flexDirection: "column", gap: 8 }}>
            {loadingAssets && (
              <div style={{ color: C.textSub, fontFamily: FONT_BODY, fontSize: 13 }}>Carregando arquivos...</div>
            )}
            {!loadingAssets && filteredAssets.length === 0 && (
              <div style={{ color: C.textMuted, fontFamily: FONT_BODY, fontSize: 13 }}>
                {allFiles.length === 0 ? "Nenhum arquivo disponível ainda." : "Nenhum arquivo nesta categoria."}
              </div>
            )}
            {!loadingAssets && filteredAssets.map((f) => (
              <FileRow key={f.id} f={f} onDownload={handleFileClick} isImage={isImageFile(f)} />
            ))}
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
          <UploadZone uploads={uploads} setUploads={setUploads} user={user} onUploadComplete={fetchClientFiles} />
        </div>
      </div>
    </>
  );
}

/* ─────────────────────────────────────────────
   PROJECTS VIEW (real implementation)
───────────────────────────────────────────── */
function ProjectsView({ user }) {
  const [projects, setProjects] = useState([]);
  const [loading, setLoading] = useState(true);
  const [expandedId, setExpandedId] = useState(null);
  const [projDeliveries, setProjDeliveries] = useState({});

  useEffect(() => {
    if (!isSupabaseConfigured || !supabase || !user?.id) {
      setLoading(false);
      return;
    }
    supabase
      .from("projects")
      .select("id, title, status, created_at")
      .eq("client_id", user.id)
      .order("created_at", { ascending: false })
      .then(({ data }) => {
        setProjects(data || []);
        setLoading(false);
      });
  }, [user?.id]);

  const toggleExpand = async (id) => {
    if (expandedId === id) {
      setExpandedId(null);
      return;
    }
    setExpandedId(id);
    if (!projDeliveries[id] && isSupabaseConfigured && supabase) {
      const { data } = await supabase
        .from("deliveries")
        .select("id, title, status, type, due_date")
        .eq("project_id", id)
        .order("created_at", { ascending: false })
        .limit(5);
      setProjDeliveries(prev => ({ ...prev, [id]: data || [] }));
    }
  };

  const projectStatus = (s) => {
    const map = {
      active: { label: "Ativo", color: C.cyan, bg: "rgba(0,216,255,0.08)", border: "rgba(0,216,255,0.2)" },
      completed: { label: "Concluído", color: C.success, bg: "rgba(37,211,102,0.08)", border: "rgba(37,211,102,0.2)" },
      paused: { label: "Pausado", color: C.amber, bg: "rgba(245,158,11,0.08)", border: "rgba(245,158,11,0.2)" },
    };
    return map[String(s || "").toLowerCase()] || map.active;
  };

  if (loading) {
    return (
      <div className={styles.emptyState} style={{ minHeight: 260 }}>
        <Clock size={28} color={C.cyan} strokeWidth={1.5} />
        <div style={{ fontFamily: FONT_DISPLAY, fontWeight: 700, fontSize: 18, color: C.text }}>Carregando projetos</div>
        <div style={{ fontFamily: FONT_BODY, fontSize: 13, color: C.textSub }}>Buscando seus dados...</div>
      </div>
    );
  }

  if (projects.length === 0) {
    return (
      <div className={styles.emptyState} style={{ minHeight: 260 }}>
        <div style={{
          width: 64, height: 64, borderRadius: "50%",
          background: "rgba(128, 64, 245, 0.08)",
          border: `1px solid rgba(128, 64, 245, 0.2)`,
          display: "flex", alignItems: "center", justifyContent: "center",
        }}>
          <FolderOpen size={26} color={C.purple} strokeWidth={1.2} />
        </div>
        <div style={{ fontFamily: FONT_DISPLAY, fontWeight: 700, fontSize: 18, color: C.text }}>Nenhum projeto ainda</div>
        <div style={{ fontFamily: FONT_BODY, fontSize: 13, color: C.textSub, textAlign: "center", maxWidth: 300, lineHeight: 1.65 }}>
          Seus projetos ativos e histórico de trabalhos aparecerão aqui.
        </div>
      </div>
    );
  }

  return (
    <div style={{ display: "flex", flexDirection: "column", gap: 12 }}>
      {projects.map((proj) => {
        const st = projectStatus(proj.status);
        const isOpen = expandedId === proj.id;
        const delivs = projDeliveries[proj.id] || [];
        const approvedCount = delivs.filter(d => normalizeStatus(d.status) === "approved").length;
        const progressPct = delivs.length ? Math.round((approvedCount / delivs.length) * 100) : 0;

        return (
          <div
            key={proj.id}
            style={{
              background: C.card,
              border: `1px solid ${isOpen ? C.borderGlow : C.border}`,
              borderRadius: 16,
              overflow: "hidden",
              transition: "border-color 0.2s, box-shadow 0.2s",
              boxShadow: isOpen ? `0 0 40px rgba(128,64,245,0.1)` : "none",
            }}
          >
            {/* Card header */}
            <button
              type="button"
              onClick={() => toggleExpand(proj.id)}
              style={{
                width: "100%", display: "flex", alignItems: "center", gap: 16,
                padding: "18px 22px", background: "transparent", border: "none",
                cursor: "pointer", textAlign: "left",
              }}
            >
              <div style={{
                width: 42, height: 42, borderRadius: 11, flexShrink: 0,
                background: "rgba(128,64,245,0.1)",
                border: `1px solid rgba(128,64,245,0.25)`,
                display: "flex", alignItems: "center", justifyContent: "center",
              }}>
                <FolderOpen size={18} color={C.purple} strokeWidth={1.5} />
              </div>
              <div style={{ flex: 1, minWidth: 0 }}>
                <div style={{ fontFamily: FONT_BODY, fontWeight: 700, fontSize: 15, color: C.text, marginBottom: 4 }}>
                  {proj.title || "Projeto sem nome"}
                </div>
                <div style={{ fontSize: 11, color: C.textSub, fontFamily: FONT_BODY }}>
                  Criado em {formatPortalDate(proj.created_at)}
                </div>
              </div>
              <div style={{
                padding: "5px 12px", borderRadius: 20, flexShrink: 0,
                background: st.bg, border: `1px solid ${st.border}`,
                fontSize: 11, fontWeight: 600, color: st.color, fontFamily: FONT_BODY,
              }}>{st.label}</div>
              <ChevronRight
                size={16} color={C.textSub} strokeWidth={1.5}
                style={{ transform: isOpen ? "rotate(90deg)" : "none", transition: "transform 0.2s", flexShrink: 0 }}
              />
            </button>

            {/* Progress bar */}
            {delivs.length > 0 && (
              <div style={{ padding: "0 22px 16px" }}>
                <div style={{ display: "flex", justifyContent: "space-between", marginBottom: 6 }}>
                  <span style={{ fontSize: 11, color: C.textSub, fontFamily: FONT_BODY }}>
                    {approvedCount} de {delivs.length} entregas aprovadas
                  </span>
                  <span style={{ fontSize: 11, fontFamily: FONT_MONO, color: C.cyan }}>{progressPct}%</span>
                </div>
                <div style={{ height: 4, borderRadius: 4, background: "rgba(255,255,255,0.05)" }}>
                  <div style={{
                    height: "100%", borderRadius: 4, background: C.grad,
                    width: `${progressPct}%`, transition: "width 0.6s ease",
                  }} />
                </div>
              </div>
            )}

            {/* Expanded deliveries */}
            {isOpen && (
              <div style={{
                borderTop: `1px solid ${C.border}`,
                padding: "16px 22px",
                display: "flex", flexDirection: "column", gap: 8,
              }}>
                {delivs.length === 0 ? (
                  <div style={{ fontFamily: FONT_BODY, fontSize: 13, color: C.textMuted }}>
                    Nenhuma entrega vinculada.
                  </div>
                ) : delivs.map((d) => {
                  const s = STATUS[normalizeStatus(d.status)] || STATUS.production;
                  const Icon = TYPE_ICON[d.type] || FileText;
                  return (
                    <div key={d.id} style={{
                      display: "flex", alignItems: "center", gap: 12,
                      padding: "10px 14px", borderRadius: 10,
                      background: "rgba(255,255,255,0.03)",
                      border: `1px solid ${C.border}`,
                    }}>
                      <Icon size={14} color={C.textSub} strokeWidth={1.5} />
                      <span style={{ flex: 1, fontSize: 13, fontFamily: FONT_BODY, color: C.text }}>{d.title || "Entrega"}</span>
                      <span style={{
                        fontSize: 10.5, fontWeight: 500, color: s.color,
                        padding: "3px 9px", borderRadius: 20,
                        background: s.bg, border: `1px solid ${s.border}`,
                        fontFamily: FONT_BODY,
                      }}>{s.label}</span>
                    </div>
                  );
                })}
              </div>
            )}
          </div>
        );
      })}
    </div>
  );
}

/* ─────────────────────────────────────────────
   SUPPORT VIEW
───────────────────────────────────────────── */
function SupportView({ user }) {
  const [msg, setMsg] = useState("");
  const [messages, setMessages] = useState([]);
  const [sending, setSending] = useState(false);
  const [attachName, setAttachName] = useState(null);
  const [attachFile, setAttachFile] = useState(null);
  const fileInputRef = useRef(null);
  const messagesEndRef = useRef(null);

  useEffect(() => {
    if (!isSupabaseConfigured || !supabase || !user?.id) return;
    supabase
      .from("messages")
      .select("id, content, from_client, created_at")
      .eq("client_id", user.id)
      .order("created_at", { ascending: true })
      .then(({ data }) => setMessages(data || []));
  }, [user?.id]);

  useEffect(() => {
    if (!isSupabaseConfigured || !supabase || !user?.id) return;
    const channel = supabase
      .channel(`support:${user.id}`)
      .on('postgres_changes', {
        event: 'INSERT',
        schema: 'public',
        table: 'messages',
        filter: `client_id=eq.${user.id}`,
      }, (payload) => {
        if (!payload.new.from_client) {
          setMessages(prev => [...prev, payload.new]);
        }
      })
      .subscribe();
    return () => { supabase.removeChannel(channel); };
  }, [user?.id]);

  useEffect(() => {
    messagesEndRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [messages]);

  const sendMessage = async () => {
    const content = msg.trim();
    if ((!content && !attachFile) || !user?.id || !isSupabaseConfigured || !supabase || sending) return;
    setSending(true);

    let fileUrl = null;
    if (attachFile) {
      const path = `${user.id}/chat/${Date.now()}_${attachFile.name}`;
      const { error: uploadErr } = await supabase.storage.from("client-uploads").upload(path, attachFile, { upsert: false });
      if (!uploadErr) {
        const { data: { publicUrl } } = supabase.storage.from("client-uploads").getPublicUrl(path);
        fileUrl = publicUrl;
      }
    }

    const fileLabel = attachFile ? `\n📎 Arquivo anexado: ${attachFile.name}${fileUrl ? `\n${fileUrl}` : ""}` : "";
    const messageContent = (content + fileLabel).trim() || `[Arquivo: ${attachFile?.name}]`;
    setMsg("");
    setAttachFile(null);
    setAttachName(null);

    const { error } = await supabase.from("messages").insert({
      client_id: user.id,
      content: messageContent,
      from_client: true,
    });
    if (!error) {
      setMessages((prev) => [
        ...prev,
        { id: crypto.randomUUID(), content: messageContent, from_client: true, created_at: new Date().toISOString() },
      ]);
    }
    setSending(false);
  };

  const onAttachChange = (e) => {
    const f = e.target.files?.[0];
    if (!f) return;
    setAttachFile(f);
    setAttachName(f.name);
    e.target.value = "";
  };

  return (
    <div className={styles.supportView}>
      {/* Header with team status */}
      <div style={{ marginBottom: 20 }}>
        <div style={{ fontSize: 10, color: C.cyan, letterSpacing: 2, textTransform: "uppercase", fontFamily: FONT_MONO, fontWeight: 500, marginBottom: 6 }}>Central de Atendimento</div>
        <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", flexWrap: "wrap", gap: 12 }}>
          <h2 style={{ fontFamily: FONT_DISPLAY, fontWeight: 700, fontSize: 22, color: C.text, margin: 0, letterSpacing: "-0.01em" }}>Fale com a equipe</h2>
          <div style={{
            display: "flex", alignItems: "center", gap: 8,
            padding: "7px 14px", borderRadius: 20,
            background: "rgba(37,211,102,0.08)",
            border: "1px solid rgba(37,211,102,0.25)",
          }}>
            <div style={{
              width: 7, height: 7, borderRadius: "50%",
              background: C.success,
              boxShadow: `0 0 8px ${C.success}`,
              animation: "pulse 2s infinite",
            }} />
            <Users size={12} color={C.success} strokeWidth={1.8} />
            <span style={{ fontSize: 11.5, fontFamily: FONT_BODY, color: C.success, fontWeight: 600 }}>
              Equipe disponível · Resposta em até 24h
            </span>
          </div>
        </div>
        <p style={{ fontFamily: FONT_BODY, fontSize: 13, color: C.textSub, marginTop: 8, lineHeight: 1.65 }}>Dúvidas, feedback ou solicitações — estamos aqui para ajudar.</p>
      </div>

      {/* Histórico de mensagens */}
      {messages.length > 0 && (
        <div style={{
          display: "flex", flexDirection: "column", gap: 10,
          maxHeight: 340, overflowY: "auto",
          marginBottom: 20, padding: "4px 2px",
        }}>
          {messages.map((m) => (
            <div key={m.id} style={{
              padding: "10px 14px", borderRadius: 12,
              maxWidth: "78%",
              alignSelf: m.from_client ? "flex-end" : "flex-start",
              background: m.from_client ? "rgba(128,64,245,0.15)" : "rgba(20,20,48,0.6)",
              border: `1px solid ${m.from_client ? "rgba(128,64,245,0.3)" : C.border}`,
              fontFamily: FONT_BODY, fontSize: 13, color: C.text, lineHeight: 1.6,
            }}>
              {m.content}
              <div style={{ fontSize: 10, color: C.textMuted, marginTop: 4 }}>{formatPortalDate(m.created_at)}</div>
            </div>
          ))}
          <div ref={messagesEndRef} />
        </div>
      )}

      <div style={{
        background: "rgba(20,20,48,0.5)",
        backdropFilter: "blur(16px)",
        WebkitBackdropFilter: "blur(16px)",
        border: `1px solid ${C.border}`,
        borderRadius: 16,
        padding: 20,
      }}>
        {/* Attachment preview */}
        {attachName && (
          <div style={{
            display: "flex", alignItems: "center", gap: 8,
            padding: "8px 12px", borderRadius: 8, marginBottom: 10,
            background: "rgba(128,64,245,0.08)",
            border: "1px solid rgba(128,64,245,0.2)",
          }}>
            <Paperclip size={13} color={C.purple} strokeWidth={1.5} />
            <span style={{ flex: 1, fontSize: 12, fontFamily: FONT_BODY, color: C.textSub, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{attachName}</span>
            <button type="button" onClick={() => { setAttachFile(null); setAttachName(null); }} style={{ background: "none", border: "none", cursor: "pointer", color: C.textSub, padding: 2 }}>
              <X size={13} />
            </button>
          </div>
        )}

        <textarea
          value={msg}
          onChange={(e) => setMsg(e.target.value)}
          onKeyDown={(e) => { if (e.key === "Enter" && (e.ctrlKey || e.metaKey)) sendMessage(); }}
          placeholder="Descreva sua dúvida ou solicitação..."
          rows={4}
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

        <div style={{ marginTop: 10, display: "flex", alignItems: "center", justifyContent: "space-between", gap: 10 }}>
          <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
            {/* File attach button */}
            <input ref={fileInputRef} type="file" style={{ display: "none" }} onChange={onAttachChange} />
            <button
              type="button"
              onClick={() => fileInputRef.current?.click()}
              title="Anexar arquivo"
              style={{
                width: 36, height: 36, borderRadius: 9,
                background: "rgba(255,255,255,0.04)",
                border: `1px solid ${C.border}`,
                display: "flex", alignItems: "center", justifyContent: "center",
                cursor: "pointer", color: C.textSub,
                transition: "all 0.15s",
              }}
            >
              <Paperclip size={15} strokeWidth={1.5} />
            </button>
            <span style={{ fontSize: 11, color: C.textMuted, fontFamily: FONT_BODY }}>Ctrl+Enter para enviar</span>
          </div>

          <button
            onClick={sendMessage}
            disabled={sending || (!msg.trim() && !attachFile)}
            style={{
              display: "flex", alignItems: "center", gap: 8,
              padding: "11px 24px", borderRadius: 10,
              background: C.grad,
              border: "none", color: "#fff",
              fontFamily: FONT_DISPLAY, fontWeight: 700, fontSize: 13,
              cursor: sending || (!msg.trim() && !attachFile) ? "not-allowed" : "pointer",
              opacity: sending || (!msg.trim() && !attachFile) ? 0.6 : 1,
              boxShadow: "0 0 20px rgba(128, 64, 245, 0.3)",
            }}
          >
            <Send size={14} /> {sending ? "Enviando..." : "Enviar mensagem"}
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
  const navigate = useNavigate();
  const [activeNav,        setActiveNav]        = useState("Início");
  const [selectedDelivery, setSelectedDelivery] = useState(null);
  const [deliveries,       setDeliveries]       = useState([]);
  const [loadingDeliveries, setLoadingDeliveries] = useState(true);
  const [deliveriesError, setDeliveriesError] = useState("");
  const [actionStatus, setActionStatus] = useState(null);
  const [profile,          setProfile]          = useState(null);

  // Carrega perfil real da tabela profiles
  useEffect(() => {
    if (!isSupabaseConfigured || !supabase || !user?.id) return;
    supabase
      .from("profiles")
      .select("full_name, company_name, avatar_url")
      .eq("id", user.id)
      .single()
      .then(({ data }) => { if (data) setProfile(data); });
  }, [user?.id]);

  const clientName =
    profile?.full_name ||
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
    { icon: Files,         label: "Documentos" },
    { icon: MessageCircle, label: "Atendimento"  },
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
      .select(DELIVERY_SELECT_FIELDS)
      .eq("client_id", user.id)
      .order("created_at", { ascending: false });

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

  // Real-time: atualiza automaticamente quando o admin publica ou altera uma entrega
  useEffect(() => {
    if (!isSupabaseConfigured || !supabase || !user?.id) return;

    const channel = supabase
      .channel(`deliveries:client:${user.id}`)
      .on(
        "postgres_changes",
        { event: "*", schema: "public", table: "deliveries", filter: `client_id=eq.${user.id}` },
        (payload) => {
          if (payload.eventType === "INSERT") {
            const newItem = mapDelivery(payload.new);
            setDeliveries(prev =>
              [newItem, ...prev].sort((a, b) => getDeliverySortDate(b.source) - getDeliverySortDate(a.source))
            );
          } else if (payload.eventType === "UPDATE") {
            const updated = mapDelivery(payload.new);
            setDeliveries(prev => prev.map(d => d.id === updated.id ? updated : d));
            setSelectedDelivery(prev => prev?.id === updated.id ? updated : prev);
          } else if (payload.eventType === "DELETE") {
            setDeliveries(prev => prev.filter(d => d.id !== payload.old.id));
            setSelectedDelivery(prev => prev?.id === payload.old.id ? null : prev);
          }
        }
      )
      .subscribe();

    return () => { supabase.removeChannel(channel); };
  }, [user?.id]);

  const PAGE_TITLES = {
    "Início":   { supra: "Bem-vindo de volta",      h1: "Olá 👋"  },
    "Projetos": { supra: "Operação Pixelry",         h1: "Seus Projetos"  },
    "Documentos": { supra: "Operação Pixelry",         h1: "Ativos e Documentação" },
    "Atendimento": { supra: "Estamos aqui para ajudar", h1: "Central de Atendimento" },
  };

  const page =
    activeNav === NAV[0].label
      ? { ...PAGE_TITLES[activeNav], h1: `Olá, ${clientName}` }
      : PAGE_TITLES[activeNav];

  const updateDeliveryStatus = async (id, status) => {
    const normalizedStatus = normalizeStatus(status);
    const canUpdateStatus = CLIENT_MUTABLE_STATUSES.has(normalizedStatus);
    const deliveryExists = deliveries.some((delivery) => delivery.id === id);

    if (!canUpdateStatus || !deliveryExists) {
      setDeliveriesError("Acao invalida para esta entrega.");
      return;
    }

    if (!isSupabaseConfigured || !supabase) {
      setDeliveriesError("O portal ainda não está conectado ao Supabase neste deploy.");
      return;
    }

    const previousDeliveries = deliveries;
    setActionStatus({ id, status: normalizedStatus });
    setDeliveriesError("");
    setDeliveries((current) =>
      current.map((delivery) =>
        delivery.id === id
          ? {
              ...delivery,
              status: normalizedStatus,
              description:
                normalizedStatus === "approved"
                  ? "Entrega aprovada pelo cliente no portal."
                  : "Ajuste solicitado pelo cliente no portal. Nossa equipe vai revisar os pontos enviados.",
            }
          : delivery
      )
    );
    const { error } = await supabase
      .from("deliveries")
      .update({ status: normalizedStatus })
      .eq("id", id)
      .eq("client_id", user.id);

    if (error) {
      setDeliveries(previousDeliveries);
      setDeliveriesError("Não foi possível atualizar o status da entrega. Tente novamente.");
      setActionStatus(null);
      return;
    }

    // Log de auditoria
    if (user?.id) {
      const delivery = previousDeliveries.find((d) => d.id === id);
      await supabase.from("portal_events").insert({
        client_id: user.id,
        event_type: normalizedStatus === "approved" ? "delivery_approved" : "revision_requested",
        metadata: { delivery_id: id, title: delivery?.title },
      });
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
          <Logo onClick={() => navigate('/')} />
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
        <AnimatePresence mode="wait">
          <motion.div
            key={activeNav}
            initial={{ opacity: 0, y: 10 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: -6 }}
            transition={{ duration: 0.2, ease: "easeOut" }}
          >
            {activeNav === "Início" && (
              <>
                <div className={styles.metricGrid} style={{ display: "grid", gridTemplateColumns: "1fr 1fr 1fr 1fr", gap: 14, marginBottom: 24 }}>
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

                {/* Quick Actions */}
                <div style={{ marginBottom: 24 }}>
                  <div style={{ fontSize: 10, color: C.cyan, letterSpacing: 2, textTransform: "uppercase", fontFamily: FONT_MONO, fontWeight: 500, marginBottom: 12 }}>
                    Ações Rápidas
                  </div>
                  <div style={{ display: "flex", gap: 10 }}>
                    <QuickActionBtn icon={CheckCircle2} label="Revisar Entregas" color={C.cyan}
                      onClick={() => { if (firstPending) setSelectedDelivery(firstPending); }} />
                    <QuickActionBtn icon={Upload} label="Novo Upload" color={C.purple}
                      onClick={() => setActiveNav("Documentos")} />
                    <QuickActionBtn icon={MessageCircle} label="Falar com Equipe" color={C.success}
                      onClick={() => setActiveNav("Atendimento")} />
                    <QuickActionBtn icon={FolderOpen} label="Ver Projetos" color={C.amber}
                      onClick={() => setActiveNav("Projetos")} />
                  </div>
                </div>

                {/* Project Timeline */}
                {!loadingDeliveries && <ProjectTimeline deliveries={deliveries} />}

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
                      onClick={() => setActiveNav("Documentos")}
                      style={{
                        display: "flex", alignItems: "center", gap: 4,
                        padding: 0, border: "none", background: "transparent",
                        fontSize: 12, color: C.textSub, cursor: "pointer", fontFamily: FONT_BODY,
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
                        <button type="button" onClick={loadDeliveries} style={{
                          marginTop: 8, padding: "9px 18px", borderRadius: 10,
                          border: `1px solid ${C.borderGlow}`,
                          background: "rgba(128, 64, 245, 0.12)",
                          color: C.text, fontFamily: FONT_BODY, fontSize: 12, cursor: "pointer",
                        }}>Tentar novamente</button>
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

            {activeNav === "Projetos" && <ProjectsView user={user} />}
            {activeNav === "Documentos" && <FilesView user={user} />}
            {activeNav === "Atendimento" && <SupportView user={user} />}
          </motion.div>
        </AnimatePresence>

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

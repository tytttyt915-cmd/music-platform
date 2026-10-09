/**
 * 音乐推荐 Agent 原型 —— 类型定义
 * 对应 OpenMAIC: lib/orchestration/registry/types.ts 的 AgentConfig
 *             + lib/types/chat.ts 的 DirectorState / WhiteboardActionRecord
 */

// ---------- OpenMAIC 对应：AgentConfig ----------
export interface AgentConfig {
  id: string;
  name: string;
  role: string;
  /** 在 OpenMAIC 里是完整 system prompt；这里无 LLM，用规则描述代替 */
  persona: string;
  /** 能力边界：该 Agent 能用的动作名（抄 OpenMAIC 的 allowlist 思想） */
  allowedActions: string[];
  /** 导演选人时的优先级 1-10 */
  priority: number;
}

// ---------- 动作：对应 OpenMAIC 的结构化 action 事件 ----------
// OpenMAIC: { type: 'action', name: 'wb_draw_latex', params: {...} }
export interface AgentAction {
  type: 'action';
  name: string;
  params: Record<string, unknown>;
}

export interface AgentText {
  type: 'text';
  content: string;
}

export type AgentOutput = AgentAction | AgentText;

// ---------- 白板账本：对应 OpenMAIC 的 whiteboardLedger ----------
// OpenMAIC: WhiteboardActionRecord[]，随 directorState 流转，所有 Agent 可见
export interface LedgerEntry {
  seq: number;
  agentId: string;
  action: string;
  params: Record<string, unknown>;
  /** 决策理由：无 LLM 时这是规则命中的说明 */
  reason: string;
  timestamp: string;
}

// ---------- 导演状态：对应 OpenMAIC 的 DirectorState ----------
// OpenMAIC: { turnCount, agentResponses, whiteboardLedger }，无状态流转
export interface AgentResponse {
  agentId: string;
  contentPreview: string;
  actionCount: number;
}

export interface DirectorState {
  turnCount: number;
  agentResponses: AgentResponse[];
  ledger: LedgerEntry[];
}

// ---------- 业务类型 ----------
export interface Track {
  id: string;
  title: string;
  artist: string;
  album: string;
  durationMs: number;
  status: 'online' | 'offline' | string;
  playCount: string;
}

export interface RecommendRequest {
  /** 用户意图：如"给我推几首歌"、"想听夜航星这种风格" */
  intent: string;
  /** 关键词（可选），用于调 /music/search */
  keyword?: string;
  /** 想要几首 */
  limit: number;
}

export interface AuditVerdict {
  trackId: string;
  passed: boolean;
  reasons: string[];
}

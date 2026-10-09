/**
 * 三个 Agent 的实现 —— 无 LLM，规则引擎模拟
 * 对应 OpenMAIC 的 agent_generate 节点（那里调 LLM，这里调规则函数）
 */
import {
  AgentOutput, AuditVerdict, DirectorState, RecommendRequest, Track,
} from './types';
import { AGENTS, isActionAllowed } from './registry';

const API_BASE = 'http://111.230.155.174';

/** 简单的 HTTP GET（Node 18+ 原生 fetch） */
async function apiGet<T>(path: string): Promise<T> {
  const res = await fetch(`${API_BASE}${path}`);
  if (!res.ok) throw new Error(`API ${path} 返回 ${res.status}`);
  const json = await res.json() as { code: number; message: string; data: T };
  if (json.code !== 0) throw new Error(`API ${path} 业务码 ${json.code}: ${json.message}`);
  return json.data;
}

// ============================================================
// Director：意图路由（对应 OpenMAIC director-graph.ts 的 director 节点）
// OpenMAIC 用 LLM 输出 {"next_agent"}；这里用规则
// ============================================================
export type NextStep =
  | { action: 'dispatch'; agentId: 'recommender' }
  | { action: 'dispatch'; agentId: 'moderator' }
  | { action: 'finish' };

export function directorDecide(state: DirectorState, req: RecommendRequest): NextStep {
  const doneAgents = new Set(state.agentResponses.map((r) => r.agentId));

  // 规则 1：还没推荐过 → 派推荐官
  if (!doneAgents.has('recommender')) {
    return { action: 'dispatch', agentId: 'recommender' };
  }
  // 规则 2：推荐完了还没审核 → 派审核员
  if (!doneAgents.has('moderator')) {
    return { action: 'dispatch', agentId: 'moderator' };
  }
  // 规则 3：都干完了 → 结束
  return { action: 'finish' };
}

// ============================================================
// Recommender：调真实后端拿歌（对应 OpenMAIC 的 agent_generate）
// ============================================================
export async function recommenderRun(req: RecommendRequest): Promise<AgentOutput[]> {
  const outputs: AgentOutput[] = [];

  // 有关键词走搜索，无关键词走 feed（公开路由，无需 token）
  let tracks: Track[];
  let source: string;
  if (req.keyword) {
    const data = await apiGet<{ list: Track[] }>(
      `/music/search?keyword=${encodeURIComponent(req.keyword)}&page=1&pageSize=${req.limit}`,
    );
    tracks = data.list;
    source = `/music/search?keyword=${req.keyword}`;
  } else {
    const data = await apiGet<{ list: Track[] }>(
      `/music/feed?page=1&pageSize=${req.limit}`,
    );
    tracks = data.list;
    source = '/music/feed';
  }

  // 规则：按播放量倒序（当前只有 1 首，演示排序逻辑）
  const sorted = [...tracks].sort((a, b) => Number(b.playCount) - Number(a.playCount));
  const picked = sorted.slice(0, req.limit);

  // allowlist 检查：推荐官只能发 recommend_playlist
  if (!isActionAllowed('recommender', 'recommend_playlist')) {
    throw new Error('allowlist 拦截：recommender 无权执行 recommend_playlist');
  }

  outputs.push({
    type: 'text',
    content: `推荐官：从 ${source} 拿到 ${tracks.length} 首，按播放量排序取前 ${picked.length} 首。`,
  });
  outputs.push({
    type: 'action',
    name: 'recommend_playlist',
    params: {
      tracks: picked.map((t) => ({ id: t.id, title: t.title, artist: t.artist, status: t.status })),
      source,
    },
  });
  return outputs;
}

// ============================================================
// Moderator：合规检查（对应 OpenMAIC 的审核 Agent 设想）
// 只打标不删除，verdict 进共享账本（类比 whiteboardLedger）
// ============================================================
export function moderatorRun(candidates: Array<{ id: string; title: string; artist: string; status: string }>): AgentOutput[] {
  const outputs: AgentOutput[] = [];

  if (!isActionAllowed('moderator', 'audit_verdict')) {
    throw new Error('allowlist 拦截：moderator 无权执行 audit_verdict');
  }

  const verdicts: AuditVerdict[] = candidates.map((t) => {
    const reasons: string[] = [];
    let passed = true;
    // 规则 1：下架歌曲过滤
    if (t.status !== 'online') {
      passed = false;
      reasons.push(`status=${t.status}，非 online，已下架`);
    }
    // 规则 2：标题/艺人非空
    if (!t.title || !t.artist) {
      passed = false;
      reasons.push('标题或艺人为空，元数据不完整');
    }
    if (passed) reasons.push('合规：online 且元数据完整');
    return { trackId: t.id, passed, reasons };
  });

  const passedCount = verdicts.filter((v) => v.passed).length;
  outputs.push({
    type: 'text',
    content: `审核员：检查 ${candidates.length} 首，通过 ${passedCount} 首，${candidates.length - passedCount} 首被拦截。`,
  });
  outputs.push({
    type: 'action',
    name: 'audit_verdict',
    params: { verdicts },
  });
  return outputs;
}

/** 演示 allowlist 门卫：让推荐官试着调审核动作，应该被拦 */
export function demoAllowlistBlock(): string {
  const allowed = isActionAllowed('recommender', 'audit_verdict');
  return allowed
    ? '异常：recommender 竟然能调 audit_verdict！'
    : 'allowlist 门卫：recommender 调 audit_verdict 被拦截 ✓（能力边界是配置，不是靠自觉）';
}

export { AGENTS };

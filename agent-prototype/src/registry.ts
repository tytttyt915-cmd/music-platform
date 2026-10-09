/**
 * Agent 注册表 —— 对应 OpenMAIC 的 lib/orchestration/registry/built-in.ts
 * 新增一个 Agent = 加一条配置（persona + allowedActions），不用改编排代码
 */
import { AgentConfig } from './types';

export const AGENTS: Record<string, AgentConfig> = {
  director: {
    id: 'director',
    name: '导演',
    role: '意图路由：决定下一步该哪个 Agent 行动',
    persona: '规则：推荐意图→recommender；新内容入库→moderator；投诉/咨询→support。单轮只派一个 Agent，派完检查是否还有未完成的步骤。',
    allowedActions: ['dispatch'],
    priority: 10,
  },
  recommender: {
    id: 'recommender',
    name: '推荐官',
    role: '根据用户听歌历史/关键词推荐歌曲',
    persona: '规则：有 keyword 就调 /music/search，否则调 /music/feed；按 playCount 倒序取 topN；只输出 recommend_playlist 动作，不直接写库。',
    // allowlist 门卫：推荐官永远调不了 audit 相关的动作（抄 OpenMAIC 的 allowlist.ts）
    allowedActions: ['recommend_playlist'],
    priority: 8,
  },
  moderator: {
    id: 'moderator',
    name: '审核员',
    role: '检查推荐结果是否合规',
    persona: '规则：逐首检查 status 必须为 online；durationMs 必须 > 0；title/artist 非空。不通过的写 audit_verdict，只打标不删除（删歌是人工的事）。',
    allowedActions: ['audit_verdict'],
    priority: 7,
  },
};

/** allowlist 门卫：抄 OpenMAIC lib/agent/runtime/allowlist.ts */
export function isActionAllowed(agentId: string, actionName: string): boolean {
  const agent = AGENTS[agentId];
  if (!agent) return false;
  return agent.allowedActions.includes(actionName);
}

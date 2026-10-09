/**
 * 编排器 —— 对应 OpenMAIC 的 lib/orchestration/director-graph.ts
 * OpenMAIC: LangGraph StateGraph START→director→agent_generate→END（单轮）
 * 这里：同步循环 directorDecide → agent 执行 → 记账本 → 直到 finish
 */
import {
  AgentOutput, DirectorState, LedgerEntry, RecommendRequest, Track,
} from './types';
import { directorDecide, recommenderRun, moderatorRun, demoAllowlistBlock } from './agents';

/** 账本写入：对应 OpenMAIC 的 whiteboardLedger 追加逻辑 */
function appendLedger(
  state: DirectorState,
  agentId: string,
  action: string,
  params: Record<string, unknown>,
  reason: string,
): void {
  const entry: LedgerEntry = {
    seq: state.ledger.length + 1,
    agentId,
    action,
    params,
    reason,
    timestamp: new Date().toISOString(),
  };
  state.ledger.push(entry);
  console.log(`  📒 账本 #${entry.seq} [${agentId}] ${action} —— ${reason}`);
}

/** 从账本里取推荐官的候选歌曲（跨 Agent 共享状态，抄 whiteboardLedger 用法） */
function getCandidatesFromLedger(state: DirectorState): Array<{ id: string; title: string; artist: string; status: string }> {
  const rec = state.ledger.find((e) => e.action === 'recommend_playlist');
  if (!rec) return [];
  return (rec.params.tracks as Array<{ id: string; title: string; artist: string; status: string }>) ?? [];
}

/** 从账本里取审核员的 verdict */
function getVerdictsFromLedger(state: DirectorState): Array<{ trackId: string; passed: boolean; reasons: string[] }> {
  const audit = state.ledger.find((e) => e.action === 'audit_verdict');
  if (!audit) return [];
  return ((audit.params as { verdicts: Array<{ trackId: string; passed: boolean; reasons: string[] }> }).verdicts) ?? [];
}

export interface RunResult {
  finalPlaylist: Track[];
  state: DirectorState;
}

/** 主流程：一轮完整的 Director → 推荐 → 审核 → 输出 */
export async function runRecommendFlow(req: RecommendRequest): Promise<RunResult> {
  // DirectorState：无状态编排（抄 OpenMAIC：状态随请求走，不常驻服务端）
  const state: DirectorState = { turnCount: 0, agentResponses: [], ledger: [] };

  console.log('══════════════════════════════════════════');
  console.log(`🎵 推荐请求：${req.intent}${req.keyword ? `（关键词：${req.keyword}）` : ''}，要 ${req.limit} 首`);
  console.log('══════════════════════════════════════════\n');

  // eslint-disable-next-line no-constant-condition
  while (true) {
    state.turnCount += 1;
    const step = directorDecide(state, req);

    if (step.action === 'finish') {
      console.log(`\n🏁 Director：第 ${state.turnCount} 轮，推荐+审核都完成了，结束。`);
      break;
    }

    console.log(`\n── 第 ${state.turnCount} 轮：Director 派 [${step.agentId}] ──`);

    let outputs: AgentOutput[];
    if (step.agentId === 'recommender') {
      outputs = await recommenderRun(req);
    } else {
      outputs = moderatorRun(getCandidatesFromLedger(state));
    }

    let actionCount = 0;
    for (const out of outputs) {
      if (out.type === 'text') {
        console.log(`  💬 ${out.content}`);
      } else {
        actionCount += 1;
        const reason = out.name === 'recommend_playlist'
          ? `推荐 ${((out.params.tracks as unknown[]) ?? []).length} 首候选`
          : `审核完成，verdict 已写入账本`;
        appendLedger(state, step.agentId, out.name, out.params, reason);
      }
    }

    state.agentResponses.push({
      agentId: step.agentId,
      contentPreview: outputs.filter((o) => o.type === 'text').map((o) => (o as { content: string }).content).join(' ').slice(0, 80),
      actionCount,
    });

    if (state.turnCount > 10) {
      console.log('⚠️ 超过 10 轮，强制结束（防死循环，对应 OpenMAIC 的 quota.ts）');
      break;
    }
  }

  // 最终歌单 = 推荐候选 ∩ 审核通过（确定性代码组装，LLM 只做决策不碰数据——抄 OpenMAIC 防火墙思想）
  const candidates = getCandidatesFromLedger(state);
  const verdicts = getVerdictsFromLedger(state);
  const passedIds = new Set(verdicts.filter((v) => v.passed).map((v) => v.trackId));
  const finalPlaylist: Track[] = candidates
    .filter((c) => passedIds.has(c.id))
    .map((c) => ({ ...c, durationMs: 0, playCount: '0', album: '' }));

  console.log('\n══════════════════════════════════════════');
  console.log('📀 最终推荐歌单（审核通过）：');
  finalPlaylist.forEach((t, i) => console.log(`   ${i + 1}. ${t.title} — ${t.artist}`));
  if (finalPlaylist.length === 0) console.log('   （空：全部被审核拦截）');
  console.log('══════════════════════════════════════════');

  // 演示 allowlist 门卫
  console.log(`\n🛡️ ${demoAllowlistBlock()}`);

  return { finalPlaylist, state };
}

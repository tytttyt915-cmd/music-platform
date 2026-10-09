/**
 * 入口：跑两遍完整流程
 * 1. 无关键词：调 /music/feed
 * 2. 有关键词：调 /music/search
 */
import { runRecommendFlow } from './orchestrator';

async function main() {
  // 场景 1：用户说"给我推几首歌" → 走 feed
  await runRecommendFlow({ intent: '给我推几首歌', limit: 5 });

  console.log('\n\n');

  // 场景 2：用户说"想听夜航星这种" → 走 search
  await runRecommendFlow({ intent: '想听夜航星这种风格', keyword: '夜航星', limit: 5 });
}

main().catch((e) => {
  console.error('❌ 流程失败：', e.message);
  process.exit(1);
});

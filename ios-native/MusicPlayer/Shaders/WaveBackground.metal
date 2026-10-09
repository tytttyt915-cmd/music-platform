#include <metal_stdlib>
using namespace metal;

// MARK: - WaveBackground（Vanta.js WAVES 风格）
//
// 职责：播放页的音频律动背景。Vanta WAVES 的极简 Metal 复刻：
//   - 三层正弦波叠加，随时间流动
//   - 音频振幅（amplitude 0~1）调制辉光强度——Vanta 做不到的音频联动
//   - 品牌色（tintColor）着色，深色基底
//   - 垂直渐隐：底部更亮，营造舞台氛围
//
// 参数：
//   - time: 秒级时间戳，驱动波流动
//   - amplitude: 0~1，播放时 0.35~0.9 跳动，暂停时 0.12 保底呼吸感
//   - tintColor: 品牌色（主题强调色）的 RGB
//   - bounds: 视图边界（.boundingRect 传入），用于归一化 uv
//
// 性能：纯 fragment 计算，无纹理采样，GPU 负载极低。
// 调用方用 TimelineView 驱动；暂停时降帧、低电量时直接不用（见 AudioReactiveBackground.swift）。

[[ stitchable ]] half4 waveBackground(
    float2 position,
    half4 color,
    float time,
    float amplitude,
    float3 tintColor,
    float4 bounds
) {
    // 归一化坐标
    float2 uv = position / bounds.zw;

    // 三层波：主波 + 细节波 + 斜向波，相位错开
    float w1 = sin(uv.x * 6.0 + time * 1.2 + uv.y * 2.0);
    float w2 = sin(uv.x * 11.0 - time * 0.8 + uv.y * 4.0);
    float w3 = sin((uv.x + uv.y) * 4.0 + time * 0.5);

    float wave = w1 * 0.5 + w2 * 0.3 + w3 * 0.2;  // -1 ~ 1
    wave = wave * 0.5 + 0.5;                       // 0 ~ 1

    // 垂直渐隐：顶部暗、底部亮
    float verticalFade = 1.0 - uv.y * 0.55;

    // 辉光：波峰处提亮，振幅调制整体强度
    float glow = smoothstep(0.35, 0.95, wave) * (0.12 + amplitude * 0.88) * verticalFade;

    // 深底 + 品牌色辉光
    half3 base = half3(0.03, 0.03, 0.055);
    half3 tint = half3(tintColor);
    half3 result = base + tint * half3(glow * 0.45);

    return half4(result, 1.0);
}

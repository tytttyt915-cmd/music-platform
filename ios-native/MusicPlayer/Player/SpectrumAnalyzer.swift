import AVFoundation
import Accelerate
import MediaToolbox
import Foundation

// MARK: - SpectrumAnalyzer（真 FFT 三频段频谱）
//
// 职责：从 AVPlayer 的音频流里实时提取三频段能量，驱动播放页 Shader 律动。
//
// 原理：
//   AVPlayer 不支持 AVAudioEngine.installTap（那是 AVAudioPlayerNode 的），
//   正确做法是 MTAudioProcessingTap——挂在 AVPlayerItem.audioMix 上的音频处理 tap，
//   process 回调里拿到原始 PCM，用 Accelerate vDSP 做 2048 点 FFT，
//   按频率分三段（低 20–250Hz / 中 250–2000Hz / 高 2k–8kHz）取平均幅度。
//
// 自适应归一化：每段维护一个缓慢衰减的 runningMax，能量除以它——
//   不用手动调 gain，大声小声的歌都自动满量程。
// 平滑：attack 瞬时跟上（鼓点不丢），release 慢衰减（视觉不抖）。
//
// 线程：process 回调跑在音频实时线程，只做拷贝+FFT（约 0.1ms）；
//   结果经 NSLock 保护，UI 经 TimelineView 每帧读 liveSpectrum，无 @Published 开销。
// 性能：每 2048 帧（约 46ms）一次 FFT，CPU < 1%。

final class SpectrumAnalyzer {
    static let shared = SpectrumAnalyzer()

    // MARK: - 对外接口（线程安全）

    /// 当前三频段能量 0~1（x=低频 y=中频 z=高频）
    var liveSpectrum: SIMD3<Float> {
        lock.lock()
        defer { lock.unlock() }
        return _spectrum
    }

    /// tap 是否已挂上且收到过音频
    var hasSignal: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _hasSignal
    }

    // MARK: - 挂到播放项

    /// 把同一个 tap 挂到每个新 AVPlayerItem 的 audioMix 上。
    /// 在 AudioPlayerManager.playURL 里、player.play() 之前调用。
    func attach(to item: AVPlayerItem) {
        if tap == nil {
            var callbacks = MTAudioProcessingTapCallbacks(
                version: kMTAudioProcessingTapCallbacksVersion_0,
                clientInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
                init: spectrumTapInit,
                finalize: spectrumTapFinalize,
                prepare: spectrumTapPrepare,
                unprepare: spectrumTapUnprepare,
                process: spectrumTapProcess
            )
            var tapOut: MTAudioProcessingTap?
            let status = MTAudioProcessingTapCreate(
                kCFAllocatorDefault,
                &callbacks,
                kMTAudioProcessingTapCreationFlag_PostEffects,
                &tapOut
            )
            guard status == noErr, let created = tapOut else { return }
            tap = created
        }
        guard let tap = tap else { return }
        // 无 track 的 inputParameters = 应用于所有音轨
        let params = AVMutableAudioMixInputParameters()
        params.audioTapProcessor = tap
        let mix = AVMutableAudioMix()
        mix.inputParameters = [params]
        item.audioMix = mix
    }

    // MARK: - 内部状态（仅音频线程访问，除了 lock 保护的发布值）

    private var tap: MTAudioProcessingTap?
    private let lock = NSLock()
    private var _spectrum = SIMD3<Float>(0, 0, 0)
    private var _hasSignal = false

    private let fftSize = 2048
    private let log2n: vDSP_Length = 11
    private var fftSetup: FFTSetup?
    private var sampleRate: Float = 44100
    private var scratch = [Float]()
    private var runningMax = SIMD3<Float>(1e-6, 1e-6, 1e-6)

    private init() {
        scratch.reserveCapacity(fftSize)
        fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))
    }

    deinit {
        if let setup = fftSetup { vDSP_destroy_fftsetup(setup) }
    }

    // MARK: - tap 回调入口（音频线程）

    fileprivate func tapPrepared(sampleRate: Float) {
        self.sampleRate = sampleRate > 0 ? sampleRate : 44100
    }

    fileprivate func processAudio(bufferList: AudioBufferList, frameCount: Int) {
        guard frameCount > 0 else { return }
        var abl = bufferList
        // 取各声道平均为单声道（通常 tap 给非交错 float）
        let buffers = UnsafeBufferPointer<AudioBuffer>(
            start: &abl.mBuffers,
            count: Int(abl.mNumberBuffers)
        )
        for i in 0..<frameCount {
            var sample: Float = 0
            var channels: Float = 0
            for buf in buffers {
                guard let data = buf.mData else { continue }
                let ptr = data.assumingMemoryBound(to: Float.self)
                sample += ptr[i]
                channels += 1
            }
            if channels > 0 {
                scratch.append(sample / channels)
            }
            if scratch.count >= fftSize {
                runFFT()
                scratch.removeAll(keepingCapacity: true)
            }
        }
        lock.lock()
        _hasSignal = true
        lock.unlock()
    }

    // MARK: - FFT

    private func runFFT() {
        guard let fftSetup = fftSetup, scratch.count >= fftSize else { return }
        let n = fftSize

        // Hann 窗减少频谱泄漏
        var windowed = [Float](repeating: 0, count: n)
        var window = [Float](repeating: 0, count: n)
        vDSP_hann_window(&window, vDSP_Length(n), Int32(vDSP_HANN_NORM))
        vDSP_vmul(scratch, 1, window, 1, &windowed, 1, vDSP_Length(n))

        // 实数 FFT：ctoz → zrip → zvmags
        var realp = [Float](repeating: 0, count: n / 2)
        var imagp = [Float](repeating: 0, count: n / 2)
        var mags = [Float](repeating: 0, count: n / 2)
        realp.withUnsafeMutableBufferPointer { rp in
            imagp.withUnsafeMutableBufferPointer { ip in
                var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                windowed.withUnsafeBufferPointer { wb in
                    wb.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: n / 2) { complex in
                        vDSP_ctoz(complex, 2, &split, 1, vDSP_Length(n / 2))
                    }
                }
                vDSP_fft_zrip(fftSetup, &split, 1, log2n, FFT_FORWARD)
                vDSP_zvmags(&split, 1, &mags, 1, vDSP_Length(n / 2))
            }
        }
        // 平方幅度 → 幅度
        var amps = [Float](repeating: 0, count: n / 2)
        vvsqrtf(&amps, mags, [Int32(n / 2)])

        // 三频段平均
        let binHz = sampleRate / Float(n)
        let low = bandMean(amps, fromHz: 20, toHz: 250, binHz: binHz)
        let mid = bandMean(amps, fromHz: 250, toHz: 2000, binHz: binHz)
        let high = bandMean(amps, fromHz: 2000, toHz: 8000, binHz: binHz)

        // 自适应归一化（runningMax 慢衰减，自动满量程）
        runningMax.x = max(runningMax.x * 0.9995, max(low, 1e-6))
        runningMax.y = max(runningMax.y * 0.9995, max(mid, 1e-6))
        runningMax.z = max(runningMax.z * 0.9995, max(high, 1e-6))
        let target = SIMD3<Float>(
            min(low / runningMax.x, 1),
            min(mid / runningMax.y, 1),
            min(high / runningMax.z, 1)
        )

        // attack 快 / release 慢
        lock.lock()
        var cur = _spectrum
        cur.x = target.x > cur.x ? target.x : cur.x + (target.x - cur.x) * 0.25
        cur.y = target.y > cur.y ? target.y : cur.y + (target.y - cur.y) * 0.25
        cur.z = target.z > cur.z ? target.z : cur.z + (target.z - cur.z) * 0.25
        _spectrum = cur
        lock.unlock()
    }

    private func bandMean(_ amps: [Float], fromHz: Float, toHz: Float, binHz: Float) -> Float {
        let lo = max(1, Int(fromHz / binHz))
        let hi = min(amps.count - 1, Int(toHz / binHz))
        guard hi > lo else { return 0 }
        var sum: Float = 0
        for i in lo...hi { sum += amps[i] }
        return sum / Float(hi - lo + 1)
    }
}

// MARK: - MTAudioProcessingTap C 回调（顶层函数，不捕获）

private func spectrumTapInit(
    _ tap: MTAudioProcessingTap,
    _ clientInfo: UnsafeMutableRawPointer,
    _ tapStorageOut: UnsafeMutablePointer<UnsafeMutableRawPointer?>
) {
    tapStorageOut.pointee = clientInfo
}

private func spectrumTapFinalize(_ tap: MTAudioProcessingTap) {
    // 单例常驻，无需释放
}

private func spectrumTapPrepare(
    _ tap: MTAudioProcessingTap,
    _ maxFrames: CMItemCount,
    _ processingFormat: UnsafePointer<AudioStreamBasicDescription>
) {
    let analyzer = Unmanaged<SpectrumAnalyzer>.fromOpaque(
        MTAudioProcessingTapGetStorage(tap)
    ).takeUnretainedValue()
    analyzer.tapPrepared(sampleRate: Float(processingFormat.pointee.mSampleRate))
}

private func spectrumTapUnprepare(_ tap: MTAudioProcessingTap) {
    // 无需清理
}

private func spectrumTapProcess(
    _ tap: MTAudioProcessingTap,
    _ numberFrames: CMItemCount,
    _ flags: MTAudioProcessingTapFlags,
    _ bufferListInOut: UnsafeMutablePointer<AudioBufferList>,
    _ numberFramesOut: UnsafeMutablePointer<CMItemCount>,
    _ flagsOut: UnsafeMutablePointer<MTAudioProcessingTapFlags>
) {
    // 先拿源音频（直通，不修改）
    MTAudioProcessingTapGetSourceAudio(
        tap, numberFrames, bufferListInOut, flagsOut, nil, numberFramesOut
    )
    let analyzer = Unmanaged<SpectrumAnalyzer>.fromOpaque(
        MTAudioProcessingTapGetStorage(tap)
    ).takeUnretainedValue()
    analyzer.processAudio(bufferList: bufferListInOut.pointee, frameCount: Int(numberFramesOut.pointee))
}

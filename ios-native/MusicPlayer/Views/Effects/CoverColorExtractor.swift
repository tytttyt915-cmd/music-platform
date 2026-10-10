import CoreImage
import SwiftUI
import UIKit

/// 封面主色提取：下载封面 → CIAreaAverage 取平均色 → 饱和度增强 → 驱动播放页主题
final class CoverColorExtractor: ObservableObject {
    @Published var themeColor: Color = .blue
    @Published var isReady: Bool = false

    private var task: Task<Void, Never>?
    private static let ciContext = CIContext(options: nil)

    /// 传入新的封面 URL，异步提取主色
    @MainActor
    func extract(from url: URL?) {
        task?.cancel()
        guard let url = url else {
            setColor(.blue, ready: false)
            return
        }
        task = Task { [weak self] in
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                guard let uiImage = UIImage(data: data),
                      let cgImage = uiImage.cgImage else {
                    await self?.setColor(.blue, ready: false)
                    return
                }
                let color = Self.dominantColor(of: cgImage)
                await self?.setColor(color, ready: true)
            } catch {
                await self?.setColor(.blue, ready: false)
            }
        }
    }

    @MainActor
    private func setColor(_ color: Color, ready: Bool) {
        // 只有在任务未被取消时才更新，避免旧封面的颜色覆盖新封面
        guard task?.isCancelled != true else { return }
        themeColor = color
        isReady = ready
    }

    /// CIAreaAverage 取平均色 + 饱和度/明度增强，得到有活力的主题色
    private static func dominantColor(of cgImage: CGImage) -> Color {
        let input = CIImage(cgImage: cgImage)
        // 缩小到 64x64 加速
        let scaleX = 64 / CGFloat(cgImage.width)
        let scaleY = 64 / CGFloat(cgImage.height)
        let small = input.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

        guard let filter = CIFilter(name: "CIAreaAverage"),
              let extent = Optional(small.extent) else {
            return .blue
        }
        filter.setValue(small, forKey: kCIInputImageKey)
        filter.setValue(CIVector(cgRect: extent), forKey: kCIInputExtentKey)
        guard let output = filter.outputImage else { return .blue }

        var bitmap = [UInt8](repeating: 0, count: 4)
        ciContext.render(
            output,
            toBitmap: &bitmap,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        let r = CGFloat(bitmap[0]) / 255
        let g = CGFloat(bitmap[1]) / 255
        let b = CGFloat(bitmap[2]) / 255

        // 转 HSB：impeccable quieter 原则——饱和度钳在 70-85%，不刺眼；
        // 轻微提升（×1.2）但上限 0.85，灰色保持灰，不强制上色
        var h: CGFloat = 0, s: CGFloat = 0, br: CGFloat = 0
        UIColor(red: r, green: g, blue: b, alpha: 1).getHue(&h, saturation: &s, brightness: &br, alpha: nil)
        let quietS = min(0.85, s * 1.2)
        let quietB = min(1, max(br, 0.55))
        return Color(hue: Double(h), saturation: Double(quietS), brightness: Double(quietB))
    }
}

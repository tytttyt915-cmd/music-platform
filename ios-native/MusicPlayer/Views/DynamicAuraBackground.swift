import SwiftUI

/// 动态光晕背景 - 简化可靠版
struct DynamicAuraBackground: View {
    @State private var animate = false
    
    var body: some View {
        ZStack {
            // 基础深色背景
            Color(red: 0.08, green: 0.08, blue: 0.12)
                .ignoresSafeArea()
            
            // 紫色光球
            Circle()
                .fill(Color.purple.opacity(0.4))
                .frame(width: 300, height: 300)
                .blur(radius: 80)
                .offset(x: animate ? -60 : 60, y: animate ? -40 : 40)
            
            // 粉色光球
            Circle()
                .fill(Color.pink.opacity(0.35))
                .frame(width: 280, height: 280)
                .blur(radius: 80)
                .offset(x: animate ? 50 : -50, y: animate ? 60 : -60)
            
            // 蓝色光球
            Circle()
                .fill(Color.blue.opacity(0.3))
                .frame(width: 250, height: 250)
                .blur(radius: 70)
                .offset(x: animate ? 30 : -30, y: animate ? -50 : 50)
        }
        .onAppear {
            withAnimation(
                Animation.easeInOut(duration: 6)
                    .repeatForever(autoreverses: true)
            ) {
                animate.toggle()
            }
        }
    }
}

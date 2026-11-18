import SwiftUI
import UIKit

/// ホーム画面の飾り（イラストはすべて図形で描くので、どの画面サイズ・ダークモードでもくっきり）
enum Decor {
    static let pink = Color(red: 0.95, green: 0.40, blue: 0.54)
    static let peach = Color(red: 0.98, green: 0.72, blue: 0.62)
    static let gold = Color(red: 0.98, green: 0.78, blue: 0.30)
    static let leaf = Color(red: 0.62, green: 0.70, blue: 0.48)
    static let brown = Color(red: 0.42, green: 0.27, blue: 0.16)

    /// 背景のグラデーション（ライト：ピーチ、ダーク：落ち着いた茶）
    static let backgroundTop = Color(UIColor { t in
        t.userInterfaceStyle == .dark ? UIColor(red: 0.12, green: 0.09, blue: 0.09, alpha: 1)
                                      : UIColor(red: 1.00, green: 0.91, blue: 0.87, alpha: 1)
    })
    static let backgroundBottom = Color(UIColor { t in
        t.userInterfaceStyle == .dark ? UIColor(red: 0.08, green: 0.075, blue: 0.07, alpha: 1)
                                      : UIColor(red: 1.00, green: 0.96, blue: 0.94, alpha: 1)
    })
    /// 半透明の白いカード（背景が少し透ける）
    static let glass = Color(UIColor { t in
        t.userInterfaceStyle == .dark ? UIColor(red: 0.17, green: 0.15, blue: 0.14, alpha: 0.92)
                                      : UIColor(white: 1, alpha: 0.82)
    })
    static let glassStroke = Color(UIColor { t in
        t.userInterfaceStyle == .dark ? UIColor(white: 1, alpha: 0.06) : UIColor(white: 1, alpha: 0.9)
    })
}

// MARK: - 背景

/// ホームの背景：ピーチのグラデーション＋左上の葉っぱ＋やわらかい雲＋下の小花
struct HomeBackdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Decor.backgroundTop, Decor.backgroundBottom], startPoint: .top, endPoint: .bottom)
            GeometryReader { geo in
                let w = geo.size.width
                // やわらかい雲のかたまり
                Ellipse().fill(Color.white.opacity(0.35)).frame(width: w * 0.9, height: 160)
                    .blur(radius: 30).offset(x: -w * 0.35, y: 30)
                Ellipse().fill(Decor.pink.opacity(0.10)).frame(width: w * 0.8, height: 220)
                    .blur(radius: 40).offset(x: w * 0.45, y: 260)
                // 左上の枝と葉っぱ
                LeafSprig()
                    .frame(width: 130, height: 110)
                    .offset(x: -18, y: -6)
            }
        }
        .ignoresSafeArea()
    }
}

/// 枝と葉っぱ
struct LeafSprig: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            Path { p in
                p.move(to: CGPoint(x: 0, y: 92))
                p.addQuadCurve(to: CGPoint(x: 122, y: 8), control: CGPoint(x: 52, y: 22))
            }
            .stroke(Decor.leaf.opacity(0.75), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
            ForEach(Array(leaves.enumerated()), id: \.offset) { _, l in
                Leaf()
                    .fill(Decor.leaf.opacity(l.2))
                    .frame(width: 30, height: 14)
                    .rotationEffect(.degrees(l.3))
                    .position(x: l.0, y: l.1)
            }
        }
        .accessibilityHidden(true)
    }
    private let leaves: [(CGFloat, CGFloat, Double, Double)] = [
        (22, 70, 0.8, -40), (30, 48, 0.65, 25), (52, 46, 0.85, -55), (62, 26, 0.6, 15),
        (84, 30, 0.8, -60), (96, 12, 0.6, 5), (114, 16, 0.75, -50)
    ]
}

struct Leaf: Shape {
    func path(in r: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: r.minX, y: r.midY))
            p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.midY), control: CGPoint(x: r.midX, y: r.minY - r.height * 0.4))
            p.addQuadCurve(to: CGPoint(x: r.minX, y: r.midY), control: CGPoint(x: r.midX, y: r.maxY + r.height * 0.4))
        }
    }
}

/// 下の方に咲く小さな花
struct LittleFlower: View {
    var color: Color = Decor.peach
    var size: CGFloat = 18
    var body: some View {
        ZStack {
            ForEach(0..<5) { i in
                Circle().fill(color.opacity(0.85))
                    .frame(width: size * 0.45, height: size * 0.45)
                    .offset(y: -size * 0.28)
                    .rotationEffect(.degrees(Double(i) * 72))
            }
            Circle().fill(Decor.gold).frame(width: size * 0.3, height: size * 0.3)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - 小さな飾り

/// キラキラ（4方向に光る星）
struct Sparkle: Shape {
    func path(in r: CGRect) -> Path {
        let c = CGPoint(x: r.midX, y: r.midY), w = r.width / 2, h = r.height / 2, k: CGFloat = 0.22
        return Path { p in
            p.move(to: CGPoint(x: c.x, y: c.y - h))
            p.addQuadCurve(to: CGPoint(x: c.x + w, y: c.y), control: CGPoint(x: c.x + w * k, y: c.y - h * k))
            p.addQuadCurve(to: CGPoint(x: c.x, y: c.y + h), control: CGPoint(x: c.x + w * k, y: c.y + h * k))
            p.addQuadCurve(to: CGPoint(x: c.x - w, y: c.y), control: CGPoint(x: c.x - w * k, y: c.y + h * k))
            p.addQuadCurve(to: CGPoint(x: c.x, y: c.y - h), control: CGPoint(x: c.x - w * k, y: c.y - h * k))
        }
    }
}

/// 「ピカッ」とした3本線
struct Twinkle: View {
    var color: Color = Decor.pink
    var body: some View {
        ZStack {
            ForEach(0..<3) { i in
                Capsule().fill(color.opacity(0.7))
                    .frame(width: 2.5, height: 9)
                    .offset(y: -10)
                    .rotationEffect(.degrees(Double(i - 1) * 32))
            }
        }
        .frame(width: 24, height: 24)
        .accessibilityHidden(true)
    }
}

/// 小さなハート
struct TinyHeart: View {
    var color: Color = Decor.pink
    var size: CGFloat = 14
    var filled = true
    var body: some View {
        Image(systemName: filled ? "heart.fill" : "heart")
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(color.opacity(0.55))
            .accessibilityHidden(true)
    }
}

/// カードの右下にのぞく雲
struct CornerCloud: View {
    var color: Color
    var body: some View {
        ZStack {
            Circle().frame(width: 46, height: 46).offset(x: -26, y: 10)
            Circle().frame(width: 60, height: 60)
            Circle().frame(width: 40, height: 40).offset(x: 28, y: 12)
        }
        .foregroundStyle(color.opacity(0.13))
        .frame(width: 110, height: 60)
        .accessibilityHidden(true)
    }
}

// MARK: - タイトルの下線

/// タイトルの下の手書き風の線とハート
struct TitleSwoosh: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                Path { p in
                    p.move(to: CGPoint(x: w * 0.04, y: h * 0.75))
                    p.addQuadCurve(to: CGPoint(x: w * 0.9, y: h * 0.45), control: CGPoint(x: w * 0.45, y: h * 0.95))
                }
                .stroke(Decor.peach, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                Image(systemName: "heart")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Decor.peach)
                    .position(x: w * 0.95, y: h * 0.32)
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - カメラと写真のイラスト

/// 小さな写真（空・山・花）
struct MiniLandscape: View {
    var flowers = false
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                LinearGradient(colors: [Color(red: 0.98, green: 0.80, blue: 0.62), Color(red: 0.80, green: 0.88, blue: 0.98)],
                               startPoint: .top, endPoint: .bottom)
                if flowers {
                    Rectangle().fill(Color(red: 0.62, green: 0.80, blue: 0.48)).frame(height: h * 0.45).offset(y: h * 0.3)
                    ForEach(0..<6) { i in
                        LittleFlower(color: [Decor.peach, Color.white, Decor.gold][i % 3], size: w * 0.2)
                            .position(x: w * (0.12 + 0.16 * CGFloat(i)), y: h * (i % 2 == 0 ? 0.62 : 0.78))
                    }
                } else {
                    Circle().fill(Color(red: 1.0, green: 0.86, blue: 0.55)).frame(width: w * 0.2).position(x: w * 0.7, y: h * 0.3)
                    MountainShape().fill(Color(red: 0.55, green: 0.72, blue: 0.52)).frame(width: w, height: h * 0.55).offset(y: h * 0.22)
                    MountainShape().fill(Color(red: 0.70, green: 0.80, blue: 0.55)).frame(width: w * 0.8, height: h * 0.4).offset(x: w * 0.25, y: h * 0.32)
                }
            }
            .clipped()
        }
    }
}

struct MountainShape: Shape {
    func path(in r: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: r.minX, y: r.maxY))
            p.addLine(to: CGPoint(x: r.width * 0.35, y: r.minY + r.height * 0.15))
            p.addLine(to: CGPoint(x: r.width * 0.55, y: r.minY + r.height * 0.45))
            p.addLine(to: CGPoint(x: r.width * 0.7, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
            p.closeSubpath()
        }
    }
}

/// 白い縁のある写真
struct Polaroid: View {
    var flowers = false
    var body: some View {
        MiniLandscape(flowers: flowers)
            .padding(4)
            .padding(.bottom, 8)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 4, x: 0, y: 2)
    }
}

/// ヘッダー右のカメラと写真
struct CameraIllustration: View {
    var body: some View {
        ZStack {
            Polaroid().frame(width: 74, height: 76).rotationEffect(.degrees(-10)).offset(x: 6, y: -24)
            Polaroid(flowers: true).frame(width: 74, height: 76).rotationEffect(.degrees(12)).offset(x: 52, y: 6)
            CameraBody().frame(width: 92, height: 66).offset(x: -18, y: 26)
            Twinkle(color: Decor.peach).rotationEffect(.degrees(-30)).offset(x: -60, y: -30)
        }
        .frame(width: 160, height: 140)
        .accessibilityHidden(true)
    }
}

struct CameraBody: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let shell = Color(red: 0.95, green: 0.70, blue: 0.64)
            ZStack {
                // ストラップ
                Path { p in
                    p.move(to: CGPoint(x: w * 0.04, y: h * 0.4))
                    p.addQuadCurve(to: CGPoint(x: w * 0.1, y: h * 1.1), control: CGPoint(x: -w * 0.15, y: h * 0.8))
                }
                .stroke(Color(red: 0.86, green: 0.55, blue: 0.48), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                RoundedRectangle(cornerRadius: 6).fill(shell.opacity(0.9)).frame(width: w * 0.28, height: h * 0.2).offset(x: -w * 0.18, y: -h * 0.42)
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(shell).frame(width: w, height: h * 0.82).offset(y: h * 0.06)
                RoundedRectangle(cornerRadius: 4).fill(Color(red: 1.0, green: 0.95, blue: 0.90)).frame(width: w, height: h * 0.2).offset(y: h * 0.16)
                Circle().fill(Color(red: 0.96, green: 0.93, blue: 0.90)).frame(width: h * 0.72).offset(y: h * 0.08)
                Circle().fill(Color(red: 0.35, green: 0.30, blue: 0.32)).frame(width: h * 0.52).offset(y: h * 0.08)
                Circle().fill(Color(red: 0.22, green: 0.20, blue: 0.24)).frame(width: h * 0.32).offset(y: h * 0.08)
                Circle().fill(Color.white.opacity(0.7)).frame(width: h * 0.1).offset(x: -h * 0.08, y: -h * 0.02)
                RoundedRectangle(cornerRadius: 3).fill(Color(red: 0.98, green: 0.88, blue: 0.80)).frame(width: w * 0.16, height: h * 0.14).offset(x: w * 0.34, y: -h * 0.22)
            }
        }
    }
}

// MARK: - くま

/// ひょっこり顔を出すくま
struct PeekingBear: View {
    var body: some View {
        let fur = Color(red: 1.0, green: 0.90, blue: 0.80)
        let line = Decor.brown
        ZStack {
            // 耳
            Group {
                Circle().fill(fur).frame(width: 26).overlay(Circle().stroke(line, lineWidth: 2.2))
                    .overlay(Circle().fill(Color(red: 1.0, green: 0.78, blue: 0.75)).frame(width: 12))
                    .offset(x: -30, y: -26)
                Circle().fill(fur).frame(width: 26).overlay(Circle().stroke(line, lineWidth: 2.2))
                    .overlay(Circle().fill(Color(red: 1.0, green: 0.78, blue: 0.75)).frame(width: 12))
                    .offset(x: 30, y: -26)
            }
            // 顔
            Ellipse().fill(fur).frame(width: 86, height: 70).overlay(Ellipse().stroke(line, lineWidth: 2.2))
            // 目・鼻・口
            Circle().fill(line).frame(width: 7).offset(x: -16, y: -4)
            Circle().fill(line).frame(width: 7).offset(x: 16, y: -4)
            Ellipse().fill(Color.white).frame(width: 28, height: 20).offset(y: 9)
            Ellipse().fill(line).frame(width: 9, height: 6).offset(y: 4)
            Path { p in
                p.move(to: CGPoint(x: 0, y: 0)); p.addQuadCurve(to: CGPoint(x: 6, y: 0), control: CGPoint(x: 3, y: 4))
                p.addQuadCurve(to: CGPoint(x: 12, y: 0), control: CGPoint(x: 9, y: 4))
            }
            .stroke(line, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
            .frame(width: 12, height: 6).offset(y: 12)
            // ほっぺ
            Ellipse().fill(Color(red: 1.0, green: 0.70, blue: 0.70).opacity(0.7)).frame(width: 13, height: 8).offset(x: -28, y: 8)
            Ellipse().fill(Color(red: 1.0, green: 0.70, blue: 0.70).opacity(0.7)).frame(width: 13, height: 8).offset(x: 28, y: 8)
            // 手（カードのふちにかけている）
            Capsule().fill(fur).frame(width: 26, height: 18).overlay(Capsule().stroke(line, lineWidth: 2.2)).offset(x: -26, y: 34)
            Capsule().fill(fur).frame(width: 26, height: 18).overlay(Capsule().stroke(line, lineWidth: 2.2)).offset(x: 26, y: 34)
        }
        .frame(width: 110, height: 96)
        .accessibilityHidden(true)
    }
}

// MARK: - スマホとタップのイラスト（仕分けカード）

struct SorterPhoneIllustration: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(red: 0.45, green: 0.32, blue: 0.27))
                .frame(width: 70, height: 116)
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white)
                .frame(width: 62, height: 106)
            VStack(spacing: 4) {
                HStack(spacing: 4) { MiniLandscape().frame(width: 26, height: 26).clipShape(RoundedRectangle(cornerRadius: 4))
                    MiniLandscape(flowers: true).frame(width: 26, height: 26).clipShape(RoundedRectangle(cornerRadius: 4)) }
                HStack(spacing: 4) { MiniLandscape(flowers: true).frame(width: 26, height: 26).clipShape(RoundedRectangle(cornerRadius: 4))
                    MiniLandscape().frame(width: 26, height: 26).clipShape(RoundedRectangle(cornerRadius: 4)) }
                HStack(spacing: 4) { MiniLandscape().frame(width: 26, height: 26).clipShape(RoundedRectangle(cornerRadius: 4))
                    MiniLandscape(flowers: true).frame(width: 26, height: 26).clipShape(RoundedRectangle(cornerRadius: 4)) }
            }
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Decor.pink)
                .frame(width: 50, height: 50)
                .shadow(color: Decor.pink.opacity(0.4), radius: 6, x: 0, y: 3)
                .overlay(Image(systemName: "hand.tap.fill").font(.system(size: 22, weight: .semibold)).foregroundStyle(.white))
                .offset(x: 26, y: 18)
            Sparkle().fill(Decor.gold).frame(width: 14, height: 14).offset(x: -46, y: 14)
            Sparkle().fill(Decor.gold.opacity(0.8)).frame(width: 8, height: 8).offset(x: -40, y: 32)
        }
        .frame(width: 104, height: 124)
        .rotationEffect(.degrees(-6))
        .accessibilityHidden(true)
    }
}

// MARK: - 数字カードの飾り

struct StatPhotosDecor: View {
    var body: some View {
        ZStack {
            Polaroid().frame(width: 46, height: 46).rotationEffect(.degrees(-8)).offset(x: -10, y: 2)
            Polaroid(flowers: false).frame(width: 52, height: 52).rotationEffect(.degrees(8)).offset(x: 10, y: 8)
            Twinkle(color: Decor.pink).offset(x: -6, y: -40)
        }
        .frame(width: 80, height: 80)
        .accessibilityHidden(true)
    }
}

struct StatFolderDecor: View {
    var body: some View {
        let c = Color(red: 0.99, green: 0.84, blue: 0.55)
        ZStack(alignment: .topLeading) {
            UnevenRoundedRectangle(topLeadingRadius: 8, topTrailingRadius: 8).fill(c).brightness(-0.05).frame(width: 30, height: 14)
            RoundedRectangle(cornerRadius: 10).fill(c).brightness(-0.03).frame(width: 74, height: 50).offset(y: 8)
            RoundedRectangle(cornerRadius: 3).fill(Color.white).frame(width: 46, height: 30).rotationEffect(.degrees(-6)).offset(x: 18, y: 4)
            RoundedRectangle(cornerRadius: 10).fill(c).frame(width: 74, height: 36).offset(y: 24)
        }
        .frame(width: 80, height: 64, alignment: .topLeading)
        .accessibilityHidden(true)
    }
}

struct StatPlanDecor: View {
    var unlocked: Bool
    var body: some View {
        ZStack {
            Image(systemName: unlocked ? "crown.fill" : "gift.fill")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(Decor.gold)
                .offset(x: 14, y: 22)
            Sparkle().fill(Decor.gold).frame(width: 22, height: 22).offset(x: -4, y: -20)
            Sparkle().fill(Decor.gold.opacity(0.8)).frame(width: 12, height: 12).offset(x: 20, y: -10)
        }
        .frame(width: 70, height: 80)
        .accessibilityHidden(true)
    }
}

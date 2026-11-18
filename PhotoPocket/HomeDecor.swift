import SwiftUI
import UIKit

/// ホーム画面の飾り（イラストはすべて図形で描くので、どの画面サイズ・ダークモードでもくっきり）
enum Decor {
    static var pink: Color { AppTheme.isBlue ? Color(red: 0.25, green: 0.52, blue: 0.88) : Color(red: 0.95, green: 0.40, blue: 0.54) }
    static var peach: Color { AppTheme.isBlue ? Color(red: 0.55, green: 0.72, blue: 0.95) : Color(red: 0.98, green: 0.72, blue: 0.62) }
    static let gold = Color(red: 0.98, green: 0.78, blue: 0.30)
    static let leaf = Color(red: 0.62, green: 0.70, blue: 0.48)
    static let brown = Color(red: 0.42, green: 0.27, blue: 0.16)

    /// 背景のグラデーション（ライト：ピーチ、ダーク：落ち着いた茶）
    static var backgroundTop: Color {
        let blue = AppTheme.isBlue
        return Color(UIColor { t in
            if t.userInterfaceStyle == .dark {
                return blue ? UIColor(red: 0.07, green: 0.10, blue: 0.15, alpha: 1) : UIColor(red: 0.12, green: 0.09, blue: 0.09, alpha: 1)
            }
            return blue ? UIColor(red: 0.84, green: 0.91, blue: 1.00, alpha: 1) : UIColor(red: 1.00, green: 0.91, blue: 0.87, alpha: 1)
        })
    }
    static var backgroundBottom: Color {
        let blue = AppTheme.isBlue
        return Color(UIColor { t in
            if t.userInterfaceStyle == .dark {
                return blue ? UIColor(red: 0.05, green: 0.06, blue: 0.08, alpha: 1) : UIColor(red: 0.08, green: 0.075, blue: 0.07, alpha: 1)
            }
            return blue ? UIColor(red: 0.96, green: 0.98, blue: 1.00, alpha: 1) : UIColor(red: 1.00, green: 0.96, blue: 0.94, alpha: 1)
        })
    }
    /// 仕分けカードの背景（左→右）
    static var sorterGradient: [Color] {
        AppTheme.isBlue ? [Color(red: 0.92, green: 0.95, blue: 1.0), Color(red: 0.84, green: 0.90, blue: 1.0)]
                        : [Color(red: 1.0, green: 0.93, blue: 0.93), Color(red: 1.0, green: 0.86, blue: 0.89)]
    }
    /// 半透明の白いカード（背景が少し透ける）
    static let glass = Color(UIColor { t in
        t.userInterfaceStyle == .dark ? UIColor(red: 0.17, green: 0.15, blue: 0.14, alpha: 0.96)
                                      : UIColor(white: 1, alpha: 0.96)
    })
    /// カードの枠線（背景との境目がはっきり見えるよう、テーマの色を薄く）
    static var glassStroke: Color {
        let blue = AppTheme.isBlue
        return Color(UIColor { t in
            if t.userInterfaceStyle == .dark { return UIColor(white: 1, alpha: 0.14) }
            return blue ? UIColor(red: 0.55, green: 0.70, blue: 0.92, alpha: 0.55)
                        : UIColor(red: 0.92, green: 0.62, blue: 0.66, alpha: 0.55)
        })
    }
    /// カードの影
    static let cardShadow = Color(UIColor { t in
        t.userInterfaceStyle == .dark ? UIColor(white: 0, alpha: 0.5) : UIColor(red: 0.45, green: 0.25, blue: 0.20, alpha: 0.13)
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
                if Art.isShown("deco_sprig") {
                    LeafSprig()
                        .frame(width: 120, height: 100)
                        .offset(x: -26, y: -14)
                }
                // 下の小花
                if Art.isShown("deco_sakura") {
                    Art.image("deco_sakura").resizable().scaledToFit()
                        .frame(width: 34, height: 34).opacity(0.85)
                        .position(x: 22, y: geo.size.height - 40)
                    Art.image("deco_flower").resizable().scaledToFit()
                        .frame(width: 34, height: 30).opacity(0.85)
                        .position(x: w - 22, y: geo.size.height - 44)
                }
            }
        }
        .ignoresSafeArea()
    }
}

/// 枝と葉っぱ
struct LeafSprig: View {
    var body: some View {
        Art.image("deco_sprig")
            .resizable()
            .scaledToFit()
            .rotationEffect(.degrees(-28))
            .opacity(0.9)
            .accessibilityHidden(true)
    }
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
        Art.image("deco_heart")
            .resizable()
            .scaledToFit()
            .frame(width: size * 1.5, height: size * 1.5)
            .accessibilityHidden(true)
    }
}

/// カードの右下にのぞく雲
struct CornerCloud: View {
    var color: Color
    var body: some View {
        Art.image("deco_cloud")
            .resizable()
            .scaledToFit()
            .frame(width: 110, height: 60)
            .opacity(0.45)
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
            Art.image("deco_polaroids").resizable().scaledToFit()
                .frame(width: 112, height: 92)
                .offset(x: 26, y: -18)
            Art.image("deco_camera").resizable().scaledToFit()
                .frame(width: 104, height: 90)
                .offset(x: -22, y: 24)
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
        Art.image("deco_bear")
            .resizable()
            .scaledToFit()
            .frame(width: 110, height: 96)
            .opacity(Art.isShown("deco_bear") ? 1 : 0)
            .accessibilityHidden(true)
    }
}

// MARK: - スマホとタップのイラスト（仕分けカード）

struct SorterPhoneIllustration: View {
    var body: some View {
        ZStack {
            Art.image("deco_phone").resizable().scaledToFit()
                .frame(width: 104, height: 112)
                .offset(x: 6)
            Sparkle().fill(Decor.gold).frame(width: 14, height: 14).offset(x: -46, y: 14)
            Sparkle().fill(Decor.gold.opacity(0.8)).frame(width: 8, height: 8).offset(x: -40, y: 32)
        }
        .frame(width: 104, height: 124)
        .accessibilityHidden(true)
    }
}

// MARK: - 数字カードの飾り

struct StatPhotosDecor: View {
    var body: some View {
        ZStack {
            Art.image("deco_polaroids").resizable().scaledToFit().frame(width: 78, height: 66).offset(y: 6)
            Twinkle(color: Decor.pink).offset(x: -6, y: -40)
        }
        .frame(width: 80, height: 80)
        .accessibilityHidden(true)
    }
}

struct StatFolderDecor: View {
    var body: some View {
        Art.image("deco_folder").resizable().scaledToFit()
            .frame(width: 80, height: 64)
            .accessibilityHidden(true)
    }
}

struct StatPlanDecor: View {
    var unlocked: Bool
    var body: some View {
        ZStack {
            if unlocked {
                Art.image("deco_crown").resizable().scaledToFit().frame(width: 44, height: 38).offset(x: 12, y: 20)
            } else {
                Image(systemName: "gift.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(Decor.gold)
                    .offset(x: 14, y: 22)
            }
            Art.image("deco_sparkles").resizable().scaledToFit().frame(width: 34, height: 34).offset(x: 0, y: -18)
        }
        .frame(width: 70, height: 80)
        .accessibilityHidden(true)
    }
}


/// 分類のアイコン：イラストがあるものはイラスト、ないものはSF Symbols
enum CategoryArt {
    static func asset(for symbol: String) -> String? {
        if AppTheme.isBlue {
            switch symbol {
            case "cart.fill": return "blue_tag"
            case "briefcase.fill": return "blue_briefcase"
            case "person.2.fill": return "blue_people"
            case "doc.text.fill": return "blue_clipboard"
            case "star.fill": return "blue_star"
            case "camera.fill": return "blue_camera"
            default: return nil
            }
        }
        switch symbol {
        case "cart.fill": return "cat_cart"
        case "house.fill": return "cat_house"
        case "briefcase.fill": return "cat_bag"
        case "pawprint.fill": return "cat_paw"
        default: return nil
        }
    }
}

/// テーマに合わせたイラスト（ブルーでは青いイラストに入れ替え、合うものがない飾りは出さない）
enum Art {
    private static let blue: [String: String] = [
        "deco_camera": "blue_camera", "deco_polaroids": "blue_photos", "deco_folder": "blue_folder",
        "deco_photo_icon": "blue_picture", "deco_badge": "blue_shield", "deco_crown": "blue_star",
        "deco_phone": "blue_phone", "deco_cloud": "blue_cloud", "deco_heart": "blue_star",
    ]
    private static let pinkOnly: Set<String> = ["deco_bear", "deco_sprig", "deco_sakura", "deco_flower"]

    static func image(_ base: String) -> Image {
        Image(AppTheme.isBlue ? (blue[base] ?? base) : base)
    }
    static func isShown(_ base: String) -> Bool {
        !(AppTheme.isBlue && pinkOnly.contains(base))
    }
}

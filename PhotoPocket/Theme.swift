import SwiftUI
import UIKit

/// アプリ全体の見た目（あたたかみのある色・丸い文字・やわらかいカード）
/// 色のテーマ（ピンク・ブルー）
enum AppTheme: String, CaseIterable, Identifiable {
    case pink, blue
    var id: String { rawValue }
    var label: String { self == .pink ? "ピンク" : "ブルー" }
    static var current: AppTheme {
        AppTheme(rawValue: UserDefaults.standard.string(forKey: "appTheme") ?? "") ?? .pink
    }
    static var isBlue: Bool { current == .blue }
}

private func themed(light: (CGFloat, CGFloat, CGFloat), dark: (CGFloat, CGFloat, CGFloat)) -> Color {
    Color(UIColor { trait in
        let c = trait.userInterfaceStyle == .dark ? dark : light
        return UIColor(red: c.0, green: c.1, blue: c.2, alpha: 1)
    })
}

enum Theme {
    /// メインの色（ピンク：やさしいピンク／ブルー：落ち着いた青）
    static var accent: Color {
        AppTheme.isBlue ? Color(red: 0.20, green: 0.48, blue: 0.86) : Color(red: 0.95, green: 0.40, blue: 0.54)
    }

    /// 薄いメインの色（選択中のタブなど）
    static var accentSoft: Color {
        AppTheme.isBlue ? themed(light: (0.88, 0.93, 1.00), dark: (0.12, 0.18, 0.28))
                        : themed(light: (1.00, 0.90, 0.93), dark: (0.29, 0.15, 0.19))
    }

    /// 文字の色（ピンク：こげ茶／ブルー：紺）
    static var ink: Color {
        AppTheme.isBlue ? themed(light: (0.14, 0.23, 0.38), dark: (0.92, 0.94, 0.97))
                        : themed(light: (0.36, 0.23, 0.13), dark: (0.95, 0.93, 0.90))
    }

    /// あいさつカードの色
    static var greetingCard: Color {
        AppTheme.isBlue ? themed(light: (0.90, 0.94, 1.00), dark: (0.11, 0.15, 0.23))
                        : themed(light: (1.00, 0.91, 0.93), dark: (0.23, 0.13, 0.16))
    }

    /// iCloudカードの色（淡い水色）
    static let cloudCard = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.11, green: 0.16, blue: 0.23, alpha: 1)
            : UIColor(red: 0.90, green: 0.95, blue: 1.00, alpha: 1)
    })

    /// 空の色
    static let skyTop = Color(red: 0.81, green: 0.91, blue: 0.98)
    static let skyBottom = Color(red: 0.95, green: 0.98, blue: 1.00)

    /// 背景：ライトはクリーム色（ブルーは淡い水色）、ダークは落ち着いた黒
    static var background: Color {
        AppTheme.isBlue ? themed(light: (0.96, 0.975, 1.00), dark: (0.06, 0.07, 0.09))
                        : themed(light: (1.00, 0.976, 0.96), dark: (0.08, 0.075, 0.07))
    }

    /// カードの色
    static let card = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.16, green: 0.15, blue: 0.14, alpha: 1)
            : .white
    })

    static let corner: CGFloat = 20

    /// 時間帯のあいさつ
    static var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 4..<11: return "おはようございます"
        case 11..<17: return "こんにちは"
        default: return "こんばんは"
        }
    }
}

struct CardBackground: ViewModifier {
    var corner: CGFloat = Theme.corner
    func body(content: Content) -> some View {
        content
            .background(Theme.card, in: RoundedRectangle(cornerRadius: corner, style: .continuous))
            .shadow(color: .black.opacity(0.06), radius: 10, x: 0, y: 4)
    }
}

extension View {
    func card(corner: CGFloat = Theme.corner) -> some View {
        modifier(CardBackground(corner: corner))
    }
}

/// 丸いアイコン（色付きの円＋記号）
struct IconBadge: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 36

    var body: some View {
        Circle()
            .fill(color.opacity(0.18))
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.45, weight: .semibold))
                    .foregroundStyle(color)
            }
    }
}

/// 大きくて押しやすいメインボタン
struct BigButtonStyle: ButtonStyle {
    var color: Color = Theme.accent
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .padding(.horizontal, 26)
            .padding(.vertical, 15)
            .background(color, in: Capsule())
            .shadow(color: color.opacity(0.35), radius: 10, x: 0, y: 5)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}

/// やさしい空の状態（イラスト代わりのアイコン＋説明）
struct FriendlyEmptyView<Actions: View>: View {
    let symbol: String
    let title: String
    let message: String
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle().fill(Theme.accent.opacity(0.12)).frame(width: 150, height: 150)
                Circle().fill(Theme.accent.opacity(0.18)).frame(width: 104, height: 104)
                Image(systemName: symbol)
                    .font(.system(size: 46, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }
            .padding(.bottom, 4)
            Text(title)
                .font(.title2.bold())
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, 28)
            VStack(spacing: 12) { actions() }
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

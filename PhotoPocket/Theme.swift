import SwiftUI
import UIKit

/// アプリ全体の見た目（あたたかみのある色・丸い文字・やわらかいカード）
enum Theme {
    /// メインの色（やさしいピンク）
    static let accent = Color(red: 0.95, green: 0.40, blue: 0.54)

    /// 薄いピンク（選択中のタブなど）
    static let accentSoft = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.29, green: 0.15, blue: 0.19, alpha: 1)
            : UIColor(red: 1.00, green: 0.90, blue: 0.93, alpha: 1)
    })

    /// 文字の色（こげ茶）
    static let ink = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.95, green: 0.93, blue: 0.90, alpha: 1)
            : UIColor(red: 0.36, green: 0.23, blue: 0.13, alpha: 1)
    })

    /// あいさつカードの色（淡いピンク）
    static let greetingCard = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.23, green: 0.13, blue: 0.16, alpha: 1)
            : UIColor(red: 1.00, green: 0.91, blue: 0.93, alpha: 1)
    })

    /// iCloudカードの色（淡い水色）
    static let cloudCard = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.11, green: 0.16, blue: 0.23, alpha: 1)
            : UIColor(red: 0.90, green: 0.95, blue: 1.00, alpha: 1)
    })

    /// 空の色
    static let skyTop = Color(red: 0.81, green: 0.91, blue: 0.98)
    static let skyBottom = Color(red: 0.95, green: 0.98, blue: 1.00)

    /// 背景：ライトはクリーム色、ダークは落ち着いた黒
    static let background = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.08, green: 0.075, blue: 0.07, alpha: 1)
            : UIColor(red: 1.00, green: 0.976, blue: 0.96, alpha: 1)
    })

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

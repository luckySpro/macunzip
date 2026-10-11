import SwiftUI

/// 界面配色：几套经典色卡，整体替换强调色。
enum Theme: String, CaseIterable, Identifiable {
    case system, blue, graphite, green, teal, orange, red, purple

    var id: String { rawValue }

    var name: String {
        switch self {
        case .system: return "跟随系统"
        case .blue: return "经典蓝"
        case .graphite: return "石墨"
        case .green: return "森林绿"
        case .teal: return "湖水青"
        case .orange: return "珊瑚橙"
        case .red: return "玫瑰红"
        case .purple: return "葡萄紫"
        }
    }

    var color: Color {
        switch self {
        case .system: return .accentColor
        case .blue: return Color(red: 0.00, green: 0.48, blue: 1.00)
        case .graphite: return Color(red: 0.45, green: 0.47, blue: 0.51)
        case .green: return Color(red: 0.18, green: 0.62, blue: 0.36)
        case .teal: return Color(red: 0.08, green: 0.62, blue: 0.66)
        case .orange: return Color(red: 0.98, green: 0.47, blue: 0.27)
        case .red: return Color(red: 0.90, green: 0.28, blue: 0.42)
        case .purple: return Color(red: 0.56, green: 0.36, blue: 0.85)
        }
    }

    static let storageKey = "theme"

    /// 当前强调色，各界面用它代替系统强调色。
    @MainActor static var accent: Color { ThemeStore.shared.theme.color }
}

/// 当前配色。用 ObservableObject 显式通知，所有窗口在切换时立即刷新。
@MainActor
final class ThemeStore: ObservableObject {
    static let shared = ThemeStore()

    @Published var theme: Theme {
        didSet { SharedSettings.shared.defaults.set(theme.rawValue, forKey: Theme.storageKey) }
    }

    private init() {
        theme = Theme(rawValue: SharedSettings.shared.defaults.string(forKey: Theme.storageKey) ?? "") ?? .system
    }
}

/// 加在每个窗口的根视图上：应用强调色，并在切换色卡时重建界面。
struct ThemedRoot: ViewModifier {
    @ObservedObject private var store = ThemeStore.shared

    func body(content: Content) -> some View {
        content
            .tint(store.theme.color)
            .accentColor(store.theme.color)
            .id(store.theme)
    }
}

extension View {
    func themed() -> some View { modifier(ThemedRoot()) }
}

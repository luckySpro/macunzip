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

    /// 窗口底色：系统毛玻璃，顶部再晕染一层很淡的主题色，避免整块平涂发灰。
    var windowBackground: some View {
        ZStack {
            VisualEffect(material: .underWindowBackground)
            LinearGradient(colors: [color.opacity(self == .system ? 0.06 : 0.14), color.opacity(0.02), .clear],
                           startPoint: .topLeading, endPoint: .bottom)
        }
    }

    static let storageKey = "theme"

    /// 当前强调色，各界面用它代替系统强调色。
    @MainActor static var accent: Color { ThemeStore.shared.theme.color }
    /// 非 MainActor 场合用的强调色（视图都会随主题切换重建）。
    static var accentStatic: Color {
        Theme(rawValue: SharedSettings.shared.defaults.string(forKey: storageKey) ?? "")?.color ?? .accentColor
    }
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
            .scrollContentBackground(.hidden)
            .background(store.theme.windowBackground.ignoresSafeArea())
            .id(store.theme)
    }
}

extension View {
    func themed() -> some View { modifier(ThemedRoot()) }
}

/// AppKit 毛玻璃背景。
struct VisualEffect: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) { view.material = material }
}

/// 统一的卡片外观：半透明底、细描边、轻阴影。
struct CardStyle: ViewModifier {
    var radius: CGFloat = 12
    var highlighted = false
    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(highlighted ? AnyShapeStyle(Theme.accentStatic.opacity(0.12)) : AnyShapeStyle(.background.opacity(0.55))))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(highlighted ? Theme.accentStatic.opacity(0.7) : Color.primary.opacity(0.08), lineWidth: highlighted ? 1.5 : 1))
            .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
    }
}

extension View {
    func card(radius: CGFloat = 12, highlighted: Bool = false) -> some View {
        modifier(CardStyle(radius: radius, highlighted: highlighted))
    }
}

/// 胶囊式模式切换，替代系统分段控件。
struct ModeSwitch<T: Hashable & Identifiable>: View {
    @Binding var selection: T
    let items: [T]
    let title: (T) -> String
    let icon: (T) -> String
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items) { item in
                let on = item == selection
                Button { withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { selection = item } } label: {
                    Label(title(item), systemImage: icon(item))
                        .font(.callout.weight(on ? .semibold : .regular))
                        .foregroundStyle(on ? Color.white : Color.secondary)
                        .padding(.horizontal, 14).frame(height: 28)
                        .background {
                            if on { Capsule().fill(Theme.accentStatic.gradient).matchedGeometryEffect(id: "pill", in: ns)
                                .shadow(color: Theme.accentStatic.opacity(0.35), radius: 4, y: 1) }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Capsule().fill(Color.primary.opacity(0.06)))
    }
}

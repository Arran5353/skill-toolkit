import SwiftUI
import SkillDeckCore

/// Per-kind visual identity (accent color + SF Symbol) so the whole UI reads at a glance,
/// the way a good dev tool color-codes message types.
enum NodeTheme {
    static func accent(_ kind: NodeKind) -> Color {
        switch kind {
        case .skill:          return Color(red: 0.55, green: 0.36, blue: 0.96) // violet
        case .localSkill:     return Color(red: 0.40, green: 0.52, blue: 0.96) // indigo-blue
        case .command:        return Color(red: 0.13, green: 0.62, blue: 0.74) // teal
        case .builtinCommand: return Color(red: 0.30, green: 0.55, blue: 0.55) // muted teal-green
        case .plugin:         return Color(red: 0.93, green: 0.55, blue: 0.18) // amber
        case .marketplace:    return Color(red: 0.85, green: 0.33, blue: 0.45) // rose
        case .mcpServer:      return Color(red: 0.30, green: 0.62, blue: 0.55) // teal-green
        }
    }

    static func icon(_ kind: NodeKind) -> String {
        switch kind {
        case .skill:          return "sparkles"
        case .localSkill:     return "folder.badge.gearshape"
        case .command:        return "terminal.fill"
        case .builtinCommand: return "command"
        case .plugin:         return "puzzlepiece.extension.fill"
        case .marketplace:    return "bag.fill"
        case .mcpServer:      return "network"
        }
    }

    static func label(_ kind: NodeKind) -> String {
        switch kind {
        case .skill:          return "SKILL"
        case .localSkill:     return "LOCAL SKILL"
        case .command:        return "COMMAND"
        case .builtinCommand: return "BUILT-IN"
        case .plugin:         return "PLUGIN"
        case .marketplace:    return "MARKETPLACE"
        case .mcpServer:      return "MCP SERVER"
        }
    }
}

/// The gradient rounded-square icon tile used in detail-view headers.
struct NodeIconTile: View {
    let kind: NodeKind
    var size: CGFloat = 52
    var body: some View {
        let c = NodeTheme.accent(kind)
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(c.gradient.opacity(0.9))
                .frame(width: size, height: size)
                .shadow(color: c.opacity(0.35), radius: 8, y: 3)
            Image(systemName: NodeTheme.icon(kind))
                .font(.system(size: size * 0.46, weight: .semibold))
                .foregroundStyle(.white)
        }
    }
}

extension View {
    /// The subtle top accent wash used behind detail views.
    func accentBackdrop(_ accent: Color) -> some View {
        background(
            LinearGradient(colors: [accent.opacity(0.06), .clear],
                           startPoint: .top, endPoint: .center)
                .ignoresSafeArea()
        )
    }
}

/// A small colored pill (e.g. the kind badge).
struct KindBadge: View {
    let kind: NodeKind
    var body: some View {
        let c = NodeTheme.accent(kind)
        Text(NodeTheme.label(kind))
            .font(.system(size: 10, weight: .heavy, design: .rounded))
            .tracking(0.8)
            .foregroundStyle(c)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(c.opacity(0.14), in: Capsule())
            .overlay(Capsule().strokeBorder(c.opacity(0.30), lineWidth: 1))
    }
}

/// A titled section container — icon + uppercased label header over bordered content,
/// echoing the clearly-delineated blocks of a good history viewer.
struct SectionCard<Content: View>: View {
    let title: String
    let systemImage: String
    var accent: Color = .secondary
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(accent)
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(1.0)
                    .foregroundStyle(.secondary)
            }
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}

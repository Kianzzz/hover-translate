import SwiftUI
import AppKit

/// Design tokens and primitives inspired by coss.com/ui (neutral palette,
/// semi-transparent crisp borders, tactile subtle shadows, CardFrame layering,
/// and full macOS Light/Dark appearance support).
enum Coss {
    private static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }

    // Surfaces
    static let background = dynamic(
        light: NSColor(srgbRed: 1.0, green: 1.0, blue: 1.0, alpha: 1.0),
        dark: NSColor(srgbRed: 0.078, green: 0.078, blue: 0.082, alpha: 1.0)
    )
    static let sidebar = dynamic(
        light: NSColor(srgbRed: 0.980, green: 0.980, blue: 0.982, alpha: 1.0),
        dark: NSColor(srgbRed: 0.058, green: 0.058, blue: 0.062, alpha: 1.0)
    )
    static let card = dynamic(
        light: NSColor(srgbRed: 1.0, green: 1.0, blue: 1.0, alpha: 1.0),
        dark: NSColor(srgbRed: 0.098, green: 0.098, blue: 0.104, alpha: 1.0)
    )
    static let popover = dynamic(
        light: NSColor(srgbRed: 1.0, green: 1.0, blue: 1.0, alpha: 0.98),
        dark: NSColor(srgbRed: 0.106, green: 0.106, blue: 0.112, alpha: 0.98)
    )
    static let frame = dynamic(
        light: NSColor(srgbRed: 0.968, green: 0.968, blue: 0.971, alpha: 1.0),
        dark: NSColor(srgbRed: 0.068, green: 0.068, blue: 0.072, alpha: 1.0)
    )
    static let muted = dynamic(
        light: NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.04),
        dark: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.05)
    )
    static let accent = dynamic(
        light: NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.055),
        dark: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.075)
    )

    // Foreground & Ink
    static let foreground = dynamic(
        light: NSColor(srgbRed: 0.149, green: 0.149, blue: 0.149, alpha: 1.0),
        dark: NSColor(srgbRed: 0.961, green: 0.961, blue: 0.961, alpha: 1.0)
    )
    static let mutedForeground = dynamic(
        light: NSColor(srgbRed: 0.40, green: 0.40, blue: 0.42, alpha: 1.0),
        dark: NSColor(srgbRed: 0.60, green: 0.60, blue: 0.63, alpha: 1.0)
    )
    static let primary = dynamic(
        light: NSColor(srgbRed: 0.149, green: 0.149, blue: 0.149, alpha: 1.0),
        dark: NSColor(srgbRed: 0.961, green: 0.961, blue: 0.961, alpha: 1.0)
    )
    static let primaryForeground = dynamic(
        light: NSColor(srgbRed: 0.980, green: 0.980, blue: 0.980, alpha: 1.0),
        dark: NSColor(srgbRed: 0.10, green: 0.10, blue: 0.10, alpha: 1.0)
    )

    // Borders & Sheens (coss ui opaque-feel semi-transparent hairlines)
    static let border = dynamic(
        light: NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.085),
        dark: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.095)
    )
    static let sidebarBorder = dynamic(
        light: NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.065),
        dark: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.07)
    )
    static let inputBorder = dynamic(
        light: NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.12),
        dark: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.13)
    )
    static let innerHighlight = dynamic(
        light: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.16),
        dark: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.08)
    )
    static let subtleShadow = dynamic(
        light: NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.055),
        dark: NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.35)
    )

    // Semantic statuses (matching coss.com/ui badge & status tokens)
    static let success = Color(red: 0.0, green: 0.733, blue: 0.498)
    static let successForeground = dynamic(
        light: NSColor(srgbRed: 0.0, green: 0.475, blue: 0.337, alpha: 1.0),
        dark: NSColor(srgbRed: 0.0, green: 0.824, blue: 0.580, alpha: 1.0)
    )
    static let successBg = dynamic(
        light: NSColor(srgbRed: 0.0, green: 0.733, blue: 0.498, alpha: 0.10),
        dark: NSColor(srgbRed: 0.0, green: 0.733, blue: 0.498, alpha: 0.16)
    )

    static let warning = Color(red: 0.976, green: 0.612, blue: 0.0)
    static let warningForeground = dynamic(
        light: NSColor(srgbRed: 0.718, green: 0.314, blue: 0.0, alpha: 1.0),
        dark: NSColor(srgbRed: 0.988, green: 0.733, blue: 0.0, alpha: 1.0)
    )
    static let warningBg = dynamic(
        light: NSColor(srgbRed: 0.976, green: 0.612, blue: 0.0, alpha: 0.11),
        dark: NSColor(srgbRed: 0.976, green: 0.612, blue: 0.0, alpha: 0.16)
    )

    static let destructiveForeground = dynamic(
        light: NSColor(srgbRed: 0.749, green: 0.0, blue: 0.059, alpha: 1.0),
        dark: NSColor(srgbRed: 1.0, green: 0.396, blue: 0.408, alpha: 1.0)
    )
}

enum CossButtonVariant { case primary, outline, ghost, secondary }

struct CossButtonStyle: ButtonStyle {
    var variant: CossButtonVariant = .outline
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        let radius: CGFloat = compact ? 7 : 8
        configuration.label
            .font(.system(size: compact ? 11 : 12.5, weight: .medium))
            .padding(.horizontal, compact ? 9 : 12)
            .padding(.vertical, compact ? 5 : 7)
            .foregroundStyle(foregroundColor)
            .background(backgroundColor(pressed: configuration.isPressed))
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(borderColor, lineWidth: variant == .ghost ? 0 : 1)
            )
            .overlay(alignment: .top) {
                if variant == .primary {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .stroke(Coss.innerHighlight, lineWidth: 0.5)
                        .padding(0.5)
                }
            }
            .shadow(color: variant == .ghost ? .clear : Coss.subtleShadow, radius: variant == .primary ? 3 : 1.5, y: 1)
            .opacity(configuration.isPressed ? 0.86 : 1)
    }

    private var foregroundColor: Color {
        switch variant {
        case .primary: return Coss.primaryForeground
        case .outline, .secondary, .ghost: return Coss.foreground
        }
    }

    private func backgroundColor(pressed: Bool) -> Color {
        switch variant {
        case .primary: return Coss.primary.opacity(pressed ? 0.88 : 1)
        case .outline: return pressed ? Coss.accent : Coss.card
        case .secondary: return pressed ? Coss.accent : Coss.muted
        case .ghost: return pressed ? Coss.accent : Color.clear
        }
    }

    private var borderColor: Color {
        switch variant {
        case .primary: return Coss.primary
        case .outline: return Coss.inputBorder
        case .secondary: return Coss.border
        case .ghost: return .clear
        }
    }
}

/// Coss UI Card: crisp 1px border + subtle bottom elevation shadow.
struct CossCard<Content: View>: View {
    var padding: CGFloat = 20
    var radius: CGFloat = 14
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Coss.card)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(Coss.border, lineWidth: 1)
            )
            .shadow(color: Coss.subtleShadow, radius: 3, y: 1)
    }
}

/// Coss UI CardFrame: tinted outer frame housing a header and an inset Card panel.
struct CossCardFrame<Header: View, Content: View>: View {
    var contentPadding: CGFloat = 20
    @ViewBuilder var header: Header
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
            VStack(alignment: .leading, spacing: 0) { content }
                .padding(contentPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Coss.card)
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(Coss.border, lineWidth: 1)
                )
                .padding(4)
        }
        .background(Coss.frame)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Coss.border, lineWidth: 1)
        )
        .shadow(color: Coss.subtleShadow, radius: 3, y: 1)
    }
}

struct CossIconTile: View {
    let symbol: String
    var size: CGFloat = 32
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.43, weight: .medium))
            .foregroundStyle(Coss.foreground.opacity(0.82))
            .frame(width: size, height: size)
            .background(Coss.muted)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Coss.border, lineWidth: 1)
            )
    }
}

enum CossBadgeTone { case neutral, success, warning, outline }

struct CossBadge: View {
    let text: String
    var symbol: String? = nil
    var tone: CossBadgeTone = .neutral

    var body: some View {
        HStack(spacing: 4) {
            if let symbol {
                Image(systemName: symbol).font(.system(size: 10, weight: .semibold))
            }
            Text(text).font(.system(size: 10.5, weight: .medium))
        }
        .foregroundStyle(fg)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(bg)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(tone == .outline ? Coss.border : .clear, lineWidth: 1)
        )
    }

    private var fg: Color {
        switch tone {
        case .neutral, .outline: return Coss.foreground
        case .success: return Coss.successForeground
        case .warning: return Coss.warningForeground
        }
    }

    private var bg: Color {
        switch tone {
        case .neutral: return Coss.muted
        case .outline: return Coss.card
        case .success: return Coss.successBg
        case .warning: return Coss.warningBg
        }
    }
}

struct CossKbd: View {
    let keys: String
    var label: String? = nil

    var body: some View {
        HStack(spacing: 5) {
            Text(keys)
                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                .foregroundStyle(Coss.foreground)
                .padding(.horizontal, 6)
                .padding(.vertical, 2.5)
                .background(Coss.card)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(Coss.inputBorder, lineWidth: 1)
                )
                .shadow(color: Coss.subtleShadow, radius: 0.5, y: 1)
            if let label {
                Text(label)
                    .font(.system(size: 11))
                    .foregroundStyle(Coss.mutedForeground)
            }
        }
    }
}

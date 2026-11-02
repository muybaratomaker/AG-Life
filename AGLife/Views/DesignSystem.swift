import SwiftUI
import UIKit

enum LifeArea {
    case spending, calendar, thoughts

    var accent: Color {
        switch self {
        case .spending: return LifePalette.adaptive(0x087B70, 0x60DDC3)
        case .calendar: return LifePalette.adaptive(0x4F53BD, 0xB0B3FF)
        case .thoughts: return LifePalette.adaptive(0xB74655, 0xFFADB1)
        }
    }
    var ink: Color {
        switch self {
        case .spending: return Color(red: 0.02, green: 0.34, blue: 0.33)
        case .calendar: return Color(red: 0.23, green: 0.23, blue: 0.57)
        case .thoughts: return Color(red: 0.58, green: 0.19, blue: 0.29)
        }
    }
    var gradient: LinearGradient {
        LinearGradient(colors: [ink, ink.opacity(0.86)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

enum LifePalette {
    static let canvas = adaptive(0xF4F7F5, 0x111B20)
    static let surface = adaptive(0xFFFFFF, 0x1D2A31)
    static func adaptive(_ light: UInt, _ dark: UInt) -> Color {
        func uiColor(_ hex: UInt) -> UIColor {
            UIColor(red: CGFloat((hex >> 16) & 255) / 255,
                green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1)
        }
        let lightColor = uiColor(light)
        let darkColor = uiColor(dark)
        return Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? darkColor : lightColor })
    }
}

struct LifeBackdrop: View {
    var area: LifeArea = .spending
    var body: some View {
        LinearGradient(colors: [area.accent.opacity(0.12), LifePalette.canvas, LifePalette.canvas],
            startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea()
    }
}

struct LifeCard<Content: View>: View {
    var area: LifeArea = .spending
    @ViewBuilder var content: Content
    var body: some View {
        content.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(LifePalette.surface, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(area.accent.opacity(0.12), lineWidth: 1)
            }
    }
}

struct LifeHeading: View {
    let title: String
    let subtitle: String
    var area: LifeArea = .spending
    var symbol: String
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol).font(.title2.weight(.semibold))
                .foregroundStyle(area.accent).frame(width: 48, height: 48)
                .background(area.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 17))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.system(.title2, design: .rounded, weight: .bold)).foregroundStyle(.primary)
                    .accessibilityAddTraits(.isHeader)
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct LifeField<Content: View>: View {
    let title: String
    let symbol: String
    var area: LifeArea = .spending
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: symbol).font(.subheadline.weight(.semibold)).foregroundStyle(area.accent)
            content.font(.body).frame(maxWidth: .infinity, alignment: .leading)
        }.padding(18)
            .background(LifePalette.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 22).strokeBorder(area.accent.opacity(0.16), lineWidth: 1) }
    }
}

struct LifePrimaryButton: View {
    let title: String
    var symbol = "checkmark"
    var area: LifeArea = .spending
    var enabled = true
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol).font(.system(.headline, design: .rounded))
                .frame(maxWidth: .infinity, minHeight: 56).padding(.horizontal, 16)
                .foregroundStyle(.white).background(area.gradient, in: RoundedRectangle(cornerRadius: 21))
        }
        .buttonStyle(GentlePressStyle()).disabled(!enabled).opacity(enabled ? 1 : 0.45)
    }
}

struct LifeSaveBar: View {
    var area: LifeArea
    var enabled = true
    let action: () -> Void
    var body: some View {
        LifePrimaryButton(title: "Salva", area: area, enabled: enabled, action: action)
            .padding(.horizontal, 20).padding(.vertical, 10).background(.bar)
    }
}

struct LifeEmptyState: View {
    let title: String
    let message: String
    let symbol: String
    var area: LifeArea = .spending
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbol).font(.system(size: 30, weight: .medium))
                .foregroundStyle(area.accent).frame(width: 72, height: 72)
                .background(area.accent.opacity(0.12), in: Circle()).accessibilityHidden(true)
            Text(title).font(.system(.headline, design: .rounded))
            Text(message).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity).padding(.vertical, 20)
    }
}

extension View {
    func lifeList(area: LifeArea) -> some View {
        listStyle(.insetGrouped).scrollContentBackground(.hidden)
            .background(LifeBackdrop(area: area)).tint(area.accent)
    }
    func lifeFloatingRow() -> some View {
        listRowBackground(Color.clear).listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
    }
}

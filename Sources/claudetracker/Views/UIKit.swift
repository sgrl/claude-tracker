import SwiftUI

/// Uniform section header used across every card in the popover.
struct SectionHeader: View {
    let title: String
    var trailing: AnyView? = nil

    init(_ title: String) {
        self.title = title
        self.trailing = nil
    }

    init<Trailing: View>(_ title: String, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.trailing = AnyView(trailing())
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .kerning(0.4)
            Spacer()
            trailing
        }
    }
}

/// Subtle divider used between popover sections.
struct SectionDivider: View {
    var body: some View {
        Divider()
            .background(Color.secondary.opacity(0.15))
            .padding(.vertical, 10)
    }
}

/// Rate-limit bar with threshold marks at 50% and 80%.
struct ThresholdProgressBar: View {
    let value: Double  // 0...100

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Track
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.secondary.opacity(0.15))
                // Fill
                RoundedRectangle(cornerRadius: 3)
                    .fill(tint)
                    .frame(width: max(0, min(1, value / 100)) * geo.size.width)
                // Threshold ticks
                tick(at: 0.50, in: geo.size)
                tick(at: 0.80, in: geo.size)
            }
        }
        .frame(height: 6)
    }

    private func tick(at ratio: CGFloat, in size: CGSize) -> some View {
        Rectangle()
            .fill(Color.primary.opacity(0.25))
            .frame(width: 1, height: size.height)
            .offset(x: ratio * size.width)
    }

    private var tint: Color {
        switch value {
        case ..<50:  return .green
        case ..<80:  return .yellow
        default:     return .red
        }
    }
}

/// Right-aligned monospaced dollars used for card lead numbers.
struct LeadAmount: View {
    let amount: Double
    let approximate: Bool

    var body: some View {
        HStack(spacing: 2) {
            Text(Fmt.dollars(amount))
                .font(.system(.body, design: .monospaced).weight(.semibold))
            if approximate {
                Text("+")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

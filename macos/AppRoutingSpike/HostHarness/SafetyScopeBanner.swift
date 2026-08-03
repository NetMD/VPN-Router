import SwiftUI

struct SafetyScopeBanner: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                phase("P0", "범위")
                connector
                phase("P1", "격리")
                connector
                phase("P2", "흐름·신원", isCurrent: true)
            }

            Label(
                "P3 WireGuard 전달과 제품 통합은 진행하지 않습니다.",
                systemImage: "hand.raised.fill"
            )
            .font(.callout.weight(.medium))
            .foregroundStyle(.orange)
        }
        .padding(14)
        .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("P0 범위, P1 격리, 현재 P2 흐름과 신원 시험. P3 전달과 제품 통합은 진행하지 않습니다.")
    }

    private var connector: some View {
        Rectangle()
            .fill(.tertiary)
            .frame(height: 1)
            .frame(maxWidth: 24)
            .accessibilityHidden(true)
    }

    private func phase(_ code: String, _ label: String, isCurrent: Bool = false) -> some View {
        HStack(spacing: 6) {
            Text(code)
                .font(.caption.monospaced().weight(.bold))
            Text(label)
                .font(.caption)
        }
        .foregroundStyle(isCurrent ? Color.accentColor : Color.secondary)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(
            isCurrent ? Color.accentColor.opacity(0.12) : Color.clear,
            in: Capsule()
        )
    }
}

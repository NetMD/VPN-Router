import SwiftUI

struct ValidationAxisSummaryView: View {
    let title: String
    let summary: ValidationAxisSummary

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .frame(width: 120, alignment: .leading)
            Text(verdictText)
                .font(.headline.monospaced())
                .foregroundStyle(verdictColor)
            Spacer()
            Text("실행 \(summary.executedCount) · 통과 \(summary.passedCount) · 실패 \(summary.failedCount)")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var verdictText: String {
        switch summary.validationVerdict {
        case .notRun: return "NOT_RUN"
        case .pass: return "PASS"
        case .fail: return "FAIL"
        case .inconclusive: return "INCONCLUSIVE"
        case .noGo: return "NO-GO"
        }
    }

    private var verdictColor: Color {
        switch summary.validationVerdict {
        case .pass: return .green
        case .fail: return .red
        case .inconclusive: return .orange
        case .notRun, .noGo: return .secondary
        }
    }
}

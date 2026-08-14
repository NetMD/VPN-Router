import SwiftUI

struct TrafficHarnessView: View {
    let role: TrafficHarnessRole

    @State private var actionInProgress = false
    @State private var tcpResult: HarnessActionResult?
    @State private var udpResult: HarnessActionResult?
    @State private var connectivityResult: HarnessActionResult?

    private let flowTrigger = LocalFlowTrigger()
    private let connectivityProbe = ControlConnectivityProbe()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(role.title)
                .font(.title.weight(.semibold))

            Text("각 버튼은 정책 적용 뒤 새 흐름을 한 번 만듭니다. 응답 성공은 이 시험의 판정 기준이 아닙니다.")
                .font(.callout)
                .foregroundStyle(.secondary)

            if role == .invalidConfiguration {
                Label("시험 앱 역할을 확인하지 못했습니다", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            } else {
                actionRow(
                    title: "새 TCP 흐름 만들기",
                    result: tcpResult,
                    action: { await runFlow(.tcp) }
                )
                actionRow(
                    title: "새 UDP 흐름 만들기",
                    result: udpResult,
                    action: { await runFlow(.udp) }
                )

                if role == .controlApp {
                    Divider()
                    actionRow(
                        title: "일반 인터넷 확인",
                        result: connectivityResult,
                        action: { await runConnectivityProbe() }
                    )
                    Text("목적지·주소·DNS 내용·응답 본문은 표시하거나 저장하지 않습니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(minWidth: 460, minHeight: 300)
    }

    private func actionRow(
        title: String,
        result: HarnessActionResult?,
        action: @escaping @MainActor () async -> Void
    ) -> some View {
        HStack {
            Button(title) {
                Task { await action() }
            }
            .disabled(actionInProgress)

            if actionInProgress {
                ProgressView()
                    .controlSize(.small)
            } else if let result {
                Label(
                    result.completed ? "요청 완료" : "요청 실패",
                    systemImage: result.completed ? "checkmark.circle.fill" : "xmark.circle.fill"
                )
                .foregroundStyle(result.completed ? .green : .red)
            } else {
                Text("실행 전")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @MainActor
    private func runFlow(_ transport: HarnessFlowTransport) async {
        actionInProgress = true
        let result = await flowTrigger.trigger(transport)
        switch transport {
        case .tcp: tcpResult = result
        case .udp: udpResult = result
        }
        actionInProgress = false
    }

    @MainActor
    private func runConnectivityProbe() async {
        actionInProgress = true
        connectivityResult = await connectivityProbe.probe()
        actionInProgress = false
    }
}

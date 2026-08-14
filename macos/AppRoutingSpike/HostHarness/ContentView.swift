import AppKit
import SwiftUI
import UniformTypeIdentifiers

public struct ContentView: View {
    @ObservedObject private var viewModel: SpikeViewModel
    @State private var baselineDNSAvailable = true
    @State private var baselineIPv4Available = true
    @State private var baselineIPv6Available = false
    @State private var cleanupDNSAvailable = true
    @State private var cleanupIPv4Available = true
    @State private var cleanupIPv6Available = false
    @State private var controlInternetReachable = false
    @State private var controlPlaneRecursionFree = false

    public init(viewModel: SpikeViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("앱 라우팅 기술 시험")
                    .font(.largeTitle.weight(.semibold))

                SafetyScopeBanner()
                validationSummary
                readinessControls
                runControls
                cleanupControls

                if let error = viewModel.displayState.userFacingError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .accessibilityLabel("오류: \(error)")
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 680, minHeight: 680)
        .onDisappear {
            Task { await viewModel.shutdown() }
        }
    }

    private var validationSummary: some View {
        GroupBox("검증 판정") {
            VStack(alignment: .leading, spacing: 12) {
                Label(viewModel.displayState.statusText, systemImage: statusSymbol)
                Text(viewModel.displayState.resultCountText)
                    .foregroundStyle(.secondary)

                ValidationAxisSummaryView(
                    title: "자동 검사",
                    summary: viewModel.displayState.automatedSummary
                )
                ValidationAxisSummaryView(
                    title: "실제 서명 Mac",
                    summary: viewModel.displayState.signedMacSummary
                )
                ValidationAxisSummaryView(
                    title: "P3·제품 통합",
                    summary: viewModel.displayState.p3ProductIntegrationSummary
                )

                Text("P2는 흐름 수신과 앱 신원, 안전한 닫힘을 확인합니다. WireGuard 전달은 수행하지 않습니다.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }

    private var readinessControls: some View {
        GroupBox("실제 서명 시험 준비") {
            VStack(alignment: .leading, spacing: 14) {
                Text("권한·프로비저닝 확인이 필요합니다")
                    .font(.headline)

                evidencePicker(
                    "개발 팀 권한",
                    selection: Binding(
                        get: { viewModel.displayState.entitlementEvidenceState },
                        set: { viewModel.setEntitlementEvidenceState($0) }
                    )
                )

                provisioningPicker

                HStack {
                    Button("시스템 확장 설치 요청") {
                        Task { await viewModel.requestInstallation() }
                    }
                    .disabled(!viewModel.displayState.canRequestInstallation)

                    Text(activationText)
                        .foregroundStyle(.secondary)
                }

                Divider()

                HStack {
                    Button("시험 앱 지정") {
                        Task { await viewModel.selectTestApp() }
                    }
                    .disabled(!viewModel.displayState.canSelectTestApp)

                    if viewModel.displayState.hasSelectedTestApp {
                        Label("서명된 시험 앱 준비됨", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Text("시험 앱을 지정해 주세요")
                            .foregroundStyle(.secondary)
                    }
                }

                Toggle(
                    "가려진 시험 fixture를 준비했습니다",
                    isOn: Binding(
                        get: { viewModel.displayState.hasSanitizedFixture },
                        set: { viewModel.setSanitizedFixtureReady($0) }
                    )
                )
                .disabled(!viewModel.displayState.canSelectTestApp)

                baselineControls
            }
            .padding(.vertical, 4)
        }
    }

    private var provisioningPicker: some View {
        HStack {
            Text("이 Mac용 프로비저닝")
            Spacer()
            Picker(
                "이 Mac용 프로비저닝",
                selection: Binding(
                    get: { viewModel.displayState.provisioningEvidenceState },
                    set: { viewModel.setProvisioningEvidenceState($0) }
                )
            ) {
                Text("미제공").tag(ProvisioningEvidenceState.notProvided)
                Text("확인됨").tag(ProvisioningEvidenceState.confirmed)
                Text("거절됨").tag(ProvisioningEvidenceState.declined)
            }
            .labelsHidden()
            .frame(width: 140)
            .disabled(viewModel.displayState.isBusy)
        }
    }

    private var baselineControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("설치 전 네트워크 기준선")
                .font(.headline)
            Text("주소나 DNS 내용은 기록하지 않고 가용 여부만 입력합니다.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Toggle("DNS 사용 가능", isOn: $baselineDNSAvailable)
            Toggle("IPv4 사용 가능", isOn: $baselineIPv4Available)
            Toggle("IPv6 사용 가능", isOn: $baselineIPv6Available)
            Button("기준선 확정") {
                viewModel.captureBaseline(
                    dnsAvailable: baselineDNSAvailable,
                    ipv4Available: baselineIPv4Available,
                    ipv6Available: baselineIPv6Available
                )
            }
            .disabled(viewModel.displayState.isBusy)

            if viewModel.displayState.baselineState == .captured {
                Label("기준선 확인됨", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
    }

    private var runControls: some View {
        HStack {
            Button("시험 시작") {
                Task { await viewModel.start() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.displayState.canStart)

            Button("시험 중단", role: .destructive) {
                Task { await viewModel.stop() }
            }
            .disabled(!viewModel.displayState.canStop)

            Button("가려진 결과 내보내기") {
                presentExportPanel()
            }
            .disabled(!viewModel.displayState.canExport)
        }
    }

    @ViewBuilder
    private var cleanupControls: some View {
        if viewModel.displayState.lifecycle == .awaitingControlVerification {
            GroupBox("중단 뒤 네트워크 회복 확인") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("DNS·IPv4·IPv6 회복 확인이 필요합니다")
                        .font(.headline)
                    Text("현재 가용 여부를 설치 전 기준선과 비교합니다. 시작부터 IPv6가 없었다면 그대로 선택하지 않습니다.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Toggle("DNS 사용 가능", isOn: $cleanupDNSAvailable)
                    Toggle("IPv4 사용 가능", isOn: $cleanupIPv4Available)
                    Toggle("IPv6 사용 가능", isOn: $cleanupIPv6Available)
                    Toggle("통제 앱 일반 인터넷 확인", isOn: $controlInternetReachable)
                    Toggle("제어 경로 재귀 0건 확인", isOn: $controlPlaneRecursionFree)
                    Button("회복 비교 완료") {
                        viewModel.completeCleanupComparison(
                            dnsAvailable: cleanupDNSAvailable,
                            ipv4Available: cleanupIPv4Available,
                            ipv6Available: cleanupIPv6Available,
                            controlInternetReachable: controlInternetReachable,
                            controlPlaneRecursionCount: controlPlaneRecursionFree ? 0 : 1
                        )
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.vertical, 4)
            }
        } else if viewModel.displayState.cleanupPhase != .idle {
            Text(cleanupStatusText)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private func evidencePicker(
        _ title: String,
        selection: Binding<EntitlementEvidenceState>
    ) -> some View {
        HStack {
            Text(title)
            Spacer()
            Picker(title, selection: selection) {
                Text("미제공").tag(EntitlementEvidenceState.notProvided)
                Text("확인됨").tag(EntitlementEvidenceState.confirmed)
                Text("거절됨").tag(EntitlementEvidenceState.declined)
            }
            .labelsHidden()
            .frame(width: 140)
            .disabled(viewModel.displayState.isBusy)
        }
    }

    private var activationText: String {
        switch viewModel.displayState.activationEvidenceState {
        case .notObserved:
            return "실제 서명 시험을 시작하지 않았습니다"
        case .confirmed:
            return "시스템 확장 활성화 확인됨"
        case .rebootRequired:
            return "재부팅 뒤 활성화 확인이 필요합니다"
        case .failed:
            return "시스템 확장 활성화를 확인하지 못했습니다"
        }
    }

    private var cleanupStatusText: String {
        switch viewModel.displayState.cleanupPhase {
        case .idle, .running:
            return "시험 실행 상태입니다"
        case .rejectingNewFlows, .providerStopRequested, .providerStopped,
             .ownedManagersRemoved, .managerCountVerifiedZero:
            return "VPN Router 소유 설정을 정리하는 중"
        case .dnsCompared, .ipv4Compared, .ipv6Compared:
            return "DNS·IPv4·IPv6 회복을 확인하는 중"
        case .complete:
            return "네트워크 회복을 확인했습니다"
        case .failed:
            return "시험 상태 정리를 확인하지 못했습니다"
        }
    }

    private var statusSymbol: String {
        switch viewModel.displayState.lifecycle {
        case .running:
            return "eye.circle.fill"
        case .awaitingApproval, .stopping, .awaitingControlVerification:
            return "clock"
        case .stopped, .stoppedWithError, .cleanupFailed:
            return "stop.circle"
        case .notReady, .ready, .configurationInvalid:
            return "wrench.and.screwdriver"
        }
    }

    private func presentExportPanel() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "app-routing-spike-redacted.json"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let destination = panel.url else {
            return
        }
        viewModel.export(to: destination)
    }
}

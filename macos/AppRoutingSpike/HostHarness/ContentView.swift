import AppKit
import SwiftUI
import UniformTypeIdentifiers

public struct ContentView: View {
    @ObservedObject private var viewModel: SpikeViewModel
    @State private var controlDNSAvailable = false
    @State private var controlIPv4Available = false
    @State private var controlIPv6Available = false

    public init(viewModel: SpikeViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("앱 라우팅 기술 시험")
                .font(.largeTitle.weight(.semibold))

            SafetyScopeBanner()

            GroupBox("시험 상태") {
                VStack(alignment: .leading, spacing: 8) {
                    Label(viewModel.displayState.statusText, systemImage: statusSymbol)
                    Text(viewModel.displayState.resultCountText)
                        .foregroundStyle(.secondary)
                    Text("P2는 흐름 수신과 앱 신원만 확인합니다. WireGuard 전달은 수행하지 않습니다.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }

            GroupBox("수동 준비") {
                VStack(alignment: .leading, spacing: 12) {
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

                    HStack {
                        Button("시스템 확장 설치 요청") {
                            Task { await viewModel.requestInstallation() }
                        }
                        .disabled(!viewModel.displayState.canRequestInstallation)

                        if viewModel.displayState.hasSignedEntitlement {
                            Label("필요한 권한 확인됨", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                    }
                }
                .padding(.vertical, 4)
            }

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

            if viewModel.displayState.lifecycle == .awaitingControlVerification {
                GroupBox("중단 뒤 통제 인터넷 확인") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("실제 Mac에서 통제 앱을 사용해 세 항목을 직접 확인해 주세요.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Toggle("DNS 정상", isOn: $controlDNSAvailable)
                        Toggle("IPv4 일반 인터넷 정상", isOn: $controlIPv4Available)
                        Toggle("IPv6 일반 인터넷 정상", isOn: $controlIPv6Available)
                        Button("통제 인터넷 확인 완료") {
                            viewModel.completeControlConnectivityVerification(
                                dnsAvailable: controlDNSAvailable,
                                ipv4Available: controlIPv4Available,
                                ipv6Available: controlIPv6Available
                            )
                            controlDNSAvailable = false
                            controlIPv4Available = false
                            controlIPv6Available = false
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(.vertical, 4)
                }
            }

            if let error = viewModel.displayState.userFacingError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .accessibilityLabel("오류: \(error)")
            }

            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(minWidth: 620, minHeight: 460)
        .onDisappear {
            Task { await viewModel.shutdown() }
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

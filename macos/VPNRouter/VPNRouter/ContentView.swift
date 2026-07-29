import SwiftUI
import NetworkExtension
import UniformTypeIdentifiers
import AppKit

struct ContentView: View {
    @StateObject private var dnsProxySystemExtensionController = DNSProxySystemExtensionController()
    @StateObject private var dnsProxyConfigurationController = DNSProxyConfigurationController()
    @StateObject private var connectionCoordinator = ConsumerConnectionCoordinator()
    @StateObject private var lifecycleMonitor = LifecycleMonitor()
    @State private var selectedSection: SidebarSection = .home
    @State private var status: NEVPNStatus = .invalid
    @State private var lastMessage = "설치된 VPN 구성이 없습니다."
    @State private var manager: NETunnelProviderManager?
    @State private var statusObserver: NSObjectProtocol?
    @State private var profiles: [ProfileMetadata] = []
    @State private var profileName = ""
    @State private var selectedConfigFileName = "선택한 파일 없음"
    @State private var isImportingConfigFile = false
    @State private var importMessage = "가져온 VPN 프로필이 없습니다."
    @State private var selectedProfileId: ProfileMetadata.ID?
    @State private var profileRenameText = ""
    @State private var profilePendingDeletion: ProfileMetadata?
    @State private var isShowingConfigurationRemovalConfirmation = false
    @State private var siteDomainInput = ""
    @State private var siteDomains: [String] = []
    @State private var siteMessage = "VPN 프로필을 선택하고 VPN으로 보낼 사이트를 추가하세요."
    @State private var routePlan: DomainRoutePlan?
    @State private var routePlanProfileId: ProfileMetadata.ID?
    @State private var dnsProxyProbeMessage = "DNS Proxy 권한과 preferences 접근 여부를 아직 확인하지 않았습니다."
    @State private var isRunningDNSProxyProbe = false
    @State private var isShowingDNSProxyEnableConfirmation = false
    @State private var isShowingDNSProxyEmergencyDisableConfirmation = false
    @State private var isShowingConsumerConnectionConfirmation = false
    @State private var dnsProxyObservationMessage = "이번 진단 실행에서 확인한 대상 DNS 관찰이 없습니다."
    @State private var encryptedDNSPreflightMessage = "DNS Proxy 활성화 전에 브라우저 보안 DNS와 Private Relay 확인이 필요합니다."
    @State private var diagnosticExportMessage = "진단 파일에는 상태와 개수만 포함되며, 개인 키·설정 원문·도메인·IP 주소는 포함되지 않습니다."
    @State private var troubleshootingReportDocument: TroubleshootingReportDocument?
    @State private var troubleshootingReportFilename = "VPNRouter-Diagnostics"
    @State private var isExportingTroubleshootingReport = false
    @State private var activeOperation: AppOperation?
    @AppStorage(AppAppearance.storageKey)
    private var appAppearanceRawValue = AppAppearance.automatic.rawValue
    @FocusState private var focusedField: FocusedField?
#if DEBUG
    @State private var developerDiagnosticsEnabled = false
#endif

    var body: some View {
        dialogContent
    }

    private var lifecycleContent: some View {
        navigationContent
        .task {
            await initializeContent()
        }
        .task(
            id: ConsumerRouteRefreshKey(
                tunnelStatus: status,
                consumerConnectionReady: connectionCoordinator.state.isReady
            )
        ) {
            await runConnectedRouteRefreshLoop()
        }
        .task(
            id: DNSProxyDynamicRefreshKey(
                tunnelStatus: status,
                dnsProxyEnabled: dnsProxyConfigurationController.isEnabled,
                consumerConnectionReady: connectionCoordinator.state.isReady
            )
        ) {
            await runDNSProxyDynamicRouteRefreshLoop()
        }
        .task(
            id: DNSProxyOwnershipMonitorKey(
                tunnelStatus: status,
                dnsProxyEnabled: dnsProxyConfigurationController.isEnabled,
                consumerConnectionReady: connectionCoordinator.state.isReady
            )
        ) {
            await runDNSProxyOwnershipMonitor()
        }
        .onChange(of: selectedProfileId) { _, _ in
            profileRenameText = selectedProfile?.displayName ?? ""
            Task {
                await loadSiteDomainsForSelectedProfile()
            }
        }
        .onChange(of: status) { _, newStatus in
            announceForVoiceOver("VPN 상태: \(statusText)")
            if newStatus == .disconnected,
               dnsProxyConfigurationController.isEnabled {
                Task {
                    await disableOrphanedDNSProxy()
                }
            }
        }
        .onChange(of: lifecycleMonitor.wakeCount) { _, _ in
            Task {
                await loadStatus()
            }
        }
        .onDisappear {
            removeStatusObserver()
        }
        .fileImporter(
            isPresented: $isImportingConfigFile,
            allowedContentTypes: supportedWireGuardConfigTypes,
            allowsMultipleSelection: false,
            onCompletion: importConfigFile
        )
        .fileExporter(
            isPresented: $isExportingTroubleshootingReport,
            document: troubleshootingReportDocument,
            contentType: .json,
            defaultFilename: troubleshootingReportFilename,
            onCompletion: finishTroubleshootingExport
        )
    }

    private var dialogContent: some View {
        lifecycleContent
        .confirmationDialog(
            "VPN 프로필 삭제",
            isPresented: profileDeletionPresented,
            presenting: profilePendingDeletion
        ) { profile in
            Button("\(profile.displayName) 삭제", role: .destructive) {
                Task {
                    await performOperation(.deletingProfile) {
                        await deleteProfile(profile)
                    }
                }
            }
            Button("취소", role: .cancel) {
                profilePendingDeletion = nil
            }
        } message: { profile in
            Text("이 Mac에서 프로필 정보와 키체인 개인 키를 삭제합니다. VPN 사이트 목록은 유지됩니다.")
        }
        .confirmationDialog(
            "설치된 VPN Router 구성을 제거할까요?",
            isPresented: $isShowingConfigurationRemovalConfirmation
        ) {
            Button("VPN Router 구성 제거", role: .destructive) {
                Task {
                    await performOperation(.removingConfiguration) {
                        await removeVPNRouterConfigurations()
                    }
                }
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("VPN Router가 소유한 macOS VPN 구성만 제거합니다. 저장된 프로필, 키체인 개인 키, 사이트 목록과 다른 앱의 구성은 변경하지 않습니다.")
        }
        .confirmationDialog(
            "DNS 보호 전제조건을 확인했나요?",
            isPresented: $isShowingConsumerConnectionConfirmation
        ) {
            Button("확인하고 연결") {
                Task {
                    await performOperation(.connecting) {
                        await startTunnel(manualPreconditionsConfirmed: true)
                    }
                }
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("정책이 없는 브라우저의 보안 DNS와 현재 네트워크의 ‘IP 주소 추적 제한’을 직접 확인하세요. VPN Router는 이 설정이나 다른 보안·VPN 제품을 변경하지 않습니다.")
        }
        .confirmationDialog(
            "DNS Proxy 진단을 활성화할까요?",
            isPresented: $isShowingDNSProxyEnableConfirmation
        ) {
            Button("진단용 DNS Proxy 활성화") {
                Task {
                    guard status == .connected else {
                        dnsProxyObservationMessage = "DNS Proxy를 활성화하려면 먼저 Packet Tunnel에 연결하세요."
                        return
                    }
                    let preflight = EncryptedDNSPreflightService().evaluate()
                    encryptedDNSPreflightMessage = EncryptedDNSPreflightService()
                        .message(for: preflight)
                    guard preflight.allowsDNSProxyActivation else {
                        dnsProxyObservationMessage = "암호화 DNS 충돌 사전점검에서 활성화를 중단했습니다."
                        return
                    }
                    await dnsProxyConfigurationController.enableForDiagnostics(
                        expectedBundleIdentifier: TunnelIdentifiers.dnsProxySystemExtensionBundleIdentifier
                    )
                    guard dnsProxyConfigurationController.isEnabled else {
                        return
                    }
                    do {
                        try await DNSProxyObservationSettingsStore()
                            .configureForDiagnosticRun(domains: siteDomains)
                        dnsProxyObservationMessage = "XPC로 대상 도메인을 설정했습니다. 대상 사이트에서 새 DNS 요청을 발생시키세요."
                    } catch {
                        await failSafeForDNSProxyLoss(
                            reason: "DNS Proxy 초기 XPC 설정을 준비하지 못했습니다: \(error.localizedDescription)"
                        )
                    }
                }
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("DNS 요청 전달을 시작합니다. Private Relay의 ‘IP 주소 추적 제한’과 정책이 없는 브라우저의 보안 DNS는 직접 확인하세요. VPN Router는 제3자 제품을 자동으로 끄거나 변경하지 않습니다.")
        }
        .confirmationDialog(
            "DNS Proxy를 즉시 끌까요?",
            isPresented: $isShowingDNSProxyEmergencyDisableConfirmation
        ) {
            Button("즉시 끄기", role: .destructive) {
                Task {
                    await disableDNSProxyForDiagnostics(
                        allowOwnedRemovalFallback: true
                    )
                }
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("먼저 VPN Router 구성을 비활성화합니다. 저장이 실패할 때만 VPN Router가 소유한 DNS Proxy 구성을 제거합니다. 다른 제품의 구성은 변경하지 않습니다.")
        }
    }

    private var navigationContent: some View {
        NavigationSplitView {
            List(selection: $selectedSection) {
                ForEach(SidebarSection.allCases) { section in
                    NavigationLink(value: section) {
                        Label(section.title, systemImage: section.systemImage)
                    }
                }
            }
            .navigationTitle("VPN Router")
            .navigationSplitViewColumnWidth(min: 180, ideal: 210)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let activeOperation {
                        HStack(spacing: 10) {
                            ProgressView()
                                .controlSize(.small)
                            Text(activeOperation.progressLabel)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(activeOperation.accessibilityLabel)
                    }

                    detailView
                }
                .frame(maxWidth: 960, alignment: .topLeading)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .contentMargins(32)
            .background(Color(nsColor: .windowBackgroundColor))
            .frame(minWidth: 440, minHeight: 420, alignment: .topLeading)
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch selectedSection {
        case .home:
            homeView
        case .profiles:
            profilesView
        case .sites:
            sitesView
        case .diagnostics:
            diagnosticsView
        case .settings:
            settingsView
        }
    }

    private var homeView: some View {
        VStack(alignment: .leading, spacing: 24) {
            header(
                title: "홈",
                subtitle: "선택한 사이트만 VPN으로 안전하게 연결합니다."
            )
            if connectionCoordinator.state.stage == .activatingDNSProxyExtension {
                Label(
                    dnsProxySystemExtensionController.message,
                    systemImage: "checkmark.shield"
                )
                .font(.callout)
                .foregroundStyle(.secondary)
                .accessibilityLabel(
                    "DNS Proxy 시스템 확장 준비 상태. \(dnsProxySystemExtensionController.message)"
                )
            }

            connectionOverviewCard
            ipv6BypassWarning

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    homeProfileCard
                    homeRecentStatusCard
                }
                VStack(alignment: .leading, spacing: 16) {
                    homeProfileCard
                    homeRecentStatusCard
                }
            }
            Spacer()
        }
    }

    private var connectionOverviewCard: some View {
        ProductCard {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 32) {
                    primaryConnectionButton
                    connectionOverviewDetails
                }
                VStack(alignment: .leading, spacing: 24) {
                    primaryConnectionButton
                        .frame(maxWidth: .infinity)
                    connectionOverviewDetails
                }
            }
        }
    }

    private var primaryConnectionButton: some View {
        Button {
            Task {
                if canStop {
                    await performOperation(.disconnecting) {
                        await stopTunnel()
                    }
                } else {
                    await requestConsumerConnection()
                }
            }
        } label: {
            VStack(spacing: 10) {
                Image(systemName: connectionButtonSymbol)
                    .font(.system(size: 38, weight: .semibold))
                Text(connectionButtonTitle)
                    .font(.headline)
            }
            .foregroundStyle(.white)
            .frame(width: 148, height: 148)
            .background(connectionButtonColor, in: Circle())
            .overlay {
                Circle()
                    .stroke(.white.opacity(0.35), lineWidth: 1)
                    .padding(7)
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!canStart && !canStop)
        .keyboardShortcut(.return, modifiers: .command)
        .accessibilityLabel(connectionButtonTitle)
        .accessibilityHint(
            canStop
                ? "현재 VPN 연결을 안전하게 해제합니다."
                : "선택한 프로필과 사이트 경로로 VPN 연결을 시작합니다."
        )
    }

    private var connectionOverviewDetails: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(statusText, systemImage: connectionStatusSymbol)
                .font(.title2.weight(.semibold))
                .foregroundStyle(connectionStatusColor)

            Text(connectionStatusDescription)
                .font(.callout)
                .foregroundStyle(.secondary)

            Divider()

            LabeledContent(
                "VPN 프로필",
                value: selectedProfile?.displayName ?? "선택되지 않음"
            )
            LabeledContent("VPN 사이트", value: "\(siteDomains.count)개")
            LabeledContent(
                "보호 경로",
                value: routePlan.map { "\($0.includedRoutes.count)개" } ?? "준비되지 않음"
            )

            Button {
                Task {
                    await performOperation(.buildingRoutes) {
                        await validateConnectionReadiness()
                    }
                }
            } label: {
                Label("연결 준비 확인", systemImage: "checkmark.circle")
            }
            .disabled(
                selectedProfile == nil
                    || siteDomains.isEmpty
                    || activeOperation != nil
                    || canStop
            )
            .accessibilityHint("선택한 프로필과 사이트로 연결 가능한 IPv4 경로 계획을 확인합니다.")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var homeProfileCard: some View {
        ProductCard(title: "선택한 VPN 프로필", systemImage: "doc.text") {
            if let selectedProfile {
                ProfileRow(profile: selectedProfile)
                Button("VPN 프로필 관리") {
                    selectedSection = .profiles
                }
            } else {
                Text("가져온 프로필을 선택하면 연결할 수 있습니다.")
                    .foregroundStyle(.secondary)
                Button("VPN 프로필 가져오기") {
                    selectedSection = .profiles
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var homeRecentStatusCard: some View {
        ProductCard(title: "최근 상태", systemImage: "clock.arrow.circlepath") {
            DiagnosticMessageView(message: lastMessage)
            Button("문제 해결 열기") {
                selectedSection = .diagnostics
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var profilesView: some View {
        VStack(alignment: .leading, spacing: 24) {
            header(
                title: "VPN 프로필",
                subtitle: "WireGuard 프로필을 가져오고 연결 대상을 선택합니다."
            )

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    ProductCard(title: "프로필 가져오기", systemImage: "square.and.arrow.down") {
                        profileImportPanel
                    }
                    .frame(minWidth: 320, idealWidth: 400, maxWidth: 520)

                    ProductCard(title: "저장된 프로필", systemImage: "doc.on.doc") {
                        storedProfilesPanel
                    }
                    .frame(minWidth: 260, maxWidth: .infinity)
                }

                VStack(alignment: .leading, spacing: 16) {
                    ProductCard(title: "프로필 가져오기", systemImage: "square.and.arrow.down") {
                        profileImportPanel
                    }
                    ProductCard(title: "저장된 프로필", systemImage: "doc.on.doc") {
                        storedProfilesPanel
                    }
                }
            }
        }
    }

    private var profileImportPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            TextField("프로필 이름", text: $profileName)
                .textFieldStyle(.roundedBorder)
                .focused($focusedField, equals: .profileName)
                .accessibilityLabel("VPN 프로필 이름")
                .accessibilityHint("비워 두면 선택한 파일 이름을 사용합니다.")

            HStack(spacing: 12) {
                Image(systemName: "doc.badge.plus")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 4) {
                    Text(selectedConfigFileName)
                        .font(.headline)
                        .lineLimit(1)
                    Text("WireGuard .conf 파일을 선택하세요. 개인 키는 키체인에 저장됩니다.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(.quaternary)
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    profileImportButtons
                }
                VStack(alignment: .leading, spacing: 8) {
                    profileImportButtons
                }
            }

            Text(importMessage)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var profileImportButtons: some View {
        Button {
            isImportingConfigFile = true
        } label: {
            Label("파일 가져오기", systemImage: "folder")
        }
        .buttonStyle(.borderedProminent)
        .disabled(activeOperation != nil)
        .keyboardShortcut("o", modifiers: .command)

        Button {
            selectedConfigFileName = "선택한 파일 없음"
            profileName = ""
        } label: {
            Label("입력 지우기", systemImage: "xmark.circle")
        }
        .disabled(selectedConfigFileName == "선택한 파일 없음" && profileName.isEmpty)
    }

    private var storedProfilesPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            if profiles.isEmpty {
                ContentUnavailableView("저장된 프로필 없음", systemImage: "doc.text.magnifyingglass")
                    .frame(minHeight: 160)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(profiles) { profile in
                        HStack(spacing: 12) {
                            Button {
                                selectedProfileId = profile.id
                            } label: {
                                ProfileRow(profile: profile)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(profile.displayName) 프로필")
                            .accessibilityValue(
                                selectedProfileId == profile.id ? "선택됨" : "선택되지 않음"
                            )
                            .accessibilityHint("이 프로필을 연결 대상으로 선택합니다.")
                            Spacer()
                            Button(role: .destructive) {
                                profilePendingDeletion = profile
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("\(profile.displayName) 프로필 삭제")
                            .accessibilityHint("확인 후 프로필 정보와 키체인 개인 키를 삭제합니다.")
                            .help("\(profile.displayName) 삭제")
                        }
                        .padding(10)
                        .background(
                            selectedProfileId == profile.id
                                ? Color.accentColor.opacity(0.12)
                                : Color.clear,
                            in: RoundedRectangle(cornerRadius: 8)
                        )
                    }
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        profileManagementButtons
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        profileManagementButtons
                    }
                }

                Divider()

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        profileRenameField
                        renameProfileButton
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        profileRenameField
                        renameProfileButton
                    }
                }
            }
        }
    }

    private var profileRenameField: some View {
        TextField("새 프로필 이름", text: $profileRenameText)
            .textFieldStyle(.roundedBorder)
            .focused($focusedField, equals: .profileRename)
            .onSubmit {
                Task {
                    await renameSelectedProfile()
                }
            }
            .accessibilityLabel("선택한 VPN 프로필의 새 이름")
    }

    private var renameProfileButton: some View {
        Button {
            Task {
                await renameSelectedProfile()
            }
        } label: {
            Label("이름 변경", systemImage: "pencil")
        }
        .disabled(
            selectedProfile == nil
                || normalizedProfileRenameText == nil
                || normalizedProfileRenameText == selectedProfile?.displayName
                || activeOperation != nil
                || canStop
        )
        .accessibilityHint("VPN 연결이 끊어진 상태에서 선택한 프로필의 표시 이름을 바꿉니다.")
    }

    @ViewBuilder
    private var profileManagementButtons: some View {
        Button {
            Task {
                await performOperation(.installingProfile) {
                    await installSelectedProfileConfiguration()
                }
            }
        } label: {
            Label("선택한 프로필 설치", systemImage: "arrow.down.doc")
        }
        .buttonStyle(.borderedProminent)
        .disabled(selectedProfile == nil || activeOperation != nil)

        Button(role: .destructive) {
            if let selectedProfile {
                profilePendingDeletion = selectedProfile
            }
        } label: {
            Label("선택한 프로필 삭제", systemImage: "trash")
        }
        .disabled(selectedProfile == nil || activeOperation != nil)
    }

    private var sitesView: some View {
        VStack(alignment: .leading, spacing: 24) {
            header(
                title: "VPN 사이트",
                subtitle: selectedProfile.map { "\($0.displayName) 프로필로 보낼 사이트를 관리합니다." }
                    ?? "연결할 프로필에 공통으로 적용되는 사이트를 관리합니다."
            )

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    ProductCard(title: "사이트 목록", systemImage: "globe") {
                        siteEditorPanel
                    }
                    .frame(minWidth: 320, idealWidth: 400, maxWidth: 520)

                    ProductCard(title: "경로 계획", systemImage: "point.3.connected.trianglepath.dotted") {
                        routePlanPanel
                    }
                    .frame(minWidth: 260, maxWidth: .infinity)
                }

                VStack(alignment: .leading, spacing: 16) {
                    ProductCard(title: "사이트 목록", systemImage: "globe") {
                        siteEditorPanel
                    }
                    ProductCard(title: "경로 계획", systemImage: "point.3.connected.trianglepath.dotted") {
                        routePlanPanel
                    }
                }
            }
        }
    }

    private var siteEditorPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    siteInputField
                    addSiteButton
                }
                VStack(alignment: .leading, spacing: 8) {
                    siteInputField
                    addSiteButton
                }
            }

            if siteDomains.isEmpty {
                ContentUnavailableView("등록된 사이트 없음", systemImage: "globe.badge.chevron.backward")
                    .frame(minHeight: 160)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(siteDomains, id: \.self) { domain in
                        HStack(spacing: 8) {
                            Text(domain)
                                .font(.system(.body, design: .monospaced))
                            Spacer()
                            Button {
                                removeSiteDomain(domain)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("\(domain) 사이트 삭제")
                            .accessibilityHint("VPN으로 보낼 사이트 목록에서 제거합니다.")
                            .help("\(domain) 삭제")
                        }
                        .padding(.vertical, 6)
                    }
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    siteManagementButtons
                }
                VStack(alignment: .leading, spacing: 8) {
                    siteManagementButtons
                }
            }

            Text(siteMessage)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var siteInputField: some View {
        TextField("example.com", text: $siteDomainInput)
            .textFieldStyle(.roundedBorder)
            .onSubmit(addSiteDomain)
            .focused($focusedField, equals: .siteDomain)
            .accessibilityLabel("VPN으로 보낼 사이트")
            .accessibilityHint("example.com 형식으로 입력하고 Return을 누르세요.")
    }

    private var addSiteButton: some View {
        Button {
            addSiteDomain()
        } label: {
            Label("사이트 추가", systemImage: "plus")
        }
        .buttonStyle(.borderedProminent)
        .disabled(normalizedSiteDomainInput == nil)
        .keyboardShortcut(.return, modifiers: [])
    }

    @ViewBuilder
    private var siteManagementButtons: some View {
        Button {
            Task {
                await performOperation(.buildingRoutes) {
                    await saveDomainsAndBuildRoutePlan()
                }
            }
        } label: {
            Label("경로 만들기", systemImage: "point.3.connected.trianglepath.dotted")
        }
        .buttonStyle(.borderedProminent)
        .disabled(selectedProfile == nil || siteDomains.isEmpty || activeOperation != nil)

        Button {
            siteDomains.removeAll()
            routePlan = nil
            routePlanProfileId = nil
            siteMessage = "입력 중인 사이트 목록을 지웠습니다."
        } label: {
            Label("목록 지우기", systemImage: "xmark.circle")
        }
        .disabled(siteDomains.isEmpty)
    }

    private var routePlanPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let routePlan, routePlanProfileId == selectedProfile?.id {
                RoutePlanSummary(plan: routePlan)
            } else {
                ContentUnavailableView("만든 경로 없음", systemImage: "map")
                    .frame(minHeight: 160)
            }
        }
    }

    private var diagnosticsView: some View {
        VStack(alignment: .leading, spacing: 24) {
                header(
                    title: "문제 해결",
                    subtitle: "연결 상태를 확인하고 안전한 복구 작업을 실행합니다."
                )

                ProductCard(title: "연결 및 경로 상태", systemImage: "waveform.path.ecg") {
                    Label(statusText, systemImage: connectionStatusSymbol)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(connectionStatusColor)

                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) {
                            diagnosticTunnelControls
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            diagnosticTunnelControls
                        }
                    }

                    DiagnosticMessageView(message: lastMessage)
                }
                ipv6BypassWarning

                ProductCard(title: "Mac 및 네트워크 상태", systemImage: "network") {
                    LabeledContent("기본 네트워크", value: lifecycleMonitor.networkState)
                    LabeledContent("네트워크 변경", value: "\(lifecycleMonitor.networkChangeCount)회")
                    LabeledContent(
                        "잠자기 / 깨우기",
                        value: "\(lifecycleMonitor.sleepCount)회 / \(lifecycleMonitor.wakeCount)회"
                    )
                    DiagnosticMessageView(message: lifecycleMonitor.latestEvent)
                    Text("이 정보는 읽기 전용입니다. VPN Router는 다른 VPN이나 보안 제품을 자동으로 변경하지 않습니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ProductCard(title: "진단 파일 및 복구", systemImage: "wrench.and.screwdriver") {
                    Text("지원 요청에 첨부할 수 있는 JSON 파일을 저장합니다. 개인 키, WireGuard 설정 원문, 사이트 이름, IP 주소와 DNS 내용은 제외합니다.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Button {
                        prepareTroubleshootingExport()
                    } label: {
                        Label("진단 파일 저장", systemImage: "square.and.arrow.down")
                    }
                    .disabled(activeOperation != nil || isExportingTroubleshootingReport)
                    DiagnosticMessageView(message: diagnosticExportMessage)

                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) {
                            recoveryButtons
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            recoveryButtons
                        }
                    }
                }
                #if DEBUG
                if developerDiagnosticsEnabled {
                    Divider()
                    VStack(alignment: .leading, spacing: 10) {
                    Text("개발자용 DNS Proxy 실험")
                        .font(.headline)
                    Text("지원되는 소비자 기능이 아닙니다. DNS 설정을 저장하지 않고 현재 서명 빌드의 preferences 읽기 권한부터 확인합니다.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Button {
                        Task {
                            await runDNSProxyCapabilityProbe()
                        }
                    } label: {
                        Label(
                            isRunningDNSProxyProbe ? "확인 중" : "DNS Proxy 권한 확인",
                            systemImage: "network.badge.shield.half.filled"
                        )
                    }
                    .disabled(isRunningDNSProxyProbe)
                    DiagnosticMessageView(message: dnsProxyProbeMessage)

                    Divider()

                    Text("System Extension 활성화")
                        .font(.headline)
                    Text("확장만 설치·활성화합니다. DNS Proxy preferences를 저장하거나 DNS 트래픽 가로채기를 켜지 않습니다.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Button {
                        dnsProxySystemExtensionController.requestActivation()
                    } label: {
                        Label(
                            dnsProxySystemExtensionController.isRequestInFlight ? "활성화 요청 중" : "DNS Proxy System Extension 활성화",
                            systemImage: "puzzlepiece.extension"
                        )
                    }
                    .disabled(dnsProxySystemExtensionController.isRequestInFlight)
                    DiagnosticMessageView(message: dnsProxySystemExtensionController.message)

                    Divider()

                    Text("DNS Proxy 전달 진단")
                        .font(.headline)
                    Text("저장된 VPN 사이트 \(siteDomains.count)개를 대상으로만 A 레코드와 TTL을 관찰합니다. 실제 DNS 요청을 전달하므로 signed 빌드에서만 사용하세요.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) {
                            dnsProxyDiagnosticControls
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            dnsProxyDiagnosticControls
                        }
                    }
                    DiagnosticMessageView(message: dnsProxyConfigurationController.message)
                    DiagnosticMessageView(message: encryptedDNSPreflightMessage)
                    DiagnosticMessageView(message: dnsProxyObservationMessage)
                    }
                }
                #endif
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var dnsProxyDiagnosticControls: some View {
        Button {
            let service = EncryptedDNSPreflightService()
            let preflight = service.evaluate()
            encryptedDNSPreflightMessage = service.message(for: preflight)
            if preflight.allowsDNSProxyActivation {
                isShowingDNSProxyEnableConfirmation = true
            } else {
                dnsProxyObservationMessage = "암호화 DNS 충돌 사전점검에서 활성화를 중단했습니다."
            }
        } label: {
            Label(
                dnsProxyConfigurationController.isRequestInFlight
                    ? "처리 중"
                    : "진단용 DNS Proxy 활성화",
                systemImage: "network"
            )
        }
        .buttonStyle(.borderedProminent)
        .disabled(
            dnsProxyConfigurationController.isRequestInFlight
                || dnsProxyConfigurationController.isEnabled
                || siteDomains.isEmpty
                || status != .connected
        )

        Button(role: .destructive) {
            isShowingDNSProxyEmergencyDisableConfirmation = true
        } label: {
            Label("DNS Proxy 즉시 끄기", systemImage: "exclamationmark.octagon")
        }
        .disabled(dnsProxyConfigurationController.isRequestInFlight)

        Button {
            Task {
                await dnsProxyConfigurationController.refresh(
                    expectedBundleIdentifier: TunnelIdentifiers.dnsProxySystemExtensionBundleIdentifier
                )
            }
        } label: {
            Label("상태 새로고침", systemImage: "arrow.clockwise")
        }
        .disabled(dnsProxyConfigurationController.isRequestInFlight)

        Button {
            Task {
                await refreshDNSProxyObservationSummary()
            }
        } label: {
            Label("관찰 결과 확인", systemImage: "list.number")
        }

        Button {
            Task {
                await applyDNSProxyObservedRoutes()
            }
        } label: {
            Label("관찰 경로 적용", systemImage: "arrow.triangle.branch")
        }
        .disabled(
            status != .connected
                || !dnsProxyConfigurationController.isEnabled
                || dnsProxyConfigurationController.isRequestInFlight
        )

#if DEBUG
        Button(role: .destructive) {
            Task {
                let didDisable = await dnsProxyConfigurationController
                    .simulateExternalDisableForFailSafeTest(
                        expectedBundleIdentifier: TunnelIdentifiers.dnsProxySystemExtensionBundleIdentifier
                    )
                if didDisable {
                    dnsProxyObservationMessage = "DNS Proxy 활성 상태 상실을 만들었습니다. 5초 감시가 Packet Tunnel을 fail-safe로 해제해야 합니다."
                }
            }
        } label: {
            Label("활성 상태 상실 테스트", systemImage: "bolt.shield")
        }
        .disabled(
            status != .connected
                || !dnsProxyConfigurationController.isEnabled
                || dnsProxyConfigurationController.isRequestInFlight
        )
        .help("VPN Router가 소유한 DNS Proxy만 비활성화해 fail-safe 감지를 시험합니다.")
#endif
    }

    @ViewBuilder
    private var recoveryButtons: some View {
        Button {
            Task {
                await performOperation(.checkingTunnel) {
                    await loadStatus()
                }
            }
        } label: {
            Label("시스템 상태 다시 불러오기", systemImage: "arrow.clockwise")
        }
        .disabled(activeOperation != nil)

        Button(role: .destructive) {
            isShowingConfigurationRemovalConfirmation = true
        } label: {
            Label("설치 구성 제거", systemImage: "trash.slash")
        }
        .disabled(activeOperation != nil || canStop)
        .accessibilityHint("VPN 연결이 끊어진 상태에서 VPN Router가 소유한 시스템 구성만 제거합니다.")
    }

    private var settingsView: some View {
        VStack(alignment: .leading, spacing: 24) {
            header(title: "설정", subtitle: "연결 보호 동작을 관리합니다.")

            ProductCard(title: "화면", systemImage: "circle.lefthalf.filled") {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("화면 테마", selection: $appAppearanceRawValue) {
                        ForEach(AppAppearance.allCases) { appearance in
                            Text(appearance.title)
                                .tag(appearance.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text("자동은 macOS의 현재 화면 모양을 따릅니다.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            ProductCard(title: "연결 보호", systemImage: "checkmark.shield") {
                VStack(alignment: .leading, spacing: 12) {
                    Label(
                        "필수 만료 보호가 항상 켜져 있습니다.",
                        systemImage: "checkmark.shield.fill"
                    )
                    .font(.headline)

                    Text("경로 계획을 15분 안에 갱신하지 못하면 VPN Router 연결을 자동으로 끊어 선택 사이트가 일반 네트워크로 우회하지 않게 합니다.")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    Text("VPN Router가 소유한 연결과 네트워크 상태만 정리하며 다른 VPN이나 보안 제품은 변경하지 않습니다.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

#if DEBUG
            ProductCard(title: "개발자 옵션", systemImage: "hammer") {
                Toggle(
                    "DNS Proxy 실험 도구 표시",
                    isOn: $developerDiagnosticsEnabled
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
#endif
            Spacer()
        }
    }

    @ViewBuilder
    private var diagnosticTunnelControls: some View {
#if DEBUG
        if developerDiagnosticsEnabled {
            Button {
                Task {
                    await performOperation(.installingTestConfiguration) {
                        await installStubConfiguration()
                    }
                }
            } label: {
                Label("테스트 구성 설치", systemImage: "plus.circle")
            }
            .disabled(activeOperation != nil)
        }
#endif

        Button {
            Task {
                await performOperation(.checkingTunnel) {
                    await requestProviderDiagnostics()
                }
            }
        } label: {
            Label("터널 상태 확인", systemImage: "waveform.path.ecg")
        }
        .disabled(status != .connected || activeOperation != nil)
        .keyboardShortcut("r", modifiers: .command)

        Button {
            Task {
                await performOperation(.refreshingRoutes) {
                    await refreshConnectedRoutePlan()
                }
            }
        } label: {
            Label("경로 새로고침", systemImage: "arrow.clockwise")
        }
        .disabled(status != .connected || activeOperation != nil)
    }

    @ViewBuilder
    private var ipv6BypassWarning: some View {
        let domains = currentIPv6BypassDomains
        if !domains.isEmpty {
            Label {
                Text("IPv6 우회 위험: 선택하거나 자동 확장한 도메인 중 \(domains.count)개에서 AAAA 응답을 확인했습니다. 현재 IPv4 전용 버전은 해당 IPv6 연결을 VPN으로 보내지 못합니다.")
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
            }
            .font(.callout)
            .foregroundStyle(.orange)
            .accessibilityLabel("IPv6 우회 경고")
        }
    }

    private func header(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.largeTitle)
                .fontWeight(.semibold)
            Text(subtitle)
                .foregroundStyle(.secondary)
        }
    }

    private var statusText: String {
        switch connectionCoordinator.state {
        case .running(let stage):
            return stage == .disconnecting ? "연결 해제 중" : "보호 연결 준비 중"
        case .ready:
            return status == .reasserting ? "경로 갱신 중" : "연결됨"
        case .failed:
            return "연결 실패"
        case .idle:
            break
        }

        switch status {
        case .invalid:
            return "설치된 VPN 구성 없음"
        case .disconnected:
            return "연결 안 됨"
        case .connecting:
            return "연결 중"
        case .connected:
            return "DNS 보호 확인 중"
        case .reasserting:
            return "경로 갱신 중"
        case .disconnecting:
            return "연결 해제 중"
        @unknown default:
            return "알 수 없는 상태"
        }
    }

    private var connectionButtonTitle: String {
        canStop ? "연결 해제" : "연결"
    }

    private var connectionButtonSymbol: String {
        canStop ? "stop.fill" : "power"
    }

    private var connectionButtonColor: Color {
        if connectionCoordinator.state.isReady {
            return .green
        }
        if canStop {
            return .orange
        }
        return .accentColor
    }

    private var connectionStatusSymbol: String {
        switch connectionCoordinator.state {
        case .ready:
            return "checkmark.shield.fill"
        case .failed:
            return "exclamationmark.triangle.fill"
        case .running:
            return "arrow.triangle.2.circlepath"
        case .idle:
            return status == .invalid ? "shield.slash" : "shield"
        }
    }

    private var connectionStatusColor: Color {
        switch connectionCoordinator.state {
        case .ready:
            return .green
        case .failed:
            return .red
        case .running:
            return .orange
        case .idle:
            return .primary
        }
    }

    private var connectionStatusDescription: String {
        switch connectionCoordinator.state {
        case .ready:
            return "DNS 보호와 선택 사이트 경로가 모두 준비되었습니다."
        case .failed:
            return "연결 준비를 완료하지 못했습니다. 최근 상태에서 원인을 확인하세요."
        case .running:
            return activeOperation?.progressLabel ?? "필요한 시스템 보호 기능을 준비하고 있습니다."
        case .idle:
            if selectedProfile == nil {
                return "먼저 VPN 프로필을 가져오고 선택하세요."
            }
            if siteDomains.isEmpty {
                return "VPN으로 보낼 사이트를 한 개 이상 추가하세요."
            }
            return "연결하면 선택한 사이트만 VPN을 사용합니다."
        }
    }

    private var canStart: Bool {
        (status == .disconnected || status == .invalid)
            && !connectionCoordinator.state.isStarting
            && activeOperation == nil
    }

    private var canStop: Bool {
        activeOperation == nil
            && (
                connectionCoordinator.state.isStarting
                    || connectionCoordinator.state.isReady
                    || status == .connecting
                    || status == .connected
                    || status == .reasserting
            )
    }

    private var selectedProfile: ProfileMetadata? {
        guard let selectedProfileId else {
            return profiles.first
        }

        return profiles.first { $0.id == selectedProfileId }
    }

    private var currentIPv6BypassDomains: [String] {
        if let routePlan {
            return routePlan.ipv6BypassDomains
        }
        if let manager, let payload = providerPayload(for: manager) {
            return payload.routePlan.ipv6BypassDomains
        }
        return []
    }

    private var supportedWireGuardConfigTypes: [UTType] {
        var types: [UTType] = [.plainText, .text]
        if let confType = UTType(filenameExtension: "conf") {
            types.insert(confType, at: 0)
        }
        return types
    }

    private var normalizedSiteDomainInput: String? {
        let normalized = DomainRuleExpander.normalize(siteDomainInput)
        guard isValidSiteDomain(normalized), !siteDomains.contains(where: { $0.caseInsensitiveCompare(normalized) == .orderedSame }) else {
            return nil
        }

        return normalized
    }

    private var normalizedProfileRenameText: String? {
        let normalized = profileRenameText.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    private var profileDeletionPresented: Binding<Bool> {
        Binding(
            get: { profilePendingDeletion != nil },
            set: { isPresented in
                if !isPresented {
                    profilePendingDeletion = nil
                }
            }
        )
    }

    private func installStatusObserverIfNeeded() {
        guard statusObserver == nil else {
            return
        }

        statusObserver = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange,
            object: nil,
            queue: .main
        ) { notification in
            guard let connection = notification.object as? NEVPNConnection else {
                return
            }

            status = connection.status
        }
    }

    private func initializeContent() async {
        installStatusObserverIfNeeded()
        await loadStatus()
        await loadProfiles()
        await loadSiteDomainsForSelectedProfile()
        let legacyFailSafeWasDisabled = FailSafeSettingsStore().enforceEnabled()
        await migrateMandatoryFailSafeIfNeeded(
            legacyFailSafeWasDisabled: legacyFailSafeWasDisabled
        )
        await reconcileDNSProxyAfterLaunch()
    }

    private func migrateMandatoryFailSafeIfNeeded(
        legacyFailSafeWasDisabled: Bool
    ) async {
        guard legacyFailSafeWasDisabled,
              status == .connected,
              let session = manager?.connection as? NETunnelProviderSession else {
            return
        }

        do {
            let responseData = try await sendProviderMessage(
                try JSONEncoder().encode(TunnelMandatoryFailSafeRequest()),
                through: session
            )
            guard
                let responseData,
                let response = try? JSONDecoder().decode(
                    TunnelRouteUpdateResponse.self,
                    from: responseData
                ),
                response.success
            else {
                throw TunnelConfigurationError.unreadableRouteUpdateResponse
            }
            lastMessage = "이전 보호 설정을 필수 만료 보호로 안전하게 전환했습니다."
        } catch {
            await stopTunnel()
            lastMessage = "이전 보호 설정을 안전하게 전환하지 못해 VPN Router 연결을 해제했습니다."
        }
    }

    private func removeStatusObserver() {
        guard let statusObserver else {
            return
        }

        NotificationCenter.default.removeObserver(statusObserver)
        self.statusObserver = nil
    }

    private func loadProfiles() async {
        do {
            profiles = try await AppBackgroundWork.loadProfiles()
            if selectedProfileId == nil,
               let manager,
               let installedProfileId = providerProfileId(for: manager),
               profiles.contains(where: { $0.id == installedProfileId }) {
                selectedProfileId = installedProfileId
            }
            if selectedProfileId == nil {
                selectedProfileId = profiles.first?.id
            }
            profileRenameText = selectedProfile?.displayName ?? ""
            importMessage = profiles.isEmpty ? "가져온 VPN 프로필이 없습니다." : "저장된 VPN 프로필을 불러왔습니다."
        } catch {
            importMessage = "VPN 프로필을 불러오지 못했습니다: \(error.localizedDescription)"
        }
    }

    private func loadSiteDomainsForSelectedProfile() async {
        do {
            siteDomains = try await AppBackgroundWork.loadSharedSiteDomains()
            routePlan = nil
            routePlanProfileId = nil
            siteMessage = siteDomains.isEmpty ? "VPN으로 보낼 사이트를 추가하세요." : "공통 VPN 사이트 \(siteDomains.count)개를 불러왔습니다."
        } catch {
            siteMessage = "VPN 사이트를 불러오지 못했습니다: \(error.localizedDescription)"
        }
    }

    private func importConfigFile(_ result: Result<[URL], Error>) {
        do {
            guard let fileURL = try result.get().first else {
                importMessage = "선택한 WireGuard 설정 파일이 없습니다."
                return
            }

            Task {
                await performOperation(.importingProfile) {
                    await importProfile(from: fileURL)
                }
            }
        } catch {
            importMessage = "프로필을 가져오지 못했습니다: \(error.localizedDescription)"
        }
    }

    private func importProfile(from fileURL: URL) async {
        let safeDisplayName = profileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? fileURL.deletingPathExtension().lastPathComponent
            : profileName
        do {
            let result = try await AppBackgroundWork.importProfile(
                from: fileURL,
                displayName: safeDisplayName
            )
            profiles = result.profiles
            selectedProfileId = result.profile.id
            profileRenameText = result.profile.displayName
            profileName = ""
            selectedConfigFileName = fileURL.lastPathComponent
            importMessage = "\(result.profile.displayName) 프로필을 가져왔습니다. 개인 키는 키체인에 저장했습니다."
        } catch {
            importMessage = "프로필을 가져오지 못했습니다: \(error.localizedDescription)"
        }
    }

    private func deleteProfile(_ profile: ProfileMetadata) async {
        do {
            if let installedManager = try await installedManager(for: profile.id) {
                if installedManager.connection.status == .connecting
                    || installedManager.connection.status == .connected
                    || installedManager.connection.status == .reasserting {
                    installedManager.connection.stopVPNTunnel()
                }

                try await installedManager.removeFromPreferences()
                if manager === installedManager {
                    manager = nil
                    status = .invalid
                }
            }

            let remainingProfiles = try await AppBackgroundWork.deleteProfile(id: profile.id)

            profiles = remainingProfiles
            if selectedProfileId == profile.id {
                selectedProfileId = profiles.first?.id
            }
            if routePlanProfileId == profile.id {
                routePlan = nil
                routePlanProfileId = nil
            }
            profilePendingDeletion = nil
            await loadSiteDomainsForSelectedProfile()
            importMessage = "\(profile.displayName) 프로필과 키체인 개인 키를 삭제했습니다. VPN 사이트 목록은 유지했습니다."
            lastMessage = "\(profile.displayName) 프로필을 삭제했습니다. VPN 사이트 목록은 다른 프로필에도 사용할 수 있습니다."
        } catch {
            importMessage = "프로필을 삭제하지 못했습니다: \(error.localizedDescription)"
        }
    }

    private func renameSelectedProfile() async {
        guard let selectedProfile,
              let newDisplayName = normalizedProfileRenameText else {
            importMessage = "새 프로필 이름을 입력하세요."
            focusedField = .profileRename
            return
        }
        guard !canStop else {
            importMessage = "VPN 연결을 해제한 뒤 프로필 이름을 변경하세요."
            return
        }

        do {
            profiles = try await AppBackgroundWork.renameProfile(
                id: selectedProfile.id,
                displayName: newDisplayName
            )
            profileRenameText = newDisplayName
            routePlan = nil
            routePlanProfileId = nil
            importMessage = "\(selectedProfile.displayName) 프로필 이름을 \(newDisplayName)(으)로 변경했습니다."
            lastMessage = "프로필 이름을 변경했습니다. 다음 연결부터 새 이름을 사용합니다."
        } catch {
            importMessage = "프로필 이름을 변경하지 못했습니다: \(error.localizedDescription)"
        }
    }

    private func addSiteDomain() {
        guard let domain = normalizedSiteDomainInput else {
            siteMessage = "example.com과 같은 올바른 도메인을 입력하세요."
            focusedField = .siteDomain
            return
        }

        siteDomains.append(domain)
        siteDomains.sort { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        siteDomainInput = ""
        routePlan = nil
        routePlanProfileId = nil
        siteMessage = "\(domain)을 추가했습니다."
    }

    private func removeSiteDomain(_ domain: String) {
        siteDomains.removeAll { $0.caseInsensitiveCompare(domain) == .orderedSame }
        routePlan = nil
        routePlanProfileId = nil
        siteMessage = "\(domain)을 삭제했습니다."
    }

    private func isValidSiteDomain(_ domain: String) -> Bool {
        let labels = domain.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2 else {
            return false
        }

        return labels.allSatisfy { label in
            guard !label.isEmpty, label.count <= 63 else {
                return false
            }
            return label.allSatisfy { character in
                character.isLetter || character.isNumber || character == "-"
            } && label.first != "-" && label.last != "-"
        }
    }

    private func saveDomainsAndBuildRoutePlan() async {
        guard let selectedProfile else {
            siteMessage = "먼저 가져온 VPN 프로필을 선택하세요."
            return
        }

        do {
            let plan = try await AppBackgroundWork.replaceRulesAndBuildPlan(
                domains: siteDomains
            )
            routePlan = plan
            routePlanProfileId = selectedProfile.id
            if plan.includedRoutes.isEmpty {
                siteMessage = "사이트 \(siteDomains.count)개를 저장했지만 사용할 수 있는 IPv4 주소를 찾지 못했습니다."
            } else if plan.unresolvedDomains.isEmpty {
                siteMessage = "확장된 도메인 \(plan.domains.count)개에서 IPv4 경로 \(plan.includedRoutes.count)개를 만들었습니다."
            } else {
                siteMessage = "IPv4 경로 \(plan.includedRoutes.count)개를 만들었습니다. 도메인 \(plan.unresolvedDomains.count)개는 IPv4 주소를 찾지 못했습니다."
            }
            if !plan.ipv6BypassDomains.isEmpty {
                siteMessage += " 주의: 도메인 \(plan.ipv6BypassDomains.count)개에서 현재 경로 계획으로 처리할 수 없는 IPv6 주소를 확인했습니다."
            }
        } catch {
            siteMessage = "경로를 만들지 못했습니다: \(error.localizedDescription)"
        }
    }

    private func validateConnectionReadiness() async {
        await saveDomainsAndBuildRoutePlan()
        if let routePlan,
           routePlanProfileId == selectedProfile?.id,
           !routePlan.includedRoutes.isEmpty {
            lastMessage = "연결 준비 확인 통과. \(siteMessage)"
        } else {
            lastMessage = "연결 준비를 완료하지 못했습니다. \(siteMessage)"
        }
    }

    private func routePlanForInstall(profileId: ProfileMetadata.ID) async throws -> DomainRoutePlan {
        let plan: DomainRoutePlan
        if let routePlan,
           routePlanProfileId == profileId,
           !DomainRouteRefreshPolicy.standard.needsRefresh(routePlan) {
            plan = routePlan
        } else {
            plan = try await AppBackgroundWork.buildSharedRoutePlan()
            routePlan = plan
            routePlanProfileId = profileId
        }

        guard !plan.includedRoutes.isEmpty else {
            throw TunnelConfigurationError.emptyRoutePlan(unresolvedCount: plan.unresolvedDomains.count)
        }

        return plan
    }

    private func loadStatus() async {
        do {
            manager = try await loadOrCreateManager(preferPhase1: true)
            status = manager?.connection.status ?? .invalid
            lastMessage = "시스템에서 현재 VPN 상태를 불러왔습니다."
        } catch {
            status = .invalid
            lastMessage = "VPN 구성을 불러오지 못했습니다: \(error.localizedDescription)"
        }
    }

    private func installStubConfiguration() async {
        do {
            let manager = try await loadOrCreateManager()
            let tunnelProtocol = NETunnelProviderProtocol()
            tunnelProtocol.providerBundleIdentifier = TunnelIdentifiers.packetTunnelBundleIdentifier
            tunnelProtocol.serverAddress = "VPN Router Phase 0 Stub"
            tunnelProtocol.providerConfiguration = [
                TunnelProviderConfigurationKeys.schemaVersion: 1,
                TunnelProviderConfigurationKeys.mode: TunnelProviderModes.phase0Stub
            ]

            try await saveTunnelConfiguration(
                manager: manager,
                tunnelProtocol: tunnelProtocol,
                successMessage: "Packet Tunnel 테스트 구성을 설치했습니다."
            )
        } catch {
            lastMessage = "테스트 구성을 설치하지 못했습니다: \(error.localizedDescription)"
        }
    }

    private func installSelectedProfileConfiguration() async {
        guard let selectedProfile else {
            importMessage = "먼저 가져온 VPN 프로필을 선택하세요."
            return
        }

        do {
            let selectedRoutePlan = try await routePlanForInstall(profileId: selectedProfile.id)
            let tunnelProtocol = try makeSelectedProfileProtocol(selectedProfile, routePlan: selectedRoutePlan)
            let manager = try await loadOrCreateManager(preferPhase1: true)

            try await saveTunnelConfiguration(
                manager: manager,
                tunnelProtocol: tunnelProtocol,
                successMessage: "\(selectedProfile.displayName) 프로필과 분할 경로 \(selectedRoutePlan.includedRoutes.count)개를 설치했습니다."
            )
            importMessage = "\(selectedProfile.displayName) 프로필과 경로 \(selectedRoutePlan.includedRoutes.count)개를 설치했습니다. 연결하면 WireGuard 터널을 시작합니다."
            if !selectedRoutePlan.ipv6BypassDomains.isEmpty {
                importMessage += " 도메인 \(selectedRoutePlan.ipv6BypassDomains.count)개에 IPv6 우회 위험이 있습니다."
            }
        } catch {
            importMessage = "VPN 프로필을 설치하지 못했습니다: \(error.localizedDescription)"
        }
    }

    private func makeSelectedProfileProtocol(_ profile: ProfileMetadata, routePlan: DomainRoutePlan) throws -> NETunnelProviderProtocol {
        try TunnelProfileConfigurationFactory.makeProtocol(
            profile: profile,
            routePlan: routePlan
        )
    }

    private func saveTunnelConfiguration(
        manager: NETunnelProviderManager,
        tunnelProtocol: NETunnelProviderProtocol,
        successMessage: String
    ) async throws {
        manager.localizedDescription = "VPN Router"
        manager.protocolConfiguration = tunnelProtocol
        manager.isEnabled = true

        try await manager.saveToPreferences()
        try await manager.loadFromPreferences()

        self.manager = manager
        status = manager.connection.status
        lastMessage = successMessage
    }

    private func requestConsumerConnection() async {
        let service = EncryptedDNSPreflightService()
        let result = service.evaluate()
        encryptedDNSPreflightMessage = service.message(for: result)

        guard result.allowsDNSProxyActivation else {
            connectionCoordinator.recordFailure(
                stage: .preflighting,
                code: "encrypted-dns-conflict"
            )
            lastMessage = "보안 DNS 충돌 때문에 연결을 시작하지 않았습니다. 설정을 직접 확인한 뒤 다시 시도하세요."
            return
        }

        if result.disposition == .needsManualVerification {
            isShowingConsumerConnectionConfirmation = true
            return
        }

        await performOperation(.connecting) {
            await startTunnel(manualPreconditionsConfirmed: false)
        }
    }

    private func startTunnel(manualPreconditionsConfirmed: Bool) async {
        var preparedManager: NETunnelProviderManager?
        let expectedDNSProxyIdentifier =
            TunnelIdentifiers.dnsProxySystemExtensionBundleIdentifier

        await connectionCoordinator.connect(
            using: .init(
                preflight: {
                    guard selectedProfile != nil else {
                        throw ConsumerConnectionStepError(
                            code: "profile-not-selected",
                            message: TunnelConfigurationError.noSelectedProfile.localizedDescription
                        )
                    }
                    guard !siteDomains.isEmpty else {
                        throw ConsumerConnectionStepError(
                            code: "sites-empty",
                            message: TunnelConfigurationError.noRouteRules.localizedDescription
                        )
                    }

                    let service = EncryptedDNSPreflightService()
                    let result = service.evaluate()
                    encryptedDNSPreflightMessage = service.message(for: result)
                    guard result.allowsDNSProxyActivation else {
                        throw ConsumerConnectionStepError(
                            code: "encrypted-dns-conflict",
                            message: "지원되는 브라우저의 보안 DNS 정책이 DNS Proxy와 충돌합니다."
                        )
                    }
                    guard result.disposition != .needsManualVerification
                            || manualPreconditionsConfirmed else {
                        throw ConsumerConnectionStepError(
                            code: "manual-precondition-unconfirmed",
                            message: "보안 DNS와 ‘IP 주소 추적 제한’의 수동 확인이 필요합니다."
                        )
                    }
                },
                activateDNSProxyExtension: {
                    lastMessage = "선택 사이트 DNS 보호를 위한 시스템 확장을 확인하고 있습니다."
                    do {
                        try await dnsProxySystemExtensionController
                            .activateForConsumerConnection()
                    } catch {
                        throw ConsumerConnectionStepError(
                            code: "dns-proxy-extension-activation-failed",
                            message: error.localizedDescription
                        )
                    }
                },
                preparePacketTunnel: {
                    guard let selectedProfile else {
                        throw ConsumerConnectionStepError(
                            code: "profile-not-selected",
                            message: TunnelConfigurationError.noSelectedProfile.localizedDescription
                        )
                    }
                    do {
                        let selectedRoutePlan = try await routePlanForInstall(
                            profileId: selectedProfile.id
                        )
                        let tunnelProtocol = try makeSelectedProfileProtocol(
                            selectedProfile,
                            routePlan: selectedRoutePlan
                        )
                        let candidate = try await loadOrCreateManager(
                            preferPhase1: true
                        )
                        try await saveTunnelConfiguration(
                            manager: candidate,
                            tunnelProtocol: tunnelProtocol,
                            successMessage: "\(selectedProfile.displayName) 프로필과 초기 경로 \(selectedRoutePlan.includedRoutes.count)개를 준비했습니다."
                        )
                        preparedManager = self.manager ?? candidate
                    } catch {
                        throw ConsumerConnectionStepError(
                            code: "packet-tunnel-preparation-failed",
                            message: error.localizedDescription
                        )
                    }
                },
                startPacketTunnel: {
                    guard let preparedManager else {
                        throw ConsumerConnectionStepError(
                            code: "packet-tunnel-manager-missing",
                            message: "준비된 Packet Tunnel 구성을 찾지 못했습니다."
                        )
                    }
                    do {
                        try preparedManager.connection.startVPNTunnel()
                        status = preparedManager.connection.status
                        try await waitForPacketTunnelConnection(preparedManager)
                    } catch {
                        throw ConsumerConnectionStepError(
                            code: "packet-tunnel-start-failed",
                            message: error.localizedDescription
                        )
                    }
                },
                enableDNSProxy: {
                    await dnsProxyConfigurationController.enableForDiagnostics(
                        expectedBundleIdentifier: expectedDNSProxyIdentifier
                    )
                    guard dnsProxyConfigurationController.runtimeState
                            == .ownedEnabled else {
                        throw ConsumerConnectionStepError(
                            code: "dns-proxy-enable-failed",
                            message: dnsProxyConfigurationController.message
                        )
                    }
                },
                publishTargets: {
                    do {
                        try await DNSProxyObservationSettingsStore()
                            .configureForDiagnosticRun(domains: siteDomains)
                    } catch {
                        throw ConsumerConnectionStepError(
                            code: "dns-target-publication-failed",
                            message: error.localizedDescription
                        )
                    }
                },
                verifyDNSProxy: {
                    await dnsProxyConfigurationController.refresh(
                        expectedBundleIdentifier: expectedDNSProxyIdentifier
                    )
                    guard dnsProxyConfigurationController.runtimeState
                            == .ownedEnabled else {
                        throw ConsumerConnectionStepError(
                            code: "dns-proxy-ownership-unverified",
                            message: dnsProxyConfigurationController.message
                        )
                    }
                    do {
                        try await DNSProxyObservationSettingsStore()
                            .verifyConsumerReadiness()
                    } catch {
                        throw ConsumerConnectionStepError(
                            code: "dns-proxy-xpc-unready",
                            message: error.localizedDescription
                        )
                    }
                },
                armSafetyMonitor: {
                    guard TunnelInterfaceFingerprint.current() != nil else {
                        throw ConsumerConnectionStepError(
                            code: "tunnel-interface-state-unreadable",
                            message: "활성 터널 인터페이스 상태를 읽지 못했습니다."
                        )
                    }
                },
                disableOwnedDNSProxy: {
                    await dnsProxyConfigurationController.disable(
                        expectedBundleIdentifier: expectedDNSProxyIdentifier,
                        allowOwnedRemovalFallback: false
                    )
                },
                stopPacketTunnel: {
                    preparedManager?.connection.stopVPNTunnel()
                    status = preparedManager?.connection.status ?? .disconnected
                }
            )
        )

        switch connectionCoordinator.state {
        case .ready:
            status = preparedManager?.connection.status ?? .connected
            lastMessage = "DNS 보호와 동적 사이트 경로가 준비되어 VPN Router에 연결했습니다."
            dnsProxyObservationMessage = "DNS Proxy 대상 게시, XPC 상태, AAAA 필터 경로와 안전 감시가 준비되었습니다."
        case .failed(let stage, let code):
            let detail = connectionCoordinator.failureMessage
                .map { " \($0)" } ?? ""
            lastMessage = "연결 준비 단계 \(stage.rawValue)에서 실패했습니다(\(code)).\(detail)"
            dnsProxyObservationMessage = "부분 연결을 정리하고 VPN Router가 소유한 연결 상태만 해제했습니다."
        default:
            break
        }
    }

    private func stopTunnel() async {
        await connectionCoordinator.disconnect(
            disableOwnedDNSProxy: {
                if dnsProxyConfigurationController.runtimeState == .ownedEnabled {
                    await dnsProxyConfigurationController.disable(
                        expectedBundleIdentifier: TunnelIdentifiers.dnsProxySystemExtensionBundleIdentifier,
                        allowOwnedRemovalFallback: false
                    )
                }
            },
            stopPacketTunnel: {
                manager?.connection.stopVPNTunnel()
                status = manager?.connection.status ?? .invalid
            }
        )
        dnsProxyObservationMessage = "VPN Router DNS Proxy를 먼저 비활성화하고 Packet Tunnel 연결 해제를 요청했습니다."
        lastMessage = "VPN 연결 해제를 요청했습니다."
    }

    private func waitForPacketTunnelConnection(
        _ manager: NETunnelProviderManager
    ) async throws {
        for _ in 0..<300 {
            switch manager.connection.status {
            case .connected:
                status = .connected
                return
            case .invalid, .disconnected:
                throw ConsumerConnectionStepError(
                    code: "packet-tunnel-disconnected-during-start",
                    message: "Packet Tunnel이 준비되기 전에 연결이 종료되었습니다."
                )
            default:
                break
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        throw ConsumerConnectionStepError(
            code: "packet-tunnel-start-timeout",
            message: "Packet Tunnel 연결 준비 시간이 초과되었습니다."
        )
    }

    private func requestProviderDiagnostics() async {
        guard let session = manager?.connection as? NETunnelProviderSession else {
            lastMessage = "실행 중인 Packet Tunnel 세션이 없습니다."
            return
        }

        do {
            let response = try await sendProviderMessage(Data(), through: session)
            guard
                let response,
                let diagnostics = try? JSONDecoder().decode(TunnelDiagnostics.self, from: response)
            else {
                lastMessage = "Packet Tunnel의 진단 응답을 읽지 못했습니다."
                return
            }

            let expiryMessage = diagnostics.routePlanExpiresAt.map {
                " 경로 계획 만료 시각: \($0.formatted(date: .omitted, time: .standard))."
            } ?? ""
            let ipv6Message = (diagnostics.ipv6BypassDomainCount ?? 0) > 0
                ? " IPv6 우회 위험 도메인: \(diagnostics.ipv6BypassDomainCount ?? 0)개."
                : ""
            let failSafeMessage = diagnostics.failSafeEnabled == false
                ? " 안전 오류: Packet Tunnel의 필수 만료 보호가 꺼져 있습니다."
                : " 필수 만료 보호: 켜짐."
            lastMessage = "Packet Tunnel 응답 정상. 적용 경로: \(diagnostics.plannedRouteCount)개. \(diagnostics.message)\(expiryMessage)\(ipv6Message)\(failSafeMessage)"
        } catch {
            lastMessage = "Packet Tunnel 상태를 확인하지 못했습니다: \(error.localizedDescription)"
        }
    }

    private func runDNSProxyCapabilityProbe() async {
        isRunningDNSProxyProbe = true
        defer { isRunningDNSProxyProbe = false }

        let result = await DNSProxyCapabilityProbe.run()
        dnsProxyProbeMessage = result.message
        if result.preferenceAccessAvailable {
            dnsProxyProbeMessage += result.configurationEnabled
                ? " 현재 구성은 활성 상태입니다."
                : " 현재 활성화된 VPN Router DNS Proxy 구성은 없습니다."
        } else {
            dnsProxyProbeMessage += " Xcode에서 DNS Proxy capability와 프로비저닝을 확인해야 합니다."
        }
    }

    private func disableDNSProxyForDiagnostics(
        allowOwnedRemovalFallback: Bool
    ) async {
        await dnsProxyConfigurationController.disable(
            expectedBundleIdentifier: TunnelIdentifiers.dnsProxySystemExtensionBundleIdentifier,
            allowOwnedRemovalFallback: allowOwnedRemovalFallback
        )
        guard !dnsProxyConfigurationController.isEnabled, status == .connected else {
            return
        }

        do {
            let restoredRouteCount = try await restoreStaticRoutePlan()
            dnsProxyObservationMessage = """
            DNS Proxy를 끄고 Packet Tunnel을 정적 경로 \(restoredRouteCount)개로 되돌렸습니다.
            """
        } catch {
            manager?.connection.stopVPNTunnel()
            lastMessage = "정적 경로 복구에 실패해 Packet Tunnel 연결 해제를 요청했습니다."
            dnsProxyObservationMessage = """
            DNS Proxy는 꺼졌지만 정적 경로를 복구하지 못해 VPN을 안전하게 해제합니다: \
            \(error.localizedDescription)
            """
        }
    }

    private func restoreStaticRoutePlan() async throws -> Int {
        guard
            let manager,
            manager.connection.status == .connected,
            let session = manager.connection as? NETunnelProviderSession,
            let profileId = providerProfileId(for: manager)
        else {
            throw TunnelConfigurationError.missingPacketTunnelSession
        }

        let staticPlan = try await AppBackgroundWork.buildSharedRoutePlan()
        guard !staticPlan.includedRoutes.isEmpty else {
            throw TunnelConfigurationError.emptyRoutePlan(
                unresolvedCount: staticPlan.unresolvedDomains.count
            )
        }

        let request = TunnelRouteUpdateRequest(
            profileId: profileId,
            routePlan: staticPlan
        )
        let responseData = try await sendProviderMessage(
            try JSONEncoder().encode(request),
            through: session
        )
        guard
            let responseData,
            let response = try? JSONDecoder().decode(
                TunnelRouteUpdateResponse.self,
                from: responseData
            )
        else {
            throw TunnelConfigurationError.unreadableRouteUpdateResponse
        }
        guard response.success else {
            throw TunnelConfigurationError.routeUpdateRejected(response.message)
        }

        routePlan = staticPlan
        routePlanProfileId = profileId
        return response.plannedRouteCount
    }

    private func refreshDNSProxyObservationSummary() async {
        do {
            let summary = try await DNSProxyObservationSettingsStore().summary()
            let latestMessage = summary.latestObservationAt.map {
                " 최근 관찰: \($0.formatted(date: .abbreviated, time: .standard))."
            } ?? ""
            let counts = summary.eventCounts
            let failureMessage: String
            if let domain = summary.lastFailureDomain, let code = summary.lastFailureCode {
                failureMessage = " 마지막 오류: \(domain) \(code)."
            } else {
                failureMessage = ""
            }
            dnsProxyObservationMessage = """
            유효한 대상 IPv4 관찰 \(summary.activeCount)개, 만료된 관찰 \(summary.expiredCount)개.\(latestMessage) \
            런타임 — 시작 \(counts["providerStarted", default: 0]), UDP 수락 \(counts["udpFlowAccepted", default: 0]), \
            TCP 수락 \(counts["tcpFlowAccepted", default: 0]), flow 열림 \(counts["flowOpened", default: 0]), \
            upstream 준비 \(counts["upstreamReady", default: 0]), 응답 수신 \(counts["responseReceived", default: 0]), \
            응답 전달 \(counts["responseDelivered", default: 0]), 대상 AAAA 차단 \(counts["aaaaResponseFiltered", default: 0]), \
            전달 오류 \(counts["forwardingFailure", default: 0]).\(failureMessage)
            """
        } catch {
            dnsProxyObservationMessage = "DNS 관찰 요약을 읽지 못했습니다: \(error.localizedDescription)"
        }
    }

    private func applyDNSProxyObservedRoutes() async {
        do {
            let result = try await updateDNSProxyObservedRoutes()
            dnsProxyObservationMessage = dynamicRouteUpdateMessage(result)
        } catch {
            dnsProxyObservationMessage = "DNS 관찰 경로를 적용하지 못했습니다: \(error.localizedDescription)"
        }
    }

    private func updateDNSProxyObservedRoutes() async throws -> DNSProxyDynamicRouteUpdateResult {
        guard status == .connected else {
            throw TunnelConfigurationError.packetTunnelNotConnected
        }
        guard
            let manager,
            manager.connection.status == .connected,
            let session = manager.connection as? NETunnelProviderSession,
            let profileId = providerProfileId(for: manager)
        else {
            throw TunnelConfigurationError.missingPacketTunnelSession
        }

        let summary = try await DNSProxyObservationSettingsStore().summary()
        let now = Date()
        let observations = summary.routes.map {
            DynamicRouteObservation(
                domain: $0.domain,
                ipv4Address: $0.address,
                observedAt: $0.observedAt,
                expiresAt: $0.expiresAt
            )
        }
        guard let payload = providerPayload(for: manager) else {
            throw TunnelConfigurationError.missingBaseRoutePlan
        }
        let basePlan = payload.routePlan
        let currentPlan = if let routePlan, routePlanProfileId == profileId {
            routePlan
        } else {
            basePlan
        }
        let mergedPlan = try DynamicRoutePlanMerger.merge(
            basePlan: basePlan,
            observations: observations,
            at: now
        )
        let dynamicRouteCount = mergedPlan.includedRoutes.count - basePlan.includedRoutes.count
        guard dynamicRouteCount > 0
                || currentPlan.includedRoutes.count > basePlan.includedRoutes.count else {
            throw TunnelConfigurationError.noNewObservedRoutes
        }
        if currentPlan.includedRoutes == mergedPlan.includedRoutes,
           abs(currentPlan.expiresAt.timeIntervalSince(mergedPlan.expiresAt)) < 1 {
            throw TunnelConfigurationError.dynamicRoutePlanUnchanged
        }

        let request = TunnelRouteUpdateRequest(
            profileId: profileId,
            routePlan: mergedPlan
        )
        let responseData = try await sendProviderMessage(
            try JSONEncoder().encode(request),
            through: session
        )
        guard
            let responseData,
            let response = try? JSONDecoder().decode(
                TunnelRouteUpdateResponse.self,
                from: responseData
            )
        else {
            throw TunnelConfigurationError.unreadableRouteUpdateResponse
        }
        guard response.success else {
            throw TunnelConfigurationError.routeUpdateRejected(response.message)
        }

        let removedCount = max(
            0,
            currentPlan.includedRoutes.count - mergedPlan.includedRoutes.count
        )
        routePlan = mergedPlan
        routePlanProfileId = profileId
        return DNSProxyDynamicRouteUpdateResult(
            dynamicRouteCount: dynamicRouteCount,
            removedRouteCount: removedCount,
            totalRouteCount: response.plannedRouteCount
        )
    }

    private func runDNSProxyDynamicRouteRefreshLoop() async {
        guard
            status == .connected,
            connectionCoordinator.state.isReady,
            dnsProxyConfigurationController.isEnabled
        else {
            return
        }

        while !Task.isCancelled
                && status == .connected
                && connectionCoordinator.state.isReady
                && dnsProxyConfigurationController.isEnabled {
            do {
                let result = try await updateDNSProxyObservedRoutes()
                dnsProxyObservationMessage = dynamicRouteUpdateMessage(result)
            } catch let error as TunnelConfigurationError
                    where error == .noNewObservedRoutes
                        || error == .dynamicRoutePlanUnchanged {
                // The active route set already matches the latest DNS snapshot.
            } catch {
                dnsProxyObservationMessage = "DNS 관찰 경로 자동 갱신 실패: \(error.localizedDescription)"
            }

            do {
                try await Task.sleep(nanoseconds: 15_000_000_000)
            } catch {
                return
            }
        }
    }

    private func reconcileDNSProxyAfterLaunch() async {
        await dnsProxyConfigurationController.refresh(
            expectedBundleIdentifier: TunnelIdentifiers.dnsProxySystemExtensionBundleIdentifier
        )
        guard status == .connected else {
            if dnsProxyConfigurationController.runtimeState == .ownedEnabled {
                await dnsProxyConfigurationController.disable(
                    expectedBundleIdentifier: TunnelIdentifiers.dnsProxySystemExtensionBundleIdentifier,
                    allowOwnedRemovalFallback: false
                )
                dnsProxyObservationMessage = "실행 중인 Packet Tunnel이 없어 남아 있던 VPN Router DNS Proxy 구성을 비활성화했습니다."
            }
            connectionCoordinator.reset()
            return
        }

        guard dnsProxyConfigurationController.runtimeState == .ownedEnabled else {
            manager?.connection.stopVPNTunnel()
            connectionCoordinator.recordFailure(
                stage: .verifyingDNSProxy,
                code: "dns-proxy-missing-after-relaunch"
            )
            lastMessage = "재실행 후 DNS Proxy 소유 상태를 확인하지 못해 VPN Router Packet Tunnel만 안전하게 해제했습니다."
            return
        }

        do {
            try await DNSProxyObservationSettingsStore()
                .configureForDiagnosticRun(domains: siteDomains)
            try await DNSProxyObservationSettingsStore()
                .verifyConsumerReadiness()
            guard TunnelInterfaceFingerprint.current() != nil else {
                throw ConsumerConnectionStepError(
                    code: "tunnel-interface-state-unreadable",
                    message: "활성 터널 인터페이스 상태를 읽지 못했습니다."
                )
            }
            connectionCoordinator.restoreReadyState()
            dnsProxyObservationMessage = "기존 DNS Proxy 세션의 대상, XPC 상태와 안전 감시를 복구했습니다."
        } catch {
            await failSafeForDNSProxyLoss(
                reason: "재실행 후 DNS Proxy XPC 연결을 복구하지 못했습니다: \(error.localizedDescription)"
            )
        }
    }

    private func disableOrphanedDNSProxy() async {
        guard dnsProxyConfigurationController.runtimeState == .ownedEnabled else {
            return
        }
        await dnsProxyConfigurationController.disable(
            expectedBundleIdentifier: TunnelIdentifiers.dnsProxySystemExtensionBundleIdentifier,
            allowOwnedRemovalFallback: false
        )
        dnsProxyObservationMessage = dnsProxyConfigurationController.runtimeState == .ownedEnabled
            ? "Packet Tunnel은 해제됐지만 VPN Router DNS Proxy 비활성화를 확인하지 못했습니다."
            : "Packet Tunnel 종료 후 VPN Router DNS Proxy를 비활성화했습니다."
    }

    private func runDNSProxyOwnershipMonitor() async {
        guard
            status == .connected,
            connectionCoordinator.state.isReady,
            dnsProxyConfigurationController.isEnabled
        else {
            return
        }

        guard let initialTunnelInterfaces = TunnelInterfaceFingerprint.current() else {
            await failSafeForDNSProxyLoss(
                reason: "활성 터널 인터페이스 상태를 읽지 못했습니다."
            )
            return
        }
        dnsProxyObservationMessage = "DNS Proxy 소유권, XPC 상태와 활성 터널 인터페이스 변경 감시가 준비되었습니다."
        var consecutiveHealthFailures = 0
        var monitorIteration = 0
        while !Task.isCancelled
                && status == .connected
                && connectionCoordinator.state.isReady
                && dnsProxyConfigurationController.isEnabled {
            do {
                try await Task.sleep(nanoseconds: 1_000_000_000)
            } catch {
                return
            }

            let currentTunnelInterfaces = TunnelInterfaceFingerprint.current()
            let tunnelInterfaceSetChanged = currentTunnelInterfaces == nil
                || currentTunnelInterfaces != initialTunnelInterfaces

            monitorIteration += 1
            if monitorIteration.isMultiple(of: 5) {
                await dnsProxyConfigurationController.refresh(
                    expectedBundleIdentifier: TunnelIdentifiers.dnsProxySystemExtensionBundleIdentifier
                )
                if dnsProxyConfigurationController.runtimeState == .ownedEnabled {
                    do {
                        try await DNSProxyObservationSettingsStore().healthCheck()
                        consecutiveHealthFailures = 0
                    } catch {
                        consecutiveHealthFailures += 1
                    }
                }
            }

            switch DNSProxyConfigurationPolicy.monitorDecision(
                runtimeState: dnsProxyConfigurationController.runtimeState,
                consecutiveHealthFailures: consecutiveHealthFailures,
                tunnelInterfaceSetChanged: tunnelInterfaceSetChanged
            ) {
            case .healthy:
                continue
            case .waitForHealthRetry:
                dnsProxyObservationMessage = "DNS Proxy 상태 확인이 일시적으로 실패했습니다. 안전을 위해 다시 확인합니다."
            case .failSafe:
                await failSafeForDNSProxyLoss(
                    reason: tunnelInterfaceSetChanged
                        ? "DNS Proxy 활성화 후 활성 터널 인터페이스가 변경되어 다른 VPN의 연결 전환을 감지했습니다."
                        : dnsProxyConfigurationController.runtimeState == .ownedEnabled
                            ? "DNS Proxy provider 응답을 연속으로 확인하지 못했습니다."
                            : "DNS Proxy 구성의 활성 상태 또는 소유권을 잃었습니다."
                )
                return
            }
        }
    }

    private func failSafeForDNSProxyLoss(reason: String) async {
        manager?.connection.stopVPNTunnel()
        status = manager?.connection.status ?? .invalid
        connectionCoordinator.recordFailure(
            stage: .verifyingDNSProxy,
            code: "dns-proxy-runtime-safety-loss"
        )
        lastMessage = "\(reason) 선택 사이트가 일반 경로로 우회하지 않도록 VPN Router 연결을 해제했습니다."

        if dnsProxyConfigurationController.runtimeState == .ownedEnabled {
            await dnsProxyConfigurationController.disable(
                expectedBundleIdentifier: TunnelIdentifiers.dnsProxySystemExtensionBundleIdentifier,
                allowOwnedRemovalFallback: false
            )
        }
        dnsProxyObservationMessage = lastMessage
    }

    private func dynamicRouteUpdateMessage(
        _ result: DNSProxyDynamicRouteUpdateResult
    ) -> String {
        if result.dynamicRouteCount == 0, result.removedRouteCount > 0 {
            return """
            만료된 DNS 관찰 경로 \(result.removedRouteCount)개를 제거하고 정적 경로 \
            \(result.totalRouteCount)개로 되돌렸습니다.
            """
        }

        return """
        DNS 관찰 경로 \(result.dynamicRouteCount)개를 포함해 Packet Tunnel에 총 \
        \(result.totalRouteCount)개를 적용했습니다. 15초마다 TTL을 다시 확인합니다.
        """
    }

    private func runConnectedRouteRefreshLoop() async {
        guard status == .connected, connectionCoordinator.state.isReady else {
            return
        }

        let interval = DomainRouteRefreshPolicy.standard.refreshInterval
        let nanoseconds = UInt64(interval * 1_000_000_000)
        while !Task.isCancelled
                && status == .connected
                && connectionCoordinator.state.isReady {
            do {
                try await Task.sleep(nanoseconds: nanoseconds)
            } catch {
                return
            }

            guard
                !Task.isCancelled,
                status == .connected,
                connectionCoordinator.state.isReady
            else {
                return
            }
            guard activeOperation == nil else {
                continue
            }
            await performOperation(.refreshingRoutes) {
                await refreshConnectedRoutePlan()
            }
        }
    }

    private func refreshConnectedRoutePlan() async {
        guard status == .connected else {
            lastMessage = "경로를 새로고치려면 먼저 VPN에 연결하세요."
            return
        }
        guard
            let manager,
            let session = manager.connection as? NETunnelProviderSession,
            let profileId = providerProfileId(for: manager),
            profiles.contains(where: { $0.id == profileId })
        else {
            lastMessage = "현재 VPN 연결에 해당하는 저장된 프로필을 찾지 못했습니다."
            return
        }

        do {
            let refreshedPlan = try await AppBackgroundWork.buildSharedRoutePlan()
            guard !refreshedPlan.includedRoutes.isEmpty else {
                throw TunnelConfigurationError.emptyRoutePlan(
                    unresolvedCount: refreshedPlan.unresolvedDomains.count
                )
            }

            let request = TunnelRouteUpdateRequest(
                profileId: profileId,
                routePlan: refreshedPlan
            )
            let responseData = try await sendProviderMessage(
                try JSONEncoder().encode(request),
                through: session
            )
            guard
                let responseData,
                let response = try? JSONDecoder().decode(TunnelRouteUpdateResponse.self, from: responseData)
            else {
                throw TunnelConfigurationError.unreadableRouteUpdateResponse
            }
            guard response.success else {
                throw TunnelConfigurationError.routeUpdateRejected(response.message)
            }

            routePlan = refreshedPlan
            routePlanProfileId = profileId
            lastMessage = "분할 경로 \(response.plannedRouteCount)개를 새로고쳤습니다."
            if !refreshedPlan.ipv6BypassDomains.isEmpty {
                lastMessage += " 도메인 \(refreshedPlan.ipv6BypassDomains.count)개에 IPv6 우회 위험이 남아 있습니다."
            }
        } catch {
            lastMessage = "경로를 새로고치지 못했습니다: \(error.localizedDescription). 기존 경로는 만료 전까지 유지됩니다."
        }
    }

    private func loadOrCreateManager(preferPhase1: Bool = false) async throws -> NETunnelProviderManager {
        let managers = try await NETunnelProviderManager.loadAllFromPreferences()
        let vpnRouterManagers = managers.filter { $0.localizedDescription == "VPN Router" }

        if preferPhase1,
           let phase1Manager = vpnRouterManagers.first(where: { providerMode(for: $0) == TunnelProviderModes.phase1WireGuard }) {
            return phase1Manager
        }

        if let existing = vpnRouterManagers.first {
            return existing
        }

        let manager = NETunnelProviderManager()
        manager.localizedDescription = "VPN Router"
        return manager
    }

    private func installedManager(for profileId: ProfileMetadata.ID) async throws -> NETunnelProviderManager? {
        let managers = try await NETunnelProviderManager.loadAllFromPreferences()
        return managers.first { manager in
            manager.localizedDescription == "VPN Router" && providerProfileId(for: manager) == profileId
        }
    }

    private func providerMode(for manager: NETunnelProviderManager) -> String? {
        guard let tunnelProtocol = manager.protocolConfiguration as? NETunnelProviderProtocol else {
            return nil
        }

        return tunnelProtocol.providerConfiguration?[TunnelProviderConfigurationKeys.mode] as? String
    }

    private func providerRouteCount(for manager: NETunnelProviderManager) -> Int {
        providerPayload(for: manager)?.routePlan.includedRoutes.count ?? 0
    }

    private func providerProfileId(for manager: NETunnelProviderManager) -> ProfileMetadata.ID? {
        guard let tunnelProtocol = manager.protocolConfiguration as? NETunnelProviderProtocol else {
            return nil
        }

        if let payload = providerPayload(for: manager) {
            return payload.profileId
        }

        guard let profileId = tunnelProtocol.providerConfiguration?[TunnelProviderConfigurationKeys.profileId] as? String else {
            return nil
        }

        return UUID(uuidString: profileId)
    }

    private func providerPayload(for manager: NETunnelProviderManager) -> TunnelProfileProviderConfiguration? {
        guard
            let tunnelProtocol = manager.protocolConfiguration as? NETunnelProviderProtocol,
            let payloadData = tunnelProtocol.providerConfiguration?[TunnelProviderConfigurationKeys.payload] as? Data
        else {
            return nil
        }

        return try? JSONDecoder().decode(TunnelProfileProviderConfiguration.self, from: payloadData)
    }

    private func sendProviderMessage(
        _ message: Data,
        through session: NETunnelProviderSession
    ) async throws -> Data? {
        try await withCheckedThrowingContinuation { continuation in
            let gate = ProviderMessageContinuationGate()
            let timeout = DispatchWorkItem {
                if gate.claim() {
                    continuation.resume(
                        throwing: TunnelConfigurationError.providerMessageTimedOut
                    )
                }
            }
            DispatchQueue.global(qos: .userInitiated).asyncAfter(
                deadline: .now() + 5,
                execute: timeout
            )
            do {
                try session.sendProviderMessage(message) { response in
                    timeout.cancel()
                    if gate.claim() {
                        continuation.resume(returning: response)
                    }
                }
            } catch {
                timeout.cancel()
                if gate.claim() {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func performOperation(
        _ operation: AppOperation,
        action: () async -> Void
    ) async {
        guard activeOperation == nil else {
            lastMessage = "현재 \(activeOperation?.progressLabel ?? "다른 작업")이 끝난 뒤 다시 시도하세요."
            return
        }

        activeOperation = operation
        defer {
            activeOperation = nil
        }
        await action()
    }

    private func prepareTroubleshootingExport() {
        do {
            let report = makeTroubleshootingReport()
            let data = try TroubleshootingReportEncoder.encode(report)
            troubleshootingReportDocument = TroubleshootingReportDocument(data: data)
            troubleshootingReportFilename = "VPNRouter-Diagnostics-\(exportTimestamp())"
            isExportingTroubleshootingReport = true
        } catch {
            diagnosticExportMessage = "진단 파일을 준비하지 못했습니다: \(error.localizedDescription)"
        }
    }

    private func finishTroubleshootingExport(_ result: Result<URL, Error>) {
        troubleshootingReportDocument = nil

        switch result {
        case .success(let fileURL):
            diagnosticExportMessage = "비밀정보를 제외한 진단 파일을 저장했습니다: \(fileURL.lastPathComponent)"
        case .failure(let error):
            let cocoaError = error as NSError
            if cocoaError.domain == NSCocoaErrorDomain,
               cocoaError.code == NSUserCancelledError {
                diagnosticExportMessage = "진단 파일 저장을 취소했습니다."
            } else {
                diagnosticExportMessage = "진단 파일을 저장하지 못했습니다: \(error.localizedDescription)"
            }
        }
    }

    private func removeVPNRouterConfigurations() async {
        guard !canStop else {
            diagnosticExportMessage = "VPN 연결을 먼저 해제한 뒤 설치 구성을 제거하세요."
            return
        }

        do {
            let managers = try await NETunnelProviderManager.loadAllFromPreferences()
            let ownedManagers = managers.filter(isVPNRouterOwnedManager)
            for ownedManager in ownedManagers {
                try await ownedManager.removeFromPreferences()
            }

            manager = nil
            status = .invalid
            routePlan = nil
            routePlanProfileId = nil
            diagnosticExportMessage = ownedManagers.isEmpty
                ? "제거할 VPN Router 시스템 구성이 없습니다."
                : "VPN Router 시스템 구성 \(ownedManagers.count)개를 제거했습니다. 저장된 프로필과 사이트 목록은 유지했습니다."
        } catch {
            diagnosticExportMessage = "VPN Router 시스템 구성을 제거하지 못했습니다: \(error.localizedDescription)"
        }
    }

    private func isVPNRouterOwnedManager(_ candidate: NETunnelProviderManager) -> Bool {
        guard
            candidate.localizedDescription == "VPN Router",
            let tunnelProtocol = candidate.protocolConfiguration as? NETunnelProviderProtocol
        else {
            return false
        }
        return tunnelProtocol.providerBundleIdentifier
            == TunnelIdentifiers.packetTunnelBundleIdentifier
    }

    private func makeTroubleshootingReport() -> TroubleshootingReport {
        let activePlan = routePlan ?? manager.flatMap(providerPayload(for:))?.routePlan
        let info = Bundle.main.infoDictionary
        return TroubleshootingReport(
            app: .init(
                version: info?["CFBundleShortVersionString"] as? String ?? "0.1.0",
                build: info?["CFBundleVersion"] as? String ?? "unknown"
            ),
            system: .init(
                operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
                architecture: currentArchitecture
            ),
            connection: .init(
                state: diagnosticConnectionState,
                stage: connectionCoordinator.state.stage.rawValue,
                failureCode: connectionCoordinator.state.failureCode,
                configurationInstalled: manager?.protocolConfiguration != nil,
                packetTunnelSessionAvailable: manager?.connection is NETunnelProviderSession
            ),
            routing: .init(
                plannedRouteCount: activePlan?.includedRoutes.count ?? 0,
                unresolvedDomainCount: activePlan?.unresolvedDomains.count ?? 0,
                ipv6BypassRiskDomainCount: activePlan?.ipv6BypassDomains.count ?? 0,
                generatedAt: activePlan?.generatedAt,
                expiresAt: activePlan?.expiresAt
            ),
            storage: .init(
                profileCount: profiles.count,
                selectedSiteCount: siteDomains.count
            ),
            protection: .init(
                routeExpiryDisconnectEnabled: true,
                stateOwnership: "vpn-router-only"
            ),
            lifecycle: .init(
                networkState: lifecycleMonitor.networkState,
                networkChangeCount: lifecycleMonitor.networkChangeCount,
                sleepCount: lifecycleMonitor.sleepCount,
                wakeCount: lifecycleMonitor.wakeCount
            )
        )
    }

    private var diagnosticConnectionState: String {
        switch status {
        case .invalid: return "invalid"
        case .disconnected: return "disconnected"
        case .connecting: return "connecting"
        case .connected: return "connected"
        case .reasserting: return "reasserting"
        case .disconnecting: return "disconnecting"
        @unknown default: return "unknown"
        }
    }

    private var currentArchitecture: String {
#if arch(arm64)
        return "arm64"
#elseif arch(x86_64)
        return "x86_64"
#else
        return "unknown"
#endif
    }

    private func exportTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }

    private func announceForVoiceOver(_ message: String) {
        guard let application = NSApp else {
            return
        }
        NSAccessibility.post(
            element: application,
            notification: .announcementRequested,
            userInfo: [
                .announcement: message,
                .priority: 50
            ]
        )
    }
}

private enum AppOperation: String {
    case importingProfile
    case deletingProfile
    case buildingRoutes
    case installingProfile
    case installingTestConfiguration
    case connecting
    case disconnecting
    case refreshingRoutes
    case checkingTunnel
    case removingConfiguration

    var progressLabel: String {
        switch self {
        case .importingProfile:
            return "VPN 프로필을 가져오는 중"
        case .deletingProfile:
            return "VPN 프로필을 삭제하는 중"
        case .buildingRoutes:
            return "사이트 주소와 경로를 확인하는 중"
        case .installingProfile:
            return "VPN 프로필 구성을 설치하는 중"
        case .installingTestConfiguration:
            return "테스트 구성을 설치하는 중"
        case .connecting:
            return "VPN 연결을 준비하는 중"
        case .disconnecting:
            return "VPN 연결과 DNS Proxy를 안전하게 해제하는 중"
        case .refreshingRoutes:
            return "VPN 경로를 새로고치는 중"
        case .checkingTunnel:
            return "Packet Tunnel 상태를 확인하는 중"
        case .removingConfiguration:
            return "VPN Router 시스템 구성을 제거하는 중"
        }
    }

    var accessibilityLabel: String {
        "\(progressLabel)입니다. 완료될 때까지 관련 작업을 사용할 수 없습니다."
    }
}

private enum FocusedField: Hashable {
    case profileName
    case profileRename
    case siteDomain
}

private final class ProviderMessageContinuationGate: @unchecked Sendable {
    private let lock = NSLock()
    private var isClaimed = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !isClaimed else {
            return false
        }
        isClaimed = true
        return true
    }
}

private struct RoutePlanSummary: View {
    let plan: DomainRoutePlan

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Label("\(plan.domains.count)", systemImage: "globe")
                Label("\(plan.includedRoutes.count)", systemImage: "arrow.triangle.branch")
                Label("\(plan.unresolvedDomains.count)", systemImage: "questionmark.circle")
                if !plan.ipv6BypassDomains.isEmpty {
                    Label("\(plan.ipv6BypassDomains.count)", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 14) {
                DisclosureGroup("VPN으로 보내는 경로") {
                    ForEach(plan.includedRoutes.prefix(24), id: \.destinationAddress) { route in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(route.destinationAddress)/32")
                                .font(.system(.body, design: .monospaced))
                            Text(route.sourceDomain)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }

                if !plan.unresolvedDomains.isEmpty {
                    DisclosureGroup("주소를 찾지 못한 도메인") {
                        ForEach(plan.unresolvedDomains.prefix(24), id: \.self) { domain in
                            Text(domain)
                                .font(.system(.body, design: .monospaced))
                                .padding(.vertical, 2)
                        }
                    }
                }

                if !plan.ipv6BypassDomains.isEmpty {
                    DisclosureGroup("IPv6 우회 위험") {
                        ForEach(plan.ipv6BypassDomains.prefix(24), id: \.self) { domain in
                            Text(domain)
                                .font(.system(.body, design: .monospaced))
                                .padding(.vertical, 2)
                        }
                    }
                }
            }
        }
    }
}

private struct DiagnosticMessageView: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.callout)
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .topLeading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(message)
    }
}

private struct TroubleshootingReportDocument: FileDocument {
    static var readableContentTypes: [UTType] {
        [.json]
    }

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

private struct ProfileRow: View {
    let profile: ProfileMetadata

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(profile.displayName)
                .font(.headline)
            HStack(spacing: 10) {
                Label("\(profile.summary.peerCount)", systemImage: "point.3.connected.trianglepath.dotted")
                Label("\(profile.summary.interfaceAddresses.count)", systemImage: "network")
                Label("\(profile.summary.dnsServers.count)", systemImage: "server.rack")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if let endpoint = profile.summary.endpoints.first {
                Text(endpoint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct ProductCard<Content: View>: View {
    private let title: String?
    private let systemImage: String?
    @ViewBuilder private let content: Content

    init(
        title: String? = nil,
        systemImage: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let title {
                if let systemImage {
                    Label(title, systemImage: systemImage)
                        .font(.headline)
                } else {
                    Text(title)
                        .font(.headline)
                }
            }

            content
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(nsColor: .separatorColor).opacity(0.55), lineWidth: 1)
        }
    }
}

private enum SidebarSection: String, CaseIterable, Identifiable {
    case home
    case profiles
    case sites
    case diagnostics
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home:
            return "홈"
        case .profiles:
            return "VPN 프로필"
        case .sites:
            return "VPN 사이트"
        case .diagnostics:
            return "문제 해결"
        case .settings:
            return "설정"
        }
    }

    var systemImage: String {
        switch self {
        case .home:
            return "house"
        case .profiles:
            return "doc.text"
        case .sites:
            return "globe"
        case .diagnostics:
            return "stethoscope"
        case .settings:
            return "gearshape"
        }
    }
}

struct TunnelDiagnostics: Decodable {
    let schemaVersion: Int
    let providerState: String
    let profileId: String?
    let profileDisplayName: String?
    let plannedRouteCount: Int
    let ipv6BypassDomainCount: Int?
    let routePlanExpiresAt: Date?
    let failSafeEnabled: Bool?
    let wireGuardKitLinked: Bool
    let message: String
    let updatedAt: Date
}

enum TunnelConfigurationError: LocalizedError, Equatable {
    case noSelectedProfile
    case noRouteRules
    case emptyRoutePlan(unresolvedCount: Int)
    case routeUpdateRejected(String)
    case unreadableRouteUpdateResponse
    case missingBaseRoutePlan
    case noNewObservedRoutes
    case packetTunnelNotConnected
    case missingPacketTunnelSession
    case dynamicRoutePlanUnchanged
    case providerMessageTimedOut

    var errorDescription: String? {
        switch self {
        case .noSelectedProfile:
            return "연결하기 전에 가져온 VPN 프로필을 선택하고 설치하세요."
        case .noRouteRules:
            return "사이트를 하나 이상 추가하고 경로를 만든 뒤 설치하거나 연결하세요."
        case .emptyRoutePlan(let unresolvedCount):
            return "사용할 수 있는 IPv4 경로가 없습니다. 주소를 찾지 못한 도메인: \(unresolvedCount)개. 사이트를 확인하고 경로를 다시 만드세요."
        case .routeUpdateRejected(let message):
            return "Packet Tunnel이 경로 새로고침을 거부했습니다: \(message)"
        case .unreadableRouteUpdateResponse:
            return "Packet Tunnel의 응답을 읽지 못했습니다."
        case .missingBaseRoutePlan:
            return "현재 Packet Tunnel의 기준 경로 계획을 찾지 못했습니다."
        case .noNewObservedRoutes:
            return "현재 기준 경로에 없는 유효한 DNS 관찰 경로가 없습니다."
        case .packetTunnelNotConnected:
            return "관찰 경로를 적용하려면 먼저 Packet Tunnel에 연결하세요."
        case .missingPacketTunnelSession:
            return "실행 중인 Packet Tunnel 세션을 찾지 못했습니다."
        case .dynamicRoutePlanUnchanged:
            return "Packet Tunnel에 이미 같은 DNS 관찰 경로가 적용되어 있습니다."
        case .providerMessageTimedOut:
            return "Packet Tunnel 응답 시간이 초과되었습니다."
        }
    }
}

private struct DNSProxyDynamicRouteUpdateResult {
    let dynamicRouteCount: Int
    let removedRouteCount: Int
    let totalRouteCount: Int
}

private struct DNSProxyDynamicRefreshKey: Equatable {
    let tunnelStatus: NEVPNStatus
    let dnsProxyEnabled: Bool
    let consumerConnectionReady: Bool
}

private struct DNSProxyOwnershipMonitorKey: Equatable {
    let tunnelStatus: NEVPNStatus
    let dnsProxyEnabled: Bool
    let consumerConnectionReady: Bool
}

private struct ConsumerRouteRefreshKey: Equatable {
    let tunnelStatus: NEVPNStatus
    let consumerConnectionReady: Bool
}

enum TunnelIdentifiers {
    nonisolated static var packetTunnelBundleIdentifier: String {
        guard let appBundleIdentifier = Bundle.main.bundleIdentifier else {
            return "VPNRouter.PacketTunnel"
        }

        return "\(appBundleIdentifier).PacketTunnel"
    }

    nonisolated static var dnsProxySystemExtensionBundleIdentifier: String {
        guard let appBundleIdentifier = Bundle.main.bundleIdentifier else {
            return "VPNRouter.DNSProxyExtension"
        }

        return "\(appBundleIdentifier).DNSProxyExtension"
    }
}

enum TunnelProviderConfigurationKeys {
    nonisolated static let schemaVersion = "schemaVersion"
    nonisolated static let mode = "mode"
    nonisolated static let profileId = "profileId"
    nonisolated static let profileDisplayName = "profileDisplayName"
    nonisolated static let payload = "payload"
}

enum TunnelProviderModes {
    nonisolated static let phase0Stub = "phase0-stub"
    nonisolated static let phase1WireGuard = "phase1-wireguard"
}

import SwiftUI
import NetworkExtension
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var dnsProxySystemExtensionController = DNSProxySystemExtensionController()
    @StateObject private var dnsProxyConfigurationController = DNSProxyConfigurationController()
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
    @State private var profilePendingDeletion: ProfileMetadata?
    @State private var siteDomainInput = ""
    @State private var siteDomains: [String] = []
    @State private var siteMessage = "VPN 프로필을 선택하고 VPN으로 보낼 사이트를 추가하세요."
    @State private var routePlan: DomainRoutePlan?
    @State private var routePlanProfileId: ProfileMetadata.ID?
    @State private var failSafeEnabled = true
    @State private var settingsMessage = "만료 시 자동 연결 해제가 켜져 있습니다."
    @State private var isShowingFailSafeDisableConfirmation = false
    @State private var dnsProxyProbeMessage = "DNS Proxy 권한과 preferences 접근 여부를 아직 확인하지 않았습니다."
    @State private var isRunningDNSProxyProbe = false
    @State private var isShowingDNSProxyEnableConfirmation = false
    @State private var isShowingDNSProxyEmergencyDisableConfirmation = false
    @State private var dnsProxyObservationMessage = "이번 진단 실행에서 확인한 대상 DNS 관찰이 없습니다."

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedSection) {
                ForEach(SidebarSection.allCases) { section in
                    NavigationLink(value: section) {
                        Label(section.title, systemImage: section.systemImage)
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 210)
        } detail: {
            detailView
                .padding(32)
                .frame(minWidth: 720, minHeight: 520, alignment: .topLeading)
        }
        .task {
            installStatusObserverIfNeeded()
            await loadStatus()
            loadProfiles()
            loadSiteDomainsForSelectedProfile()
            loadFailSafeSetting()
            await dnsProxyConfigurationController.refresh(
                expectedBundleIdentifier: TunnelIdentifiers.dnsProxySystemExtensionBundleIdentifier
            )
        }
        .task(id: status) {
            await runConnectedRouteRefreshLoop()
        }
        .task(
            id: DNSProxyDynamicRefreshKey(
                tunnelStatus: status,
                dnsProxyEnabled: dnsProxyConfigurationController.isEnabled
            )
        ) {
            await runDNSProxyDynamicRouteRefreshLoop()
        }
        .onChange(of: selectedProfileId) { _, _ in
            loadSiteDomainsForSelectedProfile()
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
        .confirmationDialog(
            "VPN 프로필 삭제",
            isPresented: Binding(
                get: { profilePendingDeletion != nil },
                set: { isPresented in
                    if !isPresented {
                        profilePendingDeletion = nil
                    }
                }
            ),
            presenting: profilePendingDeletion
        ) { profile in
            Button("\(profile.displayName) 삭제", role: .destructive) {
                Task {
                    await deleteProfile(profile)
                }
            }
            Button("취소", role: .cancel) {
                profilePendingDeletion = nil
            }
        } message: { profile in
            Text("이 Mac에서 프로필 정보와 키체인 개인 키를 삭제합니다. VPN 사이트 목록은 유지됩니다.")
        }
        .confirmationDialog(
            "만료 보호 기능을 끌까요?",
            isPresented: $isShowingFailSafeDisableConfirmation
        ) {
            Button("보호 기능 끄기", role: .destructive) {
                Task {
                    await updateFailSafeSetting(false)
                }
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("경로가 15분 이상 갱신되지 않아도 VPN 연결을 유지합니다. 선택한 사이트가 일반 네트워크로 우회할 수 있습니다.")
        }
        .confirmationDialog(
            "DNS Proxy 진단을 활성화할까요?",
            isPresented: $isShowingDNSProxyEnableConfirmation
        ) {
            Button("진단용 DNS Proxy 활성화") {
                Task {
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
                        dnsProxyObservationMessage = "DNS Proxy XPC 설정에 실패해 구성을 다시 끕니다: \(error.localizedDescription)"
                        await disableDNSProxyForDiagnostics(
                            allowOwnedRemovalFallback: false
                        )
                    }
                }
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("DNS 요청 전달을 시작합니다. 다른 DNS Proxy 또는 보안 DNS가 활성화되어 있으면 취소하고 해당 제품의 안내를 먼저 확인하세요. VPN Router는 제3자 제품을 자동으로 끄거나 변경하지 않습니다.")
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
            header(title: "VPN Router", subtitle: statusText)
            tunnelControls
            failSafeWarning
            ipv6BypassWarning
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Text("1단계")
                    .font(.headline)
                Text("WireGuard 프로필과 선택한 사이트만 VPN으로 보내는 분할 라우팅을 관리합니다.")
                    .foregroundStyle(.secondary)
                DiagnosticMessageView(message: lastMessage)
            }
            Spacer()
        }
    }

    private var profilesView: some View {
        HStack(alignment: .top, spacing: 28) {
            VStack(alignment: .leading, spacing: 16) {
                header(title: "VPN 프로필", subtitle: "가져온 프로필 \(profiles.count)개")

                VStack(alignment: .leading, spacing: 10) {
                    TextField("프로필 이름", text: $profileName)
                        .textFieldStyle(.roundedBorder)

                    HStack(spacing: 12) {
                        Image(systemName: "doc.badge.plus")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                            .frame(width: 32)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(selectedConfigFileName)
                                .font(.headline)
                                .lineLimit(1)
                            Text("WireGuard .conf 파일을 선택하세요. 개인 키는 키체인에 안전하게 저장됩니다.")
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

                    HStack(spacing: 12) {
                        Button {
                            isImportingConfigFile = true
                        } label: {
                            Label("파일 가져오기", systemImage: "folder")
                        }
                        .buttonStyle(.borderedProminent)

                        Button {
                            selectedConfigFileName = "선택한 파일 없음"
                            profileName = ""
                        } label: {
                            Label("입력 지우기", systemImage: "xmark.circle")
                        }
                        .disabled(selectedConfigFileName == "선택한 파일 없음" && profileName.isEmpty)
                    }
                }

                Text(importMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(minWidth: 360, idealWidth: 420, maxWidth: 520, alignment: .topLeading)

            VStack(alignment: .leading, spacing: 14) {
                Text("저장된 프로필")
                    .font(.headline)

                if profiles.isEmpty {
                    ContentUnavailableView("저장된 프로필 없음", systemImage: "doc.text.magnifyingglass")
                } else {
                    List(selection: $selectedProfileId) {
                        ForEach(profiles) { profile in
                            HStack(spacing: 12) {
                                ProfileRow(profile: profile)
                                Spacer()
                                Button(role: .destructive) {
                                    profilePendingDeletion = profile
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                                .help("\(profile.displayName) 삭제")
                            }
                            .tag(profile.id)
                        }
                    }
                    .listStyle(.inset)

                    HStack(spacing: 12) {
                        Button {
                            Task {
                                await installSelectedProfileConfiguration()
                            }
                        } label: {
                            Label("선택한 프로필 설치", systemImage: "arrow.down.doc")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(selectedProfile == nil)

                        Button(role: .destructive) {
                            if let selectedProfile {
                                profilePendingDeletion = selectedProfile
                            }
                        } label: {
                            Label("선택한 프로필 삭제", systemImage: "trash")
                        }
                        .disabled(selectedProfile == nil)
                    }
                }
            }
            .frame(minWidth: 280, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var sitesView: some View {
        HStack(alignment: .top, spacing: 28) {
            VStack(alignment: .leading, spacing: 16) {
                header(
                    title: "VPN 사이트",
                    subtitle: selectedProfile.map { "\($0.displayName) 프로필로 보낼 사이트" } ?? "연결할 프로필에 공통으로 적용되는 사이트"
                )

                HStack(spacing: 10) {
                    TextField("example.com", text: $siteDomainInput)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(addSiteDomain)

                    Button {
                        addSiteDomain()
                    } label: {
                        Label("사이트 추가", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(normalizedSiteDomainInput == nil)
                }

                if siteDomains.isEmpty {
                    ContentUnavailableView("등록된 사이트 없음", systemImage: "globe.badge.chevron.backward")
                        .frame(minHeight: 220)
                } else {
                    List {
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
                                .help("\(domain) 삭제")
                            }
                        }
                    }
                    .listStyle(.inset)
                    .frame(minHeight: 220)
                }

                HStack(spacing: 12) {
                    Button {
                        Task {
                            await saveDomainsAndBuildRoutePlan()
                        }
                    } label: {
                        Label("경로 만들기", systemImage: "point.3.connected.trianglepath.dotted")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedProfile == nil || siteDomains.isEmpty)

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

                Text(siteMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(minWidth: 360, idealWidth: 420, maxWidth: 520, alignment: .topLeading)

            VStack(alignment: .leading, spacing: 14) {
                Text("경로 계획")
                    .font(.headline)

                if let routePlan, routePlanProfileId == selectedProfile?.id {
                    RoutePlanSummary(plan: routePlan)
                } else {
                    ContentUnavailableView("만든 경로 없음", systemImage: "map")
                }
            }
            .frame(minWidth: 280, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var diagnosticsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header(title: "진단", subtitle: statusText)
                tunnelControls
                ipv6BypassWarning
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text("Packet Tunnel 상태")
                        .font(.headline)
                    DiagnosticMessageView(message: lastMessage)
                }
                Divider()
                VStack(alignment: .leading, spacing: 10) {
                    Text("Phase 3 DNS Proxy 준비 상태")
                        .font(.headline)
                    Text("이 검사는 DNS 설정을 저장하거나 활성화하지 않고 현재 서명 빌드의 preferences 읽기 권한만 확인합니다.")
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
                    DiagnosticMessageView(message: dnsProxyObservationMessage)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    @ViewBuilder
    private var dnsProxyDiagnosticControls: some View {
        Button {
            isShowingDNSProxyEnableConfirmation = true
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
    }

    private var settingsView: some View {
        VStack(alignment: .leading, spacing: 24) {
            header(title: "설정", subtitle: "연결 보호 동작을 관리합니다.")

            GroupBox("연결 보호") {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle(
                        "경로 계획 만료 시 자동으로 연결 해제",
                        isOn: Binding(
                            get: { failSafeEnabled },
                            set: { newValue in
                                if newValue {
                                    Task {
                                        await updateFailSafeSetting(true)
                                    }
                                } else {
                                    isShowingFailSafeDisableConfirmation = true
                                }
                            }
                        )
                    )

                    Text("켜면 15분 안에 경로를 갱신하지 못했을 때 VPN을 자동으로 끊어 오래된 경로로 인한 우회를 막습니다.")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    if !failSafeEnabled {
                        Label(
                            "보호 기능이 꺼져 있습니다. 경로가 오래되어도 VPN 연결이 유지되며 선택한 사이트가 일반 네트워크로 우회할 수 있습니다.",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(.callout)
                        .foregroundStyle(.orange)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }

            DiagnosticMessageView(message: settingsMessage)
            Spacer()
        }
    }

    private var tunnelControls: some View {
        HStack(spacing: 12) {
            Button {
                Task {
                    await installStubConfiguration()
                }
            } label: {
                Label("테스트 구성 설치", systemImage: "plus.circle")
            }

            Button {
                Task {
                    await startTunnel()
                }
            } label: {
                Label("연결", systemImage: "power")
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canStart)

            Button {
                Task {
                    await requestProviderDiagnostics()
                }
            } label: {
                Label("터널 상태 확인", systemImage: "waveform.path.ecg")
            }
            .disabled(status != .connected)

            Button {
                Task {
                    await refreshConnectedRoutePlan()
                }
            } label: {
                Label("경로 새로고침", systemImage: "arrow.clockwise")
            }
            .disabled(status != .connected)

            Button {
                stopTunnel()
            } label: {
                Label("연결 해제", systemImage: "stop.circle")
            }
            .disabled(!canStop)
        }
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

    @ViewBuilder
    private var failSafeWarning: some View {
        if !failSafeEnabled {
            Label(
                "만료 시 자동 연결 해제가 꺼져 있습니다.",
                systemImage: "shield.slash.fill"
            )
            .font(.callout)
            .foregroundStyle(.orange)
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

    private func placeholderView(title: String, systemImage: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            header(title: title, subtitle: message)
            ContentUnavailableView(title, systemImage: systemImage)
            Spacer()
        }
    }

    private var statusText: String {
        switch status {
        case .invalid:
            return "설치된 VPN 구성 없음"
        case .disconnected:
            return "연결 안 됨"
        case .connecting:
            return "연결 중"
        case .connected:
            return "연결됨"
        case .reasserting:
            return "경로 갱신 중"
        case .disconnecting:
            return "연결 해제 중"
        @unknown default:
            return "알 수 없는 상태"
        }
    }

    private var canStart: Bool {
        status == .disconnected
    }

    private var canStop: Bool {
        status == .connecting || status == .connected || status == .reasserting
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

    private func removeStatusObserver() {
        guard let statusObserver else {
            return
        }

        NotificationCenter.default.removeObserver(statusObserver)
        self.statusObserver = nil
    }

    private func loadProfiles() {
        do {
            let store = try ProfileStore()
            profiles = try store.loadProfiles().sorted { $0.updatedAt > $1.updatedAt }
            if selectedProfileId == nil,
               let manager,
               let installedProfileId = providerProfileId(for: manager),
               profiles.contains(where: { $0.id == installedProfileId }) {
                selectedProfileId = installedProfileId
            }
            importMessage = profiles.isEmpty ? "가져온 VPN 프로필이 없습니다." : "저장된 VPN 프로필을 불러왔습니다."
        } catch {
            importMessage = "VPN 프로필을 불러오지 못했습니다: \(error.localizedDescription)"
        }
    }

    private func loadFailSafeSetting() {
        failSafeEnabled = FailSafeSettingsStore().isEnabled
        settingsMessage = failSafeEnabled
            ? "만료 시 자동 연결 해제가 켜져 있습니다."
            : "만료 시 자동 연결 해제가 꺼져 있습니다."
    }

    private func updateFailSafeSetting(_ isEnabled: Bool) async {
        failSafeEnabled = isEnabled
        FailSafeSettingsStore().setEnabled(isEnabled)

        guard status == .connected,
              let session = manager?.connection as? NETunnelProviderSession else {
            settingsMessage = isEnabled
                ? "보호 기능을 켰습니다. 다음 연결부터 적용됩니다."
                : "보호 기능을 껐습니다. 다음 연결부터 적용됩니다."
            return
        }

        do {
            let request = TunnelFailSafeUpdateRequest(failSafeEnabled: isEnabled)
            let responseData = try await sendProviderMessage(
                try JSONEncoder().encode(request),
                through: session
            )
            guard
                let responseData,
                let response = try? JSONDecoder().decode(TunnelRouteUpdateResponse.self, from: responseData),
                response.success
            else {
                throw TunnelConfigurationError.unreadableRouteUpdateResponse
            }

            settingsMessage = isEnabled
                ? "보호 기능을 켰습니다. 현재 연결에도 바로 적용했습니다."
                : "보호 기능을 껐습니다. 현재 연결은 경로가 만료되어도 자동으로 끊기지 않습니다."
        } catch {
            settingsMessage = "설정은 저장했지만 현재 연결에는 적용하지 못했습니다: \(error.localizedDescription)"
        }
    }

    private func loadSiteDomainsForSelectedProfile() {
        do {
            let store = try DomainRuleStore()
            try migrateLegacyProfileSiteRulesIfNeeded(store: store)
            siteDomains = try store.loadRules(profileId: DomainRuleStore.sharedSiteRulesProfileId)
                .filter(\.enabled)
                .map { DomainRuleExpander.normalize($0.domain) }
                .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            routePlan = nil
            routePlanProfileId = nil
            siteMessage = siteDomains.isEmpty ? "VPN으로 보낼 사이트를 추가하세요." : "공통 VPN 사이트 \(siteDomains.count)개를 불러왔습니다."
        } catch {
            siteMessage = "VPN 사이트를 불러오지 못했습니다: \(error.localizedDescription)"
        }
    }

    private func migrateLegacyProfileSiteRulesIfNeeded(store: DomainRuleStore) throws {
        guard try store.loadRules(profileId: DomainRuleStore.sharedSiteRulesProfileId).isEmpty else {
            return
        }

        let legacyDomains = try store.loadRules()
            .filter { $0.profileId != DomainRuleStore.sharedSiteRulesProfileId && $0.enabled }
            .map { DomainRuleExpander.normalize($0.domain) }
        guard !legacyDomains.isEmpty else {
            return
        }

        _ = try DomainRoutePlanService(ruleStore: store).replaceRules(
            profileId: DomainRuleStore.sharedSiteRulesProfileId,
            domains: legacyDomains
        )
    }

    private func importConfigFile(_ result: Result<[URL], Error>) {
        do {
            guard let fileURL = try result.get().first else {
                importMessage = "선택한 WireGuard 설정 파일이 없습니다."
                return
            }

            try importProfile(from: fileURL)
        } catch {
            importMessage = "프로필을 가져오지 못했습니다: \(error.localizedDescription)"
        }
    }

    private func importProfile(from fileURL: URL) throws {
        let didStartAccessing = fileURL.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                fileURL.stopAccessingSecurityScopedResource()
            }
        }

        let configText = try String(contentsOf: fileURL, encoding: .utf8)
        let safeDisplayName = profileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? fileURL.deletingPathExtension().lastPathComponent
            : profileName
        let store = try ProfileStore()
        let service = ProfileImportService(profileStore: store)
        let profile = try service.importProfile(
            displayName: safeDisplayName,
            configText: configText
        )

        profiles = try store.loadProfiles().sorted { $0.updatedAt > $1.updatedAt }
        selectedProfileId = profile.id
        profileName = ""
        selectedConfigFileName = fileURL.lastPathComponent
        importMessage = "\(profile.displayName) 프로필을 가져왔습니다. 개인 키는 키체인에 저장했습니다."
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

            let profileStore = try ProfileStore()
            let remainingProfiles = try profileStore.deleteProfile(id: profile.id)
                .sorted { $0.updatedAt > $1.updatedAt }
            try KeychainSecretStore().deletePrivateKey(profileId: profile.id)

            profiles = remainingProfiles
            if selectedProfileId == profile.id {
                selectedProfileId = profiles.first?.id
            }
            if routePlanProfileId == profile.id {
                routePlan = nil
                routePlanProfileId = nil
            }
            profilePendingDeletion = nil
            loadSiteDomainsForSelectedProfile()
            importMessage = "\(profile.displayName) 프로필과 키체인 개인 키를 삭제했습니다. VPN 사이트 목록은 유지했습니다."
            lastMessage = "\(profile.displayName) 프로필을 삭제했습니다. VPN 사이트 목록은 다른 프로필에도 사용할 수 있습니다."
        } catch {
            importMessage = "프로필을 삭제하지 못했습니다: \(error.localizedDescription)"
        }
    }

    private func addSiteDomain() {
        guard let domain = normalizedSiteDomainInput else {
            siteMessage = "example.com과 같은 올바른 도메인을 입력하세요."
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
            let store = try DomainRuleStore()
            let service = DomainRoutePlanService(ruleStore: store)
            _ = try service.replaceRules(
                profileId: DomainRuleStore.sharedSiteRulesProfileId,
                domains: siteDomains
            )
            let plan = try service.buildPlan(profileId: DomainRuleStore.sharedSiteRulesProfileId)
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

    private func routePlanForInstall(profileId: ProfileMetadata.ID) throws -> DomainRoutePlan {
        let plan: DomainRoutePlan
        if let routePlan,
           routePlanProfileId == profileId,
           !DomainRouteRefreshPolicy.standard.needsRefresh(routePlan) {
            plan = routePlan
        } else {
            let store = try DomainRuleStore()
            try migrateLegacyProfileSiteRulesIfNeeded(store: store)
            let rules = try store.loadRules(profileId: DomainRuleStore.sharedSiteRulesProfileId)
            guard !rules.isEmpty else {
                throw TunnelConfigurationError.noRouteRules
            }

            plan = try DomainRoutePlanService(ruleStore: store).buildPlan(profileId: DomainRuleStore.sharedSiteRulesProfileId)
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
            let selectedRoutePlan = try routePlanForInstall(profileId: selectedProfile.id)
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

    private func startTunnel() async {
        do {
            var manager = try await loadOrCreateManager(preferPhase1: true)
            if let selectedProfile {
                let selectedRoutePlan = try routePlanForInstall(profileId: selectedProfile.id)
                let tunnelProtocol = try makeSelectedProfileProtocol(selectedProfile, routePlan: selectedRoutePlan)
                try await saveTunnelConfiguration(
                    manager: manager,
                    tunnelProtocol: tunnelProtocol,
                    successMessage: "\(selectedProfile.displayName) 프로필과 분할 경로 \(selectedRoutePlan.includedRoutes.count)개를 준비했습니다."
                )
                manager = self.manager ?? manager
            } else if providerMode(for: manager) != TunnelProviderModes.phase1WireGuard || providerRouteCount(for: manager) == 0 {
                throw TunnelConfigurationError.noSelectedProfile
            }

            try manager.connection.startVPNTunnel()
            status = manager.connection.status
            lastMessage = "VPN 연결을 요청했습니다. 경로 \(providerRouteCount(for: manager))개를 적용합니다."
            if let payload = providerPayload(for: manager), !payload.routePlan.ipv6BypassDomains.isEmpty {
                lastMessage += " 주의: 도메인 \(payload.routePlan.ipv6BypassDomains.count)개가 IPv6로 우회할 수 있습니다."
            }
        } catch {
            lastMessage = "VPN에 연결하지 못했습니다: \(error.localizedDescription)"
        }
    }

    private func stopTunnel() {
        manager?.connection.stopVPNTunnel()
        status = manager?.connection.status ?? .invalid
        lastMessage = "VPN 연결 해제를 요청했습니다."
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
                ? " 만료 시 자동 연결 해제: 꺼짐."
                : " 만료 시 자동 연결 해제: 켜짐."
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

        let store = try DomainRuleStore()
        let staticPlan = try DomainRoutePlanService(ruleStore: store)
            .buildPlan(profileId: DomainRuleStore.sharedSiteRulesProfileId)
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
            응답 전달 \(counts["responseDelivered", default: 0]), 전달 오류 \(counts["forwardingFailure", default: 0]).\(failureMessage)
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
        guard status == .connected, dnsProxyConfigurationController.isEnabled else {
            return
        }

        while !Task.isCancelled
                && status == .connected
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
        guard status == .connected else {
            return
        }

        let interval = DomainRouteRefreshPolicy.standard.refreshInterval
        let nanoseconds = UInt64(interval * 1_000_000_000)
        while !Task.isCancelled && status == .connected {
            do {
                try await Task.sleep(nanoseconds: nanoseconds)
            } catch {
                return
            }

            guard !Task.isCancelled && status == .connected else {
                return
            }
            await refreshConnectedRoutePlan()
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
            let store = try DomainRuleStore()
            let refreshedPlan = try DomainRoutePlanService(ruleStore: store)
                .buildPlan(profileId: DomainRuleStore.sharedSiteRulesProfileId)
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
            let gate = ProviderMessageContinuationGate(continuation)
            let timeout = DispatchWorkItem {
                gate.resume(throwing: TunnelConfigurationError.providerMessageTimedOut)
            }
            DispatchQueue.global(qos: .userInitiated).asyncAfter(
                deadline: .now() + 5,
                execute: timeout
            )
            do {
                try session.sendProviderMessage(message) { response in
                    timeout.cancel()
                    gate.resume(returning: response)
                }
            } catch {
                timeout.cancel()
                gate.resume(throwing: error)
            }
        }
    }
}

private final class ProviderMessageContinuationGate<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?

    init(_ continuation: CheckedContinuation<Value, Error>) {
        self.continuation = continuation
    }

    func resume(returning value: Value) {
        takeContinuation()?.resume(returning: value)
    }

    func resume(throwing error: Error) {
        takeContinuation()?.resume(throwing: error)
    }

    private func takeContinuation() -> CheckedContinuation<Value, Error>? {
        lock.lock()
        defer { lock.unlock() }
        let continuation = continuation
        self.continuation = nil
        return continuation
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

            List {
                Section("VPN으로 보내는 경로") {
                    ForEach(plan.includedRoutes.prefix(24), id: \.destinationAddress) { route in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(route.destinationAddress)/32")
                                .font(.system(.body, design: .monospaced))
                            Text(route.sourceDomain)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if !plan.unresolvedDomains.isEmpty {
                    Section("주소를 찾지 못한 도메인") {
                        ForEach(plan.unresolvedDomains.prefix(24), id: \.self) { domain in
                            Text(domain)
                                .font(.system(.body, design: .monospaced))
                        }
                    }
                }

                if !plan.ipv6BypassDomains.isEmpty {
                    Section("IPv6 우회 위험") {
                        ForEach(plan.ipv6BypassDomains.prefix(24), id: \.self) { domain in
                            Text(domain)
                                .font(.system(.body, design: .monospaced))
                        }
                    }
                }
            }
            .listStyle(.inset)
        }
    }
}

private struct DiagnosticMessageView: View {
    let message: String

    var body: some View {
        ScrollView {
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: 64, maxHeight: 140)
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
            return "진단"
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

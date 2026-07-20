import SwiftUI
import NetworkExtension
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var selectedSection: SidebarSection = .home
    @State private var status: NEVPNStatus = .invalid
    @State private var lastMessage = "No tunnel configuration loaded."
    @State private var manager: NETunnelProviderManager?
    @State private var statusObserver: NSObjectProtocol?
    @State private var profiles: [ProfileMetadata] = []
    @State private var profileName = ""
    @State private var selectedConfigFileName = "No file selected."
    @State private var isImportingConfigFile = false
    @State private var importMessage = "No imported profiles."
    @State private var selectedProfileId: ProfileMetadata.ID?
    @State private var profilePendingDeletion: ProfileMetadata?
    @State private var siteDomainInput = ""
    @State private var siteDomains: [String] = []
    @State private var siteMessage = "Select a profile and add domains to plan split routes."
    @State private var routePlan: DomainRoutePlan?
    @State private var routePlanProfileId: ProfileMetadata.ID?

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
            "Delete Profile",
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
            Button("Delete \(profile.displayName)", role: .destructive) {
                Task {
                    await deleteProfile(profile)
                }
            }
            Button("Cancel", role: .cancel) {
                profilePendingDeletion = nil
            }
        } message: { profile in
            Text("This removes the profile, its saved site rules, and its Keychain private key from this Mac.")
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
            placeholderView(
                title: "Settings",
                systemImage: "gearshape",
                message: "Signing, entitlements, and Network Extension capabilities are managed in Xcode."
            )
        }
    }

    private var homeView: some View {
        VStack(alignment: .leading, spacing: 24) {
            header(title: "VPN Router", subtitle: statusText)
            tunnelControls
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Text("Phase 1")
                    .font(.headline)
                Text("WireGuard import, local profile storage, and static split-route planning foundation.")
                    .foregroundStyle(.secondary)
                DiagnosticMessageView(message: lastMessage)
            }
            Spacer()
        }
    }

    private var profilesView: some View {
        HStack(alignment: .top, spacing: 28) {
            VStack(alignment: .leading, spacing: 16) {
                header(title: "VPN Profiles", subtitle: "Imported profiles: \(profiles.count)")

                VStack(alignment: .leading, spacing: 10) {
                    TextField("Profile name", text: $profileName)
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
                            Text("Choose a WireGuard .conf file. The private key is stored in Keychain.")
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
                            Label("Import File", systemImage: "folder")
                        }
                        .buttonStyle(.borderedProminent)

                        Button {
                            selectedConfigFileName = "No file selected."
                            profileName = ""
                        } label: {
                            Label("Clear", systemImage: "xmark.circle")
                        }
                        .disabled(selectedConfigFileName == "No file selected." && profileName.isEmpty)
                    }
                }

                Text(importMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(minWidth: 360, idealWidth: 420, maxWidth: 520, alignment: .topLeading)

            VStack(alignment: .leading, spacing: 14) {
                Text("Stored Profiles")
                    .font(.headline)

                if profiles.isEmpty {
                    ContentUnavailableView("No Profiles", systemImage: "doc.text.magnifyingglass")
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
                                .help("Delete \(profile.displayName)")
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
                            Label("Install Selected", systemImage: "arrow.down.doc")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(selectedProfile == nil)

                        Button(role: .destructive) {
                            if let selectedProfile {
                                profilePendingDeletion = selectedProfile
                            }
                        } label: {
                            Label("Delete Selected", systemImage: "trash")
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
                    title: "VPN Sites",
                    subtitle: selectedProfile.map { "Shared sites, currently previewing routes for \($0.displayName)" } ?? "Shared sites for whichever profile you connect"
                )

                HStack(spacing: 10) {
                    TextField("example.com", text: $siteDomainInput)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(addSiteDomain)

                    Button {
                        addSiteDomain()
                    } label: {
                        Label("Add Site", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(normalizedSiteDomainInput == nil)
                }

                if siteDomains.isEmpty {
                    ContentUnavailableView("No Sites", systemImage: "globe.badge.chevron.backward")
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
                                .help("Remove \(domain)")
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
                        Label("Build Plan", systemImage: "point.3.connected.trianglepath.dotted")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedProfile == nil || siteDomains.isEmpty)

                    Button {
                        siteDomains.removeAll()
                        routePlan = nil
                        routePlanProfileId = nil
                        siteMessage = "Cleared pending site rules."
                    } label: {
                        Label("Clear", systemImage: "xmark.circle")
                    }
                    .disabled(siteDomains.isEmpty)
                }

                Text(siteMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(minWidth: 360, idealWidth: 420, maxWidth: 520, alignment: .topLeading)

            VStack(alignment: .leading, spacing: 14) {
                Text("Route Plan")
                    .font(.headline)

                if let routePlan, routePlanProfileId == selectedProfile?.id {
                    RoutePlanSummary(plan: routePlan)
                } else {
                    ContentUnavailableView("No Route Plan", systemImage: "map")
                }
            }
            .frame(minWidth: 280, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var diagnosticsView: some View {
        VStack(alignment: .leading, spacing: 24) {
            header(title: "Diagnostics", subtitle: statusText)
            tunnelControls
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Text("Provider")
                    .font(.headline)
                DiagnosticMessageView(message: lastMessage)
            }
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
                Label("Install Stub", systemImage: "plus.circle")
            }

            Button {
                Task {
                    await startTunnel()
                }
            } label: {
                Label("Connect", systemImage: "power")
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canStart)

            Button {
                Task {
                    await requestProviderDiagnostics()
                }
            } label: {
                Label("Check Provider", systemImage: "waveform.path.ecg")
            }
            .disabled(status != .connected)

            Button {
                stopTunnel()
            } label: {
                Label("Disconnect", systemImage: "stop.circle")
            }
            .disabled(!canStop)
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
            return "No installed tunnel configuration"
        case .disconnected:
            return "Disconnected"
        case .connecting:
            return "Connecting"
        case .connected:
            return "Connected"
        case .reasserting:
            return "Reasserting"
        case .disconnecting:
            return "Disconnecting"
        @unknown default:
            return "Unknown"
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
            importMessage = profiles.isEmpty ? "No imported profiles." : "Loaded imported profile metadata."
        } catch {
            importMessage = "Unable to load profiles: \(error.localizedDescription)"
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
            siteMessage = siteDomains.isEmpty ? "Add domains to plan split routes." : "Loaded \(siteDomains.count) shared site rule(s)."
        } catch {
            siteMessage = "Unable to load site rules: \(error.localizedDescription)"
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
                importMessage = "No WireGuard config file was selected."
                return
            }

            try importProfile(from: fileURL)
        } catch {
            importMessage = "Import failed: \(error.localizedDescription)"
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
        importMessage = "Imported \(profile.displayName). Private key stored in Keychain."
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
            importMessage = "Deleted \(profile.displayName). Profile and Keychain secret were removed. Shared site rules were kept."
            lastMessage = "Deleted \(profile.displayName). Shared site rules are still available for another profile."
        } catch {
            importMessage = "Delete failed: \(error.localizedDescription)"
        }
    }

    private func addSiteDomain() {
        guard let domain = normalizedSiteDomainInput else {
            siteMessage = "Enter a valid domain such as example.com."
            return
        }

        siteDomains.append(domain)
        siteDomains.sort { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        siteDomainInput = ""
        routePlan = nil
        routePlanProfileId = nil
        siteMessage = "Added \(domain)."
    }

    private func removeSiteDomain(_ domain: String) {
        siteDomains.removeAll { $0.caseInsensitiveCompare(domain) == .orderedSame }
        routePlan = nil
        routePlanProfileId = nil
        siteMessage = "Removed \(domain)."
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
            siteMessage = "Select an imported profile first."
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
                siteMessage = "Saved \(siteDomains.count) site rule(s), but no IPv4 routes were resolved yet."
            } else if plan.unresolvedDomains.isEmpty {
                siteMessage = "Built \(plan.includedRoutes.count) IPv4 /32 routes for \(plan.domains.count) expanded domains."
            } else {
                siteMessage = "Built \(plan.includedRoutes.count) IPv4 /32 routes. \(plan.unresolvedDomains.count) domain(s) had no IPv4 answer yet."
            }
        } catch {
            siteMessage = "Route planning failed: \(error.localizedDescription)"
        }
    }

    private func routePlanForInstall(profileId: ProfileMetadata.ID) throws -> DomainRoutePlan {
        let plan: DomainRoutePlan
        if let routePlan, routePlanProfileId == profileId {
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
            lastMessage = "Loaded Network Extension status from NEVPNStatus."
        } catch {
            status = .invalid
            lastMessage = "Unable to load tunnel configuration: \(error.localizedDescription)"
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
                successMessage: "Installed stub Packet Tunnel configuration."
            )
        } catch {
            lastMessage = "Failed to install stub configuration: \(error.localizedDescription)"
        }
    }

    private func installSelectedProfileConfiguration() async {
        guard let selectedProfile else {
            importMessage = "Select an imported profile first."
            return
        }

        do {
            let selectedRoutePlan = try routePlanForInstall(profileId: selectedProfile.id)
            let tunnelProtocol = try makeSelectedProfileProtocol(selectedProfile, routePlan: selectedRoutePlan)
            let manager = try await loadOrCreateManager(preferPhase1: true)

            try await saveTunnelConfiguration(
                manager: manager,
                tunnelProtocol: tunnelProtocol,
                successMessage: "Installed \(selectedProfile.displayName) with \(selectedRoutePlan.includedRoutes.count) split route(s)."
            )
            importMessage = "Installed \(selectedProfile.displayName) with \(selectedRoutePlan.includedRoutes.count) route(s). Connect will start WireGuardKit."
        } catch {
            importMessage = "Install failed: \(error.localizedDescription)"
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
                    successMessage: "Prepared \(selectedProfile.displayName) with \(selectedRoutePlan.includedRoutes.count) split route(s)."
                )
                manager = self.manager ?? manager
            } else if providerMode(for: manager) != TunnelProviderModes.phase1WireGuard || providerRouteCount(for: manager) == 0 {
                throw TunnelConfigurationError.noSelectedProfile
            }

            try manager.connection.startVPNTunnel()
            status = manager.connection.status
            lastMessage = "Start requested through NETunnelProviderManager using \(providerMode(for: manager) ?? "unknown") mode with \(providerRouteCount(for: manager)) route(s)."
        } catch {
            lastMessage = "Failed to start tunnel: \(error.localizedDescription)"
        }
    }

    private func stopTunnel() {
        manager?.connection.stopVPNTunnel()
        status = manager?.connection.status ?? .invalid
        lastMessage = "Stop requested through NEVPNConnection."
    }

    private func requestProviderDiagnostics() async {
        guard let session = manager?.connection as? NETunnelProviderSession else {
            lastMessage = "No active Packet Tunnel provider session is available."
            return
        }

        do {
            let response = try await sendProviderMessage(Data(), through: session)
            guard
                let response,
                let diagnostics = try? JSONDecoder().decode(TunnelDiagnostics.self, from: response)
            else {
                lastMessage = "Provider responded without readable diagnostics."
                return
            }

            lastMessage = "Provider reachable: \(diagnostics.providerState), routes: \(diagnostics.plannedRouteCount). \(diagnostics.message)"
        } catch {
            lastMessage = "Provider diagnostics failed: \(error.localizedDescription)"
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
        guard
            let tunnelProtocol = manager.protocolConfiguration as? NETunnelProviderProtocol,
            let payloadData = tunnelProtocol.providerConfiguration?[TunnelProviderConfigurationKeys.payload] as? Data,
            let payload = try? JSONDecoder().decode(TunnelProfileProviderConfiguration.self, from: payloadData)
        else {
            return 0
        }

        return payload.routePlan.includedRoutes.count
    }

    private func providerProfileId(for manager: NETunnelProviderManager) -> ProfileMetadata.ID? {
        guard let tunnelProtocol = manager.protocolConfiguration as? NETunnelProviderProtocol else {
            return nil
        }

        if
            let payloadData = tunnelProtocol.providerConfiguration?[TunnelProviderConfigurationKeys.payload] as? Data,
            let payload = try? JSONDecoder().decode(TunnelProfileProviderConfiguration.self, from: payloadData) {
            return payload.profileId
        }

        guard let profileId = tunnelProtocol.providerConfiguration?[TunnelProviderConfigurationKeys.profileId] as? String else {
            return nil
        }

        return UUID(uuidString: profileId)
    }

    private func sendProviderMessage(
        _ message: Data,
        through session: NETunnelProviderSession
    ) async throws -> Data? {
        try await withCheckedThrowingContinuation { continuation in
            do {
                try session.sendProviderMessage(message) { response in
                    continuation.resume(returning: response)
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
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
            }
            .font(.callout)
            .foregroundStyle(.secondary)

            List {
                Section("Included Routes") {
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
                    Section("Unresolved Domains") {
                        ForEach(plan.unresolvedDomains.prefix(24), id: \.self) { domain in
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
            return "Home"
        case .profiles:
            return "VPN Profiles"
        case .sites:
            return "VPN Sites"
        case .diagnostics:
            return "Diagnostics"
        case .settings:
            return "Settings"
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
    let wireGuardKitLinked: Bool
    let message: String
    let updatedAt: Date
}

enum TunnelConfigurationError: LocalizedError {
    case noSelectedProfile
    case noRouteRules
    case emptyRoutePlan(unresolvedCount: Int)

    var errorDescription: String? {
        switch self {
        case .noSelectedProfile:
            return "Select and install an imported profile before connecting."
        case .noRouteRules:
            return "Add at least one site and build a route plan before installing or connecting."
        case .emptyRoutePlan(let unresolvedCount):
            return "The route plan has no IPv4 routes (\(unresolvedCount) unresolved domain(s)). Add a resolvable site or rebuild the plan before connecting."
        }
    }
}

enum TunnelIdentifiers {
    nonisolated static var packetTunnelBundleIdentifier: String {
        guard let appBundleIdentifier = Bundle.main.bundleIdentifier else {
            return "VPNRouter.PacketTunnel"
        }

        return "\(appBundleIdentifier).PacketTunnel"
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

using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Diagnostics;
using System.Threading;
using System.Threading.Tasks;
using VpnRouter.Core.Rules;
using VpnRouter.Ipc.Contracts;
using VpnRouter.Ipc.NamedPipes;
using VpnRouter.Vpn.WireGuard;
using Windows.Storage.Pickers;
using WinRT.Interop;

namespace VpnRouter;

public sealed partial class MainWindow : Window
{
    private readonly VpnRouterPipeClient _pipeClient = new();
    private bool _isConnected;
    private bool _isRefreshingProfiles;

    public MainWindow()
    {
        InitializeComponent();
        AppWindow.Resize(new Windows.Graphics.SizeInt32(1120, 780));
        RefreshWireGuardInstallStatus();
        _ = RefreshConnectionStateAsync(false);
        _ = RefreshProfilesAsync(null, false);
        _ = RefreshDiagnosticsAsync(false);
    }

    private void MainNavigation_SelectionChanged(NavigationView sender, NavigationViewSelectionChangedEventArgs args)
    {
        var selectedTag = (args.SelectedItemContainer as NavigationViewItem)?.Tag?.ToString() ?? "home";
        HomePanel.Visibility = selectedTag == "home" ? Visibility.Visible : Visibility.Collapsed;
        ProfilesPanel.Visibility = selectedTag == "profiles" ? Visibility.Visible : Visibility.Collapsed;
        SitesPanel.Visibility = selectedTag == "sites" ? Visibility.Visible : Visibility.Collapsed;
        DiagnosticsPanel.Visibility = selectedTag == "diagnostics" ? Visibility.Visible : Visibility.Collapsed;
        SettingsPanel.Visibility = selectedTag == "settings" ? Visibility.Visible : Visibility.Collapsed;
    }

    private async void ConnectButton_Click(object sender, Microsoft.UI.Xaml.RoutedEventArgs e)
    {
        ConnectButton.IsEnabled = false;
        try
        {
            var profileId = GetSelectedProfileId();
            if (profileId is null)
            {
                AppendRecentStatus("연결하기 전에 WireGuard 프로필을 가져오세요.");
                return;
            }

            var rules = BuildDomainRules(profileId.Value);
            var command = _isConnected ? IpcCommandKind.Disconnect : IpcCommandKind.Connect;
            var payload = _isConnected
                ? new DisconnectRequest(profileId.Value)
                : (object)new ConnectRequest(profileId.Value, rules, ProtectionModeToggle.IsOn);

            var response = await _pipeClient.SendAsync(command, payload, TimeSpan.FromSeconds(30), CancellationToken.None);
            if (!response.Success)
            {
                AppendRecentStatus($"{(_isConnected ? "연결 끊기" : "연결")} 실패: {response.Message}");
                return;
            }

            _isConnected = !_isConnected;
            AppendRecentStatus(response.Message);
            await RefreshConnectionStateAsync(true);
            await RefreshDiagnosticsAsync(false);
        }
        catch (Exception ex)
        {
            AppendRecentStatus($"서비스에 연결할 수 없습니다: {ex.Message}");
        }
        finally
        {
            ConnectButton.IsEnabled = true;
        }
    }

    private async void AddDomainButton_Click(object sender, Microsoft.UI.Xaml.RoutedEventArgs e)
    {
        var domain = NormalizeDomain(DomainTextBox.Text);
        if (string.IsNullOrWhiteSpace(domain))
        {
            AppendRecentStatus("example.com 같은 사이트 주소를 입력하세요.");
            return;
        }

        if (GetDomainListItems().Any(item => string.Equals(item, domain, StringComparison.OrdinalIgnoreCase)))
        {
            AppendRecentStatus($"{domain}은 이미 목록에 있습니다.");
            return;
        }

        AddDomainListItem(domain);
        DomainTextBox.Text = string.Empty;
        AppendRecentStatus($"{domain}을 VPN 사이트 목록에 추가했습니다.");
        await SaveCurrentDomainRulesAsync(true);
    }

    private async void ValidateConnectionPlanButton_Click(object sender, Microsoft.UI.Xaml.RoutedEventArgs e)
    {
        ValidateConnectionPlanButton.IsEnabled = false;
        try
        {
            var profileId = GetSelectedProfileId();
            if (profileId is null)
            {
                AppendRecentStatus("연결 전 점검을 하려면 WireGuard 프로필을 먼저 선택하세요.");
                return;
            }

            var response = await _pipeClient.SendAsync(
                IpcCommandKind.ValidateConnectionPlan,
                new ValidateConnectionPlanRequest(profileId.Value, BuildDomainRules(profileId.Value), ProtectionModeToggle.IsOn),
                TimeSpan.FromSeconds(10),
                CancellationToken.None);

            if (!response.Success || response.Payload is null)
            {
                AppendRecentStatus($"연결 전 점검 실패: {response.Message}");
                return;
            }

            var result = response.Payload.Value.Deserialize<ValidateConnectionPlanResponse>(VpnRouterIpcJson.Options);
            if (result is null)
            {
                AppendRecentStatus("연결 전 점검 결과를 읽을 수 없습니다.");
                return;
            }

            AppendRecentStatus(result.CanConnect ? "연결 전 점검 통과" : "연결 전 점검에 경고가 있습니다.");
            foreach (var warning in result.Warnings.Take(4).Reverse())
            {
                AppendRecentStatus($"점검 경고: {warning}");
            }

            foreach (var check in result.Checks.Take(4).Reverse())
            {
                AppendRecentStatus($"점검 확인: {check}");
            }
        }
        catch (Exception ex)
        {
            AppendRecentStatus($"연결 전 점검 실패: {ex.Message}");
        }
        finally
        {
            ValidateConnectionPlanButton.IsEnabled = true;
        }
    }

    private async void RemoveDomainButton_Click(object sender, Microsoft.UI.Xaml.RoutedEventArgs e)
    {
        if (sender is Button { Tag: string domain })
        {
            var target = DomainRulesList.Items
                .OfType<ListViewItem>()
                .FirstOrDefault(item => item.Tag is string itemDomain && string.Equals(itemDomain, domain, StringComparison.OrdinalIgnoreCase));

            if (target is not null)
            {
                DomainRulesList.Items.Remove(target);
                AppendRecentStatus($"{domain}을 VPN 사이트 목록에서 제거했습니다.");
                await SaveCurrentDomainRulesAsync(true);
            }
        }
    }

    private async void RenameProfileButton_Click(object sender, Microsoft.UI.Xaml.RoutedEventArgs e)
    {
        var profileId = GetSelectedProfileId();
        var name = ProfileNameTextBox.Text.Trim();
        if (profileId is null || string.IsNullOrWhiteSpace(name))
        {
            AppendRecentStatus("이름을 변경할 프로필과 새 이름을 확인하세요.");
            return;
        }

        try
        {
            var response = await _pipeClient.SendAsync(
                IpcCommandKind.RenameProfile,
                new RenameProfileRequest(profileId.Value, name),
                TimeSpan.FromSeconds(3),
                CancellationToken.None);

            AppendRecentStatus(response.Success ? "프로필 이름을 변경했습니다." : $"프로필 이름 변경 실패: {response.Message}");
            if (response.Success)
            {
                await RefreshProfilesAsync(profileId.Value, true);
            }
        }
        catch (Exception ex)
        {
            AppendRecentStatus($"서비스에 연결할 수 없습니다: {ex.Message}");
        }
    }

    private async void DeleteProfileButton_Click(object sender, Microsoft.UI.Xaml.RoutedEventArgs e)
    {
        var profileId = GetSelectedProfileId();
        if (profileId is null)
        {
            AppendRecentStatus("삭제할 프로필이 없습니다.");
            return;
        }

        try
        {
            var response = await _pipeClient.SendAsync(
                IpcCommandKind.DeleteProfile,
                new DeleteProfileRequest(profileId.Value),
                TimeSpan.FromSeconds(3),
                CancellationToken.None);

            AppendRecentStatus(response.Success ? "프로필을 삭제했습니다." : $"프로필 삭제 실패: {response.Message}");
            if (response.Success)
            {
                await RefreshProfilesAsync(null, true);
                await RefreshDiagnosticsAsync(false);
            }
        }
        catch (Exception ex)
        {
            AppendRecentStatus($"서비스에 연결할 수 없습니다: {ex.Message}");
        }
    }

    private async void RestoreNetworkButton_Click(object sender, Microsoft.UI.Xaml.RoutedEventArgs e)
    {
        try
        {
            var response = await _pipeClient.SendAsync(
                IpcCommandKind.RestoreNetwork,
                new RestoreNetworkRequest("사용자가 네트워크 설정 복구를 눌렀습니다."),
                TimeSpan.FromSeconds(3),
                CancellationToken.None);

            AppendRecentStatus(response.Success ? response.Message : $"복구 실패: {response.Message}");
            if (response.Success)
            {
                await RefreshConnectionStateAsync(true);
                await RefreshDiagnosticsAsync(false);
            }
        }
        catch (Exception ex)
        {
            AppendRecentStatus($"서비스에 연결할 수 없습니다: {ex.Message}");
        }
    }

    private async void ImportWireGuardButton_Click(object sender, Microsoft.UI.Xaml.RoutedEventArgs e)
    {
        try
        {
            var picker = new FileOpenPicker();
            picker.FileTypeFilter.Add(".conf");
            picker.FileTypeFilter.Add(".txt");
            InitializeWithWindow.Initialize(picker, WindowNative.GetWindowHandle(this));

            var file = await picker.PickSingleFileAsync();
            if (file is null) return;

            var configText = await File.ReadAllTextAsync(file.Path);
            var importResult = new WireGuardConfigParser().PrepareImport(configText);
            var profileName = Path.GetFileNameWithoutExtension(file.Name);
            var response = await _pipeClient.SendAsync(
                IpcCommandKind.ImportWireGuardProfile,
                new ImportWireGuardProfileRequest(profileName, configText),
                TimeSpan.FromSeconds(5),
                CancellationToken.None);

            if (!response.Success)
            {
                AppendRecentStatus($"가져오기 실패: {response.Message}");
                return;
            }

            var imported = response.Payload?.Deserialize<ImportWireGuardProfileResponse>(VpnRouterIpcJson.Options);
            ProfileDetailsText.Text =
                $"피어 {imported?.PeerCount ?? importResult.Summary.PeerCount}개, " +
                $"주소 {imported?.InterfaceAddresses.Count ?? importResult.Summary.InterfaceAddresses.Count}개, " +
                $"DNS 서버 {imported?.DnsServers.Count ?? importResult.Summary.DnsServers.Count}개를 저장했습니다. 개인 키는 Windows로 암호화됩니다.";

            AppendRecentStatus(response.Message);
            await RefreshProfilesAsync(imported?.ProfileId, true);
            await SaveCurrentDomainRulesAsync(false);
            await RefreshDiagnosticsAsync(false);
        }
        catch (WireGuardConfigException ex)
        {
            AppendRecentStatus($"WireGuard 설정이 올바르지 않습니다: {ex.Message}");
        }
        catch (Exception ex)
        {
            AppendRecentStatus($"가져오기 실패: {ex.Message}");
        }
    }

    private void InstallWireGuardButton_Click(object sender, Microsoft.UI.Xaml.RoutedEventArgs e)
    {
        RefreshWireGuardInstallStatus();

        try
        {
            Process.Start(new ProcessStartInfo
            {
                FileName = "https://www.wireguard.com/install/",
                UseShellExecute = true
            });
            AppendRecentStatus("WireGuard는 별도 설치가 필요합니다. 공식 설치 페이지를 열었습니다.");
        }
        catch (Exception ex)
        {
            AppendRecentStatus($"WireGuard 설치 페이지를 열 수 없습니다: {ex.Message}");
        }
    }

    private void RefreshWireGuardInstallStatus()
    {
        var installation = WireGuardInstallationDetector.Detect();
        WireGuardInstallStatusText.Text = installation.IsInstalled
            ? $"WireGuard 별도 설치 확인됨: {installation.ExecutablePath}"
            : "WireGuard는 이 앱에 포함되지 않습니다. WireGuard for Windows를 별도로 설치한 뒤 사용하세요.";
        InstallWireGuardButton.Content = installation.IsInstalled ? "WireGuard 공식 페이지 열기" : "WireGuard 별도 설치 안내";
    }

    private async void RefreshDiagnosticsButton_Click(object sender, Microsoft.UI.Xaml.RoutedEventArgs e) => await RefreshDiagnosticsAsync(true);

    private async void CreateTroubleshootingFileButton_Click(object sender, Microsoft.UI.Xaml.RoutedEventArgs e)
    {
        try
        {
            var response = await _pipeClient.SendAsync(IpcCommandKind.CreateTroubleshootingFile, new { }, TimeSpan.FromSeconds(3), CancellationToken.None);
            if (!response.Success || response.Payload is null)
            {
                AppendRecentStatus($"문제 해결 파일 생성 실패: {response.Message}");
                return;
            }

            var result = response.Payload.Value.Deserialize<TroubleshootingFileResponse>(VpnRouterIpcJson.Options);
            AppendRecentStatus($"문제 해결 파일을 만들었습니다: {result?.FilePath}");
        }
        catch (Exception ex)
        {
            AppendRecentStatus($"서비스에 연결할 수 없습니다: {ex.Message}");
        }
    }

    private async void ProfileComboBox_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_isRefreshingProfiles) return;
        if (GetSelectedProfileId() is { } profileId)
        {
            ProfileNameTextBox.Text = GetSelectedProfileName() ?? string.Empty;
            UpdateSelectedProfileDetails(ProfileComboBox.Items.OfType<ProfileComboBoxItem>().Count());
            await RefreshDomainRulesAsync(profileId, true);
        }
    }

    private async Task RefreshConnectionStateAsync(bool showOfflineMessage)
    {
        try
        {
            var response = await _pipeClient.SendAsync(IpcCommandKind.GetConnectionState, new { }, TimeSpan.FromSeconds(2), CancellationToken.None);
            if (!response.Success || response.Payload is null)
            {
                if (showOfflineMessage) AppendRecentStatus($"상태 새로고침 실패: {response.Message}");
                return;
            }

            var state = response.Payload.Value.Deserialize<ConnectionStateDto>(VpnRouterIpcJson.Options);
            if (state is not null) ApplyConnectionState(state);
        }
        catch (Exception ex)
        {
            if (showOfflineMessage) AppendRecentStatus($"서비스에 연결할 수 없습니다: {ex.Message}");
        }
    }

    private async Task RefreshProfilesAsync(Guid? selectProfileId, bool showOfflineMessage)
    {
        try
        {
            var response = await _pipeClient.SendAsync(IpcCommandKind.ListProfiles, new { }, TimeSpan.FromSeconds(2), CancellationToken.None);
            if (!response.Success || response.Payload is null)
            {
                if (showOfflineMessage) AppendRecentStatus($"프로필 새로고침 실패: {response.Message}");
                return;
            }

            var profiles = response.Payload.Value.Deserialize<ListProfilesResponse>(VpnRouterIpcJson.Options);
            if (profiles is null) return;

            _isRefreshingProfiles = true;
            ProfileComboBox.Items.Clear();
            foreach (var profile in profiles.Profiles)
            {
                ProfileComboBox.Items.Add(new ProfileComboBoxItem(profile.Id, profile.Name, $"WireGuard - {profile.Name}", profile.Endpoints));
            }

            if (ProfileComboBox.Items.Count == 0)
            {
                ProfileComboBox.Items.Add(new ComboBoxItem { Content = "WireGuard 프로필을 가져오세요..." });
                ProfileComboBox.SelectedIndex = 0;
                ProfileNameTextBox.Text = string.Empty;
                ProfileDetailsText.Text = "저장된 프로필이 없습니다. 계속하려면 .conf 파일을 가져오세요.";
                DomainRulesList.Items.Clear();
                _isRefreshingProfiles = false;
                return;
            }

            var selectedIndex = 0;
            if (selectProfileId is not null)
            {
                for (var i = 0; i < ProfileComboBox.Items.Count; i++)
                {
                    if (ProfileComboBox.Items[i] is ProfileComboBoxItem item && item.Id == selectProfileId.Value)
                    {
                        selectedIndex = i;
                        break;
                    }
                }
            }

            ProfileComboBox.SelectedIndex = selectedIndex;
            ProfileNameTextBox.Text = GetSelectedProfileName() ?? string.Empty;
            UpdateSelectedProfileDetails(ProfileComboBox.Items.Count);
            _isRefreshingProfiles = false;

            if (GetSelectedProfileId() is { } selectedProfileId)
            {
                await RefreshDomainRulesAsync(selectedProfileId, false);
            }
        }
        catch (Exception ex)
        {
            _isRefreshingProfiles = false;
            if (showOfflineMessage) AppendRecentStatus($"서비스에 연결할 수 없습니다: {ex.Message}");
        }
    }

    private async Task RefreshDomainRulesAsync(Guid profileId, bool showOfflineMessage)
    {
        try
        {
            var response = await _pipeClient.SendAsync(IpcCommandKind.ListDomainRules, new ListDomainRulesRequest(profileId), TimeSpan.FromSeconds(2), CancellationToken.None);
            if (!response.Success || response.Payload is null)
            {
                if (showOfflineMessage) AppendRecentStatus($"사이트 목록 새로고침 실패: {response.Message}");
                return;
            }

            var result = response.Payload.Value.Deserialize<ListDomainRulesResponse>(VpnRouterIpcJson.Options);
            DomainRulesList.Items.Clear();
            foreach (var rule in result?.Rules ?? [])
            {
                AddDomainListItem(rule.Domain);
            }

            if (DomainRulesList.Items.Count == 0)
            {
                AddDomainListItem("youtube.com");
                AddDomainListItem("netflix.com");
            }
        }
        catch (Exception ex)
        {
            if (showOfflineMessage) AppendRecentStatus($"서비스에 연결할 수 없습니다: {ex.Message}");
        }
    }

    private async Task SaveCurrentDomainRulesAsync(bool showOfflineMessage)
    {
        if (GetSelectedProfileId() is not { } profileId) return;

        try
        {
            var rules = BuildDomainRules(profileId);
            var response = await _pipeClient.SendAsync(IpcCommandKind.SaveDomainRules, new SaveDomainRulesRequest(profileId, rules), TimeSpan.FromSeconds(2), CancellationToken.None);
            if (!response.Success && showOfflineMessage) AppendRecentStatus($"사이트 목록 저장 실패: {response.Message}");
        }
        catch (Exception ex)
        {
            if (showOfflineMessage) AppendRecentStatus($"서비스에 연결할 수 없습니다: {ex.Message}");
        }
    }

    private async Task RefreshDiagnosticsAsync(bool showOfflineMessage)
    {
        try
        {
            var response = await _pipeClient.SendAsync(IpcCommandKind.GetDiagnostics, new { }, TimeSpan.FromSeconds(2), CancellationToken.None);
            if (!response.Success || response.Payload is null)
            {
                if (showOfflineMessage) AppendRecentStatus($"진단 새로고침 실패: {response.Message}");
                return;
            }

            var diagnostics = response.Payload.Value.Deserialize<DiagnosticsDto>(VpnRouterIpcJson.Options);
            if (diagnostics is not null) ApplyDiagnostics(diagnostics);
        }
        catch (Exception ex)
        {
            DiagnosticsList.Items.Clear();
            AddDiagnosticLine($"서비스 상태: 연결 안 됨 ({ex.Message})");
            ConnectionStateText.Text = "서비스 연결 안 됨";
            ConnectionDetailsText.Text = "개발 중에는 서비스 실행 스크립트를 먼저 실행한 뒤 앱을 다시 시도하세요.";
            ProfileDetailsText.Text = "서비스가 실행 중이어야 프로필과 사이트 목록을 불러올 수 있습니다.";
            ConnectButton.IsEnabled = false;
            ValidateConnectionPlanButton.IsEnabled = false;
            FeatureFlagsText.Text = "실험 기능 상태: 서비스 연결 필요";
            if (showOfflineMessage) AppendRecentStatus($"서비스에 연결할 수 없습니다: {ex.Message}");
        }
    }

    private void AddDomainListItem(string domain)
    {
        var panel = new Grid { ColumnSpacing = 8 };
        panel.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        panel.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

        var text = new TextBlock { Text = domain, VerticalAlignment = Microsoft.UI.Xaml.VerticalAlignment.Center };
        var button = new Button
        {
            Content = new SymbolIcon { Symbol = Symbol.Delete },
            Tag = domain,
            Width = 36,
            Height = 36,
            Padding = new Thickness(0)
        };
        ToolTipService.SetToolTip(button, $"{domain} 삭제");
        button.Click += RemoveDomainButton_Click;
        Grid.SetColumn(button, 1);

        panel.Children.Add(text);
        panel.Children.Add(button);
        DomainRulesList.Items.Add(new ListViewItem
        {
            Content = panel,
            Tag = domain,
            HorizontalContentAlignment = Microsoft.UI.Xaml.HorizontalAlignment.Stretch
        });
    }

    private IEnumerable<string> GetDomainListItems()
    {
        return DomainRulesList.Items
            .OfType<ListViewItem>()
            .Select(item => item.Tag?.ToString() ?? string.Empty)
            .Where(domain => !string.IsNullOrWhiteSpace(domain));
    }

    private void ApplyDiagnostics(DiagnosticsDto diagnostics)
    {
        RefreshWireGuardInstallStatus();
        DiagnosticsList.Items.Clear();
        AddDiagnosticLine("서비스 상태: 연결됨");
        AddDiagnosticLine($"WireGuard: {(diagnostics.WireGuardInstalled ? "설치됨" : "설치 안 됨")} - {diagnostics.WireGuardMessage}");
        AddDiagnosticLine($"저장된 프로필: {diagnostics.ProfileCount}개");
        AddDiagnosticLine($"네트워크 스냅샷: {(diagnostics.NetworkSnapshotExists ? "있음" : "없음")}");
        AddDiagnosticLine($"라우트 계획 파일: {(diagnostics.ManagedRoutesExists ? "있음" : "없음")}");
        AddDiagnosticLine($"DNS 관찰 로그: {(diagnostics.DnsObservationsExists ? "있음" : "없음")}");
        AddDiagnosticLine($"실제 WireGuard 실행: {(diagnostics.EnableWireGuardActivation ? "켜짐" : "꺼짐")}");
        AddDiagnosticLine($"실제 DNS 변경: {(diagnostics.EnableWindowsDnsMutation ? "켜짐" : "꺼짐")}");
        AddDiagnosticLine($"실제 라우트 변경: {(diagnostics.EnableWindowsRouteMutation ? "켜짐" : "꺼짐")}");
        FeatureFlagsText.Text =
            $"실험 기능: WireGuard 실행 {(diagnostics.EnableWireGuardActivation ? "켜짐" : "꺼짐")} / " +
            $"DNS 변경 {(diagnostics.EnableWindowsDnsMutation ? "켜짐" : "꺼짐")} / " +
            $"라우트 변경 {(diagnostics.EnableWindowsRouteMutation ? "켜짐" : "꺼짐")}";
        ConnectButton.IsEnabled = true;
        ValidateConnectionPlanButton.IsEnabled = true;
    }

    private void AddDiagnosticLine(string message) => DiagnosticsList.Items.Add(new TextBlock { Text = $"- {message}", TextWrapping = TextWrapping.Wrap });

    private void ApplyConnectionState(ConnectionStateDto state)
    {
        _isConnected = state.State is ConnectionStateKind.Connected or ConnectionStateKind.Connecting;
        ConnectionStateText.Text = state.State switch
        {
            ConnectionStateKind.Connected => "연결됨",
            ConnectionStateKind.Connecting => "연결 중",
            ConnectionStateKind.Disconnecting => "연결 끊는 중",
            ConnectionStateKind.RestoringNetwork => "네트워크 설정 복구 중",
            ConnectionStateKind.Failed => "확인 필요",
            _ => "연결 안 됨"
        };
        ConnectionDetailsText.Text = state.State switch
        {
            ConnectionStateKind.Connected => "선택한 사이트가 VPN으로 열리도록 설정되어 있습니다.",
            ConnectionStateKind.Connecting => "선택한 사이트가 VPN을 사용하도록 준비 중입니다.",
            ConnectionStateKind.Disconnecting => "선택한 사이트를 일반 인터넷으로 되돌리는 중입니다.",
            ConnectionStateKind.RestoringNetwork => "DNS와 라우트 설정을 복구하는 중입니다.",
            ConnectionStateKind.Failed => "서비스에서 문제가 보고되었습니다. 최근 상태를 확인하세요.",
            _ => "연결하면 선택한 사이트만 VPN을 사용합니다."
        };
        ConnectButton.Content = _isConnected ? "연결 끊기" : "연결";
        RecentStatusList.Items.Clear();
        foreach (var message in state.RecentMessages)
        {
            RecentStatusList.Items.Add(new TextBlock { Text = $"- {message}", TextWrapping = TextWrapping.Wrap });
        }
    }

    private void AppendRecentStatus(string message) => RecentStatusList.Items.Insert(0, new TextBlock { Text = $"- {message}", TextWrapping = TextWrapping.Wrap });

    private List<DomainRule> BuildDomainRules(Guid profileId)
    {
        return GetDomainListItems()
            .Select(NormalizeDomain)
            .Where(domain => !string.IsNullOrWhiteSpace(domain))
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .Select(domain => new DomainRule(Guid.NewGuid(), profileId, domain, true, true, DateTimeOffset.UtcNow))
            .ToList();
    }

    private Guid? GetSelectedProfileId() => ProfileComboBox.SelectedItem is ProfileComboBoxItem item ? item.Id : null;

    private string? GetSelectedProfileName() => ProfileComboBox.SelectedItem is ProfileComboBoxItem item ? item.Name : null;

    private void UpdateSelectedProfileDetails(int profileCount)
    {
        if (ProfileComboBox.SelectedItem is not ProfileComboBoxItem item)
        {
            ProfileDetailsText.Text = $"저장된 프로필 {profileCount}개.";
            return;
        }

        ProfileDetailsText.Text = $"저장된 프로필 {profileCount}개 · {item.Name}";
        if (item.Endpoints.Any(endpoint => endpoint.Contains("example.com", StringComparison.OrdinalIgnoreCase)))
        {
            AppendRecentStatus("현재 선택된 WireGuard 프로필의 Endpoint가 example.com 예제 주소입니다. 실제 VPN .conf를 다시 가져오세요.");
        }
    }

    private static string NormalizeDomain(string value)
    {
        var domain = value.Trim().ToLowerInvariant();
        if (domain.StartsWith("https://", StringComparison.OrdinalIgnoreCase)) domain = domain["https://".Length..];
        else if (domain.StartsWith("http://", StringComparison.OrdinalIgnoreCase)) domain = domain["http://".Length..];
        var slashIndex = domain.IndexOf('/');
        if (slashIndex >= 0) domain = domain[..slashIndex];
        return domain.Trim('.');
    }

    private sealed record ProfileComboBoxItem(Guid Id, string Name, string DisplayName, IReadOnlyList<string> Endpoints)
    {
        public override string ToString() => DisplayName;
    }
}

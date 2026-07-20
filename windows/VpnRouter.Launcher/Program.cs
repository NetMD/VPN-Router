using System.ComponentModel;
using System.Diagnostics;
using System.IO.Compression;
using System.IO.Pipes;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;

namespace VpnRouter.Launcher;

internal static class Program
{
    private const string PayloadResourceName = "VpnRouter.Payload.zip";
    private const string PipeName = "VpnRouter.Service";
    private const string AppExecutable = "VpnRouter.App.exe";
    private const string BackendExecutable = "VpnRouter.Service.exe";
    private static readonly string ProductVersion = GetProductVersion();

    [STAThread]
    private static int Main(string[] args)
    {
        try
        {
            using var extractionMutex = new Mutex(false, @"Local\VpnRouter.Portable.Extraction");
            if (!extractionMutex.WaitOne(TimeSpan.FromSeconds(30)))
            {
                throw new TimeoutException("다른 VPN Router 실행이 파일을 준비하는 중입니다. 잠시 후 다시 실행해 주세요.");
            }

            string payloadRoot;
            try
            {
                payloadRoot = EnsurePayloadExtracted();
            }
            finally
            {
                extractionMutex.ReleaseMutex();
            }

            if (args.Contains("--extract-only", StringComparer.OrdinalIgnoreCase))
            {
                return 0;
            }

            if (!IsBackendReady(TimeSpan.FromMilliseconds(250)))
            {
                StartElevatedBackend(payloadRoot);
                if (!IsBackendReady(TimeSpan.FromSeconds(20)))
                {
                    throw new TimeoutException("관리자 백엔드가 20초 안에 준비되지 않았습니다.");
                }
            }

            StartDesktopApp(payloadRoot);
            return 0;
        }
        catch (Win32Exception ex) when (ex.NativeErrorCode == 1223)
        {
            ShowError("관리자 권한 요청이 취소되어 VPN Router를 시작하지 않았습니다.");
            return 2;
        }
        catch (Exception ex)
        {
            ShowError($"VPN Router를 시작하지 못했습니다.\n\n{ex.Message}");
            return 1;
        }
    }

    private static string EnsurePayloadExtracted()
    {
        var appData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        var versionsRoot = Path.Combine(appData, "VpnRouter", "app");
        var payloadHash = GetPayloadHash();
        var targetRoot = Path.Combine(versionsRoot, $"{ProductVersion}-{payloadHash[..12].ToLowerInvariant()}");
        var completionMarker = Path.Combine(targetRoot, ".complete");

        if (File.Exists(completionMarker)
            && string.Equals(File.ReadAllText(completionMarker).Trim(), payloadHash, StringComparison.OrdinalIgnoreCase)
            && PayloadLooksComplete(targetRoot))
        {
            return targetRoot;
        }

        Directory.CreateDirectory(versionsRoot);
        var stagingRoot = Path.Combine(versionsRoot, $".{ProductVersion}-{Guid.NewGuid():N}.staging");

        try
        {
            Directory.CreateDirectory(stagingRoot);
            using var payload = Assembly.GetExecutingAssembly().GetManifestResourceStream(PayloadResourceName)
                ?? throw new InvalidOperationException("실행 파일에 portable payload가 포함되어 있지 않습니다.");
            using var archive = new ZipArchive(payload, ZipArchiveMode.Read);
            archive.ExtractToDirectory(stagingRoot, overwriteFiles: true);

            if (!PayloadLooksComplete(stagingRoot))
            {
                throw new InvalidDataException("압축 해제된 payload에 앱 또는 백엔드 실행 파일이 없습니다.");
            }

            File.WriteAllText(Path.Combine(stagingRoot, ".complete"), payloadHash, Encoding.UTF8);

            if (Directory.Exists(targetRoot))
            {
                Directory.Delete(targetRoot, recursive: true);
            }

            Directory.Move(stagingRoot, targetRoot);
            return targetRoot;
        }
        finally
        {
            if (Directory.Exists(stagingRoot))
            {
                Directory.Delete(stagingRoot, recursive: true);
            }
        }
    }

    private static bool PayloadLooksComplete(string root) =>
        File.Exists(Path.Combine(root, "app", AppExecutable)) &&
        File.Exists(Path.Combine(root, "backend", BackendExecutable));

    private static string GetPayloadHash()
    {
        using var payload = Assembly.GetExecutingAssembly().GetManifestResourceStream(PayloadResourceName)
            ?? throw new InvalidOperationException("실행 파일에 portable payload가 포함되어 있지 않습니다.");
        return Convert.ToHexString(SHA256.HashData(payload));
    }

    private static string GetProductVersion()
    {
        var informationalVersion = Assembly.GetExecutingAssembly()
            .GetCustomAttribute<AssemblyInformationalVersionAttribute>()?
            .InformationalVersion;
        var version = informationalVersion?.Split('+', 2)[0];
        return string.IsNullOrWhiteSpace(version) ? "0.1.0" : version;
    }

    private static void StartElevatedBackend(string payloadRoot)
    {
        var backendDirectory = Path.Combine(payloadRoot, "backend");
        var backendPath = Path.Combine(backendDirectory, BackendExecutable);
        var startInfo = new ProcessStartInfo
        {
            FileName = backendPath,
            WorkingDirectory = backendDirectory,
            UseShellExecute = true,
            Verb = "runas",
            WindowStyle = ProcessWindowStyle.Hidden
        };

        startInfo.ArgumentList.Add("--VpnRouter:Features:EnableWireGuardActivation=true");
        startInfo.ArgumentList.Add("--VpnRouter:Features:EnableWindowsDnsMutation=true");
        startInfo.ArgumentList.Add("--VpnRouter:Features:EnableWindowsRouteMutation=true");

        _ = Process.Start(startInfo) ?? throw new InvalidOperationException("관리자 백엔드 프로세스를 시작하지 못했습니다.");
    }

    private static void StartDesktopApp(string payloadRoot)
    {
        var appDirectory = Path.Combine(payloadRoot, "app");
        var appPath = Path.Combine(appDirectory, AppExecutable);
        _ = Process.Start(new ProcessStartInfo
        {
            FileName = appPath,
            WorkingDirectory = appDirectory,
            UseShellExecute = true
        }) ?? throw new InvalidOperationException("VPN Router 화면을 시작하지 못했습니다.");
    }

    private static bool IsBackendReady(TimeSpan timeout)
    {
        try
        {
            using var pipe = new NamedPipeClientStream(".", PipeName, PipeDirection.InOut, PipeOptions.None);
            pipe.Connect(Math.Max(1, (int)timeout.TotalMilliseconds));

            using var writer = new StreamWriter(pipe, leaveOpen: true) { AutoFlush = true };
            using var reader = new StreamReader(pipe, leaveOpen: true);
            writer.WriteLine("{\"command\":\"GetConnectionState\",\"payload\":{}}");
            return !string.IsNullOrWhiteSpace(reader.ReadLine());
        }
        catch (Exception ex) when (ex is TimeoutException or IOException)
        {
            return false;
        }
    }

    private static void ShowError(string message) =>
        MessageBox(IntPtr.Zero, message, "VPN Router", 0x00000010);

    [DllImport("user32.dll", CharSet = CharSet.Unicode, EntryPoint = "MessageBoxW")]
    private static extern int MessageBox(IntPtr windowHandle, string text, string caption, uint type);
}

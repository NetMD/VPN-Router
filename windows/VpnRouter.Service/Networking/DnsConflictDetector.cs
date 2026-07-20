using System.Net;
using System.Net.Sockets;

namespace VpnRouter.Service.Networking;

public static class DnsConflictDetector
{
    public static string? Detect(int port = 53)
    {
        try
        {
            using var listener = new UdpClient(AddressFamily.InterNetwork);
            listener.ExclusiveAddressUse = true;
            listener.Client.Bind(new IPEndPoint(IPAddress.Loopback, port));
            return null;
        }
        catch (SocketException ex)
        {
            return $"로컬 DNS 포트 127.0.0.1:{port}을 사용할 수 없습니다. " +
                   "DNS 보호, 광고 차단, 보안 또는 VPN 프로그램의 DNS 기능을 직접 끈 뒤 다시 확인해 주세요. " +
                   $"VPN Router는 해당 프로그램을 자동으로 종료하지 않습니다. ({ex.SocketErrorCode})";
        }
    }
}

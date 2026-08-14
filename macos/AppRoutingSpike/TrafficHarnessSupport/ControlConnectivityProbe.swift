import Foundation

/// 통제 인터넷 가용 여부만 반환하며 대상·응답·DNS 정보는 보존하지 않습니다.
public actor ControlConnectivityProbe {
    public init() {}

    public func probe() async -> HarnessActionResult {
        var request = URLRequest(url: URL(string: "https://example.com/")!)
        request.timeoutInterval = 3
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            return HarnessActionResult(completed: (200..<500).contains(status))
        } catch {
            return HarnessActionResult(completed: false)
        }
    }
}

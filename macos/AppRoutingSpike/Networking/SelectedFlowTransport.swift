import Foundation

/// P2에서 선택 흐름을 외부 연결로 전달하지 않도록 고정한 결과입니다.
public enum SelectedFlowTransportResult: Equatable, Sendable {
    case unsupported
}

/// P3 승인 전에는 어떤 TCP/UDP 외부 연결도 만들지 않습니다.
public struct SelectedFlowTransport: Sendable {
    public init() {}

    public func forward() -> SelectedFlowTransportResult {
        .unsupported
    }
}

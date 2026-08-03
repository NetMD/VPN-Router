import Foundation

/// 입력·버퍼·흐름 경계값의 단일 정의 위치입니다.
public enum SpikeLimits {
    public static let schemaVersion = 1
    public static let maximumJSONStringBytes = 4 * 1_024
    public static let maximumExportBytes = 5 * 1_024 * 1_024
    public static let maximumExportPathBytes = 1_024
    public static let snapshotBatchSize = 64
    public static let resultChannelCapacity = 256
    public static let resultBufferCapacity = 2_000
    public static let maximumTCPReadBytes = 64 * 1_024
    public static let maximumUDPDatagramBytes = 65_535
    public static let maximumSelectedFlows = 256
    public static let maximumXPCPayloadBytes = 256 * 1_024
    public static let xpcReplyTimeoutSeconds: TimeInterval = 3
    public static let maximumSigningIdentifierBytes = 255
    public static let maximumTeamIdentifierBytes = 64
    public static let maximumRunRecords = 32
}

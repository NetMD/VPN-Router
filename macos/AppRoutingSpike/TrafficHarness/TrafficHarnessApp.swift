import SwiftUI

@main
struct TrafficHarnessApp: App {
    private let role = TrafficHarnessRole.current

    var body: some Scene {
        WindowGroup {
            TrafficHarnessView(role: role)
        }
    }
}

enum TrafficHarnessRole: Equatable {
    case selectedApp
    case controlApp
    case invalidConfiguration

    static var current: TrafficHarnessRole {
        switch Bundle.main.object(forInfoDictionaryKey: "SpikeHarnessRole") as? String {
        case "selectedApp": return .selectedApp
        case "controlApp": return .controlApp
        default: return .invalidConfiguration
        }
    }

    var title: String {
        switch self {
        case .selectedApp: return "선택 앱 흐름 하네스"
        case .controlApp: return "통제 앱 흐름 하네스"
        case .invalidConfiguration: return "시험 하네스 구성 오류"
        }
    }
}

import Darwin
import Foundation

struct TunnelInterfaceFingerprint: Equatable {
    private let interfaceNames: Set<String>

    static func current() -> TunnelInterfaceFingerprint? {
        var firstAddress: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&firstAddress) == 0 else {
            return nil
        }
        defer { freeifaddrs(firstAddress) }

        var interfaceNames = Set<String>()
        var currentAddress = firstAddress
        while let address = currentAddress {
            defer { currentAddress = address.pointee.ifa_next }
            guard let socketAddress = address.pointee.ifa_addr,
                  socketAddress.pointee.sa_family == UInt8(AF_INET),
                  address.pointee.ifa_flags & UInt32(IFF_UP) != 0 else {
                continue
            }

            let name = String(cString: address.pointee.ifa_name)
            if name.hasPrefix("utun") {
                interfaceNames.insert(name)
            }
        }
        return TunnelInterfaceFingerprint(interfaceNames: interfaceNames)
    }
}

import Darwin
import Foundation

protocol DomainResolving {
    nonisolated func resolveIPv4Addresses(for domains: [String]) throws -> [ResolvedDomainAddress]
    nonisolated func resolveIPv6Domains(for domains: [String]) throws -> [String]
}

extension DomainResolving {
    nonisolated func resolveIPv6Domains(for domains: [String]) throws -> [String] {
        []
    }
}

nonisolated struct SystemDomainResolver: DomainResolving {
    func resolveIPv4Addresses(for domains: [String]) throws -> [ResolvedDomainAddress] {
        var resolvedAddresses: [ResolvedDomainAddress] = []

        for domain in Array(Set(domains.map(DomainRuleExpander.normalize))).sorted() where !domain.isEmpty {
            let addresses = resolveIPv4AddressesAllowingFailure(for: domain)
            resolvedAddresses.append(contentsOf: addresses.map { address in
                ResolvedDomainAddress(domain: domain, ipv4Address: address)
            })
        }

        return resolvedAddresses
    }

    func resolveIPv6Domains(for domains: [String]) throws -> [String] {
        Array(Set(domains.map(DomainRuleExpander.normalize)))
            .filter { !$0.isEmpty && hasIPv6AddressAllowingFailure(for: $0) }
            .sorted()
    }

    private func resolveIPv4AddressesAllowingFailure(for domain: String) -> [String] {
        (try? resolveIPv4Addresses(for: domain)) ?? []
    }

    private func hasIPv6AddressAllowingFailure(for domain: String) -> Bool {
        (try? hasIPv6Address(for: domain)) ?? false
    }

    private func hasIPv6Address(for domain: String) throws -> Bool {
        var hints = addrinfo(
            ai_flags: AI_ADDRCONFIG,
            ai_family: AF_INET6,
            ai_socktype: SOCK_STREAM,
            ai_protocol: IPPROTO_TCP,
            ai_addrlen: 0,
            ai_canonname: nil,
            ai_addr: nil,
            ai_next: nil
        )
        var result: UnsafeMutablePointer<addrinfo>?
        let status = getaddrinfo(domain, nil, &hints, &result)
        guard status == 0 else {
            throw DomainResolverError.lookupFailed(domain: domain, status: status)
        }
        defer { freeaddrinfo(result) }

        var pointer = result
        while let current = pointer {
            if current.pointee.ai_family == AF_INET6 {
                return true
            }
            pointer = current.pointee.ai_next
        }
        return false
    }

    private func resolveIPv4Addresses(for domain: String) throws -> [String] {
        var hints = addrinfo(
            ai_flags: AI_ADDRCONFIG,
            ai_family: AF_INET,
            ai_socktype: SOCK_STREAM,
            ai_protocol: IPPROTO_TCP,
            ai_addrlen: 0,
            ai_canonname: nil,
            ai_addr: nil,
            ai_next: nil
        )
        var result: UnsafeMutablePointer<addrinfo>?
        let status = getaddrinfo(domain, nil, &hints, &result)
        guard status == 0 else {
            throw DomainResolverError.lookupFailed(domain: domain, status: status)
        }
        defer { freeaddrinfo(result) }

        var addresses = Set<String>()
        var pointer = result
        while let current = pointer {
            if current.pointee.ai_family == AF_INET,
               let socketAddress = current.pointee.ai_addr?.withMemoryRebound(
                to: sockaddr_in.self,
                capacity: 1,
                { $0.pointee }
               ) {
                var ipv4Address = socketAddress.sin_addr
                var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                if inet_ntop(AF_INET, &ipv4Address, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil {
                    addresses.insert(String(cString: buffer))
                }
            }
            pointer = current.pointee.ai_next
        }

        return addresses.sorted()
    }
}

enum DomainResolverError: LocalizedError, Equatable {
    case lookupFailed(domain: String, status: Int32)

    var errorDescription: String? {
        switch self {
        case .lookupFailed(let domain, let status):
            return "\(domain)의 IP 주소를 찾지 못했습니다: \(String(cString: gai_strerror(status)))"
        }
    }
}

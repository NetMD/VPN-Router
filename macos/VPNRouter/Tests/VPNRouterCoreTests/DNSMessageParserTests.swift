import Foundation
import Testing
@testable import VPNRouterDNSObservation

struct DNSMessageParserTests {
    @Test
    func extractsMatchingIPv4AddressAndTTL() throws {
        let response = dnsResponse(
            question: "www.youtube.com",
            answers: [
                .a(owner: .questionPointer, address: [203, 0, 113, 10], ttl: 120)
            ]
        )

        let observations = try DNSMessageParser.addressObservations(
            in: response,
            matching: ["youtube.com"]
        )

        #expect(observations == [
            DNSAddressObservation(
                domain: "www.youtube.com",
                address: "203.0.113.10",
                ttl: 120
            )
        ])
    }

    @Test
    func ignoresUnrelatedQuestion() throws {
        let response = dnsResponse(
            question: "www.example.com",
            answers: [
                .a(owner: .questionPointer, address: [198, 51, 100, 7], ttl: 60)
            ]
        )

        let observations = try DNSMessageParser.addressObservations(
            in: response,
            matching: ["youtube.com"]
        )

        #expect(observations.isEmpty)
    }

    @Test
    func followsCNAMEToIPv4Address() throws {
        let response = dnsResponse(
            question: "www.youtube.com",
            answers: [
                .cname(
                    owner: .questionPointer,
                    canonicalName: "edge.googlevideo.com",
                    ttl: 20
                ),
                .a(
                    owner: .name("edge.googlevideo.com"),
                    address: [192, 0, 2, 42],
                    ttl: 30
                )
            ]
        )

        let observations = try DNSMessageParser.addressObservations(
            in: response,
            matching: ["youtube.com"]
        )

        #expect(observations == [
            DNSAddressObservation(
                domain: "edge.googlevideo.com",
                address: "192.0.2.42",
                ttl: 20
            )
        ])
    }

    @Test
    func rejectsTruncatedMessage() {
        #expect(throws: DNSMessageParserError.self) {
            try DNSMessageParser.addressObservations(
                in: Data([0, 1, 2]),
                matching: ["example.com"]
            )
        }
    }

    @Test
    func rejectsCompressionPointerLoop() {
        var response = dnsHeader(questionCount: 1, answerCount: 0)
        response.append(contentsOf: [0xc0, 0x0c, 0, 1, 0, 1])

        #expect(throws: DNSMessageParserError.self) {
            try DNSMessageParser.addressObservations(
                in: response,
                matching: ["example.com"]
            )
        }
    }

    @Test
    func replacesMatchingAAAAResponseWithEmptyNoErrorResponse() throws {
        let response = dnsResponse(
            question: "www.youtube.com",
            questionType: 28,
            answers: []
        )

        let candidate = try DNSMessageParser.emptyAAAAResponse(
            for: response,
            matching: ["youtube.com"]
        )
        let filtered = try #require(candidate)

        #expect(filtered[0] == 0x12)
        #expect(filtered[1] == 0x34)
        #expect(filtered[2] & 0x80 == 0x80)
        #expect(filtered[3] & 0x0f == 0)
        #expect(filtered[4] == 0)
        #expect(filtered[5] == 1)
        #expect(filtered[6] == 0)
        #expect(filtered[7] == 0)
    }

    @Test
    func doesNotFilterAAAAForUnrelatedDomainOrMatchingAResponse() throws {
        let unrelatedAAAA = dnsResponse(
            question: "www.example.com",
            questionType: 28,
            answers: []
        )
        let matchingA = dnsResponse(
            question: "www.youtube.com",
            answers: []
        )

        #expect(try DNSMessageParser.emptyAAAAResponse(
            for: unrelatedAAAA,
            matching: ["youtube.com"]
        ) == nil)
        #expect(try DNSMessageParser.emptyAAAAResponse(
            for: matchingA,
            matching: ["youtube.com"]
        ) == nil)
    }
}

private enum TestOwner {
    case questionPointer
    case name(String)
}

private enum TestAnswer {
    case a(owner: TestOwner, address: [UInt8], ttl: UInt32)
    case cname(owner: TestOwner, canonicalName: String, ttl: UInt32)
}

private func dnsResponse(
    question: String,
    questionType: UInt16 = 1,
    answers: [TestAnswer]
) -> Data {
    var data = dnsHeader(questionCount: 1, answerCount: UInt16(answers.count))
    appendName(question, to: &data)
    appendUInt16(questionType, to: &data)
    appendUInt16(1, to: &data)

    for answer in answers {
        switch answer {
        case .a(let owner, let address, let ttl):
            appendOwner(owner, to: &data)
            appendUInt16(1, to: &data)
            appendUInt16(1, to: &data)
            appendUInt32(ttl, to: &data)
            appendUInt16(UInt16(address.count), to: &data)
            data.append(contentsOf: address)
        case .cname(let owner, let canonicalName, let ttl):
            appendOwner(owner, to: &data)
            appendUInt16(5, to: &data)
            appendUInt16(1, to: &data)
            appendUInt32(ttl, to: &data)
            var nameData = Data()
            appendName(canonicalName, to: &nameData)
            appendUInt16(UInt16(nameData.count), to: &data)
            data.append(nameData)
        }
    }
    return data
}

private func dnsHeader(questionCount: UInt16, answerCount: UInt16) -> Data {
    var data = Data()
    appendUInt16(0x1234, to: &data)
    appendUInt16(0x8180, to: &data)
    appendUInt16(questionCount, to: &data)
    appendUInt16(answerCount, to: &data)
    appendUInt16(0, to: &data)
    appendUInt16(0, to: &data)
    return data
}

private func appendOwner(_ owner: TestOwner, to data: inout Data) {
    switch owner {
    case .questionPointer:
        data.append(contentsOf: [0xc0, 0x0c])
    case .name(let name):
        appendName(name, to: &data)
    }
}

private func appendName(_ name: String, to data: inout Data) {
    for label in name.split(separator: ".") {
        data.append(UInt8(label.utf8.count))
        data.append(contentsOf: label.utf8)
    }
    data.append(0)
}

private func appendUInt16(_ value: UInt16, to data: inout Data) {
    data.append(UInt8(value >> 8))
    data.append(UInt8(value & 0xff))
}

private func appendUInt32(_ value: UInt32, to data: inout Data) {
    data.append(UInt8((value >> 24) & 0xff))
    data.append(UInt8((value >> 16) & 0xff))
    data.append(UInt8((value >> 8) & 0xff))
    data.append(UInt8(value & 0xff))
}

import Foundation
import HegelClient
import HegelFakeAmp
import Testing
@testable import HegelRemoteCore

@Suite struct CustomButtonTests {
    @Test func buttonsAreCodableAndTheExampleIsSane() throws {
        let button = CustomButton(label: "Night", actions: [
            .amp(.selectInput(12)), .amp(.setVolume(25)),
            .http(HTTPRequestSpec(method: "POST", url: "http://ha.local:8123/api/webhook/night", body: "{}")),
        ])
        let data = try JSONEncoder().encode(button)
        #expect(try JSONDecoder().decode(CustomButton.self, from: data) == button)
        #expect(CustomButton.exampleLateNight.actions == [.amp(.selectInput(12)), .amp(.setVolume(25))])
        #expect(button.actions[2].label(inputName: { _ in nil }) == "POST http://ha.local:8123/api/webhook/night")
    }

    @Test func httpSpecBuildsARequestAndRejectsBadURLs() throws {
        let r = try HTTPRequestSpec(method: "post", url: "http://h/x", body: "{\"a\":1}").makeRequest()
        #expect(r.httpMethod == "POST")
        #expect(r.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(r.httpBody == Data("{\"a\":1}".utf8))
        #expect(throws: PlaybackError.badURL("not a url")) { try HTTPRequestSpec(url: "not a url").makeRequest() }
    }

    @Test func actionsRunInOrderAgainstAmpAndHTTP() async throws {
        let amp = try await FakeAmp.start()
        defer { amp.stop() }
        let server = try await FakeHTTPServer.start()
        defer { server.stop() }
        let client = AmpClient(host: "127.0.0.1", port: amp.port)
        try await client.connect()
        defer { Task { await client.disconnect() } }
        await client.waitForInitialState()

        let button = CustomButton(label: "Preset", actions: [
            .amp(.selectInput(3)),
            .http(HTTPRequestSpec(method: "POST", url: "\(server.baseURL)/api/webhook/preset", body: "{\"scene\":\"night\"}")),
            .amp(.setVolume(20)),
        ])
        try await CustomButtonRunner.run(button, amp: client, http: URLSessionHTTPClient(timeout: 3))

        #expect(amp.snapshot.input == 3 && amp.snapshot.volume == 20)
        // Only the commands, in order; the client's own state queries and keepalive are not the button's doing.
        #expect(amp.receivedPackets.filter { !$0.hasSuffix("?") && !$0.hasPrefix("-r.") } == ["-i.3", "-v.20"])
        #expect(server.received.count == 1)
        #expect(server.received[0].method == "POST" && server.received[0].path == "/api/webhook/preset")
        #expect(server.received[0].body == "{\"scene\":\"night\"}")
    }

    @Test func failingHTTPStopsTheSequence() async throws {
        let amp = try await FakeAmp.start()
        defer { amp.stop() }
        let server = try await FakeHTTPServer.start()
        defer { server.stop() }
        server.respond { _ in (404, "") }
        let client = AmpClient(host: "127.0.0.1", port: amp.port)
        try await client.connect()
        defer { Task { await client.disconnect() } }

        let button = CustomButton(label: "x", actions: [
            .http(HTTPRequestSpec(method: "GET", url: "\(server.baseURL)/missing")),
            .amp(.setVolume(5)),
        ])
        await #expect(throws: PlaybackError.httpStatus(404)) {
            try await CustomButtonRunner.run(button, amp: client, http: URLSessionHTTPClient(timeout: 3))
        }
        #expect(amp.snapshot.volume == 33)
    }

    @Test func ampActionWithoutConnectionFails() async throws {
        let button = CustomButton(label: "x", actions: [.amp(.togglePower)])
        await #expect(throws: CustomButtonError.noConnection) {
            try await CustomButtonRunner.run(button, amp: nil, http: URLSessionHTTPClient())
        }
    }
}

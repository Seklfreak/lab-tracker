import Foundation
import Testing
@testable import LabTracker

/// LAB-TRACKER-IOS-6 arrived 25 times as "The data couldn't be read because
/// it isn't in the correct format" and stayed unfixable, because that one
/// sentence is what `JSONDecoder` says for an empty body, an HTML page and a
/// renamed field alike. These check the three now read differently.
struct APIErrorDecodingTests {
    private func response(_ contentType: String?) -> HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: "https://labs.example.com/api/profiles")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: contentType.map { ["Content-Type": $0] }
        )!
    }

    private func message(decoding body: String, as type: (some Decodable).Type, contentType: String?) -> String {
        let data = Data(body.utf8)
        do {
            _ = try JSONDecoder().decode(type, from: data)
            Issue.record("expected \(type) to fail decoding")
            return ""
        } catch {
            let apiError = APIError.decodingFailure(error, data: data, response: response(contentType))
            guard case let .decoding(message) = apiError else {
                Issue.record("expected .decoding, got \(apiError)")
                return ""
            }
            return message
        }
    }

    @Test func anEmptyBodyIsVisiblyEmpty() {
        let message = message(decoding: "", as: [Profile].self, contentType: "application/json")
        #expect(message == "malformed JSON at root; 0 bytes of application/json")
    }

    @Test func aLoginPageServedWithA200SaysSo() {
        let message = message(
            decoding: "<!doctype html><html><body>Sign in</body></html>",
            as: [Profile].self,
            contentType: "text/html; charset=utf-8"
        )
        // The charset is dropped, and no markup rides along into Sentry.
        #expect(message == "malformed JSON at root; 48 bytes of text/html")
        #expect(!message.contains("html>"))
    }

    @Test func contractDriftNamesTheFieldAndNotTheValue() {
        // `isOwner` is the non-optional one — a missing `dateOfBirth` decodes
        // fine, because the synthesized init reads optionals with
        // `decodeIfPresent`.
        let message = message(
            decoding: #"[{"id":"p1","name":"Ada","dateOfBirth":null}]"#,
            as: [Profile].self,
            contentType: "application/json"
        )
        #expect(message.contains("missing key"))
        // The absent field is named so it can be chased in the API…
        #expect(message.contains("isOwner"))
        // …while the profile's actual data never leaves the device.
        #expect(!message.contains("Ada"))
    }

    @Test func aMissingContentTypeHeaderIsStillReportable() {
        let message = message(decoding: "not json", as: [Profile].self, contentType: nil)
        #expect(message == "malformed JSON at root; 8 bytes of no content-type")
    }
}

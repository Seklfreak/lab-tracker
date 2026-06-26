import Testing
@testable import LabTracker

struct ConfigParseTests {
    // The exact shape the server publishes at /config.js.
    private let sample = """
    window.__APP_CONFIG__ = {
      oidcAuthority: "https://idp.example.com/application/o/app/",
      oidcClientId: "my-client"
    };
    """

    @Test func extractsAuthorityAndClientId() {
        #expect(AuthSession.jsString("oidcAuthority", in: sample) == "https://idp.example.com/application/o/app/")
        #expect(AuthSession.jsString("oidcClientId", in: sample) == "my-client")
    }

    @Test func missingKeyReturnsNil() {
        #expect(AuthSession.jsString("oidcNope", in: sample) == nil)
    }

    @Test func toleratesSingleLineAndExtraSpacing() {
        let oneLine = #"window.__APP_CONFIG__ = { oidcClientId:    "x" };"#
        #expect(AuthSession.jsString("oidcClientId", in: oneLine) == "x")
    }
}

import Testing
import Foundation
@testable import LabTracker

/// Classifying the OIDC token endpoint's refresh response. The regression these
/// guard against: a transient Authentik/gateway failure used to wipe a
/// still-valid refresh token and force a daily re-login. Only a genuine
/// `invalid_grant` may sign the user out.
struct RefreshOutcomeTests {
    private func body(_ s: String) -> Data { Data(s.utf8) }

    @Test func success200Refreshes() {
        let out = AuthSession.classifyRefresh(
            status: 200,
            body: body(#"{"access_token":"a","refresh_token":"b","expires_in":3600}"#))
        #expect(out == .refreshed)
    }

    @Test func invalidGrant400Revokes() {
        let out = AuthSession.classifyRefresh(
            status: 400,
            body: body(#"{"error":"invalid_grant","error_description":"Token invalid/expired"}"#))
        #expect(out == .revoked)
    }

    // Authentik restarting/redeploying (or a gateway 5xx) must keep the token.
    @Test(arguments: [500, 502, 503, 504])
    func serverErrorsKeepToken(status: Int) {
        let out = AuthSession.classifyRefresh(status: status, body: body("upstream connect error"))
        #expect(out == .keepRetry(status))
    }

    // A 400 that isn't invalid_grant (e.g. invalid_request) is not a revocation.
    @Test func other400ErrorsDoNotRevoke() {
        let out = AuthSession.classifyRefresh(status: 400, body: body(#"{"error":"invalid_request"}"#))
        #expect(out == .keepRetry(400))
    }

    // A 400 whose body isn't the expected JSON must not be read as a revocation.
    @Test func malformed400BodyDoesNotRevoke() {
        let out = AuthSession.classifyRefresh(status: 400, body: body("<html>Bad Request</html>"))
        #expect(out == .keepRetry(400))
    }
}

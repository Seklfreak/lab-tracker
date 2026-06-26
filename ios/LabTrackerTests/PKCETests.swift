import Foundation
import Testing
@testable import LabTracker

struct PKCETests {
    @Test func base64urlHasNoPaddingOrUnsafeChars() {
        // Bytes whose standard base64 contains '+' and '/'.
        let encoded = AuthSession.base64url(Data([0xFF, 0xFF, 0xFE]))
        #expect(!encoded.contains("+"))
        #expect(!encoded.contains("/"))
        #expect(!encoded.contains("="))
        #expect(encoded == "___-")
    }

    /// RFC 7636 Appendix B test vector — proves the S256 challenge derivation.
    @Test func codeChallengeMatchesRFC7636() {
        let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        #expect(AuthSession.codeChallenge(for: verifier) == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    @Test func escapePercentEncodesReservedChars() {
        #expect(AuthSession.escape("a b/c:") == "a%20b%2Fc%3A")
        #expect(AuthSession.escape("plain-_.~") == "plain-_.~") // unreserved pass through
    }

    @Test func randomURLSafeIsURLSafeAndLongEnough() {
        let value = AuthSession.randomURLSafe(32)
        #expect(!value.contains("+"))
        #expect(!value.contains("/"))
        #expect(!value.contains("="))
        #expect(value.count >= 43) // 32 bytes → 43 base64 chars (unpadded)
    }
}

import Testing
@testable import LabTracker

/// When a screen must ask for sign-in instead of calling the API.
///
/// The regression these guard: a background relaunch (iOS waking the app for a
/// HealthKit delivery) with a dead session used to send an anonymous request
/// and file the 401 it earned as an error — LAB-TRACKER-IOS-3, one signed-out
/// session re-reported at every wake. The obvious fix, prompting whenever
/// there is no session, would have broken the other deployment: a server that
/// publishes no OIDC config serves its API unauthenticated.
struct SignInGateTests {
    @Test func promptsWhenAuthIsConfiguredAndThereIsNoSession() {
        #expect(AuthSession.needsSignIn(configured: true, signedIn: false))
    }

    @Test func loadsNormallyWithASession() {
        #expect(!AuthSession.needsSignIn(configured: true, signedIn: true))
    }

    // A server without OIDC never prompts: there is nothing to sign in to.
    @Test func serverWithoutAuthKeepsLoading() {
        #expect(!AuthSession.needsSignIn(configured: false, signedIn: false))
    }
}

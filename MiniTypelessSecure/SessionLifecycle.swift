import Foundation

/// Owns only sleep/deferred-work state, never credentials or audio bytes.
/// A deferred take is consumed once and matched by URL before processing.
struct SessionLifecycle {
    private(set) var isSleeping = false
    private(set) var deferredAudio: URL?

    mutating func beginSleep() -> Bool {
        guard !isSleeping else { return false }
        isSleeping = true
        return true
    }
    mutating func deferUntilWake(_ url: URL) { deferredAudio = url }
    mutating func wake() -> URL? {
        guard isSleeping else { return nil }
        isSleeping = false
        defer { deferredAudio = nil }
        return deferredAudio
    }
    mutating func invalidateDeferredAudio() { deferredAudio = nil }
}

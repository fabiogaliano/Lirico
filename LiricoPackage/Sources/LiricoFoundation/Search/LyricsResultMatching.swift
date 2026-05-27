@preconcurrency import LyricsKit
import Foundation

extension Lyrics {
    /// Whether `self` and `other` represent the same chosen lyrics result, even
    /// though they are distinct `Lyrics` instances. Reference identity can't be
    /// used here: a manual search always builds fresh objects, and lyrics loaded
    /// from a saved `.lrcx` carry none of the runtime metadata of the search
    /// result they were persisted from (the metadata bag isn't serialized).
    ///
    /// Identity is resolved in two tiers:
    /// 1. When both sides carry a provider service name and token, those are the
    ///    authoritative key — a result from a different provider is a genuinely
    ///    different result even when its text happens to match.
    /// 2. Otherwise (e.g. one side was loaded from disk, where the service token
    ///    is gone) fall back to a fingerprint of the timed line body, which is
    ///    exactly what the `.lrcx` round-trips.
    public func isSameResult(as other: Lyrics) -> Bool {
        if let key = serviceKey, let otherKey = other.serviceKey {
            return key == otherKey
        }
        return bodyFingerprint == other.bodyFingerprint
    }

    /// `service␟serviceToken` when both are present and non-empty, else nil.
    private var serviceKey: String? {
        guard let service = metadata.service, !service.isEmpty,
              let token = metadata.serviceToken, !token.isEmpty
        else { return nil }
        return "\(service)\u{1f}\(token)"
    }

    /// A stable fingerprint of the enabled, timed line body — independent of
    /// header tags and metadata so a re-fetched result matches the `.lrcx` that
    /// was persisted from it. Positions are quantized to milliseconds, the same
    /// precision the LRC time tag round-trips through.
    private var bodyFingerprint: [String] {
        lines
            .filter(\.enabled)
            .map { "\(Int(($0.position * 1000).rounded()))\u{1f}\($0.content)" }
    }
}

import Foundation

/// Typed view of the on-disk-persistence slice of `UserDefaults`.
///
/// Both the popup-index selector and the security-scoped bookmark live in
/// the flat `UserDefaults.DefaultsKeys` namespace; this wrapper resolves
/// them into a single "where should we write?" answer so callers don't
/// re-derive it.
struct PersistenceSettings {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Directory where the next `.lrcx` should be written, together with a
    /// flag telling the writer to start a security-scoped resource access
    /// (true for user-chosen folders outside the sandbox container).
    func localSavingDirectory() -> (url: URL, security: Bool) {
        return defaults.lyricsSavingPath()
    }
}

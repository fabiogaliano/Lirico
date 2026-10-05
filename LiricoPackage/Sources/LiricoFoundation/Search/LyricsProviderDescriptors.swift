import LiricoKit

/// The canonical lyrics-provider descriptor list, shared by the app's search
/// pipeline and any out-of-app tooling.
///
/// This is the single source of truth for *which* lyrics sources exist and in
/// what order they are queried. Adding or removing a provider here updates every
/// caller — the app's search pipeline and source preferences, and the
/// `lyrics-diag` tool — at once.
///
/// Musixmatch is appended only when a non-empty token is supplied: the source
/// returns nothing without a user token.
public func makeProviderDescriptors(musixmatchToken: String?) -> [LyricsProviders.ProviderDescriptor] {
    var descriptors: [LyricsProviders.ProviderDescriptor] = [
        LyricsProviders.ProviderDescriptor(
            source: LyricsProviders.ServiceID.netease.displayName,
            provider: LyricsProviders.Service.netease.create()
        ),
        LyricsProviders.ProviderDescriptor(
            source: LyricsProviders.ServiceID.qq.displayName,
            provider: LyricsProviders.Service.qq.create()
        ),
        LyricsProviders.ProviderDescriptor(
            source: LyricsProviders.ServiceID.kugou.displayName,
            provider: LyricsProviders.Service.kugou.create()
        ),
        LyricsProviders.ProviderDescriptor(
            source: LyricsProviders.ServiceID.lrclib.displayName,
            provider: LyricsProviders.Service.lrclib.create()
        ),
    ]
    if let token = musixmatchToken, !token.isEmpty {
        descriptors.append(LyricsProviders.ProviderDescriptor(
            source: LyricsProviders.ServiceID.musixmatch.displayName,
            provider: LyricsProviders.Service.musixmatch.create(
                LyricsProviders.MusixmatchOptions(usertoken: token)
            )
        ))
    }
    return descriptors
}

/// Reconciles a saved source-priority order with the sources that exist now: names of
/// removed providers are dropped and new providers are appended, so the user's ordering
/// survives provider changes. An empty saved order means "not customised yet".
public func normalizedSourceOrder(_ saved: [String], known: [String]) -> [String] {
    var normalized = (saved.isEmpty ? known : saved).filter(known.contains)
    for source in known where !normalized.contains(source) {
        normalized.append(source)
    }
    return normalized
}

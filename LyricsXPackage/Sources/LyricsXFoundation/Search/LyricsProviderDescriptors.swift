@preconcurrency import LyricsKit

/// The canonical lyrics-provider descriptor list, shared by the app's search
/// pipeline and any out-of-app tooling.
///
/// This is the single source of truth for *which* lyrics sources exist and in
/// what order they are queried. Adding or removing a provider here updates every
/// caller — the app's `LyricsSearchPipeline`/`LyricsSelector` and the
/// `lyrics-diag` tool — at once.
///
/// Musixmatch is appended only when a non-empty token is supplied, matching the
/// app's conditional provider group.
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

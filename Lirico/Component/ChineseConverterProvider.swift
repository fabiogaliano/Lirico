import Combine
import Foundation
import GenericID
import OpenCC

/// Owns the current `ChineseConverter` instance and keeps it in sync with the
/// user's `chineseConversionIndex` preference.
///
/// Constructed once during app startup so the converter's lifecycle is visible
/// at the composition root rather than spun up lazily by the first call site.
/// Consumers read `converter` at render/export time and pass it to
/// `LineRenderer.render` or `LyricsPersister.writeToiTunes`.
final class ChineseConverterProvider {
    @Published private(set) var converter: ChineseConverter?

    var converterPublisher: AnyPublisher<ChineseConverter?, Never> {
        $converter.eraseToAnyPublisher()
    }

    private let defaults: UserDefaults
    private var observation: (any DefaultsObservation)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        observation = defaults.observe(.chineseConversionIndex, options: [.new, .initial]) { [weak self] _, change in
            self?.rebuild(forIndex: change.newValue)
        }
    }

    private func rebuild(forIndex index: Int?) {
        switch index {
        case 1: converter = try? ChineseConverter(options: [.simplify])
        case 2: converter = try? ChineseConverter(options: [.traditionalize])
        case 3: converter = try? ChineseConverter(options: [.traditionalize, .twStandard])
        case 4: converter = try? ChineseConverter(options: [.traditionalize, .hkStandard])
        default: converter = nil
        }
    }
}

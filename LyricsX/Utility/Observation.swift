import AppKit
import GenericID

final class ArchivedColorBindingTransformer: ValueTransformer {
    static let name = NSValueTransformerName("ArchivedColorBindingTransformer")

    static func register() {
        ValueTransformer.setValueTransformer(ArchivedColorBindingTransformer(), forName: name)
    }

    override class func transformedValueClass() -> AnyClass {
        NSColor.self
    }

    override class func allowsReverseTransformation() -> Bool {
        true
    }

    override func transformedValue(_ value: Any?) -> Any? {
        guard let data = value as? Data else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data)
    }

    override func reverseTransformedValue(_ value: Any?) -> Any? {
        guard let color = value as? NSColor else { return nil }
        return try? NSKeyedArchiver.archivedData(withRootObject: color, requiringSecureCoding: true)
    }
}

extension UserDefaults.DefaultsKeys {
    fileprivate var usesArchivedColorBindingTransformer: Bool {
        switch key {
        case UserDefaults.DefaultsKeys.desktopLyricsColor.key,
             UserDefaults.DefaultsKeys.desktopLyricsProgressColor.key,
             UserDefaults.DefaultsKeys.desktopLyricsShadowColor.key,
             UserDefaults.DefaultsKeys.desktopLyricsBackgroundColor.key,
             UserDefaults.DefaultsKeys.lyricsWindowTextColor.key,
             UserDefaults.DefaultsKeys.lyricsWindowHighlightColor.key:
            return true
        default:
            return false
        }
    }
}

private class NotificationObservationToken {
    var center: NotificationCenter?
    var token: NSObjectProtocol?

    init(center: NotificationCenter, token: NSObjectProtocol) {
        self.center = center
        self.token = token
    }

    func invalidate() {
        if let center = center, let token = token {
            center.removeObserver(token)
        }
        center = nil
        token = nil
    }

    deinit {
        invalidate()
    }
}

extension NSObject {
    private static var autoDestructionTokens: Void?

    // using [Any] causes unexpected destruction, use NSMutableArray instead.
    private var autoDestruction: NSMutableArray {
        if let arr = objc_getAssociatedObject(self, &NSObject.autoDestructionTokens) as? NSMutableArray {
            return arr
        }
        let arr = NSMutableArray()
        objc_setAssociatedObject(self, &NSObject.autoDestructionTokens, arr, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return arr
    }

    func postNotification(
        center: NotificationCenter = .default,
        name: NSNotification.Name,
        userInfo: [String: Any] = [:]
    ) {
        center.post(name: name, object: self, userInfo: userInfo)
    }

    func observeNotification(
        center: NotificationCenter = .default,
        name: NSNotification.Name,
        object: Any? = nil,
        queue: OperationQueue? = nil,
        using: @escaping (Notification) -> Void
    ) {
        let token = center.addObserver(forName: name, object: object, queue: queue, using: using)
        autoDestruction.add(NotificationObservationToken(center: center, token: token))
    }

    func observeObject<Target: NSObject, Value>(
        _ object: Target,
        keyPath: KeyPath<Target, Value>,
        options: NSKeyValueObservingOptions,
        changeHandler: @escaping (NSObject, NSKeyValueObservedChange<Value>) -> Void
    ) {
        let token = object.observe(keyPath, options: options, changeHandler: changeHandler)
        autoDestruction.add(token)
    }

    func observeDefaults<T>(
        _ defaults: UserDefaults = .standard,
        key: UserDefaults.DefaultsKeys.Key<T>,
        options: NSKeyValueObservingOptions = [],
        changeHandler: @escaping (UserDefaults, UserDefaults.DefaultsObservedChange<T>) -> Void
    ) {
        let token = defaults.observe(key, options: options, changeHandler: changeHandler)
        autoDestruction.add(token)
    }

    func observeDefaults<T: DefaultConstructible>(
        _ defaults: UserDefaults = .standard,
        key: UserDefaults.DefaultsKeys.Key<T>,
        options: NSKeyValueObservingOptions = [],
        changeHandler: @escaping (UserDefaults, UserDefaults.ConstructedDefaultsObservedChange<T>) -> Void
    ) {
        let token = defaults.observe(key, options: options, changeHandler: changeHandler)
        autoDestruction.add(token)
    }

    func observeDefaults(
        _ defaults: UserDefaults = .standard,
        keys: [UserDefaults.DefaultsKeys],
        options: NSKeyValueObservingOptions = [],
        changeHandler: @escaping () -> Void
    ) {
        let token = defaults.observe(keys: keys, options: options, changeHandler: changeHandler)
        autoDestruction.add(token)
    }
}

/// MARK: Binding

protocol KeyPathBinding {}

extension NSObject {
    func bind(
        _ binding: NSBindingName,
        to observable: UserDefaults = .standard,
        withDefaultName defaultName: UserDefaults.DefaultsKeys,
        options: [NSBindingOption: Any] = [:]
    ) {
        var options = options
        if defaultName.usesArchivedColorBindingTransformer {
            options[.valueTransformerName] = ArchivedColorBindingTransformer.name
        } else if defaultName.valueTransformer != nil {
            options[.valueTransformerName] = NSValueTransformerName("NSKeyedUnarchiveFromData")
        }
        bind(binding, to: observable, withKeyPath: defaultName.key, options: options)
    }
}

extension KeyPathBinding where Self: NSObject {
    func bind<Target, Value>(
        _ binding: KeyPath<Self, Value>,
        to observable: Target,
        withKeyPath keyPath: KeyPath<Target, Value>,
        options: [NSBindingOption: Any] = [:]
    ) {
        bind(NSBindingName(binding._kvcKeyPathString!), to: observable, withKeyPath: keyPath._kvcKeyPathString!, options: options)
    }

    func bind<Target, Value>(
        _ binding: KeyPath<Self, Value?>,
        to observable: Target,
        withKeyPath keyPath: KeyPath<Target, Value>,
        options: [NSBindingOption: Any] = [:]
    ) {
        bind(NSBindingName(binding._kvcKeyPathString!), to: observable, withKeyPath: keyPath._kvcKeyPathString!, options: options)
    }

    func bind<Value>(
        _ binding: KeyPath<Self, Value>,
        to defaults: UserDefaults = .standard,
        withDefaultName defaultName: UserDefaults.DefaultsKey<Value>,
        options: [NSBindingOption: Any] = [:]
    ) {
        bind(NSBindingName(binding._kvcKeyPathString!), to: defaults, withDefaultName: defaultName, options: options)
    }

    func bind<Value>(
        _ binding: KeyPath<Self, Value>,
        to defaults: UserDefaults = .standard,
        withUnmatchedDefaultName defaultName: UserDefaults.DefaultsKeys,
        options: [NSBindingOption: Any] = [:]
    ) {
        bind(NSBindingName(binding._kvcKeyPathString!), to: defaults, withDefaultName: defaultName, options: options)
    }
}

extension NSObject: KeyPathBinding {}

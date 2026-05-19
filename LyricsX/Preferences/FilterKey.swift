import AppKit

// The @objc runtime name is preserved so Interface Builder bindings in
// Preferences.storyboard (objectClassName="FilterKey", classReference
// className="FilterKey") continue to resolve.
@objc(FilterKey)
class LyricsFilterKeyword: NSObject, NSCoding {
    @objc var keyword = "keyword"

    override init() {
        super.init()
    }

    init(keyword: String) {
        self.keyword = keyword
        super.init()
    }

    required init?(coder aDecoder: NSCoder) {
        guard let decodeKey = aDecoder.decodeObject(forKey: "keyword") as? String else {
            return nil
        }
        self.keyword = decodeKey
        super.init()
    }

    func encode(with aCoder: NSCoder) {
        aCoder.encode(keyword, forKey: "keyword")
    }
}

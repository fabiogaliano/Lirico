import AppKit

/// Fetches an artwork image from a URL. Calls back on the main queue.
/// Returns nil on any network or decoding failure; diagnostic output is
/// logged to console.
func fetchArtwork(url: URL, completion: @escaping (NSImage?) -> Void) {
    URLSession.shared.dataTask(with: url) { data, _, error in
        let image: NSImage?
        if let data, error == nil {
            image = NSImage(data: data)
            if image == nil {
                print("Failed to create image from data.")
            }
        } else {
            print("Failed to download image data: \(error?.localizedDescription ?? "Unknown error")")
            image = nil
        }
        DispatchQueue.main.async {
            completion(image)
        }
    }.resume()
}

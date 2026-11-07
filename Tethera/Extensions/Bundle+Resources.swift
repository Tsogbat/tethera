import Foundation

extension Bundle {
    /// Tethera's SwiftPM resource bundle. In a packaged app it lives in Contents/Resources,
    /// where SwiftPM's generated `Bundle.module` doesn't look (it checks the .app root, which
    /// code signing forbids, then the build folder on the machine that compiled it).
    static let tethera: Bundle = {
        let name = "Tethera_Tethera.bundle"
        if let resources = Bundle.main.resourceURL,
           let bundle = Bundle(url: resources.appendingPathComponent(name)) {
            return bundle
        }
        return Bundle.module
    }()
}

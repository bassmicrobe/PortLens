import AppKit

enum BrandResources {
    static let bundle: Bundle = {
        // App bundles keep resources in Contents/Resources. SwiftPM's generated
        // accessor also supports `swift run` through its build-directory path.
        if let url = Bundle.main.resourceURL?.appendingPathComponent("PortLens_PortLens.bundle"),
           let bundle = Bundle(url: url) {
            return bundle
        }
        return .module
    }()

    static let lightLogo = bundle.image(forResource: "portlens-lockup-light")
    static let darkLogo = bundle.image(forResource: "portlens-lockup-dark")
}

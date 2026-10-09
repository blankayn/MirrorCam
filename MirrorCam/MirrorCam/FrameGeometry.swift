import Foundation

enum PhotoAspect: Int, CaseIterable {
    case full, square, wide
    var title: String { return ["4:3 Full", "1:1 Square", "16:9 Wide"][rawValue] }
    var landscapeRatio: CGFloat { return [4.0 / 3.0, 1, 16.0 / 9.0][rawValue] }
    var portraitRatio: CGFloat { return 1 / landscapeRatio }
}

enum PhotoResolution: Int, CaseIterable {
    case maximum, medium, small
    var title: String { return ["Maximum", "1280 px", "640 px"][rawValue] }
    var maxEdge: CGFloat? { return [nil, 1280, 640][rawValue] }
}

struct PhotoOptions {
    var aspect: PhotoAspect = .full
    var resolution: PhotoResolution = .maximum
}

/// The visible frame and saved media use the same centered aspect crop.
enum FrameGeometry {
    static func crop(_ size: CGSize, aspect: PhotoAspect) -> CGRect {
        guard size.width > 0, size.height > 0 else { return .zero }
        let ratio = size.width > size.height ? aspect.landscapeRatio : aspect.portraitRatio
        let width = min(size.width, size.height * ratio)
        let height = min(size.height, size.width / ratio)
        return CGRect(x: (size.width - width) / 2, y: (size.height - height) / 2, width: width, height: height)
    }

    static func outputSize(_ size: CGSize, maxEdge: CGFloat?) -> CGSize {
        let scale = min(1, (maxEdge ?? max(size.width, size.height)) / max(size.width, size.height, 1))
        return CGSize(width: max(2, floor(size.width * scale / 2) * 2),
                      height: max(2, floor(size.height * scale / 2) * 2))
    }
}

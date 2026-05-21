import UIKit

// Downscales and JPEG-encodes a picked photo before it is copied into the
// app's SwiftData store. A motivation photo is shown at roughly card size, so
// there is no need to keep a multi-megapixel original.
enum MotivationImageProcessor {
    static let maxDimension: CGFloat = 1600
    static let jpegQuality: CGFloat = 0.8

    static func makeStorableData(from image: UIImage) -> Data? {
        downscaled(image, maxDimension: maxDimension)
            .jpegData(compressionQuality: jpegQuality)
    }

    private static func downscaled(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let longestSide = max(image.size.width, image.size.height)
        guard longestSide > maxDimension else { return image }

        let scale = maxDimension / longestSide
        let targetSize = CGSize(
            width: image.size.width * scale,
            height: image.size.height * scale
        )

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}

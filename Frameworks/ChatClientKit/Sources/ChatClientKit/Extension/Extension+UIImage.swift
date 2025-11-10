#if canImport(UIKit)
//
    //  Extension+UIImage.swift
    //  ChatClientKit
//
    //  Created by 秋星桥 on 2/19/25.
//

    import UIKit

    extension UIImage {
        enum ContentMode {
            case contentFill
            case contentAspectFill
            case contentAspectFit
        }

        func resize(withSize size: CGSize, contentMode: ContentMode = .contentAspectFill) -> UIImage? {
            let aspectWidth = size.width / self.size.width
            let aspectHeight = size.height / self.size.height

            switch contentMode {
            case .contentFill:
                return resize(withSize: size)
            case .contentAspectFit:
                let aspectRatio = min(aspectWidth, aspectHeight)
                return resize(withSize: CGSize(width: self.size.width * aspectRatio, height: self.size.height * aspectRatio))
            case .contentAspectFill:
                let aspectRatio = max(aspectWidth, aspectHeight)
                return resize(withSize: CGSize(width: self.size.width * aspectRatio, height: self.size.height * aspectRatio))
            }
        }

        private func resize(withSize size: CGSize) -> UIImage? {
            UIGraphicsBeginImageContextWithOptions(size, false, scale)
            defer { UIGraphicsEndImageContext() }
            draw(in: CGRect(x: 0.0, y: 0.0, width: size.width, height: size.height))
            return UIGraphicsGetImageFromCurrentImageContext()
        }

        convenience init(color: UIColor, size: CGSize) {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            guard let image = UIGraphicsImageRenderer(size: size, format: format).image(actions: { context in
                color.setFill()
                context.fill(context.format.bounds)
            }).cgImage else {
                self.init()
                return
            }
            self.init(cgImage: image)
        }
    }
#endif

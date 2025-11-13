//
//  ShimmerTextLabel.swift
//  FlowDown
//
//  Created by Willow Zhang on 11/14/25
//

import UIKit

/// A label that displays text with an animated shimmer effect that sweeps across characters
final class ShimmerTextLabel: UILabel {
    private var isAnimating = false
    private let gradientLayer = CAGradientLayer()
    private var originalTextColor: UIColor?
    private var cachedIntrinsicSize: CGSize?

    /// Controls the shimmer animation speed (duration for one complete cycle)
    var animationDuration: TimeInterval = 1.5

    /// The size of the shimmer band (0.3 = 30% of the view width)
    private let bandSize: CGFloat = 0.3

    override var intrinsicContentSize: CGSize {
        // Use cached size during animation to prevent incorrect sizing when textColor is clear
        if isAnimating, let cached = cachedIntrinsicSize {
            return cached
        }
        return super.intrinsicContentSize
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupGradientLayer()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()

        if window != nil, isAnimating {
            startShimmerAnimation()
        } else {
            gradientLayer.removeAllAnimations()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if isAnimating {
            gradientLayer.frame = bounds
        }
    }

    private func setupGradientLayer() {
        // Horizontal gradient, starting from left outside
        gradientLayer.startPoint = CGPoint(x: -bandSize, y: 0.5)
        gradientLayer.endPoint = CGPoint(x: 0, y: 0.5)

        updateGradientColors()
    }

    private func updateGradientColors() {
        // Gradient colors: dark -> bright -> dark
        let baseColor = originalTextColor ?? textColor ?? .label

        gradientLayer.colors = [
            baseColor.withAlphaComponent(0.3).cgColor,
            baseColor.cgColor,
            baseColor.withAlphaComponent(0.3).cgColor,
        ]

        gradientLayer.locations = [0, 0.5, 1]
    }

    /// Start the shimmer animation
    func startShimmer() {
        guard !isAnimating else { return }

        // Cache intrinsic size before changing text color
        cachedIntrinsicSize = super.intrinsicContentSize

        isAnimating = true

        // Save original text color
        originalTextColor = textColor

        // Update gradient colors
        updateGradientColors()

        // Hide original text, display via gradient layer + mask
        textColor = .clear
        gradientLayer.frame = bounds
        layer.addSublayer(gradientLayer)

        // Use text as mask
        if let maskLayer = createTextMaskLayer() {
            gradientLayer.mask = maskLayer
        }

        if window != nil {
            startShimmerAnimation()
        }
    }

    /// Stop the shimmer animation and return to normal state
    func stopShimmer() {
        isAnimating = false
        gradientLayer.removeAllAnimations()
        gradientLayer.removeFromSuperlayer()
        gradientLayer.mask = nil
        textColor = originalTextColor ?? .label
        originalTextColor = nil
        cachedIntrinsicSize = nil
    }

    private func createTextMaskLayer() -> CALayer? {
        guard let text, !text.isEmpty else { return nil }

        // Render text to image using UIGraphicsImageRenderer
        let renderer = UIGraphicsImageRenderer(size: bounds.size)
        let image = renderer.image { _ in
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = textAlignment

            let attributes: [NSAttributedString.Key: Any] = [
                .font: font as Any,
                .foregroundColor: UIColor.white,
                .paragraphStyle: paragraphStyle,
            ]

            let textRect = CGRect(origin: .zero, size: bounds.size)
            (text as NSString).draw(in: textRect, withAttributes: attributes)
        }

        let maskLayer = CALayer()
        maskLayer.frame = bounds
        maskLayer.contents = image.cgImage
        maskLayer.contentsScale = UIScreen.main.scale

        return maskLayer
    }

    private func startShimmerAnimation() {
        gradientLayer.removeAllAnimations()

        let min = -bandSize
        let max: CGFloat = 1 + bandSize

        // Start point animation: from left outside -> right outside (horizontal)
        let startPointAnimation = CABasicAnimation(keyPath: "startPoint")
        startPointAnimation.fromValue = CGPoint(x: min, y: 0.5)
        startPointAnimation.toValue = CGPoint(x: max, y: 0.5)

        // End point animation: from left -> right outside (horizontal)
        let endPointAnimation = CABasicAnimation(keyPath: "endPoint")
        endPointAnimation.fromValue = CGPoint(x: 0, y: 0.5)
        endPointAnimation.toValue = CGPoint(x: max + bandSize, y: 0.5)

        // Combine animations
        let group = CAAnimationGroup()
        group.animations = [startPointAnimation, endPointAnimation]
        group.duration = animationDuration
        group.repeatCount = .infinity
        group.timingFunction = CAMediaTimingFunction(name: .linear)

        gradientLayer.add(group, forKey: "shimmer")
    }
}

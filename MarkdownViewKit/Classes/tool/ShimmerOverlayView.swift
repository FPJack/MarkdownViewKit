//
//  ShimmerOverlayView.swift
//  MarkdownViewKit
//
//  一个可复用的「光晕 + 高光扫描」动画视图。
//
//  - 在自身范围内画一层边缘辉光（呼吸）+ 一条横向掠过的高光光带；
//  - `isAnimating` 控制是否播放；
//  - 自动处理前后台切换 / 视图重新入 window 后 CAAnimation 被系统清空的问题；
//  - `isUserInteractionEnabled = false`，不拦截手势，随意贴在其他视图上层。
//
//  用法：
//    let shimmer = ShimmerOverlayView()
//    shimmer.highlightColor = .systemBlue.withAlphaComponent(0.5)
//    shimmer.isAnimating = true
//    otherView.addSubview(shimmer)
//    shimmer.frame = otherView.bounds
//

import UIKit

public final class ShimmerOverlayView: UIView {

    // MARK: 配置

    /// 是否播放动画。默认 `false`。改动即生效。
    public var isAnimating: Bool = false {
        didSet {
            guard oldValue != isAnimating else { return }
            update()
        }
    }

    /// 高光扫描色（光带正中的颜色，两侧会淡出到透明）。
    public var highlightColor: UIColor = UIColor(red: 0.36, green: 0.62, blue: 1.0, alpha: 0.55) {
        didSet { refreshColors() }
    }

    /// 边缘辉光颜色（border + shadow）。
    public var glowColor: UIColor = UIColor(red: 0.36, green: 0.62, blue: 1.0, alpha: 0.9) {
        didSet { refreshColors() }
    }

    /// 光带扫过一次的时长（秒）。默认 1.6。
    public var duration: TimeInterval = 1.6 {
        didSet { if isAnimating { restart() } }
    }

    /// 边缘辉光的边框宽度。默认 2。
    public var glowBorderWidth: CGFloat = 2 {
        didSet { glowLayer?.borderWidth = glowBorderWidth }
    }

    /// 边缘辉光的阴影半径。默认 10。
    public var glowShadowRadius: CGFloat = 10 {
        didSet { glowLayer?.shadowRadius = glowShadowRadius }
    }

    /// 圆角，会同时应用到辉光边框。默认 0。
    public override var frame: CGRect {
        didSet { setNeedsLayout() }
    }

    // MARK: 私有

    private var gradientLayer: CAGradientLayer?
    private var glowLayer: CALayer?

    // MARK: 生命周期

    public override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        backgroundColor = .clear
        isUserInteractionEnabled = false
        setupLifecycleObservers()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func setupLifecycleObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppWillResignActive),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )
    }

    @objc private func handleAppDidBecomeActive() {
        if isAnimating { restart() }
    }

    @objc private func handleAppWillResignActive() {
        if isAnimating { uninstall() }
    }

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            if isAnimating { restart() }
        } else {
            uninstall()
        }
    }

    // MARK: Layout

    public override func layoutSubviews() {
        super.layoutSubviews()
        gradientLayer?.frame = bounds
        glowLayer?.frame = bounds
        glowLayer?.cornerRadius = layer.cornerRadius
    }

    // MARK: 内部：安装 / 卸载 / 重启

    private func update() {
        if isAnimating {
            install()
        } else {
            uninstall()
        }
    }

    private func restart() {
        uninstall()
        install()
    }

    private func install() {
        // 边缘辉光
        let glow = CALayer()
        glow.frame = bounds
        glow.borderColor = glowColor.cgColor
        glow.borderWidth = glowBorderWidth
        glow.cornerRadius = layer.cornerRadius
        glow.shadowColor = glowColor.cgColor
        glow.shadowOffset = .zero
        glow.shadowRadius = glowShadowRadius
        glow.shadowOpacity = 0.9
        glow.masksToBounds = false
        layer.addSublayer(glow)

        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 0.35
        pulse.toValue = 1.0
        pulse.duration = max(0.4, duration * 0.75)
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        pulse.isRemovedOnCompletion = false
        glow.add(pulse, forKey: "shimmer.pulse")

        // 高光扫描
        let g = CAGradientLayer()
        g.frame = bounds
        g.startPoint = CGPoint(x: 0, y: 0.5)
        g.endPoint   = CGPoint(x: 1, y: 0.5)
        g.colors = gradientColors()
        g.locations = [0.0, 0.5, 1.0]
        layer.addSublayer(g)

        let sweep = CABasicAnimation(keyPath: "locations")
        sweep.fromValue = [-1.0, -0.5, 0.0]
        sweep.toValue   = [ 1.0,  1.5, 2.0]
        sweep.duration  = max(0.3, duration)
        sweep.repeatCount = .infinity
        sweep.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        sweep.isRemovedOnCompletion = false
        g.add(sweep, forKey: "shimmer.sweep")

        glowLayer = glow
        gradientLayer = g
    }

    private func uninstall() {
        gradientLayer?.removeAllAnimations()
        gradientLayer?.removeFromSuperlayer()
        gradientLayer = nil

        glowLayer?.removeAllAnimations()
        glowLayer?.removeFromSuperlayer()
        glowLayer = nil
    }

    private func refreshColors() {
        gradientLayer?.colors = gradientColors()
        glowLayer?.borderColor = glowColor.cgColor
        glowLayer?.shadowColor = glowColor.cgColor
    }

    private func gradientColors() -> [CGColor] {
        let edge = highlightColor.withAlphaComponent(0)
        return [edge.cgColor, highlightColor.cgColor, edge.cgColor]
    }
}

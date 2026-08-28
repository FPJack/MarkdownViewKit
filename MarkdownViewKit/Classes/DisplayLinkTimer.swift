//
//  DisplayLinkTimer.swift
//  MarkdownViewKit
//
//  基于 CADisplayLink 的高精度定时器封装。
//  - 使用 block 回调，避免 target-action 生命周期陷阱。
//  - 内部持有一个 target proxy（弱引用宿主），避免 CADisplayLink 强引用造成循环。
//  - 提供 start/pause/resume/stop/reset/fire/invalidate 全套 API。
//  - 支持首次触发延时、最大 tick 次数、期望 FPS、优先级 / RunLoop mode 配置。
//

import UIKit

/// 定时器状态。
@objc public enum DisplayLinkTimerState: Int {
    /// 未启动 / 已停止（可再次 start）。
    case idle
    /// 正在运行。
    case running
    /// 已暂停（保留累计时长与 tick 计数，可 resume）。
    case paused
    /// 已失效（不可再复用，需要重新创建实例）。
    case invalidated
}

/// 每次回调携带的信息。
@objc public class DisplayLinkTimerTick: NSObject {

    /// 距离上一次回调的时间（秒）。
    @objc public let deltaTime: CFTimeInterval

    /// 从 start 开始累计的运行时长（不包括 paused 期间），秒。
    @objc public let elapsedTime: CFTimeInterval

    /// 从 start 开始累计触发次数（从 1 开始）。
    @objc public let tickCount: UInt64

    /// 本次回调对应的 CADisplayLink.timestamp（当前帧起始的绝对时间）。
    @objc public let timestamp: CFTimeInterval

    /// 本次回调对应的 CADisplayLink.targetTimestamp（下一帧预期时间）。
    @objc public let targetTimestamp: CFTimeInterval

    /// 当前实际帧间隔（duration，秒）。
    @objc public let duration: CFTimeInterval

    fileprivate init(deltaTime: CFTimeInterval,
                     elapsedTime: CFTimeInterval,
                     tickCount: UInt64,
                     timestamp: CFTimeInterval,
                     targetTimestamp: CFTimeInterval,
                     duration: CFTimeInterval) {
        self.deltaTime = deltaTime
        self.elapsedTime = elapsedTime
        self.tickCount = tickCount
        self.timestamp = timestamp
        self.targetTimestamp = targetTimestamp
        self.duration = duration
        super.init()
    }
}

/// 基于 CADisplayLink 的定时器（外部通过 block 回调）。
///
/// 用法示例：
/// ```swift
/// let timer = DisplayLinkTimer()
/// timer.preferredFramesPerSecond = 30
/// timer.onTick = { tick in
///     print(tick.deltaTime, tick.tickCount)
/// }
/// timer.start()
///
/// // 后续可以 pause / resume / stop / reset
/// timer.pause()
/// timer.resume()
/// timer.stop()
/// ```
public final class DisplayLinkTimer: NSObject {

    // MARK: - Public callbacks

    /// 每次触发回调。
    public var onTick: ((DisplayLinkTimerTick) -> Void)?

    /// 状态变化回调（可选）。
    public var onStateChange: ((DisplayLinkTimerState) -> Void)?

    /// 达到 `maxTickCount` 上限、或 `duration` 到达时的回调（只会触发一次，随后 timer 自动 stop）。
    public var onFinished: (() -> Void)?

    // MARK: - Public configuration

    /// 期望帧率（0 表示跟随屏幕最高刷新率，默认 0）。
    /// 运行中可修改，会立即生效。
    public var preferredFramesPerSecond: Int = 0 {
        didSet {
            guard oldValue != preferredFramesPerSecond else { return }
            applyPreferredFPS()
        }
    }

    /// RunLoop 运行的 mode（默认 .common，滚动时不会被暂停）。
    /// 只有在下一次 start 时生效；如需运行中切换，需要 stop 后再 start。
    public var runLoopMode: RunLoop.Mode = .common

    /// 首次触发前的延时（秒），默认 0 表示立即开始计次。
    /// 在 delay 期间也会收到 CADisplayLink 回调，但不会调用 `onTick`。
    public var startDelay: TimeInterval = 0

    /// 最大触发次数，0 表示无限制（默认 0）。
    public var maxTickCount: UInt64 = 0

    /// 最大运行时长（秒），<= 0 表示无限制（默认 0）。
    public var duration: TimeInterval = 0

    /// 触发回调所在的队列。nil 表示在 CADisplayLink 所在 RunLoop 线程（一般是主线程）直接回调。
    public var callbackQueue: DispatchQueue?

    // MARK: - Public read-only state

    /// 当前状态。
    public private(set) var state: DisplayLinkTimerState = .idle {
        didSet {
            guard oldValue != state else { return }
            onStateChange?(state)
        }
    }

    /// 累计触发次数（tick）。
    public private(set) var tickCount: UInt64 = 0

    /// 累计运行时长（秒，不包含暂停期间）。
    public private(set) var elapsedTime: CFTimeInterval = 0

    /// 上一次回调的时间戳（CADisplayLink.timestamp）。
    public private(set) var lastTimestamp: CFTimeInterval = 0

    /// 是否处于运行中。
    public var isRunning: Bool { state == .running }

    /// 是否已暂停。
    public var isPaused: Bool { state == .paused }

    /// 是否已失效。
    public var isInvalidated: Bool { state == .invalidated }

    // MARK: - Private

    private var displayLink: CADisplayLink?
    private var proxy: WeakProxy?
    /// delay 起点（用于 startDelay）。
    private var startAnchorTimestamp: CFTimeInterval = 0
    /// 是否已经完成过 delay，避免 delay 内重复判断。
    private var delayFinished: Bool = false

    // MARK: - Init / Deinit

    public override init() {
        super.init()
    }

    /// 便捷初始化。
    /// - Parameters:
    ///   - preferredFramesPerSecond: 期望帧率，0 表示跟随屏幕最高刷新率。
    ///   - onTick: 每次触发的回调。
    public convenience init(preferredFramesPerSecond: Int = 0,
                            onTick: ((DisplayLinkTimerTick) -> Void)? = nil) {
        self.init()
        self.preferredFramesPerSecond = preferredFramesPerSecond
        self.onTick = onTick
    }

    deinit {
        // 释放前一定要 invalidate，避免 CADisplayLink 悬空回调。
        invalidateInternal(setState: false)
    }

    // MARK: - Public API

    /// 启动定时器。若当前处于 .paused，会等效于 `resume()`；若已 invalidated，则忽略。
    public func start() {
        guard state != .invalidated else { return }
        if state == .paused {
            resume()
            return
        }
        if state == .running { return }

        // 每次 start 都重建 displayLink，保证行为一致。
        buildDisplayLinkIfNeeded()
        tickCount = 0
        elapsedTime = 0
        lastTimestamp = 0
        delayFinished = (startDelay <= 0)
        startAnchorTimestamp = 0
        displayLink?.isPaused = false
        state = .running
    }

    /// 暂停定时器（保留累计 tickCount / elapsedTime，可 resume）。
    public func pause() {
        guard state == .running else { return }
        displayLink?.isPaused = true
        // 暂停后需要重置 lastTimestamp，避免 resume 时 deltaTime 异常。
        lastTimestamp = 0
        state = .paused
    }

    /// 恢复定时器。
    public func resume() {
        guard state == .paused else { return }
        displayLink?.isPaused = false
        state = .running
    }

    /// 停止定时器（回到 .idle 状态，可再次 start；清空 tickCount / elapsedTime）。
    public func stop() {
        guard state != .idle, state != .invalidated else { return }
        teardownDisplayLink()
        tickCount = 0
        elapsedTime = 0
        lastTimestamp = 0
        delayFinished = false
        state = .idle
    }

    /// 重置计数（不改变运行状态）。
    public func reset() {
        tickCount = 0
        elapsedTime = 0
        lastTimestamp = 0
        delayFinished = (startDelay <= 0)
        startAnchorTimestamp = 0
    }

    /// 立即触发一次回调（不影响正常的定时器节奏）。
    /// - Parameter deltaTime: 传给回调的 deltaTime，默认 0。
    public func fire(deltaTime: CFTimeInterval = 0) {
        let now = CACurrentMediaTime()
        let dl = displayLink
        let info = DisplayLinkTimerTick(
            deltaTime: deltaTime,
            elapsedTime: elapsedTime,
            tickCount: tickCount &+ 1,
            timestamp: dl?.timestamp ?? now,
            targetTimestamp: dl?.targetTimestamp ?? now,
            duration: dl?.duration ?? 0
        )
        dispatchTick(info)
    }

    /// 永久失效（释放资源，之后无法再 start）。
    public func invalidate() {
        invalidateInternal(setState: true)
    }

    // MARK: - Internal

    private func buildDisplayLinkIfNeeded() {
        if displayLink != nil { return }
        let proxy = WeakProxy(target: self)
        let dl = CADisplayLink(target: proxy, selector: #selector(WeakProxy.step(_:)))
        self.proxy = proxy
        self.displayLink = dl
        applyPreferredFPS()
        dl.add(to: .main, forMode: runLoopMode)
    }

    private func teardownDisplayLink() {
        displayLink?.isPaused = true
        displayLink?.invalidate()
        displayLink = nil
        proxy = nil
    }

    private func invalidateInternal(setState: Bool) {
        teardownDisplayLink()
        if setState {
            state = .invalidated
        }
    }

    private func applyPreferredFPS() {
        guard let dl = displayLink else { return }
        if preferredFramesPerSecond <= 0 {
            // 跟随屏幕最大刷新率。
            if #available(iOS 15.0, *) {
                dl.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 120, preferred: 0)
            } else {
                dl.preferredFramesPerSecond = 0
            }
        } else {
            if #available(iOS 15.0, *) {
                let fps = Float(preferredFramesPerSecond)
                dl.preferredFrameRateRange = CAFrameRateRange(minimum: fps, maximum: fps, preferred: fps)
            } else {
                dl.preferredFramesPerSecond = preferredFramesPerSecond
            }
        }
    }

    /// CADisplayLink 每帧回调（由 WeakProxy 转发）。
    fileprivate func handleStep(_ link: CADisplayLink) {
        guard state == .running else { return }

        // 处理 startDelay。
        if !delayFinished {
            if startAnchorTimestamp == 0 { startAnchorTimestamp = link.timestamp }
            if link.timestamp - startAnchorTimestamp < startDelay {
                // 还没到首次触发时间，只更新 lastTimestamp。
                lastTimestamp = link.timestamp
                return
            }
            delayFinished = true
            // 首次真正触发时，把 lastTimestamp 归位到当前帧。
            lastTimestamp = link.timestamp
        }

        let delta: CFTimeInterval
        if lastTimestamp == 0 {
            delta = link.duration
        } else {
            delta = link.timestamp - lastTimestamp
        }
        lastTimestamp = link.timestamp
        elapsedTime += delta
        tickCount = tickCount &+ 1

        let info = DisplayLinkTimerTick(
            deltaTime: delta,
            elapsedTime: elapsedTime,
            tickCount: tickCount,
            timestamp: link.timestamp,
            targetTimestamp: link.targetTimestamp,
            duration: link.duration
        )
        dispatchTick(info)

        // 到达 tick 上限。
        if maxTickCount > 0 && tickCount >= maxTickCount {
            finishAndStop()
            return
        }
        // 到达 duration 上限。
        if duration > 0 && elapsedTime >= duration {
            finishAndStop()
            return
        }
    }

    private func dispatchTick(_ info: DisplayLinkTimerTick) {
        if let queue = callbackQueue {
            queue.async { [weak self] in
                self?.onTick?(info)
            }
        } else {
            onTick?(info)
        }
    }

    private func finishAndStop() {
        let finished = onFinished
        stop()
        if let finished = finished {
            if let queue = callbackQueue {
                queue.async { finished() }
            } else {
                finished()
            }
        }
    }
}

// MARK: - WeakProxy

/// 用于 CADisplayLink 目标转发，避免其强引用宿主导致循环引用。
private final class WeakProxy: NSObject {
    weak var target: DisplayLinkTimer?

    init(target: DisplayLinkTimer) {
        self.target = target
        super.init()
    }

    @objc func step(_ link: CADisplayLink) {
        target?.handleStep(link)
    }
}

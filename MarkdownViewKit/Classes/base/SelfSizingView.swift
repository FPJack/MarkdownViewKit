//
//  SelfSizingView.swift
//  MarkdownViewKit
//
//  一个可继承的「自适应尺寸」基类视图：
//    - 根据内容自动计算 `intrinsicContentSize`（宽 / 高自适应）；
//    - 支持设置最小 / 最大 宽 / 高（<=0 表示该项不限制）；
//    - 内容尺寸变化时通过 `onContentSizeChanged` 回调通知外部；
//    - 子类只需重写 `contentSize(fittingWidth:)` 返回「内容自然尺寸」即可获得自适应能力，
//      基类负责按 min/max 裁剪、失效重排与变化通知。
//

import UIKit

open class SelfSizingView: UIView {

    // MARK: - 尺寸约束（<=0 表示不限制）

    /// 最小宽度。
    open var minWidth: CGFloat = 0 { didSet { if oldValue != minWidth { invalidateContentSize() } } }
    /// 最大宽度。内容超出时会被裁剪到该宽度（并据此换行 / 压缩）。
    open var maxWidth: CGFloat = 0 { didSet { if oldValue != maxWidth { invalidateContentSize() } } }
    /// 最小高度。
    open var minHeight: CGFloat = 0 { didSet { if oldValue != minHeight { invalidateContentSize() } } }
    /// 最大高度。超出部分由子类自行决定是否滚动展示。
    open var maxHeight: CGFloat = 0 { didSet { if oldValue != maxHeight { invalidateContentSize() } } }

    /// 一次性设置全部尺寸约束（任一参数传 <=0 表示不限制该项）。
    open func setSizeLimits(minWidth: CGFloat = 0,
                            maxWidth: CGFloat = 0,
                            minHeight: CGFloat = 0,
                            maxHeight: CGFloat = 0) {
        self.minWidth = minWidth
        self.maxWidth = maxWidth
        self.minHeight = minHeight
        self.maxHeight = maxHeight
        invalidateContentSize()
    }

    // MARK: - 尺寸变化回调

    /// 解析后的内容尺寸发生变化时回调（已应用 min/max 裁剪）。
    open var onContentSizeChanged: ((CGSize) -> Void)?

    /// 上一次已通知的尺寸，用于变化去抖。
    private var lastNotifiedSize: CGSize = .zero

    /// 重入保护：`systemLayoutSizeFitting` 会同步触发一次布局，可能再次进入
    /// `layoutSubviews` / 尺寸计算，若不加保护会造成无限递归（死循环）。
    private var isResolvingSize = false

    /// 缓存上一次解析出的尺寸（供重入时返回、避免递归）。
    private var lastResolvedSize: CGSize = .zero

    // MARK: - 子类可重写

    /// 返回「内容自然尺寸」（未经过 min/max 裁剪）。
    ///
    /// - Parameter availableWidth: 可用最大宽度。当设置了 `maxWidth` 时为该值，
    ///   否则为 `.greatestFiniteMagnitude`（不限制）。子类应据此测量内容（如文本换行）。
    ///
    /// 默认实现基于内部 Auto Layout 约束用 `systemLayoutSizeFitting` 计算；
    /// 手动布局的子类应重写此方法返回自行测量的尺寸（**不要调用 super**，
    /// 以避免不必要的 `systemLayoutSizeFitting` 开销）。
    open func contentSize(fittingWidth availableWidth: CGFloat) -> CGSize {
        let hasWidthLimit = availableWidth.isFinite && availableWidth > 0
        let target = CGSize(
            width: hasWidthLimit ? availableWidth : UIView.layoutFittingCompressedSize.width,
            height: UIView.layoutFittingCompressedSize.height
        )
        return systemLayoutSizeFitting(
            target,
            withHorizontalFittingPriority: hasWidthLimit ? .required : .fittingSizeLevel,
            verticalFittingPriority: .fittingSizeLevel
        )
    }

    // MARK: - 自适应尺寸

    /// 解析后的内容尺寸（已应用 min/max 裁剪）。
    /// 内部有重入保护：递归进入时直接返回上次已解析的尺寸，切断死循环。
    open var resolvedContentSize: CGSize {
        if isResolvingSize {
            return lastResolvedSize
        }
        isResolvingSize = true
        defer { isResolvingSize = false }
        let availableWidth = maxWidth > 0 ? maxWidth : CGFloat.greatestFiniteMagnitude
        let size = clamp(contentSize(fittingWidth: availableWidth))
        lastResolvedSize = size
        return size
    }

    open override var intrinsicContentSize: CGSize {
        resolvedContentSize
    }

    open override func sizeThatFits(_ size: CGSize) -> CGSize {
        let availableWidth: CGFloat
        if size.width > 0, size.width.isFinite {
            availableWidth = maxWidth > 0 ? min(size.width, maxWidth) : size.width
        } else {
            availableWidth = maxWidth > 0 ? maxWidth : .greatestFiniteMagnitude
        }
        if isResolvingSize { return lastResolvedSize }
        isResolvingSize = true
        defer { isResolvingSize = false }
        return clamp(contentSize(fittingWidth: availableWidth))
    }

    /// 内容发生变化后调用：失效固有尺寸、请求重排，并在尺寸变化时回调。
    /// 子类在数据 / 内容更新后应调用此方法。
    open func invalidateContentSize() {
        invalidateIntrinsicContentSize()
        setNeedsLayout()
        notifyContentSizeChangeIfNeeded()
    }

    open override func layoutSubviews() {
        super.layoutSubviews()
        notifyContentSizeChangeIfNeeded()
    }

    // MARK: - 私有

    private func notifyContentSizeChangeIfNeeded() {
        // 正在解析尺寸（systemLayoutSizeFitting 触发的嵌套布局）时不重复通知，切断递归。
        guard !isResolvingSize else { return }
        let size = resolvedContentSize
        // noIntrinsicMetric / 非有限值不参与通知。
        guard size.width.isFinite, size.height.isFinite else { return }
        guard size != lastNotifiedSize else { return }
        lastNotifiedSize = size
        onContentSizeChanged?(size)
    }

    /// 按 min/max 裁剪尺寸；无有效上限时对应轴返回 `UIView.noIntrinsicMetric`。
    private func clamp(_ size: CGSize) -> CGSize {
        var w = size.width
        var h = size.height

        if maxWidth > 0 { w = min(w, maxWidth) }
        if minWidth > 0 { w = max(w, minWidth) }
        if maxHeight > 0 { h = min(h, maxHeight) }
        if minHeight > 0 { h = max(h, minHeight) }

        if !w.isFinite { w = UIView.noIntrinsicMetric }
        if !h.isFinite { h = UIView.noIntrinsicMetric }
        return CGSize(width: w, height: h)
    }
}

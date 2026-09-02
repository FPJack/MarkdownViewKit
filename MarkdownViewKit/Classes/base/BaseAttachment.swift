//
//  BaseAttachment.swift
//  MarkdownViewKit
//
//  Created by admin on 2026/8/27.
//

import UIKit

public protocol ViewLoadable: UIView {
    associatedtype ViewData
    init()
    /// 视图数据，用于初始化或更新视图内容。
    var data: ViewData { get set }
    /// 视图尺寸变化时回调，通常用于通知宿主更新附件的占位尺寸。
    var onContentSizeChanged: ((CGSize) -> Void)? { get set }
    /// 流式加载完成时回调，通常用于通知宿主更新附件的占位尺寸。
    var onStreamingFinished: (() -> Void)? {get set}
    /// 更新视图数据（通常用于刷新视图内容）。
    func updateData(data: ViewData)
    /// 开始流式加载数据（通常用于网络图片或视频）。
    func startStreaming(data: ViewData,animation: Bool)
}



public protocol AttachmentLoadable: NSTextAttachment {
    
    associatedtype ViewType: ViewLoadable

    
    var view: ViewType? { get set}
    
    var range: NSRange? { get set }
    
    var onLayoutChange: ((AttachmentLoadable) -> Void)? { get set }

    /// 布局变化时重新定位覆盖视图（尺寸取附件当前预留尺寸）。
    func updateViewFrame(_ frame: CGRect, in hostView: UIView)

    /// 从视图层级移除覆盖视图（reset / 复用时调用）。
    func removeView()
    
    func beginStreaming(
        in hostView: UIView,
        frame: CGRect,
        animated: Bool,
        onLayoutChange: @escaping (AttachmentLoadable) -> Void,
        completion: @escaping () -> Void)
}



open class BaseAttachment<V: ViewLoadable>: NSTextAttachment,AttachmentLoadable {
    public override init(data contentData: Data?, ofType uti: String?) {
        super.init(data: contentData, ofType: uti)
    }
    
    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

   lazy public var view: V? = V()
    
   public var range: NSRange?
    
   public var onLayoutChange: ((any AttachmentLoadable) -> Void)?
    
    
    public func beginStreaming(
        in hostView: UIView,
        frame: CGRect,
        animated: Bool,
        onLayoutChange: @escaping (AttachmentLoadable) -> Void,
        completion: @escaping () -> Void) {
            guard let customView = view else {return}
            hostView.addSubview(customView)
            customView.onContentSizeChanged = { [weak self] size in
                guard let self = self else { return }
                let newBounds = CGRect(x: 0, y: 0, width: size.width, height: size.height)
                self.bounds = newBounds
                onLayoutChange(self)
            }
    }
    
    public func removeView() {
        view?.removeFromSuperview()
        view = nil
        onLayoutChange = nil
    }
    
    public func updateViewFrame(_ frame: CGRect, in hostView: UIView) {
        view?.frame = CGRect(origin: frame.origin, size: bounds.size)
    }
}

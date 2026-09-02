//
//  File.swift
//  MarkdownViewKit
//
//  Created by admin on 2026/9/2.
//

import Foundation
import UIKit
public protocol CustomViewLoadable: UIView {
    init()
}

public protocol CustomAttachmentLoadable: NSTextAttachment {
    
    associatedtype ViewType: CustomViewLoadable
    
    var view: ViewType? { get set}
    
    var range: NSRange? { get set }
    
    var onLayoutChange: ((CustomAttachmentLoadable) -> Void)? { get set }

    /// 布局变化时重新定位覆盖视图（尺寸取附件当前预留尺寸）。
    func updateViewFrame(_ frame: CGRect, in hostView: UIView)

    /// 从视图层级移除覆盖视图（reset / 复用时调用）。
    func removeView()
    
    func beginStreaming(
        in hostView: UIView,
        frame: CGRect,
        animated: Bool,
        onLayoutChange: @escaping (CustomAttachmentLoadable) -> Void,
        completion: @escaping () -> Void)
}

open class CustomBaseAttachment<V: CustomViewLoadable>: NSTextAttachment,CustomAttachmentLoadable {
    public override init(data contentData: Data?, ofType uti: String?) {
        super.init(data: contentData, ofType: uti)
    }
    
    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
   }

   public lazy var view: V? = V()
    
   public var range: NSRange?
    
   public var onLayoutChange: ((any CustomAttachmentLoadable) -> Void)?
    
    
    public func beginStreaming(
        in hostView: UIView,
        frame: CGRect,
        animated: Bool,
        onLayoutChange: @escaping (CustomAttachmentLoadable) -> Void,
        completion: @escaping () -> Void) {
            
    }
    
    public func removeView() {
        view?.removeFromSuperview()
        view = nil
    }
    
    public func updateViewFrame(_ frame: CGRect, in hostView: UIView) {
        guard let view = view else { return }
        if view.superview !== hostView {
//            hostView.addSubview(view)
        }
        view.frame = CGRect(origin: frame.origin, size: bounds.size)
    }
}

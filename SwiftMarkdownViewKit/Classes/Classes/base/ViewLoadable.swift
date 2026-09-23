//
//  ViewLoadable.swift
//  SwiftMarkdownViewKit
//
//  Created by admin on 2026/9/11.
//

import UIKit
import Markdown
public struct TextMatch{
    public var content: String
    
    public let extraInfo: String?
}

public struct MarkupContext<T> {
    
    let markup: T
    
    let visitor: MarkdownAttributedStringBuilder
    /// 自定义正则匹配结果
    let match: NSTextCheckingResult?
    ///代码块是否闭合
    let isClosed: Bool?
    
    init(markup: T,
         visitor: MarkdownAttributedStringBuilder,
         match: NSTextCheckingResult? = nil,
         isClosed: Bool? = nil) {
        self.markup = markup
        self.visitor = visitor
        self.match = match
        self.isClosed = isClosed
    }
}

public protocol ViewLoadable where Self: UIView{
    
    associatedtype MarkupType: Markup
    
    /// 是否启用动画效果（通常用于流式加载数据时的过渡动画）。如果要启用动画效果，请在流式加载数据时将此属性设置为 true。并且动画完成后调用 onStreamingFinished 回调。
    var animation: Bool { get set }
    
    var viewOptions: ViewOption { get set }
    ///viewOptions 属性更新
    func updateViewOptions(_ options: ViewOption)
    /// 视图尺寸变化时回调，通常用于通知宿主更新附件的占位尺寸。
    var onContentSizeChanged: ((CGSize) -> Void)? { get set }
    /// 流式加载完成时回调，通常用于通知宿主更新附件的占位尺寸。
    var onStreamingFinished: (() -> Void)? {get set}
    /// 更新视图数据（通常用于刷新视图内容）。
    func updateData(data: MarkupContext<MarkupType>)
    /// 开始流式加载数据（通常用于网络图片或视频）。
    func startStreaming(data: MarkupContext<MarkupType>,animation: Bool)
    /// 估算视图尺寸（通常用于计算附件的占位尺寸）。
    func estimatedSize(for data: MarkupContext<MarkupType>) -> CGSize
    /// 返回内容的内边距（通常用于调整视图内容与边界的间距）。
    func attachmentContentInset() -> UIEdgeInsets
}

public extension ViewLoadable {
    func updateViewOptions(_ options: ViewOption){}
    var animation: Bool {
        get { false }
        set {}
    }
}
public class PlaceholdView: UIView,ViewLoadable {
    public func updateData(data: MarkupContext<Markdown.Text>) {
    }
    
    public func startStreaming(data: MarkupContext<Markdown.Text>, animation: Bool) {
        onStreamingFinished?()
    }
    
    public func estimatedSize(for data: MarkupContext<Markdown.Text>) -> CGSize {
        return CGSize(width: 200, height: 200)
    }
    
    public typealias MarkupType = Text
    
    public var viewOptions: ViewOption = ViewOption()
    
    public var onContentSizeChanged: ((CGSize) -> Void)?
    
    public var onStreamingFinished: (() -> Void)?
}
    
extension ViewLoadable {
   public func attachmentContentInset() -> UIEdgeInsets {
        .init(top: 10, left: 10, bottom: 10, right: 10)
    }
}

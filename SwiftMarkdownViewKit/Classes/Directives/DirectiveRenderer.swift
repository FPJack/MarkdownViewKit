//
//  File.swift
//  SwiftMarkdownViewKit
//
//  Created by admin on 2026/9/21.
//

import Foundation
import Markdown
import UIKit
/// 行内自定义规则：自带匹配逻辑，命中后把匹配片段渲染成你想展示的富文本。
public protocol DirectiveRenderer {
    
    associatedtype MarkupType: Markup
    
    var viewType: ViewLoadable.Type { get }

    func renderAttr(context:MarkupContext<MarkupType>) -> NSAttributedString?
    
    func renderView(context:MarkupContext<MarkupType>) -> ViewLoadable?

    func render(context:MarkupContext<MarkupType>) -> NSAttributedString?
}
public extension DirectiveRenderer {
   
    func renderAttr(context: MarkupContext<MarkupType>) -> NSAttributedString?{
        nil
    }
    
    func renderView(context:MarkupContext<MarkupType>) -> ViewLoadable? {
        viewType.init()
    }

    public func render(context:MarkupContext<MarkupType>) -> NSAttributedString? {
        if let attr = renderAttr(context: context) {
            return attr
        } else if let view = renderView(context: context) {
            let markup = context.markup
            let attachment = BaseAttachment(markup: MarkupContext(markup: markup, visitor: context.visitor,match: context.match,isClosed: context.isClosed),viewType: viewType, viewBlock: {
                let view = renderView(context: context) ?? PlaceholdView()
                return view
            })
            let attributed = NSAttributedString(attachment: attachment)
            return attributed
        }
        return nil
    }
}


//public struct RendererAttrImpl<T: Markup>: DirectiveRenderer {
//    public typealias MarkupType = T
//    
//    public let renderBlock: (MarkupContext<T>) -> NSAttributedString?
//    
//
//    public func renderAttr(context: MarkupContext<T>) -> NSAttributedString? {
//        let markup = context.markup
//        return renderBlock(MarkupContext(markup: markup, visitor: context.visitor, match: context.match, isClosed: context.isClosed))
//    }
//}
//
//public struct RendererViewImpl<T: Markup>: DirectiveRenderer {
//    public typealias MarkupType = T
//
//    public let renderBlock: (MarkupContext<MarkupType>) -> ViewLoadable?
//    
//    public func renderView(context: MarkupContext<T>) -> (any ViewLoadable)? {
//        let markup = context.markup
//        return renderBlock(MarkupContext(markup: markup, visitor: context.visitor, match: context.match, isClosed: context.isClosed))
//    }
//   
//}

public class ThematicView: UIView,ViewLoadable {
    public func updateData(data: MarkupContext<Markdown.ThematicBreak>) {
    }
    
    public func startStreaming(data: MarkupContext<Markdown.ThematicBreak>, animation: Bool) {
        onStreamingFinished?()
    }
    
    public func estimatedSize(for data: MarkupContext<Markdown.ThematicBreak>) -> CGSize {
        return CGSize(width: 100, height: 1)
    }
    public func updateViewOptions(_ options: ViewOption) {
        bounds = CGRect(origin: bounds.origin, size: CGSize(width: options.maxWidth ?? 100, height: 1))
    }
    
    public typealias MarkupType = ThematicBreak
    
    public var viewOptions: ViewOption = ViewOption()
    
    public var onContentSizeChanged: ((CGSize) -> Void)?
    
    public var onStreamingFinished: (() -> Void)?
    
    public func attachmentContentInset() -> UIEdgeInsets {
        return .init(top: 0, left: 0, bottom: 15, right: 0)
    }
    
    public override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .separator
    }
    
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
public struct ThematicBreakRenderer: DirectiveRenderer {
    public var viewType: any ViewLoadable.Type {ThematicView.self}
    
    public typealias MarkupType = ThematicBreak
    
    public func renderView(context: MarkupContext<MarkupType>) -> (any ViewLoadable)? {
        return ThematicView(frame: .zero)
    }
}

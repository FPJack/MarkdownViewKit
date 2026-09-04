//
//  BaseAttachment.swift
//  MarkdownViewKit
//
//  Created by admin on 2026/8/27.
//

import UIKit

public enum StreamState {
    case none
    case streaming
    case paused
    case finished
}

public protocol ViewLoadable: UIView {
    associatedtype ViewData
    ///正则表达式，用于匹配文本中需要替换为视图的内容。
    static var regex: String { get }
    static var attachment: AttachmentLoadable.Type? { get }
    
    init()
    var streamState: StreamState? { get set }
    /// 视图数据，用于初始化或更新视图内容。
    var data: ViewData { get set }
    /// 视图尺寸变化时回调，通常用于通知宿主更新附件的占位尺寸。
    var onContentSizeChanged: ((CGSize) -> Void)? { get set }
    /// 流式加载完成时回调，通常用于通知宿主更新附件的占位尺寸。
    var onStreamingFinished: (() -> Void)? {get set}
    /// 更新视图数据（通常用于刷新视图内容）。
    func flushData(data: ViewData)
    /// 开始流式加载数据（通常用于网络图片或视频）。
    func startStreaming(data: ViewData,animation: Bool)
    /// 估算视图尺寸（通常用于计算附件的占位尺寸）。
    func estimatedSize(for data: ViewData) -> CGSize
}

public extension ViewLoadable {
    /// 类型擦除安全的转发入口：方法签名不含关联类型（仅 `Bool -> Void`），
    /// 因此可以直接在 `any ViewLoadable` 存在类型上调用；内部仍以具体 `Self`
    /// 调用 `startStreaming(data:animation:)`，绕开「关联类型方法不能在
    /// 存在类型上调用」的限制。
    func beginStreamingCurrentData(animation: Bool) {
        startStreaming(data: data, animation: animation)
    }
    func estimatedSize() -> CGSize {
         estimatedSize(for: data)
    }
    
    func flushData() {
         flushData(data: data)
    }

}



public protocol AttachmentLoadable: NSTextAttachment {
    
    
    init(view: ViewLoadable)
    
    var view: ViewLoadable { get set}
    
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


public protocol CustomViewDelegate {
    ///返回需要注册的自定义视图类型数组，用于在Markdown解析时识别和替换对应的内容。
    func registerCustomViews(_ markdownView: MarkdownView) -> [ViewLoadable.Type]
    
  ///配置view
    func configureCustomView(_ markdownView: MarkdownView,
                       match: AttachmentMatch
    )
    
    ///配置表格
    func configureGridTableView(_ markdownView: MarkdownView,
                                match: AttachmentMatch
    )
    ///配置代码
    func configureCodeBlockView(_ markdownView: MarkdownView,
                                match: AttachmentMatch)
}

public extension CustomViewDelegate {
    func configureGridTableView(_ markdownView: MarkdownView, match: AttachmentMatch) {
        guard let table = match.view as? GridTableView else { return }
        let tableStr = match.matchedString
        let rows = RegxParser.gridRows(from: tableStr)
        var tableOptions = GridTableOptions()
        tableOptions.maxTableWidth = 290
        table.configuration = tableOptions
        table.data = rows
    }
    
    ///配置代码
    func configureCodeBlockView(_ markdownView: MarkdownView,
                                match: AttachmentMatch){
        guard let matchBlock = match.codeMathBlock else {return}
        let cb = match.view as! CodeBlockView
        guard let matchBlock = match.codeMathBlock else {return}
        var configuration = CodeBlockOption()
        configuration.allowsVerticalScroll = false
        configuration.allowsHorizontalScroll = false
        configuration.codeFont = UIFont(name: "Menlo", size: 15)
        ?? .systemFont(ofSize: 15)
        configuration.lineNumberFont = configuration.codeFont
        configuration.maxWidth = 290
        cb.clipsToBounds = true
        cb.layer.cornerRadius = configuration.cornerRadius
        cb.layer.borderWidth = 1
        cb.layer.borderColor = configuration.borderColor.cgColor
        cb.data = matchBlock
        let attributedText = highlightedCode(matchBlock.content, language: matchBlock.language, fontSize: 15, textColor: .black)
        cb.attributedText = attributedText
        cb.showsLineNumbers = configuration.showsLineNumbers
        cb.allowsHorizontalScroll = configuration.allowsHorizontalScroll
        cb.allowsVerticalScroll = configuration.allowsVerticalScroll
        cb.maxCellWidth = configuration.maxCellWidth
        cb.maxViewWidth = configuration.maxWidth
        cb.maxViewHeight = configuration.maxHeight
        cb.codeFont = configuration.codeFont
        cb.lineNumberFont = configuration.lineNumberFont
        cb.lineNumberColor = configuration.lineNumberColor
        cb.gutterBackgroundColor = configuration.gutterBackgroundColor
        cb.codeBackgroundColor = configuration.codeBackgroundColor
        // 头部：语言名（或默认文字）+ 右侧复制按钮。
        let header = CodeBlockHeaderView(title: matchBlock.language ?? "",
                                         config: configuration,
                                         onCopy: {
                                           
                                         })
        cb.headerView = header
    }
    
    ///配置代码
    func configureWebView(_ markdownView: MarkdownView,
                                match: AttachmentMatch){
        let view = match.view as! MarkdownWebBlockView
        guard let matchBlock = match.codeMathBlock else {return}
        var configuration = WebViewOption()
        configuration.maxWidth = 290
        configuration.backgroundColor = .white
        view.data = matchBlock
        view.clipsToBounds = true
        view.clipsToBounds = true
        view.layer.cornerRadius = configuration.cornerRadius
        view.layer.borderWidth = 1
        view.layer.borderColor = configuration.borderColor.cgColor
        view.contentBackgroundColor = configuration.backgroundColor
        view.maxViewHeight = configuration.maxHeight
        view.scrollEnabledInWebView = configuration.scrollEnabled
    }
    ///配置代码
    func configureLatexWebView(_ markdownView: MarkdownView,
                                match: AttachmentMatch){
        configureWebView(markdownView, match: match)
        let view = match.view as! MarkdownLatexWebView
        guard var matchBlock = match.codeMathBlock else {return}

        
//        view.data = RegxParser.regxLatex(str: matchBlock.content)

    }
       
}


open class BaseAttachment: NSTextAttachment,AttachmentLoadable {
    public required init(view: any ViewLoadable) {
        self.view = view
        if view is MarkdownWebBlockView {
            print(  "BaseAttachment init view is MarkdownWebBlockView")
        }
        super.init(data: nil, ofType: nil)
        self.bounds = .zero
    }
   
    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

   public var view:  ViewLoadable
    
   public var range: NSRange?
    
   public var onLayoutChange: ((any AttachmentLoadable) -> Void)?
    
    
   public func beginStreaming(
        in hostView: UIView,
        frame: CGRect,
        animated: Bool,
        onLayoutChange: @escaping (AttachmentLoadable) -> Void,
        completion: @escaping () -> Void) {
            hostView.addSubview(view)
            view.onContentSizeChanged = { [weak self] size in
                guard let self = self else { return }
                let newBounds = CGRect(x: 0, y: 0, width: size.width, height: size.height)
                self.bounds = newBounds
                onLayoutChange(self)
            }
            print("viewtypeekeek :\(view.description)")
           
            let estimeSize = view.estimatedSize()
            bounds = CGRect(origin: .zero, size: estimeSize)
            view.frame = CGRect(origin: frame.origin, size: estimeSize)
            if view is CodeBlockView {
                print("view is CodeBlockView")
            }
            if animated {
                view.onStreamingFinished = completion
                view.beginStreamingCurrentData(animation: true)
            } else {
                // 非动画：一次性显示完整表格。
                view.beginStreamingCurrentData(animation: false)
                onLayoutChange(self)
                completion()
            }
    }
    
    public func removeView() {
        view.removeFromSuperview()
        onLayoutChange = nil
    }
    
    public func updateViewFrame(_ frame: CGRect, in hostView: UIView) {
        view.frame = CGRect(origin: frame.origin, size: bounds.size)
    }
}

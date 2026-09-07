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
public struct TextMatch {
        
    public let view: ViewLoadable?
    
    public let sourceText: String

    public let pattern: String?
    
    public let match: NSTextCheckingResult?
    
    /// 匹配到的整体区间（含开头 ``` 那一行及结尾 ``` 那一行；未闭合时到字符串末尾）。
    public let range: NSRange
    
    /// 语言标识（```之后的 info 字符串，如 `swift`）；未提供时为空串。
    public let extraInfo: String?
    
    /// 代码正文（不含定界行）。
    public var content: String
    /// 代码块是否已闭合（即是否遇到收尾的 ``` ）。

}

public typealias RegxRule = (pattern: String, options: NSRegularExpression.Options)

public protocol ViewLoadable: UIView {
    
    ///正则表达式，用于匹配文本中需要替换为视图的内容。
    static func regxRule() -> RegxRule
    
    init()
    /// 视图尺寸变化时回调，通常用于通知宿主更新附件的占位尺寸。
    var onContentSizeChanged: ((CGSize) -> Void)? { get set }
    /// 流式加载完成时回调，通常用于通知宿主更新附件的占位尺寸。
    var onStreamingFinished: (() -> Void)? {get set}
    /// 更新视图数据（通常用于刷新视图内容）。
    func updateData(data: TextMatch)
    /// 开始流式加载数据（通常用于网络图片或视频）。
    func startStreaming(data: TextMatch,animation: Bool)
    /// 估算视图尺寸（通常用于计算附件的占位尺寸）。
    func estimatedSize(for data: TextMatch) -> CGSize
}

public protocol CustomViewDelegate {
    ///返回需要注册的自定义视图类型数组，用于在Markdown解析时识别和替换对应的内容。
    func registerCustomViews(_ markdownView: MarkdownView) -> [ViewLoadable.Type]
    
  ///配置view
    func configureCustomView(_ markdownView: MarkdownView,
                       match: TextMatch
    )
    
    ///配置表格
    func configureGridTableView(_ markdownView: MarkdownView,
                                match: TextMatch
    )
    ///配置代码
    func configureCodeBlockView(_ markdownView: MarkdownView,
                                match: TextMatch)
}

public extension CustomViewDelegate {
    func configureGridTableView(_ markdownView: MarkdownView, match: TextMatch) {
        guard let table = match.view as? GridTableView else { return }
        var tableOptions = GridTableOptions()
        tableOptions.maxTableWidth = 290
        table.configuration = tableOptions
    }
    
    ///配置代码
    func configureCodeBlockView(_ markdownView: MarkdownView,
                                match: TextMatch){
//        guard let matchBlock = match.codeMathBlock else {return}
//        let cb = match.view as! CodeBlockView
//        guard let matchBlock = match.codeMathBlock else {return}
//        var configuration = CodeBlockOption()
//        configuration.allowsVerticalScroll = false
//        configuration.allowsHorizontalScroll = false
//        configuration.codeFont = UIFont(name: "Menlo", size: 15)
//        ?? .systemFont(ofSize: 15)
//        configuration.lineNumberFont = configuration.codeFont
//        configuration.maxWidth = 290
//        cb.clipsToBounds = true
//        cb.layer.cornerRadius = configuration.cornerRadius
//        cb.layer.borderWidth = 1
//        cb.layer.borderColor = configuration.borderColor.cgColor
//        cb.data = matchBlock
//        let attributedText = highlightedCode(matchBlock.content, language: matchBlock.language, fontSize: 15, textColor: .black)
//        cb.attributedText = attributedText
//        cb.showsLineNumbers = configuration.showsLineNumbers
//        cb.allowsHorizontalScroll = configuration.allowsHorizontalScroll
//        cb.allowsVerticalScroll = configuration.allowsVerticalScroll
//        cb.maxCellWidth = configuration.maxCellWidth
//        cb.maxViewWidth = configuration.maxWidth
//        cb.maxViewHeight = configuration.maxHeight
//        cb.codeFont = configuration.codeFont
//        cb.lineNumberFont = configuration.lineNumberFont
//        cb.lineNumberColor = configuration.lineNumberColor
//        cb.gutterBackgroundColor = configuration.gutterBackgroundColor
//        cb.codeBackgroundColor = configuration.codeBackgroundColor
//        // 头部：语言名（或默认文字）+ 右侧复制按钮。
//        let header = CodeBlockHeaderView(title: matchBlock.language ?? "",
//                                         config: configuration,
//                                         onCopy: {
//                                           
//                                         })
//        cb.headerView = header
    }
    
    ///配置代码
    func configureWebView(_ markdownView: MarkdownView,
                                match: TextMatch){
//        let view = match.view as! MarkdownWebBlockView
//        guard let matchBlock = match.codeMathBlock else {return}
//        var configuration = WebViewOption()
//        configuration.maxWidth = 290
//        configuration.backgroundColor = .white
//        view.data = matchBlock
//        view.clipsToBounds = true
//        view.clipsToBounds = true
//        view.layer.cornerRadius = configuration.cornerRadius
//        view.layer.borderWidth = 1
//        view.layer.borderColor = configuration.borderColor.cgColor
//        view.contentBackgroundColor = configuration.backgroundColor
//        view.maxViewHeight = configuration.maxHeight
//        view.scrollEnabledInWebView = configuration.scrollEnabled
    }
    ///配置代码
    func configureLatexWebView(_ markdownView: MarkdownView,
                                match: TextMatch){
//        configureWebView(markdownView, match: match)
//        let view = match.view as! MarkdownLatexWebView
//        guard var matchBlock = match.codeMathBlock else {return}

        
//        view.data = RegxParser.regxLatex(str: matchBlock.content)

    }
       
}


open class BaseAttachment: NSTextAttachment {
    public required init(view: any ViewLoadable, streamState: StreamState, textMatch: TextMatch) {
        self.view = view
        self.streamState = streamState
        self.textMatch = textMatch
       
        super.init(data: nil, ofType: nil)
        self.bounds = .zero
    }
   
    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

   public var view:  ViewLoadable
    
   public var range: NSRange?
    
    public var streamState: StreamState
    
    public var textMatch: TextMatch
    
    public var onLayoutChange: ((BaseAttachment) -> Void)?
    
    
   public func beginStreaming(
        in hostView: UIView,
        frame: CGRect,
        animated: Bool,
        onLayoutChange: @escaping (BaseAttachment) -> Void,
        completion: @escaping () -> Void) {
            hostView.addSubview(view)
            view.onContentSizeChanged = { [weak self] size in
                guard let self = self else { return }
                let newBounds = CGRect(x: 0, y: 0, width: size.width, height: size.height)
                self.bounds = newBounds
                onLayoutChange(self)
            }
            print("viewtypeekeek :\(view.description)")
           
            let estimeSize = view.estimatedSize(for: textMatch )
            bounds = CGRect(origin: .zero, size: estimeSize)
            view.frame = CGRect(origin: frame.origin, size: estimeSize)
           
            if animated {
                view.onStreamingFinished = completion
                view.startStreaming(data: textMatch, animation: true)
            } else {
                // 非动画：一次性显示完整表格。
                view.startStreaming(data: textMatch, animation: false)
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

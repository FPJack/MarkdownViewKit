//
//  ViewController.swift
//  MarkdownViewKit
//
//  Created by fanpeng on 08/25/2026.
//  Copyright (c) 2026 fanpeng. All rights reserved.
//

import UIKit
import MarkdownViewKit
import Down
import ZLFlexKit
class ViewController: UIViewController {
    private lazy var displayLink = {
      let timer =  DisplayLinkTimer(preferredFramesPerSecond: 10) { tick in
            self.readNextChunk()
        }
      return timer
    }()
    private func readNextChunk() {
        guard readOffset < source.length else {
            displayLink.stop()
            return
        }
        let length = min(30, source.length - readOffset)
        let piece = source.substring(with: NSRange(location: readOffset, length: length))
        self.markdown.appendText(fromMarkdown: piece)
        readOffset += length
    }
    lazy var source: NSString = readmeMarkdown() as NSString
    private var readOffset: Int = 0
    lazy var markdown = MarkdownView(option: options())
    lazy var downBridge: DownBridge  = {
        DownBridge(markdownView: markdown)
    }()
    override func viewDidLoad() {
        super.viewDidLoad()
        markdown.maxTextWidth = 300
        markdown.frameInterval = 3
        markdown.charactersPerFrame = 30
        markdown.textView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        markdown.textView.backgroundColor = UIColor.lightGray.withAlphaComponent(0.2)
       
        let str = source.substring(to: 10)
        self.markdown.startStreamingText(markdown: source as String)
//        self.displayLink.start()
    let scrollView =
        VStackView {
            markdown
        }
        .wrapScrollView()
        
        scrollView.box
        .addTo(view)
        .center()
        .width(300)
        .maxHeight(700)
        markdown.onContentSizeChange = {newSize in
            let offset = scrollView.contentSize.height - scrollView.frame.height
            print("contentSizeChange: \(newSize)  content size\(scrollView.contentSize)  height\(scrollView.frame.height)")
            scrollView.setContentOffset(CGPoint(x: 0, y: offset), animated: true)
        }
    }
    
    private func options() ->MarkdownRenderOptions {
        let imageOptions = ImageAttachmentOptions()
        imageOptions.maxImageWidth = 300

        imageOptions.onImageTapped = {[weak self] tapped,allImages in
            guard let self = self else { return }
            var images: [UIImage] = []
            var startIndex = 0
            for att in allImages {
                if let img = att.image {
                    if att === tapped { startIndex = images.count }
                    images.append(img)
                }
            }
            guard !images.isEmpty else { return }
            ImagePreviewer.shared.present(images,
                                          startIndex: startIndex,
                                          from: self.view,
                                          allowsSwipe: true)
        }
        
        
        var webOptions = WebViewOption()
        webOptions.maxWidth = 290
        
        let renderOptions = MarkdownRenderOptions()
        renderOptions.imageOptions = imageOptions
        renderOptions.webOptions = webOptions
        renderOptions.onLinkTapped = { url in
            print(url)
        }
        var tableOptions = GridTableOptions()
        tableOptions.maxTableWidth = 290
        renderOptions.tableOptions = tableOptions
        return renderOptions
    }
    /// 读取 bundle 里的 Markdown 资源。
    private func readmeMarkdown() -> String {
        if let path = Bundle.main.path(forResource: "html", ofType: "md"),
           let content = try? String(contentsOfFile: path, encoding: .utf8), !content.isEmpty {
            return content
        }
        return "# Test.md 未找到"
    }

    
}


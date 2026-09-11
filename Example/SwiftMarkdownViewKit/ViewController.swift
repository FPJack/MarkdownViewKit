//
//  ViewController.swift
//  SwiftMarkdownViewKit
//
//  Created by fanpeng on 09/10/2026.
//  Copyright (c) 2026 fanpeng. All rights reserved.
//

import UIKit
import SwiftMarkdownViewKit
import ZLFlexKit
class ViewController: UIViewController {
    
    lazy var markdown = MarkdownView()
    private lazy var displayLink = {
      let timer =  DisplayLinkTimer(preferredFramesPerSecond: 10) { tick in
            self.readNextChunk()
        }
      return timer
    }()
    private func readNextChunk() {
        guard readOffset < source.count else {
            displayLink.stop()
            return
        }
        // 按字形簇（Character）切片，保证不会把 emoji / 组合字符从中间截断
        let length = min(2, source.count - readOffset)
        let piece = String(source[readOffset ..< readOffset + length])
        self.markdown.appendText(fromMarkdown: piece)
        readOffset += length
    }
    // 每个元素都是一个完整的用户感知字符（含 ZWJ emoji 序列、变体选择符等）
    lazy var source: [Character] = Array(loadMarkdown())
    private var readOffset: Int = 0


    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        
        markdown.maxTextWidth = 300
        markdown.frameInterval = 20
        markdown.charactersPerFrame = 50
        markdown.textView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        markdown.textView.backgroundColor = UIColor.lightGray.withAlphaComponent(0.2)
        let scrollView =
            VStackView {
                markdown
                30
                UISwitch()
            }
            .wrapScrollView()
            
            scrollView.box
            .addTo(view)
            .top(100)
            .leading(50)
            .width(300)
            .maxHeight(700)
            markdown.onContentSizeChange = {newSize in
                let offset = scrollView.contentSize.height - scrollView.frame.height
                print("contentSizeChange: \(newSize)  content size\(scrollView.contentSize)  height\(scrollView.frame.height)")
                scrollView.setContentOffset(CGPoint(x: 0, y: offset), animated: true)
            }
            scrollView.backgroundColor = .black.withAlphaComponent(0.1)

        // 启动流式渲染
        displayLink.start()
//        let str = source.map { String($0) }.joined()
//        markdown.startStreamingText(markdown: str)
    }

    private func loadMarkdown() -> String {
        if let url = Bundle.main.url(forResource: "html", withExtension: "md"),
           let content = try? String(contentsOf: url, encoding: .utf8) {
            return content
        } else {
            return "# 未找到 html.md\n请确认该文件已加入 App Target 的资源中。"
        }
    }

}


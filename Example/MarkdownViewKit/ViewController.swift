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
    let downBridge = DownBridge()
    override func viewDidLoad() {
        super.viewDidLoad()
      
        let markdown = MarkdownView()
        markdown.maxTextWidth = 300
        markdown.frameInterval = 60
        markdown.charactersPerFrame = 2
        markdown.textView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        
        markdown.textView.backgroundColor = UIColor.lightGray.withAlphaComponent(0.2)
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
        
        let renderOptions = MarkdownRenderOptions()
        renderOptions.imageOptions = imageOptions
        renderOptions.onLinkTapped = { url in
            print(url)
        }
        
        var tableOptions = GridTableOptions()
        tableOptions.maxTableWidth = 290
        renderOptions.tableOptions = tableOptions
        
        downBridge.attributedString(fromMarkdown: readmeMarkdown(), options: renderOptions, complete: { attributedString in
//            markdown.attributedText(attributedString)
            
            markdown.startStreamingAttributedText(attributedString!)
        })
        downBridge.bindGestures(to: markdown.textView)
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
    /// 读取 bundle 里的 Markdown 资源。
    private func readmeMarkdown() -> String {
        if let path = Bundle.main.path(forResource: "Test", ofType: "md"),
           let content = try? String(contentsOfFile: path, encoding: .utf8), !content.isEmpty {
            return content
        }
        return "# Test.md 未找到"
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }

}


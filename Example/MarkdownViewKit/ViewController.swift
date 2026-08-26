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
        
        let imageOptions = ImageAttachmentOptions()
        imageOptions.maxImageWidth = 300
        imageOptions.onImageLoaded = { [weak markdown] attachment in
            // 图片下载完成后刷新对应区域。
            guard let textView = markdown?.textView else {
                return
            }
            let lm = textView.layoutManager
            lm.invalidateLayout(forCharacterRange: attachment.range, actualCharacterRange: nil)
            lm.ensureLayout(for: textView.textContainer)
            markdown?.invalidateContentSize()
        }
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
        
        downBridge.attributedString(fromMarkdown: readmeMarkdown(), options: renderOptions, complete: { attributedString in
            markdown.attributedText(attributedString)
        })
        downBridge.bindGestures(to: markdown.textView)
    
        VStackView {
            markdown
        }
        .wrapScrollView()
        .box
        .addTo(view)
        .center()
        .width(300)
        .maxHeight(700)
        
        
        
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


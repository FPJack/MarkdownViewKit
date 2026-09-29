//
//  ChunkReader.swift
//  SwiftMarkdownViewKit_Example
//
//  Created by admin on 2026/9/24.
//  Copyright © 2026 CocoaPods. All rights reserved.
//

import Foundation
import SwiftMarkdownViewKit
class ChunkReader {
    private lazy var displayLink = {
      let timer =  DisplayLinkTimer(preferredFramesPerSecond: 5) { tick in
            self.readNextChunk()
        }
      return timer
    }()
    private func readNextChunk() {
        guard readOffset < source.count else {
            stopReading()
            return
        }
        // 按字形簇（Character）切片，保证不会把 emoji / 组合字符从中间截断
        let length = min(100, source.count - readOffset)
        let piece = String(source[readOffset ..< readOffset + length])
        readOffset += length
        callback(piece,false)
    }
    // 每个元素都是一个完整的用户感知字符（含 ZWJ emoji 序列、变体选择符等）
    lazy var source: [Character] = Array(loadMarkdown())
    private var readOffset: Int = 0
    private func loadMarkdown() -> String {
//        if isArabicDemo { return Self.arabicSample }
        if let url = Bundle.main.url(forResource: "test", withExtension: "md"),
//        if let url = Bundle.main.url(forResource: "html", withExtension: "md"),
           let content = try? String(contentsOf: url, encoding: .utf8) {
            return content
        } else {
            return "# 未找到 html.md\n请确认该文件已加入 App Target 的资源中。"
        }
    }
    
    let callback: (String,Bool) -> Void
    
    init(callback: @escaping (String,Bool) -> Void) {
        self.callback = callback
    }
    func startReading() {
        displayLink.start()
    }
    func stopReading() {
        displayLink.stop()
        readOffset = 0
        callback("",true)
    }
    deinit {
        displayLink.invalidate()
    }
}

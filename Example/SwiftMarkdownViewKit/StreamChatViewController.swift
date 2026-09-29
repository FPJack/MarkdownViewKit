//
//  StreamChatViewController.swift
//  SwiftMarkdownViewKit_Example
//
//  Created by admin on 2026/9/23.
//  Copyright © 2026 CocoaPods. All rights reserved.
//

import UIKit
import Combine
import ZLKeyboardManager
import SwiftMarkdownViewKit
import ZLAutoHeightTextView
let assistCellId = "assistCellId"
let userCellId = "userCellId"
let assistFinishedCellId = "assistFinishedCellId"

class StreamChatViewController: UIViewController,UITableViewDataSource,UITableViewDelegate,MarkdownViewDelegate {
    @IBOutlet weak var textView: ZLAutoHeightTextView!
    @IBOutlet weak var tableView: UITableView!
    
    @IBOutlet weak var sendButton: UIButton!
    var messages: [ChatMessage] = []
    var currentMsgId = ""
    var newMarkdownView: MarkdownView {
        // 宽度 / 透明背景与气泡保持一致，避免流式内容溢出气泡或露出白底。
        let view = ChatBubbleCell.makeBubbleMarkdownView(
            maxTextWidth: ChatBubbleStyle.assistantContentWidth,
            charactersPerFrame: 2,
            frameInterval: 30
        )
        view.delegate = self
        view.onContentSizeChange = {[weak self] oldSize, newSize in
            guard let self else { return }
            print("oldSize \(oldSize.height) newSize \(newSize.height)")
            print("oldSize \(oldSize.height) newSize \(newSize.height)")
            if newSize.height < self.lastHeight {return}
            self.lastHeight = max(self.lastHeight, newSize.height)
            if  newSize.height > oldSize.height {
                self.messages.last?.hegith = newSize.height
                self.reloadTableViewHeight()
            }
        }
        return view
    }
    
    lazy var markdownView: MarkdownView  = newMarkdownView
    
    
    var newChunkReader: ChunkReader {
        ChunkReader {[weak self] pice , isFinished in
            self?.readNextChunk(chunk: pice, isFinished: isFinished)
        }
    }
    
    lazy var chunkReader: ChunkReader = newChunkReader
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.textView.keyboardCfg.keyboardTopMargin = 20
        tableView.register(AssistTableCell.self, forCellReuseIdentifier: assistCellId)
        tableView.register(UserTableCell.self, forCellReuseIdentifier: userCellId)
        tableView.register(ChatTableCell.self, forCellReuseIdentifier: assistFinishedCellId)

        view.backgroundColor = ChatBubbleStyle.pageBackground
        tableView.backgroundColor = .clear
        // 气泡本身已经区分了消息边界，分隔线反而会破坏聊天观感。
        tableView.separatorStyle = .none
        tableView.contentInset = UIEdgeInsets(top: 8, left: 0, bottom: 40, right: 0)
        textView.layer.cornerRadius = 8
        textView.layer.borderWidth = 1
        textView.layer.borderColor = UIColor.lightGray.cgColor
        textView.layer.masksToBounds = true
        textView.backgroundColor = sendButton.backgroundColor
        textView.minHeight = 40
        textView.maxHeight = 80
        textView.placeholder = "请输入内容"
        textView.font = UIFont.systemFont(ofSize: 18)
        sendButton.layer.cornerRadius = 8
        sendButton.layer.masksToBounds = true
        
    }
    
    func startRead() {
        lastHeight = 0
        currentMsgId = UUID().uuidString
        let message = ChatMessage(role: .assistant,id: currentMsgId, markdown: "")
        messages.append(message)
        tableView.reloadData()
        markdownView.removeFromSuperview()
        markdownView.onContentSizeChange = nil
        markdownView.delegate = nil
        markdownView = newMarkdownView
        chunkReader.stopReading()
        chunkReader = newChunkReader
        tableView.performBatchUpdates {
            self.tableView.scrollToRow(at: IndexPath(row: self.messages.count - 1, section: 0), at: .bottom, animated: false)
        } completion: { _ in
            self.chunkReader.startReading()
        }
    }
    
    func stopRead() {
        chunkReader.stopReading()
    }
    
    func readNextChunk(chunk: String, isFinished: Bool) {
        if let msg = messages.first(where: { $0.id == currentMsgId }),let index = messages.firstIndex(where: { $0.id == currentMsgId }) {
                msg.markdown += chunk
            markdownView.appendText(fromMarkdown: chunk)
        }
    }

    @IBAction func sendAction(_ sender: Any) {
        guard let text = textView.text else { return  }
        messages.last?.isFinished = true

        let message = ChatMessage(role: .user, markdown: text)
        messages.append(message)
        textView.text = ""
        textView.resignFirstResponder()
        startRead()
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        messages.count
    }
    var lastHeight: CGFloat = 0
    var reloadAnimation = true
    var addSpacing: CGFloat = 0
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let chatMessage = messages[indexPath.row]
        if chatMessage.role == .user {
            let cell = tableView.dequeueReusableCell(withIdentifier: userCellId, for: indexPath) as! UserTableCell
            cell.message = chatMessage
            return cell
        } else {
            if chatMessage.isFinished {
                let cell = tableView.dequeueReusableCell(withIdentifier: assistFinishedCellId, for: indexPath) as! ChatTableCell
                cell.message = chatMessage
                return cell
            }else {
                let cell = tableView.dequeueReusableCell(withIdentifier: assistCellId, for: indexPath) as! AssistTableCell
                // 流式 MarkdownView 全局只有一个，挂进当前气泡即可，流式状态不受 cell 复用影响。
                cell.attach(markdownView)
                return cell
            }
        }
    }
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        ///自动估算
//        let chatMessage = messages[indexPath.row]
//        return chatMessage.hegith + 20
       return UITableView.automaticDimension
    }
    
    var isAnimation = false
    var needAnimation = false
    var attributedText = NSAttributedString(string: "")
}
extension StreamChatViewController {
    func textViewAttributesChanged(
        _ markdownView: MarkdownView,
        attributedText: NSAttributedString
    ) {
        messages.last?.attributedString = attributedText

    }

    func reloadTableViewHeight() {
        if isAnimation{
            needAnimation = true
            return
        }
        isAnimation = true
        tableView.performBatchUpdates {
            self.tableView.beginUpdates()
            self.tableView.endUpdates()
        } completion: { _ in
            self.isAnimation = false
            if self.needAnimation {
                self.needAnimation = false
                let indexpath = IndexPath(row: self.messages.count - 1, section: 0)
                self.tableView.scrollToRow(at: indexpath, at: .bottom, animated: true)
                self.reloadTableViewHeight()
            }else {
                let indexpath = IndexPath(row: self.messages.count - 1, section: 0)
                self.tableView.scrollToRow(at: indexpath, at: .bottom, animated: true)
            }
        }
    }
    
    func scrollToBottom(animated: Bool = false) {
        let y = max(
            -tableView.adjustedContentInset.top,
             tableView.contentSize.height + self.addSpacing
                - tableView.bounds.height
                + tableView.adjustedContentInset.bottom
        )
        tableView.setContentOffset(CGPoint(x: 0, y: y),animated: animated)
    }
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        print("scroll \(scrollView.contentOffset.y)")
    }
    func tableView(_ tableView: UITableView, didEndDisplaying cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        
    }
}

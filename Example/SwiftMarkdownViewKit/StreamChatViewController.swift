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
let assistCellId = "assistCellId"
let userCellId = "userCellId"
let assistFinishedCellId = "assistFinishedCellId"

class StreamChatViewController: UIViewController,UITableViewDataSource,UITableViewDelegate,MarkdownViewDelegate {
    @IBOutlet weak var textView: UITextView!
    @IBOutlet weak var tableView: UITableView!
    var messages: [ChatMessage] = []
    var currentMsgId = ""
    var newMarkdownView: MarkdownView {
        let view = MarkdownView()
        view.maxTextWidth = UIScreen.main.bounds.width - 20
        view.backgroundColor = .clear
        view.charactersPerFrame = 3
        view.frameInterval = 20
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
    
    
    
    lazy var chunkReader: ChunkReader = {
         ChunkReader {[weak self] pice , isFinished in
             self?.readNextChunk(chunk: pice, isFinished: isFinished)
        }
    }()
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.textView.keyboardCfg.keyboardTopMargin = 20
        tableView.register(AssistTableCell.self, forCellReuseIdentifier: assistCellId)
        tableView.register(UserTableCell.self, forCellReuseIdentifier: userCellId)
        tableView.register(ChatTableCell.self, forCellReuseIdentifier: assistFinishedCellId)

        view.backgroundColor = .secondarySystemBackground
        tableView.backgroundColor = .clear
        tableView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        
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
                if markdownView.superview != cell.contentView {
                    markdownView.removeFromSuperview()
                    markdownView.box
                        .addTo(cell.contentView)
                        .top(10).leading(10)
                        .trailing(-10)
                        .bottom(-10)
                        .flush()
                }
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
                self.reloadTableViewHeight()
            }
            let indexpath = IndexPath(row: self.messages.count - 1, section: 0)
            self.tableView.scrollToRow(at: indexpath, at: .bottom, animated: true)
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

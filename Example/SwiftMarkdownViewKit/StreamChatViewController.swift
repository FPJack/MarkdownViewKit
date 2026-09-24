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

class StreamChatViewController: UIViewController,UITableViewDataSource,UITableViewDelegate,MarkdownViewDelegate {

    @IBOutlet weak var textView: UITextView!
    
    @IBOutlet weak var tableView: UITableView!
    
    var messages: [ChatMessage] = []
    
    var currentMsgId = ""
    
    var assistCell: ChatTableCell? = nil
    
    lazy var chunkReader: ChunkReader = {
         ChunkReader {[weak self] pice , isFinished in
             self?.readNextChunk(chunk: pice, isFinished: isFinished)
        }
    }()
    
    private var attributesChangedSubject = PassthroughSubject<(MarkdownView, NSAttributedString), Never>()

    private var cancellables = Set<AnyCancellable>()

    private func setupAttributesChangedThrottle() {

        attributesChangedSubject

            .throttle(

                for: .milliseconds(200),

                scheduler: RunLoop.main,

                latest: true

            )

            .sink { [weak self] markdownView, attributedText in

                guard let self else { return }

//                self.attributesChanged(
//
//                    markdownView,
//
//                    attributedText: attributedText
//
//                )

            }

            .store(in: &cancellables)

    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.textView.keyboardCfg.keyboardTopMargin = 20
        tableView.register(ChatTableCell.self, forCellReuseIdentifier: assistCellId)
        tableView.register(ChatTableCell.self, forCellReuseIdentifier: userCellId)
        view.backgroundColor = .secondarySystemBackground
        tableView.backgroundColor = .clear
        tableView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: 50, right: 0)
        setupAttributesChangedThrottle()
    }
    
    func startRead() {
        currentMsgId = UUID().uuidString
        let message = ChatMessage(role: .assistant,id: currentMsgId, markdown: "")
        messages.append(message)
        tableView.reloadData()
        chunkReader.startReading()
        
        
    }
    
    func stopRead() {
        chunkReader.stopReading()
    }
    
    func readNextChunk(chunk: String, isFinished: Bool) {
        
        if let msg = messages.first(where: { $0.id == currentMsgId }),let index = messages.firstIndex(where: { $0.id == currentMsgId }) {
                msg.markdown += chunk
            assistCell?.markdownView.appendText(fromMarkdown: chunk)
        }
    }

    @IBAction func sendAction(_ sender: Any) {
        guard let text = textView.text else { return  }
        let message = ChatMessage(role: .user, markdown: text)
        messages.append(message)
        tableView.reloadData()
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
        let cell: ChatTableCell
        if chatMessage.role == .user {
            cell = tableView.dequeueReusableCell(withIdentifier: userCellId, for: indexPath) as! ChatTableCell
            cell.markdownView.delegate = self
            cell.message = chatMessage
        } else {
            cell = tableView.dequeueReusableCell(withIdentifier: assistCellId, for: indexPath) as! ChatTableCell
            cell.markdownView.delegate = self
            cell.message = chatMessage
            assistCell = cell
        }
        cell.markdownView.onContentSizeChange = {oldSize, newSize in
            print("oldSize \(oldSize.height) newSize \(newSize.height)")
            if newSize.height < self.lastHeight {
                return
            }
            self.lastHeight = max(self.lastHeight, newSize.height)
            if  newSize.height > oldSize.height {
                chatMessage.hegith = newSize.height
                self.addSpacing = newSize.height - oldSize.height
                self.reloadTableViewHeight()
            }
        }
        return cell
    }
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        ///自动估算
        let chatMessage = messages[indexPath.row]
        return chatMessage.hegith + 20
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

//        attributesChangedSubject.send(
//
//            (markdownView, attributedText)
//
//        )
//        needAnimation = true
//        if !isAnimation {
//            attributesChanged(markdownView, attributedText: attributedText)
//        }

    }
//    func attributesChanged(_ markdownView: MarkdownView, attributedText: NSAttributedString) {
//        let msg = messages.first { $0.id == markdownView.identifier}
//        if var msg = msg{
//            msg.attributedString = attributedText
//            assistCell?.layoutIfNeeded()
//           
//        }
//    }
    func reloadTableViewHeight() {
        if isAnimation{
            needAnimation = true
            return
        }
       
        isAnimation = true
        UIView.animate(withDuration: 0.5) {
            self.scrollToBottom(animated: false)
            self.tableView.beginUpdates()
            self.tableView.endUpdates()
        } completion: { _ in
            self.isAnimation = false
            if self.needAnimation {
                self.needAnimation = false
                self.reloadTableViewHeight()
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
}

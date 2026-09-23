//
//  StreamChatViewController.swift
//  SwiftMarkdownViewKit_Example
//
//  Created by admin on 2026/9/23.
//  Copyright © 2026 CocoaPods. All rights reserved.
//

import UIKit
import ZLKeyboardManager
import SwiftMarkdownViewKit
let assistCellId = "assistCellId"
let userCellId = "userCellId"

class StreamChatViewController: UIViewController,UITableViewDataSource,UITableViewDelegate,MarkdownViewDelegate {

    @IBOutlet weak var textView: UITextView!
    @IBOutlet weak var tableView: UITableView!
    var messages: [ChatMessage] = []
    override func viewDidLoad() {
        super.viewDidLoad()
        self.textView.keyboardCfg.keyboardTopMargin = 20
        tableView.register(ChatTableCell.self, forCellReuseIdentifier: assistCellId)
        tableView.register(ChatTableCell.self, forCellReuseIdentifier: userCellId)
    }

    @IBAction func sendAction(_ sender: Any) {
        guard let text = textView.text else { return  }
        let message = ChatMessage(role: .user, markdown: text)
        messages.append(message)
        tableView.reloadData()
        textView.text = ""
        textView.resignFirstResponder()
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        messages.count
    }
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
        }
//        cell.onContentSizeChange = { [weak self] size in
//            self?.tableView.beginUpdates()
//            self?.tableView.endUpdates()
//        }
        return cell
    }
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        ///自动估算
       return UITableView.automaticDimension
    }
    
    

}
extension StreamChatViewController {
    func textViewAttributesChanged(_ markdownView: MarkdownView) {
        tableView.beginUpdates()
        tableView.endUpdates()
    }
}

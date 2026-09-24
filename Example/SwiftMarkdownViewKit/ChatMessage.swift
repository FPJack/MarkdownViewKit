import UIKit

 enum ChatRole {
    case user
    case assistant
}

 class ChatMessage {
    let id: String
    let role: ChatRole
    var isFinished: Bool = false
    var markdown: String
    var hegith:CGFloat = 10
    var attributedString: NSAttributedString? = nil
     init(role: ChatRole, id: String = UUID().uuidString, markdown: String = "") {
        self.id = id
        self.role = role
        self.markdown = markdown
    }
}

import UIKit

 enum ChatRole {
    case user
    case assistant
}

 struct ChatMessage {
    let id: UUID
    let role: ChatRole
    var markdown: String
    init(role: ChatRole, markdown: String = "") {
        id = UUID()
        self.role = role
        self.markdown = markdown
    }
}

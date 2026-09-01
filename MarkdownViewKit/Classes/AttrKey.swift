//
//  AttrKey.swift
//  MarkdownViewKit
//
//  Created by admin on 2026/8/25.
//

import UIKit

struct AttrKey {
    static let image = NSAttributedString.Key("key_image")
    static let code = NSAttributedString.Key("key_code")
    static let table = NSAttributedString.Key("key_table")
    static let web = NSAttributedString.Key("key_web")
    static func key(codeTitle: String?) -> NSAttributedString.Key {
        return ["mermaid","echarts"].contains(codeTitle) ? web : code
    }
        
}
struct AttrValue {
    let value: Any
    init(_ value: Any) {
        self.value = value
    }
}
enum AttrRange {
    case table(NSRange,AttrValue)
    case code(NSRange,AttrValue)
    case image(NSRange,AttrValue)
    case web(NSRange,AttrValue)
    var range: NSRange {
            switch self {
            case let .table(range, _),
                 let .code(range, _),
                 let .image(range, _),
                 let .web(range, _):
                 return range
            }
        }
}



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
    var range: NSRange {
            switch self {
            case let .table(range, _),
                 let .code(range, _),
                 let .image(range, _):
                return range
            }
        }
}



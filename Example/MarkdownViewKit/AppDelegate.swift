//
//  AppDelegate.swift
//  MarkdownViewKit
//
//  Created by fanpeng on 08/25/2026.
//  Copyright (c) 2026 fanpeng. All rights reserved.
//

import UIKit
protocol P: UIView {
    func foo()
}

extension P {
    func foo() {
        print("protocol")
    }
}

class A: UIView, P {
    func foo() {
        print("A")
    }
}


@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?


    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplicationLaunchOptionsKey: Any]?) -> Bool {
        // Override point for customization after application launch.
        
        func compare(_ label: String, _ text: String) {
            let attr = NSAttributedString(string: text)
            let equal = text.count == attr.length
            print("""
            【\(label)】
              文本        : \(text)
              String.count = \(text.utf16.count)
              attr.length  = \(attr.length)
              两者相等     = \(equal)
            """)
            print("----------------------------")
        }

        // 1. 纯中文（BMP 单码点）→ 相等
        compare("普通中文", "你好，世界")

        // 2. 单个 Emoji（代理对）→ 不等
        compare("单个 Emoji", "😀")

        // 3. 组合字符 e + 组合重音 → 不等
        compare("组合字符", "e\u{301}")

        // 4. 家庭 Emoji（ZWJ 复合序列）→ 差最多
        compare("家庭 Emoji", "👨\u{200D}👩\u{200D}👧\u{200D}👦")

        // 5. BMP 之外的生僻字 U+20000 → 不等
        compare("生僻字", "\u{20000}")

        // 6. 带附件：附件计入 length，但不算 count
        let withAttachment = NSMutableAttributedString(string: "图片")
        withAttachment.append(NSAttributedString(attachment: NSTextAttachment()))
        print("【带附件】")
        print("  String.count = \(withAttachment.string.count)")
        print("  attr.length  = \(withAttachment.length)")
        

        let str = """
        4. 高效444绘制(https://github.com/knsv/mermaid#flowchart)//
                👨\u{200D}👩\u{200D}👧\u{200D}👦
        [eeeee]这一e\u{301}段字符串给我正
        """

        let attributedText = NSMutableAttributedString(
            string: str,
            attributes: [
                .font: UIFont.systemFont(ofSize: 16),
                .foregroundColor: UIColor.label
            ]
        )

        // 匹配所有 [...]：
        // 第 1 个是 [https://github.com/knsv/mermaid#flowchart]
        // 第 2 个是 [eeeee]
        let regex = try! NSRegularExpression(pattern: #"\[(.*?)\]"#)

        let fullRange = NSRange(
            location: 0,
            length: attributedText.string.utf16.count
        )

        let matches = regex.matches(
            in: attributedText.string,
            range: fullRange
        )

        // 取最后一个匹配：[eeeee]
        guard let lastMatch = matches.last else {
            fatalError("未找到方括号内容")
        }
        
        print((attributedText.string as NSString).substring(with: lastMatch.range))

        // 替换整个 [eeeee] 为 123456
        let replacement = NSAttributedString(
            string: "123456",
            attributes: [
                .font: UIFont.boldSystemFont(ofSize: 16),
                .foregroundColor: UIColor.systemRed
            ]
        )

        attributedText.replaceCharacters(
            in: lastMatch.range,
            with: replacement
        )
        
        

        print(attributedText.string)
        // 4\. 高效444绘制([https://github.com/knsv/mermaid#flowchart](https://github.com/knsv/mermaid#flowchart))//👨‍👩‍👧‍👦123456
        
        
        return true
    }

    func applicationWillResignActive(_ application: UIApplication) {
        // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
        // Use this method to pause ongoing tasks, disable timers, and throttle down OpenGL ES frame rates. Games should use this method to pause the game.
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
        // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        // Called as part of the transition from the background to the inactive state; here you can undo many of the changes made on entering the background.
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
    }

    func applicationWillTerminate(_ application: UIApplication) {
        // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
    }


}


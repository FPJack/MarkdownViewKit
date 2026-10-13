//
//  AppDelegate.swift
//  SwiftMarkdownViewKit
//
//  Created by fanpeng on 09/10/2026.
//  Copyright (c) 2026 fanpeng. All rights reserved.
//

import UIKit
import DebugSwift
import SwiftMarkdownViewKit

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    /// 切换首页：`true` 看数学公式 Demo，`false` 回到流式聊天页。
    private let showsMathFormulaDemo = false

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Override point for customization after application launch.
        if #available(iOS 13.0, *) {
            window?.overrideUserInterfaceStyle = .light
        }

        if showsMathFormulaDemo {
            // 提前加载 MathJax：首次排版要等脚本下载 + 初始化，
            // 在这里预热后，进页面时公式基本是秒出。
            MathJaxWebView.shared.prewarm()
            window?.rootViewController = UINavigationController(
                rootViewController: MathFormulaDemoViewController()
            )
        } else {
            window?.rootViewController = StreamChatViewController()
        }

        window?.makeKeyAndVisible()
        window?.backgroundColor = .white
        DebugSwift.setup()
        DebugSwift.show()
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


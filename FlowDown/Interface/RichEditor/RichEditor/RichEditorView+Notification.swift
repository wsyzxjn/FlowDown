//
//  RichEditorView+Notification.swift
//  RichEditor
//
//  Created by 秋星桥 on 1/20/25.
//

import UIKit

extension RichEditorView {
    @objc func applicationWillResignActive() {
        parentViewController?.view.endEditing(true)
    }

    @objc func applicationDidBecomeActive() {
        colorfulShadow.refreshAfterReturningToForeground()
    }
}

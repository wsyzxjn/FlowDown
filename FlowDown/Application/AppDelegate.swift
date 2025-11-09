//
//  AppDelegate.swift
//  FlowDown
//
//  Created by 秋星桥 on 2024/12/31.
//

import AlertController
import CloudKit
import Combine
import ConfigurableKit
import MarkdownView
import MLX
import MLXLMCommon
import ScrubberKit
import Storage
import UIKit

@objc(AppDelegate)
class AppDelegate: UIResponder, UIApplicationDelegate {
    private var templateMenuCancellable: AnyCancellable?
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UITableView.appearance().backgroundColor = .clear
        UIButton.appearance().tintColor = .accent
        UITextView.appearance().tintColor = .accent
        UINavigationBar.appearance().tintColor = .accent
        UISwitch.appearance().onTintColor = .accent
        UIUserInterfaceStyle.subscribeToConfigurableItem()

        MLX.GPU.subscribeToConfigurableItem()
        EditorBehavior.subscribeToConfigurableItem()
        MarkdownTheme.subscribeToConfigurableItem()
        ScrubberConfiguration.subscribeToConfigurableItem()
        ScrubberConfiguration.setup() // build access control rule

        AlertControllerConfiguration.alertImage = .avatar
        AlertControllerConfiguration.accentColor = .accent
        AlertControllerConfiguration.backgroundColor = .background
        AlertControllerConfiguration.separatorColor = SeparatorView.color

        templateMenuCancellable = ChatTemplateManager.shared.$templates
            .sink { _ in
                Task { @MainActor in
                    UIMenuSystem.main.setNeedsRebuild()
                }
            }

        application.registerForRemoteNotifications()

        let isSyncEnabled = SyncEngine.isSyncEnabled
        if isSyncEnabled {
            Task {
                if isSyncEnabled {
                    try await syncEngine.fetchChanges()
                }
            }
        }

        sdb.clearDeletedRecords()

        return true
    }

    func application(_: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken _: Data) {
        logger.infoFile("Did register for remote notifications")
    }

    func application(_: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        logger.errorFile("ERROR: Failed to register for notifications: \(error.localizedDescription)")
    }

    func application(_: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        guard let notification = CKNotification(fromRemoteNotificationDictionary: userInfo) else {
            completionHandler(.noData)
            return
        }
        logger.infoFile("Received cloudkit notification: \(notification)")

        guard notification.containerIdentifier == CloudKitConfig.containerIdentifier else {
            completionHandler(.noData)
            return
        }

        Task {
            do {
                logger.infoFile("cloudkit notification fetchChanges")
                try await syncEngine.fetchChanges()
                completionHandler(.newData)
            } catch {
                logger.errorFile("cloudkit notification fetchLatestChanges: \(error)")
                completionHandler(.failed)
            }
        }
    }

    func application(
        _: UIApplication,
        didDiscardSceneSessions _: Set<UISceneSession>
    ) {}

    func applicationDidBecomeActive(_: UIApplication) {
        MLX.GPU.onApplicationBecomeActivate()
    }

    func applicationWillResignActive(_: UIApplication) {
        MLX.GPU.onApplicationResignActivate()
    }
}

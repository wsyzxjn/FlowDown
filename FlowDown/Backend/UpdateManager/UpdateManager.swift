import AlertController
import Combine
import DpkgVersion
import Foundation
import UIKit

private enum DistributionChannel: String, Equatable, Hashable {
    case fromApple
    case fromGitHub
}

class UpdateManager: NSObject {
    static let shared = UpdateManager()

    private let currentChannel: DistributionChannel
    private weak var anchorView: UIView?

    var canCheckForUpdates: Bool {
        // Check if the current channel supports update checking
        [.fromGitHub].contains(currentChannel)
    }

    override private init() {
        #if targetEnvironment(macCatalyst)
            if let receiptUrl = Bundle.main.appStoreReceiptURL,
               FileManager.default.fileExists(atPath: receiptUrl.path)
            {
                currentChannel = .fromApple
            } else {
                currentChannel = .fromGitHub
            }
        #else
            currentChannel = .fromApple // it's impossible to distribute iOS/iPadOS app through GitHub (right?)
        #endif
        Logger.app.infoFile("UpdateManager initialized with channel: \(currentChannel)")
        super.init()
    }

    private var bundleVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return "\(version).\(build)"
    }

    func anchor(_ view: UIView) {
        anchorView = view
    }

    func performUpdateCheckFromUI() {
        guard let controller = anchorView?.parentViewController else {
            Logger.app.errorFile("no anchor view set for UpdateManager.")
            return
        }
        Logger.app.infoFile("checking for updates from \(bundleVersion)...")
        guard [.fromGitHub].contains(currentChannel) else {
            Logger.app.errorFile("Update check is not supported for the current distribution channel.")
            return
        }

        func completion(package: DistributionChannel.RemotePackage?) {
            Task { @MainActor in
                if let package {
                    self.presentUpdateAlert(controller: controller, package: package)
                } else {
                    Indicator.present(
                        title: "No Update Available",
                        preset: .done,
                        referencingView: controller.view
                    )
                }
            }
        }

        Indicator.progress(
            title: "Checking for Updates",
            controller: controller
        ) { completionHandler in
            var package: DistributionChannel.RemotePackage?
            do {
                let packages = try await self.currentChannel.getRemoteVersion()
                package = self.newestPackage(from: packages)
                package = self.updatePackage(from: package)
                Logger.app.infoFile("remote packages: \(packages)")
            } catch {
                Logger.app.errorFile("failed to check for updates: \(error.localizedDescription)")
            }
            await completionHandler {
                completion(package: package)
            }
        }
    }

    private func updatePackage(from remotePackage: DistributionChannel.RemotePackage?) -> DistributionChannel.RemotePackage? {
        guard let remotePackage else { return nil }
        let compare = Version.compare(remotePackage.tag, bundleVersion)
        Logger.app.infoFile("comparing \(remotePackage.tag) and \(bundleVersion) result \(compare)")
        guard compare > 0 else { return nil }
        return remotePackage
    }

    private func newestPackage(from list: [DistributionChannel.RemotePackage]) -> DistributionChannel.RemotePackage? {
        guard !list.isEmpty, var find = list.first else { return nil }
        for i in 1 ..< list.count where Version.compare(find.tag, list[i].tag) < 0 {
            find = list[i]
        }
        return find
    }

    private func presentUpdateAlert(controller: UIViewController, package: DistributionChannel.RemotePackage) {
        let alert = AlertViewController(
            title: "Update Available",
            message: "A new version \(package.tag) is available. Would you like to download it?"
        ) { context in
            context.allowSimpleDispose()
            context.addAction(title: "Cancel") {
                context.dispose()
            }
            context.addAction(title: "Download", attribute: .accent) {
                context.dispose {
                    UIApplication.shared.open(package.downloadURL, options: [:])
                }
            }
        }
        controller.present(alert, animated: true)
    }
}

extension DistributionChannel {
    enum UpdateCheckError: Error, LocalizedError {
        case invalidResponse
    }

    struct RemotePackage {
        let tag: String
        let downloadURL: URL
    }

    func getRemoteVersion() async throws -> [RemotePackage] {
        switch self {
        case .fromApple:
            return []
        case .fromGitHub:
            let url = URL(string: "https://api.github.com/repos/Lakr233/FlowDown/releases/latest")!
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String,
                  json["body"] as? String != nil, // maybe display updatelog.
                  let htmlUrl = json["html_url"] as? String,
                  let draft = json["draft"] as? Bool,
                  let prerelease = json["prerelease"] as? Bool,
                  !draft,
                  !prerelease,
                  let downloadPageUrl = URL(string: htmlUrl)
            else {
                throw NSError(domain: "UpdateManagerError", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: String(localized: "Failed to parse release information."),
                ])
            }
            Logger.app.infoFile("latest release version: \(tagName), url: \(htmlUrl)")
            return [.init(tag: tagName, downloadURL: downloadPageUrl)]
        }
    }
}

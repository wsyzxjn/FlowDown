//
//  ConversationSelectionView+Delegate.swift
//  FlowDown
//
//  Created by 秋星桥 on 2/5/25.
//

import Storage
import UIKit

extension ConversationSelectionView: UITableViewDelegate {
    func tableView(_: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let identifier = dataSource.itemIdentifier(for: indexPath) else { return }
        Logger.ui.debugFile("ConversationSelectionView didSelectRowAt: \(identifier)")
        ChatSelection.shared.select(identifier)
    }

    func tableView(_: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard dataSource.snapshot().numberOfSections > 1 else { return nil }
        let sectionIdentifier = dataSource.snapshot().sectionIdentifiers[section]
        return SectionDateHeaderView().with {
            $0.updateTitle(date: sectionIdentifier)
        }
    }
}

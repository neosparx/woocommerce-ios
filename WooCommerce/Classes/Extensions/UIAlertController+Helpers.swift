import UIKit


/// UIAlertController Helpers
///
extension UIAlertController {

    /// Discard Changes Action Sheet
    ///
    static func presentDiscardChangesActionSheet(viewController: UIViewController,
                                              onDiscard: (() -> Void)?, onCancel: (() -> Void)? = nil) {
        let actionSheet = UIAlertController(title: nil, message: ActionSheetStrings.message, preferredStyle: .actionSheet)
        actionSheet.view.tintColor = .text

        actionSheet.addDestructiveActionWithTitle(ActionSheetStrings.discard) { _ in
            onDiscard?()
        }

        actionSheet.addCancelActionWithTitle(ActionSheetStrings.cancel) { _ in
            onCancel?()
        }

        if let popoverController = actionSheet.popoverPresentationController {
            popoverController.sourceView = viewController.view
            popoverController.sourceRect = viewController.view.bounds
            popoverController.permittedArrowDirections = []
        }

        viewController.present(actionSheet, animated: true)
    }

    /// Present a discard changes action sheet when the user navigates away from adding a product.
    static func presentDiscardNewProductActionSheet(viewController: UIViewController,
                                                    onSaveDraft: @escaping (() -> Void),
                                                    onDiscard: @escaping (() -> Void),
                                                    onCancel: (() -> Void)? = nil) {
        let actionSheet = UIAlertController(title: nil, message: ActionSheetStrings.message, preferredStyle: .actionSheet)
        actionSheet.view.tintColor = .text

        actionSheet.addDefaultActionWithTitle(ActionSheetStrings.saveAsDraft) { _ in
            onSaveDraft()
        }

        actionSheet.addDestructiveActionWithTitle(ActionSheetStrings.discard) { _ in
            onDiscard()
        }

        actionSheet.addCancelActionWithTitle(ActionSheetStrings.cancel) { _ in
            onCancel?()
        }

        if let popoverController = actionSheet.popoverPresentationController {
            popoverController.sourceView = viewController.view
            popoverController.sourceRect = viewController.view.bounds
            popoverController.permittedArrowDirections = []
        }

        viewController.present(actionSheet, animated: true)
    }

    open override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        if let window = UIApplication.shared.currentKeyWindow {
            popoverPresentationController?.sourceRect = CGRect(x: window.bounds.midX, y: window.bounds.midY, width: 0, height: 0)
        }
    }
}

private enum ActionSheetStrings {
    static let message = NSLocalizedString("Are you sure you want to discard these changes?",
                                           comment: "Message title for Discard Changes Action Sheet")
    static let saveAsDraft = NSLocalizedString("Save as Draft",
                                               comment: "Button title to save a product as draft in Discard Changes Action Sheet")
    static let discard = NSLocalizedString("Discard changes",
                                          comment: "Button title Discard Changes in Discard Changes Action Sheet")
    static let cancel = NSLocalizedString("Cancel",
                                          comment: "Button title Cancel in Discard Changes Action Sheet")
}

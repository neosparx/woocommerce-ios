import UIKit
import Yosemite

struct ProductsTopBannerFactory {
    /// Creates a products tab top banner asynchronously based on the app settings.
    /// - Parameters:
    ///   - isExpanded: whether the top banner is expanded by default.
    ///   - expandedStateChangeHandler: called when the top banner expanded state changes.
    ///   - onGiveFeedbackButtonPressed: called the give feedback button is pressed.
    ///   - onDismissButtonPressed: called the dismiss button is pressed
    ///   - onCompletion: called when the view controller is created and ready for display.
    static func topBanner(isExpanded: Bool,
                          stores: StoresManager = ServiceLocator.stores,
                          analytics: Analytics = ServiceLocator.analytics,
                          expandedStateChangeHandler: @escaping () -> Void,
                          onGiveFeedbackButtonPressed: @escaping () -> Void,
                          onDismissButtonPressed: @escaping () -> Void,
                          onCompletion: @escaping (TopBannerView) -> Void) {
        let title = Localization.title
        let icon: UIImage = .megaphoneIcon
        let infoText = Localization.info
        let giveFeedbackAction = TopBannerViewModel.ActionButton(title: Localization.giveFeedback) {
            analytics.track(event: .featureFeedbackBanner(context: .productsM4, action: .gaveFeedback))
            onGiveFeedbackButtonPressed()
        }
        let dismissAction = TopBannerViewModel.ActionButton(title: Localization.dismiss) {
            analytics.track(event: .featureFeedbackBanner(context: .productsM4, action: .dismissed))
            onDismissButtonPressed()
        }
        let actions = [giveFeedbackAction, dismissAction]
        let viewModel = TopBannerViewModel(title: title,
                                           infoText: infoText,
                                           icon: icon,
                                           isExpanded: isExpanded,
                                           topButton: .chevron(handler: expandedStateChangeHandler),
                                           actionButtons: actions)
        let topBannerView = TopBannerView(viewModel: viewModel)
        topBannerView.translatesAutoresizingMaskIntoConstraints = false
        onCompletion(topBannerView)
    }
}

private extension ProductsTopBannerFactory {
    enum Localization {
        static let title =
            NSLocalizedString("Create products from the app!",
                              comment: "The title of the Work In Progress top banner on the Products tab when Products feature switch is enabled.")
        static let info =
            NSLocalizedString(
                "It’s now possible to create simple, grouped \nand external products on the go from the Woo app. Not ready yet? Save them as draft!",
                comment: "The info of the Work In Progress top banner on the Products tab when Products feature switch is enabled.")
        static let giveFeedback =
            NSLocalizedString("Give feedback",
                              comment: "The title of the button to give feedback about products beta features on the banner on the products tab")
        static let dismiss = NSLocalizedString("Dismiss", comment: "The title of the button to dismiss the banner on the products tab")

    }
}

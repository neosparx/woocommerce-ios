import Photos
import UIKit
import WordPressUI
import Yosemite

protocol ProductFormDataModel {
    var siteID: Int64 { get }
    var productID: Int64 { get }
    var name: String { get }
    var description: String? { get }
    var shortDescription: String? { get }
    var permalink: String { get }

    // Images
    var images: [ProductImage] { get }

    var regularPrice: String? { get }
    var salePrice: String? { get }
    var dateOnSaleStart: Date? { get }
    var dateOnSaleEnd: Date? { get }
    var taxStatusKey: String { get }
    var taxClass: String? { get }

    // Shipping
    var weight: String? { get }
    var dimensions: ProductDimensions { get }
    var shippingClass: String? { get }

    // Inventory
    var sku: String? { get }
}

extension ProductFormDataModel {
    var productTaxStatus: ProductTaxStatus {
        return ProductTaxStatus(rawValue: taxStatusKey)
    }

    var imageStatuses: [ProductImageStatus] {
        return images.map({ ProductImageStatus.remote(image: $0) })
    }

    /// Returns the full description without the HTML tags and leading/trailing white spaces and new lines.
    var trimmedFullDescription: String? {
        guard let description = description else {
            return nil
        }
        return description.removedHTMLTags.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension Product: ProductFormDataModel {
    var description: String? {
        fullDescription
    }

    var shortDescription: String? {
        briefDescription
    }
}
extension ProductVariation: ProductFormDataModel {

    var name: String {
        attributes.map({ $0.option }).joined(separator: " - ")
    }

    var shortDescription: String? {
        nil
    }

    var images: [ProductImage] {
        [image].compactMap { $0 }
    }
}

/// The entry UI for adding/editing a Product.
final class ProductFormViewController: UIViewController {

    @IBOutlet private weak var tableView: UITableView!
    @IBOutlet private weak var moreDetailsContainerView: UIView!

    private lazy var keyboardFrameObserver: KeyboardFrameObserver = {
        let keyboardFrameObserver = KeyboardFrameObserver { [weak self] keyboardFrame in
            self?.handleKeyboardFrameUpdate(keyboardFrame: keyboardFrame)
        }
        return keyboardFrameObserver
    }()

    private let viewModel: ProductFormViewModelProtocol
    private var product: ProductFormDataModel {
        viewModel.productValue
    }

    private var password: String? {
        viewModel.password
    }

    private var tableViewModel: ProductFormTableViewModel
    private var tableViewDataSource: ProductFormTableViewDataSource

    private let productImageActionHandler: ProductImageActionHandler
    private let productUIImageLoader: ProductUIImageLoader

    private let currency: String
    private let isEditProductsRelease2Enabled: Bool
    private let isEditProductsRelease3Enabled: Bool

    private lazy var exitForm: () -> Void = {
        presentationStyle.createExitForm(viewController: self)
    }()

    private let presentationStyle: PresentationStyle
    private let navigationRightBarButtonItemsSubject = PublishSubject<[UIBarButtonItem]>()
    private var navigationRightBarButtonItems: Observable<[UIBarButtonItem]> {
        navigationRightBarButtonItemsSubject
    }
    private var cancellableProduct: ObservationToken?
    private var cancellableProductName: ObservationToken?
    private var cancellableUpdateEnabled: ObservationToken?

    init(product: ProductFormDataModel,
         currency: String = CurrencySettings.shared.symbol(from: CurrencySettings.shared.currencyCode),
         presentationStyle: PresentationStyle,
         isEditProductsRelease2Enabled: Bool,
         isEditProductsRelease3Enabled: Bool) {
        self.currency = currency
        self.presentationStyle = presentationStyle
        self.isEditProductsRelease2Enabled = isEditProductsRelease2Enabled
        self.isEditProductsRelease3Enabled = isEditProductsRelease3Enabled
        self.productImageActionHandler = ProductImageActionHandler(siteID: product.siteID,
                                                                   product: product)
        self.productUIImageLoader = DefaultProductUIImageLoader(productImageActionHandler: productImageActionHandler,
                                                                phAssetImageLoaderProvider: { PHImageManager.default() })
        switch product {
        case let product as Product:
            self.viewModel = ProductFormViewModel(product: product,
                                                  productImageActionHandler: productImageActionHandler,
                                                  isEditProductsRelease2Enabled: isEditProductsRelease2Enabled,
                                                  isEditProductsRelease3Enabled: isEditProductsRelease3Enabled)
        default:
            fatalError()
        }

        self.tableViewModel = DefaultProductFormTableViewModel(product: product,
                                                               actionsFactory: viewModel.actionsFactory,
                                                               currency: currency)
        self.tableViewDataSource = ProductFormTableViewDataSource(viewModel: tableViewModel,
                                                                  productImageStatuses: productImageActionHandler.productImageStatuses,
                                                                  productUIImageLoader: productUIImageLoader,
                                                                  canEditImages: isEditProductsRelease2Enabled)
        super.init(nibName: nil, bundle: nil)
        tableViewDataSource.configureActions(onNameChange: { [weak self] name in
            self?.onEditProductNameCompletion(newName: name ?? "")
        }, onAddImage: { [weak self] in
            self?.showProductImages()
        })
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        cancellableProduct?.cancel()
        cancellableProductName?.cancel()
        cancellableUpdateEnabled?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        configurePresentationStyle()
        configureNavigationBar()
        configureMainView()
        configureTableView()
        configureMoreDetailsContainerView()

        startListeningToNotifications()
        handleSwipeBackGesture()

        observeProduct()
        observeProductName()
        observeUpdateCTAVisibility()

        productImageActionHandler.addUpdateObserver(self) { [weak self] (productImageStatuses, error) in
            guard let self = self else {
                return
            }

            if error != nil {
                let title = NSLocalizedString("Cannot upload image", comment: "The title of the alert when there is an error uploading an image")
                let message = NSLocalizedString("Please try again.", comment: "The message of the alert when there is an error uploading an image")
                self.displayErrorAlert(title: title, message: message)
            }

            if productImageStatuses.hasPendingUpload {
                self.onImageStatusesUpdated(statuses: productImageStatuses)
            }

            self.viewModel.updateImages(productImageStatuses.images)
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        view.endEditing(true)
    }
}

private extension ProductFormViewController {
    func configureNavigationBar() {
        updateNavigationBar(isUpdateEnabled: false)
        updateNavigationBarTitle(productName: product.name)
        removeNavigationBackBarButtonText()
    }

    func configureMainView() {
        view.backgroundColor = .basicBackground
    }

    func configureTableView() {
        registerTableViewCells()

        tableView.dataSource = tableViewDataSource
        tableView.delegate = self

        tableView.backgroundColor = .listForeground
        tableView.removeLastCellSeparator()

        // Since the table view is in a container under a stack view, the safe area adjustment should be handled in the container view.
        tableView.contentInsetAdjustmentBehavior = .never

        tableView.reloadData()
    }

    /// Registers all of the available TableViewCells
    ///
    func registerTableViewCells() {
        tableViewModel.sections.forEach { section in
            switch section {
            case .primaryFields(let rows):
                rows.forEach { row in
                    row.cellTypes.forEach { cellType in
                        tableView.register(cellType.loadNib(), forCellReuseIdentifier: cellType.reuseIdentifier)
                    }
                }
            default:
                return
            }
        }
    }

    func configurePresentationStyle() {
        switch presentationStyle {
        case .contained(let containerViewController):
            containerViewController.addCloseNavigationBarButton(target: self, action: #selector(closeNavigationBarButtonTapped))
        case .navigationStack:
            break
        }
    }

    @objc func closeNavigationBarButtonTapped() {
        guard viewModel.hasUnsavedChanges() == false else {
            presentBackNavigationActionSheet()
            return
        }
        exitForm()
    }

    func configureMoreDetailsContainerView() {
        let title = NSLocalizedString("Add more details", comment: "Title of the button at the bottom of the product form to add more product details.")
        let viewModel = BottomButtonContainerView.ViewModel(style: .link,
                                                            title: title,
                                                            image: .plusImage) { [weak self] button in
                                                                self?.moreDetailsButtonTapped(button: button)
        }
        let buttonContainerView = BottomButtonContainerView(viewModel: viewModel)

        moreDetailsContainerView.addSubview(buttonContainerView)
        moreDetailsContainerView.pinSubviewToAllEdges(buttonContainerView)
        moreDetailsContainerView.setContentCompressionResistancePriority(.required, for: .vertical)
        moreDetailsContainerView.setContentHuggingPriority(.required, for: .vertical)

        updateMoreDetailsButtonVisibility()
    }
}

// MARK: - Observations & responding to changes
//
private extension ProductFormViewController {
    func observeProduct() {
        cancellableProduct = viewModel.observableProduct.subscribe { [weak self] product in
            guard let product = product as? Product else {
                return
            }
            self?.onProductUpdated(product: product)
        }
    }

    func observeProductName() {
        cancellableProductName = viewModel.productName.subscribe { [weak self] name in
            self?.updateNavigationBarTitle(productName: name)
        }
    }

    func observeUpdateCTAVisibility() {
        cancellableUpdateEnabled = viewModel.isUpdateEnabled.subscribe { [weak self] isUpdateEnabled in
            self?.updateNavigationBar(isUpdateEnabled: isUpdateEnabled)
        }
    }

    func onProductUpdated(product: Product) {
        updateMoreDetailsButtonVisibility()

        tableViewModel = DefaultProductFormTableViewModel(product: product,
                                                          actionsFactory: viewModel.actionsFactory,
                                                          currency: currency)
        tableViewDataSource = ProductFormTableViewDataSource(viewModel: tableViewModel,
                                                             productImageStatuses: productImageActionHandler.productImageStatuses,
                                                             productUIImageLoader: productUIImageLoader,
                                                             canEditImages: isEditProductsRelease2Enabled)
        tableViewDataSource.configureActions(onNameChange: { [weak self] name in
            self?.onEditProductNameCompletion(newName: name ?? "")
        }, onAddImage: { [weak self] in
            self?.showProductImages()
        })
        tableView.dataSource = tableViewDataSource
        tableView.reloadData()
    }

    func onImageStatusesUpdated(statuses: [ProductImageStatus]) {
        tableViewDataSource = ProductFormTableViewDataSource(viewModel: tableViewModel,
                                                             productImageStatuses: statuses,
                                                             productUIImageLoader: productUIImageLoader,
                                                             canEditImages: isEditProductsRelease2Enabled)
        tableViewDataSource.configureActions(onNameChange: { [weak self] name in
            self?.onEditProductNameCompletion(newName: name ?? "")
        }, onAddImage: { [weak self] in
            self?.showProductImages()
        })
        tableView.dataSource = tableViewDataSource
        tableView.reloadData()
    }
}

// MARK: More details actions
//
private extension ProductFormViewController {
    func moreDetailsButtonTapped(button: UIButton) {
        let title = NSLocalizedString("Add more details",
                                      comment: "Title of the bottom sheet from the product form to add more product details.")
        let viewProperties = BottomSheetListSelectorViewProperties(title: title)
        let actions = viewModel.actionsFactory.bottomSheetActions()
        let dataSource = ProductFormBottomSheetListSelectorCommand(actions: actions) { [weak self] action in
                                                                    self?.dismiss(animated: true) { [weak self] in
                                                                        switch action {
                                                                        case .editInventorySettings:
                                                                            self?.editInventorySettings()
                                                                        case .editShippingSettings:
                                                                            self?.editShippingSettings()
                                                                        case .editCategories:
                                                                            self?.editCategories()
                                                                        case .editTags:
                                                                            self?.editTags()
                                                                        case .editBriefDescription:
                                                                            self?.editBriefDescription()
                                                                        case .editSKU:
                                                                            self?.editSKU()
                                                                            break
                                                                        }
                                                                    }
        }
        let listSelectorViewController = BottomSheetListSelectorViewController(viewProperties: viewProperties,
                                                                               command: dataSource) { [weak self] selectedSortOrder in
                                                                                self?.dismiss(animated: true, completion: nil)
        }
        let bottomSheet = BottomSheetViewController(childViewController: listSelectorViewController)
        bottomSheet.show(from: self, sourceView: button, arrowDirections: .down)
    }

    func updateMoreDetailsButtonVisibility() {
        let moreDetailsActions = viewModel.actionsFactory.bottomSheetActions()
        moreDetailsContainerView.isHidden = moreDetailsActions.isEmpty
    }
}

// MARK: Navigation actions
//
private extension ProductFormViewController {
    @objc func updateProduct() {
        ServiceLocator.analytics.track(.productDetailUpdateButtonTapped)
        let title = NSLocalizedString("Publishing your product...", comment: "Title of the in-progress UI while updating the Product remotely")
        let message = NSLocalizedString("Please wait while we publish this product to your store",
                                        comment: "Message of the in-progress UI while updating the Product remotely")
        let viewProperties = InProgressViewProperties(title: title, message: message)
        let inProgressViewController = InProgressViewController(viewProperties: viewProperties)

        // Before iOS 13, a modal with transparent background requires certain
        // `modalPresentationStyle` to prevent the view from turning dark after being presented.
        if #available(iOS 13.0, *) {} else {
            inProgressViewController.modalPresentationStyle = .overCurrentContext
        }

        navigationController?.present(inProgressViewController, animated: true, completion: nil)

        updateProductRemotely()
    }

    func updateProductRemotely() {
        waitUntilAllImagesAreUploaded { [weak self] in
            self?.dispatchUpdateProductAndPasswordAction()
        }
    }

    func waitUntilAllImagesAreUploaded(onCompletion: @escaping () -> Void) {
        let group = DispatchGroup()

        // Waits for all product images to be uploaded before updating the product remotely.
        group.enter()
        let observationToken = productImageActionHandler.addUpdateObserver(self) { [weak self] (productImageStatuses, error) in
            guard productImageStatuses.hasPendingUpload == false else {
                return
            }

            guard let self = self else {
                return
            }

            self.viewModel.updateImages(productImageStatuses.images)
            group.leave()
        }

        group.notify(queue: .main) {
            observationToken.cancel()
            onCompletion()
        }
    }

    func dispatchUpdateProductAndPasswordAction() {
        guard let product = product as? Product else {
            return
        }

        let group = DispatchGroup()

        // Updated Product
        if viewModel.hasProductChanged() {
            group.enter()

            viewModel.updateProductRemotely { [weak self] result in
                switch result {
                case .failure(let error):
                    let errorDescription = error.localizedDescription
                    DDLogError("⛔️ Error updating Product: \(errorDescription)")
                    ServiceLocator.analytics.track(.productDetailUpdateError)
                    // Dismisses the in-progress UI then presents the error alert.
                    self?.navigationController?.dismiss(animated: true) {
                        self?.displayError(error: error)
                    }
                case .success:
                    ServiceLocator.analytics.track(.productDetailUpdateSuccess)
                }
                group.leave()
            }
        }


        // Update product password if available
        if let password = viewModel.password, viewModel.hasPasswordChanged() {
            group.enter()
            let passwordUpdateAction = SitePostAction.updateSitePostPassword(siteID: product.siteID, postID: product.productID,
                                                                             password: password) { [weak self] (password, error) in
                guard let _ = password else {
                    DDLogError("⛔️ Error updating product password: \(error.debugDescription)")
                    group.leave()
                    return
                }

                self?.viewModel.resetPassword(password)
                group.leave()
            }
            ServiceLocator.stores.dispatch(passwordUpdateAction)
        }

        group.notify(queue: .main) { [weak self] in
            // Dismisses the in-progress UI.
            self?.navigationController?.dismiss(animated: true, completion: nil)
        }
    }

    func displayError(error: ProductUpdateError?) {
        let title = NSLocalizedString("Cannot update product", comment: "The title of the alert when there is an error updating the product")

        let message = error?.alertMessage

        displayErrorAlert(title: title, message: message)
    }

    func displayErrorAlert(title: String?, message: String?) {
        let alert = UIAlertController(title: title,
                                      message: message,
                                      preferredStyle: .alert)
        let cancel = UIAlertAction(title: NSLocalizedString(
            "OK",
            comment: "Dismiss button on the alert when there is an error updating the product"
        ), style: .cancel, handler: nil)
        alert.addAction(cancel)

        present(alert, animated: true, completion: nil)
    }

    func displayWebViewForProductInStore() {
        guard let url = URL(string: product.permalink) else {
            return
        }
        WebviewHelper.launch(url, with: self)
    }

    func displayShareProduct() {
        guard let url = URL(string: product.permalink) else {
            return
        }

        SharingHelper.shareURL(url: url, title: product.name, from: view, in: self)
    }

    func displayProductSettings() {
        guard let product = product as? Product else {
            return
        }

        let viewController = ProductSettingsViewController(product: product, password: password, completion: { [weak self] (productSettings) in
            guard let self = self else {
                return
            }
            self.viewModel.updateProductSettings(productSettings)
        }, onPasswordRetrieved: { [weak self] (originalPassword) in
            self?.viewModel.resetPassword(originalPassword)
        })
        navigationController?.pushViewController(viewController, animated: true)
    }
}

// MARK: Navigation Bar Items
//
private extension ProductFormViewController {
    func updateNavigationBarTitle(productName: String) {
        navigationItem.title = productName
        switch presentationStyle {
        case .contained(let containerViewController):
            containerViewController.navigationItem.title = productName
        default:
            break
        }
    }

    func updateNavigationBar(isUpdateEnabled: Bool) {
        var rightBarButtonItems = [UIBarButtonItem]()

        if isUpdateEnabled {
            rightBarButtonItems.append(createUpdateBarButtonItem())
        }

        if isEditProductsRelease2Enabled {
            rightBarButtonItems.insert(createMoreOptionsBarButtonItem(), at: 0)
        }

        navigationItem.rightBarButtonItems = rightBarButtonItems
        switch presentationStyle {
        case .contained(let containerViewController):
            containerViewController.navigationItem.rightBarButtonItems = rightBarButtonItems
        default:
            break
        }
    }

    func createUpdateBarButtonItem() -> UIBarButtonItem {
        let updateTitle = NSLocalizedString("Update", comment: "Action for updating a Product remotely")
        return UIBarButtonItem(title: updateTitle, style: .done, target: self, action: #selector(updateProduct))
    }

    func createMoreOptionsBarButtonItem() -> UIBarButtonItem {
        let moreButton = UIBarButtonItem(image: .moreImage,
                                     style: .plain,
                                     target: self,
                                     action: #selector(presentMoreOptionsActionSheet(_:)))
        moreButton.accessibilityLabel = NSLocalizedString("More options", comment: "Accessibility label for the Edit Product More Options action sheet")
        moreButton.accessibilityIdentifier = "edit-product-more-options-button"
        return moreButton
    }
}

extension ProductFormViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        let section = tableViewModel.sections[indexPath.section]
        switch section {
        case .primaryFields(let rows):
            let row = rows[indexPath.row]
            switch row {
            case .description:
                ServiceLocator.analytics.track(.productDetailViewProductDescriptionTapped)
                editProductDescription()
            default:
                break
            }
        case .settings(let rows):
            let row = rows[indexPath.row]
            switch row {
            case .price:
                ServiceLocator.analytics.track(.productDetailViewPriceSettingsTapped)
                editPriceSettings()
            case .shipping:
                ServiceLocator.analytics.track(.productDetailViewShippingSettingsTapped)
                editShippingSettings()
            case .inventory:
                ServiceLocator.analytics.track(.productDetailViewInventorySettingsTapped)
                editInventorySettings()
            case .categories:
                // TODO-2509 Edit Product M3 analytics
                editCategories()
            case .tags:
                // TODO-2509 Edit Product M3 analytics
                editTags()
            case .briefDescription:
                ServiceLocator.analytics.track(.productDetailViewShortDescriptionTapped)
                editBriefDescription()
            case .externalURL:
                // TODO-2509 Edit Product M3 analytics
                editExternalLink()
                break
            case .sku:
                // TODO-2509 Edit Product M3 analytics
                editSKU()
                break
            case .groupedProducts:
                editGroupedProducts()
                break
            case .variations:
                // TODO-2509 Edit Product M3 analytics
                guard let product = product as? Product else {
                    return
                }
                guard product.variations.isNotEmpty else {
                    return
                }
                let variationsViewController = ProductVariationsViewController(siteID: product.siteID,
                                                                               productID: product.productID,
                                                                               isEditProductsRelease3Enabled: isEditProductsRelease3Enabled)
                show(variationsViewController, sender: self)
            }
        }
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        let section = tableViewModel.sections[section]
        switch section {
        case .settings:
            return Constants.settingsHeaderHeight
        default:
            return 0
        }
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let section = tableViewModel.sections[section]
        switch section {
        case .settings:
            let clearView = UIView(frame: .zero)
            clearView.backgroundColor = .listBackground
            return clearView
        default:
            return nil
        }
    }
}

// MARK: - Keyboard management
//
private extension ProductFormViewController {
    /// Registers for all of the related Notifications
    ///
    func startListeningToNotifications() {
        keyboardFrameObserver.startObservingKeyboardFrame()
    }
}

extension ProductFormViewController: KeyboardScrollable {
    var scrollable: UIScrollView {
        return tableView
    }
}

// MARK: Action - Edit Product Images
//
private extension ProductFormViewController {
    func showProductImages() {
        // TODO-jc
        guard let product = product as? Product else {
            return
        }

        let imagesViewController = ProductImagesViewController(product: product,
                                                               productImageActionHandler: productImageActionHandler,
                                                               productUIImageLoader: productUIImageLoader) { [weak self] images, hasChangedData in
                                                                self?.onEditProductImagesCompletion(images: images, hasChangedData: hasChangedData)
        }
        navigationController?.pushViewController(imagesViewController, animated: true)
    }

    func onEditProductImagesCompletion(images: [ProductImage], hasChangedData: Bool) {
        defer {
            navigationController?.popViewController(animated: true)
        }
        ServiceLocator.analytics.track(.productImageSettingsDoneButtonTapped, withProperties: ["has_changed_data": hasChangedData])
        guard hasChangedData else {
            return
        }
        self.viewModel.updateImages(images)
    }
}

// MARK: Action - Edit Product Name
//
private extension ProductFormViewController {
    func onEditProductNameCompletion(newName: String) {
        viewModel.updateName(newName)
    }
}


// MARK: - Navigation actions handling
//
extension ProductFormViewController {
    override func shouldPopOnBackButton() -> Bool {
        if viewModel.hasUnsavedChanges() {
            presentBackNavigationActionSheet()
            return false
        }
        return true
    }

    override func shouldPopOnSwipeBack() -> Bool {
        return shouldPopOnBackButton()
    }

    private func presentBackNavigationActionSheet() {
        UIAlertController.presentDiscardChangesActionSheet(viewController: self, onDiscard: { [weak self] in
            guard let self = self else {
                return
            }
            self.exitForm()
        })
    }
}


// MARK: Action - Edit Product Parameters
//
private extension ProductFormViewController {
    func editProductDescription() {
        let editorViewController = EditorFactory().productDescriptionEditor(product: product) { [weak self] content in
            self?.onEditProductDescriptionCompletion(newDescription: content)
        }
        navigationController?.pushViewController(editorViewController, animated: true)
    }

    func onEditProductDescriptionCompletion(newDescription: String) {
        defer {
            navigationController?.popViewController(animated: true)
        }
        let hasChangedData = newDescription != product.description
        ServiceLocator.analytics.track(.productDescriptionDoneButtonTapped, withProperties: ["has_changed_data": hasChangedData])

        guard hasChangedData else {
            return
        }
        viewModel.updateDescription(newDescription)
    }
}

// MARK: Action - Edit Product Price Settings
//
private extension ProductFormViewController {
    func editPriceSettings() {
        // TODO-jc
        guard let product = product as? Product else {
            return
        }

        let priceSettingsViewController = ProductPriceSettingsViewController(product: product) { [weak self]
            (regularPrice, salePrice, dateOnSaleStart, dateOnSaleEnd, taxStatus, taxClass) in
            self?.onEditPriceSettingsCompletion(regularPrice: regularPrice,
                                                salePrice: salePrice,
                                                dateOnSaleStart: dateOnSaleStart,
                                                dateOnSaleEnd: dateOnSaleEnd,
                                                taxStatus: taxStatus,
                                                taxClass: taxClass)
        }
        navigationController?.pushViewController(priceSettingsViewController, animated: true)
    }

    func onEditPriceSettingsCompletion(regularPrice: String?,
                                       salePrice: String?,
                                       dateOnSaleStart: Date?,
                                       dateOnSaleEnd: Date?,
                                       taxStatus: ProductTaxStatus,
                                       taxClass: TaxClass?) {
        defer {
            navigationController?.popViewController(animated: true)
        }

        let hasChangedData: Bool = {
                getDecimalPrice(regularPrice) != getDecimalPrice(product.regularPrice) ||
                getDecimalPrice(salePrice) != getDecimalPrice(product.salePrice) ||
                dateOnSaleStart != product.dateOnSaleStart ||
                dateOnSaleEnd != product.dateOnSaleEnd ||
                taxStatus != product.productTaxStatus ||
                taxClass?.slug != product.taxClass
        }()

        ServiceLocator.analytics.track(.productPriceSettingsDoneButtonTapped, withProperties: ["has_changed_data": hasChangedData])
        guard hasChangedData else {
            return
        }

        viewModel.updatePriceSettings(regularPrice: regularPrice,
                                      salePrice: salePrice,
                                      dateOnSaleStart: dateOnSaleStart,
                                      dateOnSaleEnd: dateOnSaleEnd,
                                      taxStatus: taxStatus,
                                      taxClass: taxClass)
    }
}

// MARK: Action - Edit Product Shipping Settings
//
private extension ProductFormViewController {
    func editShippingSettings() {
        // TODO-jc
        guard let product = product as? Product else {
            return
        }

        let shippingSettingsViewController = ProductShippingSettingsViewController(product: product) { [weak self] (weight, dimensions, shippingClass) in
            self?.onEditShippingSettingsCompletion(weight: weight, dimensions: dimensions, shippingClass: shippingClass)
        }
        navigationController?.pushViewController(shippingSettingsViewController, animated: true)
    }

    func onEditShippingSettingsCompletion(weight: String?, dimensions: ProductDimensions, shippingClass: ProductShippingClass?) {
        defer {
            navigationController?.popViewController(animated: true)
        }
        let hasChangedData: Bool = {
            weight != self.product.weight ||
                dimensions != self.product.dimensions ||
                shippingClass?.slug != product.shippingClass
        }()
        ServiceLocator.analytics.track(.productShippingSettingsDoneButtonTapped, withProperties: ["has_changed_data": hasChangedData])

        guard hasChangedData else {
            return
        }
        viewModel.updateShippingSettings(weight: weight, dimensions: dimensions, shippingClass: shippingClass)
    }
}

// MARK: Action - Edit Product Inventory Settings
//
private extension ProductFormViewController {
    func editInventorySettings() {
        // TODO-jc
        guard let product = product as? Product else {
            return
        }

        let inventorySettingsViewController = ProductInventorySettingsViewController(product: product) { [weak self] data in
            self?.onEditInventorySettingsCompletion(data: data)
        }
        navigationController?.pushViewController(inventorySettingsViewController, animated: true)
    }

    func onEditInventorySettingsCompletion(data: ProductInventoryEditableData) {
        // TODO-jc
        guard let product = product as? Product else {
            return
        }

        defer {
            navigationController?.popViewController(animated: true)
        }
        let originalData = ProductInventoryEditableData(product: product)
        let hasChangedData = originalData != data
        ServiceLocator.analytics.track(.productInventorySettingsDoneButtonTapped, withProperties: ["has_changed_data": hasChangedData])

        guard hasChangedData else {
            return
        }
        viewModel.updateInventorySettings(sku: data.sku,
                                          manageStock: data.manageStock,
                                          soldIndividually: data.soldIndividually,
                                          stockQuantity: data.stockQuantity,
                                          backordersSetting: data.backordersSetting,
                                          stockStatus: data.stockStatus)
    }
}

// MARK: Action - Edit Product Brief Description (Short Description)
//
private extension ProductFormViewController {
    func editBriefDescription() {
        let editorViewController = EditorFactory().productBriefDescriptionEditor(product: product) { [weak self] content in
            self?.onEditBriefDescriptionCompletion(newBriefDescription: content)
        }
        navigationController?.pushViewController(editorViewController, animated: true)
    }

    func onEditBriefDescriptionCompletion(newBriefDescription: String) {
        defer {
            navigationController?.popViewController(animated: true)
        }
        let hasChangedData = newBriefDescription != product.shortDescription
        ServiceLocator.analytics.track(.productShortDescriptionDoneButtonTapped, withProperties: ["has_changed_data": hasChangedData])

        guard hasChangedData else {
            return
        }
        viewModel.updateBriefDescription(newBriefDescription)
    }
}

// MARK: Action - Edit Product Categories
//

private extension ProductFormViewController {
    func editCategories() {
        guard let product = product as? Product else {
            return
        }

        let categoryListViewController = ProductCategoryListViewController(product: product) { [weak self] (categories) in
            self?.onEditCategoriesCompletion(categories: categories)
        }
        show(categoryListViewController, sender: self)
    }

    func onEditCategoriesCompletion(categories: [ProductCategory]) {
        guard let product = product as? Product else {
            return
        }

        defer {
            navigationController?.popViewController(animated: true)
        }
        //TODO: Edit Product M3 analytics
        let hasChangedData = categories.sorted() != product.categories.sorted()
        guard hasChangedData else {
            return
        }
        viewModel.updateProductCategories(categories)
    }
}

// MARK: Action - Edit Product Tags
//

private extension ProductFormViewController {
    func editTags() {
        //TODO-2081: add action
    }

    func onEditTagsCompletion(tags: [ProductTag]) {
        //TODO-2081: manage completion in editTags()
    }
}

// MARK: Action - Edit Product SKU
//
private extension ProductFormViewController {
    func editSKU() {
        // TODO-jc
        guard let product = product as? Product else {
            return
        }

        let viewController = ProductInventorySettingsViewController(product: product, formType: .sku) { [weak self] data in
            self?.onEditSKUCompletion(sku: data.sku)
        }
        show(viewController, sender: self)
    }

    func onEditSKUCompletion(sku: String?) {
        defer {
            navigationController?.popViewController(animated: true)
        }
        // TODO-2509: Edit Product M3 analytics
        let hasChangedData = sku != product.sku
        guard hasChangedData else {
            return
        }
        viewModel.updateSKU(sku)
    }
}

// MARK: Action - Edit Grouped Products (Grouped Products Only)
//
private extension ProductFormViewController {
    func editGroupedProducts() {
        guard let product = product as? Product else {
            return
        }

        let viewController = GroupedProductsViewController(product: product) { [weak self] groupedProductIDs in
            self?.onEditGroupedProductsCompletion(groupedProductIDs: groupedProductIDs)
        }
        show(viewController, sender: self)
    }

    func onEditGroupedProductsCompletion(groupedProductIDs: [Int64]) {
        guard let product = product as? Product else {
            return
        }

        defer {
            navigationController?.popViewController(animated: true)
        }
        // TODO-2000: Edit Product M3 analytics
        let hasChangedData = groupedProductIDs != product.groupedProducts
        guard hasChangedData else {
            return
        }
        viewModel.updateGroupedProductIDs(groupedProductIDs)
    }
}

// MARK: Action - Edit Product External Link
//
private extension ProductFormViewController {
    func editExternalLink() {
        guard let product = product as? Product else {
            return
        }

        let viewController = ProductExternalLinkViewController(product: product) { [weak self] externalURL, buttonText in
            self?.onEditExternalLinkCompletion(externalURL: externalURL, buttonText: buttonText)
        }
        show(viewController, sender: self)
    }

    func onEditExternalLinkCompletion(externalURL: String?, buttonText: String) {
        guard let product = product as? Product else {
            return
        }

        defer {
            navigationController?.popViewController(animated: true)
        }
        // TODO-2000: Edit Product M3 analytics
        let hasChangedData = externalURL != product.externalURL || buttonText != product.buttonText
        guard hasChangedData else {
            return
        }
        viewModel.updateExternalLink(externalURL: externalURL, buttonText: buttonText)
    }
}

// MARK: Convenience Methods
//
private extension ProductFormViewController {
    func getDecimalPrice(_ price: String?) -> NSDecimalNumber? {
        guard let price = price else {
            return nil
        }
        let currencyFormatter = CurrencyFormatter()
        return currencyFormatter.convertToDecimal(from: price)
    }
}

// MARK: Action Sheet
//
private extension ProductFormViewController {

    /// More Options Action Sheet
    ///
    @objc func presentMoreOptionsActionSheet(_ sender: UIBarButtonItem) {
        let actionSheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        actionSheet.view.tintColor = .text

        /// The "View product in store" action will be shown only if the product is published.
        if viewModel.canViewProductInStore() {
            actionSheet.addDefaultActionWithTitle(ActionSheetStrings.viewProduct) { [weak self] _ in
                ServiceLocator.analytics.track(.productDetailViewProductButtonTapped)
                self?.displayWebViewForProductInStore()
            }
        }

        actionSheet.addDefaultActionWithTitle(ActionSheetStrings.share) { [weak self] _ in
            ServiceLocator.analytics.track(.productDetailShareButtonTapped)
            self?.displayShareProduct()
        }

        actionSheet.addDefaultActionWithTitle(ActionSheetStrings.productSettings) { [weak self] _ in
            ServiceLocator.analytics.track(.productDetailViewSettingsButtonTapped)
            self?.displayProductSettings()
        }

        actionSheet.addCancelActionWithTitle(ActionSheetStrings.cancel) { _ in
        }

        let popoverController = actionSheet.popoverPresentationController
        popoverController?.barButtonItem = sender

        present(actionSheet, animated: true)
    }

    enum ActionSheetStrings {
        static let viewProduct = NSLocalizedString("View Product in Store",
                                                   comment: "Button title View product in store in Edit Product More Options Action Sheet")
        static let share = NSLocalizedString("Share", comment: "Button title Share in Edit Product More Options Action Sheet")
        static let productSettings = NSLocalizedString("Product Settings", comment: "Button title Product Settings in Edit Product More Options Action Sheet")
        static let cancel = NSLocalizedString("Cancel", comment: "Button title Cancel in Edit Product More Options Action Sheet")
    }
}

// MARK: Constants
//
private extension ProductFormViewController {
    enum Constants {
        static let settingsHeaderHeight = CGFloat(16)
    }
}

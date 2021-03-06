import Foundation
import Yosemite

final class ProductCategoryListViewModel {

    /// Obscure token that allows the view model to retry the synchronizeCategories operation
    ///
    struct RetryToken: Equatable {
        fileprivate let fromPageNumber: Int
    }

    /// Represents the current state of `synchronizeCategories` action. Useful for the consumer to update it's UI upon changes
    ///
    enum SyncingState: Equatable {
        case initialized
        case syncing
        case failed(RetryToken)
        case synced
    }

    /// Reference to the StoresManager to dispatch Yosemite Actions.
    ///
    private let storesManager: StoresManager

    /// Product the user is editiing
    ///
    private let product: Product

    /// Product categories that will be eventually modified by the user
    ///
    private(set) var selectedCategories: [ProductCategory]

    /// Array of view models to be rendered by the View Controller.
    ///
    private(set) var categoryViewModels: [ProductCategoryCellViewModel] = []

    /// Closure to be invoked when `synchronizeCategories` state  changes
    ///
    private var onSyncStateChange: ((SyncingState) -> Void)?

    /// Current  category synchronization state
    ///
    private var syncCategoriesState: SyncingState = .initialized {
        didSet {
            guard syncCategoriesState != oldValue else {
                return
            }
            onSyncStateChange?(syncCategoriesState)
        }
    }

    private lazy var resultController: ResultsController<StorageProductCategory> = {
        let storageManager = ServiceLocator.storageManager
        let predicate = NSPredicate(format: "siteID = %ld", self.product.siteID)
        let descriptor = NSSortDescriptor(keyPath: \StorageProductCategory.name, ascending: true)
        return ResultsController<StorageProductCategory>(storageManager: storageManager, matching: predicate, sortedBy: [descriptor])
    }()

    init(storesManager: StoresManager = ServiceLocator.stores, product: Product) {
        self.storesManager = storesManager
        self.product = product
        selectedCategories = product.categories
    }

    /// Load existing categories from storage and fire the synchronize all categories action.
    ///
    func performFetch() {
        synchronizeAllCategories()
        try? resultController.performFetch()
    }

    /// Retry product categories synchronization when `syncCategoriesState` is on a `.failed` state.
    ///
    func retryCategorySynchronization(retryToken: RetryToken) {
        guard syncCategoriesState == .failed(retryToken) else {
            return
        }
        synchronizeAllCategories(fromPageNumber: retryToken.fromPageNumber)
    }

    /// Observes and notifies of changes made to product categories. the current state will be dispatched upon subscription.
    /// Calling this method will remove any other previous observer.
    ///
    func observeCategoryListStateChanges(onStateChanges: @escaping (SyncingState) -> Void) {
        onSyncStateChange = onStateChanges
        onSyncStateChange?(syncCategoriesState)
    }

    /// Select or Deselect a category
    ///
    func selectOrDeselectCategory(index: Int) {
        guard let categoryViewModel = categoryViewModels[safe: index] else {
            return
        }

        // If the category selected exist, remove it, otherwise, add it to `selectedCategories`.
        if let indexCategory = selectedCategories.firstIndex(where: { $0.categoryID == categoryViewModel.categoryID}) {
            selectedCategories.remove(at: indexCategory)
        }
        else if let category = resultController.fetchedObjects.first(where: { $0.categoryID == categoryViewModel.categoryID }) {
            selectedCategories.append(category)
        }

        updateViewModelsArray()
    }

    /// Add a new category added remotely, and that will be selected
    ///
    func addAndSelectNewCategory(category: ProductCategory) {
        selectedCategories.append(category)
        updateViewModelsArray()
    }

    func hasUnsavedChanges() -> Bool {
        return product.categories.sorted() != selectedCategories.sorted()
    }
}

// MARK: - Synchronize Categories
//
private extension ProductCategoryListViewModel {
    /// Synchronizes all product categories starting at a specific page number. Default initial page number is set on `Default.firstPageNumber`
    ///
    func synchronizeAllCategories(fromPageNumber: Int = Default.firstPageNumber) {
        self.syncCategoriesState = .syncing
        let action = ProductCategoryAction.synchronizeProductCategories(siteID: product.siteID, fromPageNumber: fromPageNumber) { [weak self] error in
            // Make sure we always have view models to display
            self?.updateViewModelsArray()

            if let error = error {
                ServiceLocator.analytics.track(.productCategoryListLoadFailed, withError: error)
                self?.handleSychronizeAllCategoriesError(error)
            } else {
                ServiceLocator.analytics.track(.productCategoryListLoaded)
                self?.syncCategoriesState = .synced
            }
        }
        storesManager.dispatch(action)
    }

    /// Update `syncCategoriesState` with the proper retryToken
    ///
    func handleSychronizeAllCategoriesError(_ error: ProductCategoryActionError) {
        switch error {
        case let .categoriesSynchronization(pageNumber, rawError):
            let retryToken = RetryToken(fromPageNumber: pageNumber)
            syncCategoriesState = .failed(retryToken)
            DDLogError("⛔️ Error fetching product categories: \(rawError.localizedDescription)")
        }
    }

    /// Updates  `categoryViewModels` from  the resultController's fetched objects.
    ///
    func updateViewModelsArray() {
        let fetchedCategories = resultController.fetchedObjects
        categoryViewModels = CellViewModelBuilder.viewModels(from: fetchedCategories, selectedCategories: selectedCategories)
    }
}

// MARK: - Constants
//
private extension ProductCategoryListViewModel {
    enum Default {
        public static let firstPageNumber = 1
    }
}

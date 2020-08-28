import Storage
import CoreData
import Combine

@available(iOS 13.0, *)
public final class DiffableResultsController: NSObject {

    public typealias Snapshot = NSDiffableDataSourceSnapshot<String, NSManagedObjectID>

    private let storage: StorageType

    private lazy var wrappedController: NSFetchedResultsController<StorageOrder> = {
        let sortDescriptor = NSSortDescriptor(keyPath: \StorageOrder.dateCreated, ascending: false)
        let fetchRequest = NSFetchRequest<StorageOrder>(entityName: StorageOrder.entityName)
        fetchRequest.sortDescriptors = [sortDescriptor]

        let sectionNameKeyPath = #selector(StorageOrder.normalizedAgeAsString)
        let resultsController = storage.createFetchedResultsController(
            fetchRequest: fetchRequest,
            sectionNameKeyPath: "\(sectionNameKeyPath)",
            cacheName: nil
        )
        resultsController.delegate = self
        return resultsController
    }()

    private let snapshotSubject = CurrentValueSubject<Snapshot, Never>(Snapshot())

    public var snapshot: AnyPublisher<Snapshot, Never> {
        snapshotSubject.eraseToAnyPublisher()
    }

    public init(storage: StorageType) {
        self.storage = storage
    }

    public func performFetch() throws {
        try wrappedController.performFetch()
    }

    public var numberOfObjects: Int {
        snapshotSubject.value.numberOfItems
    }

    /// Indicates if there are any Objects matching the specified criteria.
    ///
    public var isEmpty: Bool {
        snapshotSubject.value.numberOfItems == 0
    }

    public func indexOfObject(_ managedObjectID: NSManagedObjectID) -> Int? {
        snapshotSubject.value.indexOfItem(managedObjectID)
    }

    public func object(withID managedObjectID: NSManagedObjectID) -> Order? {
        #warning("we don't want NSManagedObjectID :D. Fix this later")
        let context = storage as! NSManagedObjectContext
        if let storageOrder = try? context.existingObject(with: managedObjectID) as? StorageOrder {
            return storageOrder.toReadOnly()
        } else {
            return nil
        }
    }

    public func nameOfSection(at section: Int) -> String? {
        wrappedController.sections?[section].name
    }
}

@available(iOS 13.0, *)
extension DiffableResultsController: NSFetchedResultsControllerDelegate {
    public func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>,
                           didChangeContentWith snapshot: NSDiffableDataSourceSnapshotReference) {
        let snapshot = snapshot as Snapshot
        snapshotSubject.send(snapshot)
    }
}

import Photos
import UIKit
import Yosemite

/// Displays Product images in grid layout.
///
final class ProductImagesCollectionViewController: UICollectionViewController {

    private var productImageStatuses: [ProductImageStatus]

    private let imageService: ImageService
    private let onDeletion: ProductImageViewController.Deletion

    init(imageStatuses: [ProductImageStatus],
         imageService: ImageService = ServiceLocator.imageService,
         onDeletion: @escaping ProductImageViewController.Deletion) {
        self.productImageStatuses = imageStatuses
        self.imageService = imageService
        self.onDeletion = onDeletion
        let columnLayout = ColumnFlowLayout(
            cellsPerRow: 2,
            minimumInteritemSpacing: 16,
            minimumLineSpacing: 16,
            sectionInset: UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        )
        super.init(collectionViewLayout: columnLayout)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        collectionView.backgroundColor = .basicBackground

        collectionView.register(ProductImageCollectionViewCell.loadNib(), forCellWithReuseIdentifier: ProductImageCollectionViewCell.reuseIdentifier)
        collectionView.register(InProgressProductImageCollectionViewCell.loadNib(),
                                forCellWithReuseIdentifier: InProgressProductImageCollectionViewCell.reuseIdentifier)

        collectionView.reloadData()
    }

    func updateProductImageStatuses(_ productImageStatuses: [ProductImageStatus]) {
        self.productImageStatuses = productImageStatuses

        collectionView.reloadData()
    }
}

// MARK: UICollectionViewDataSource
//
extension ProductImagesCollectionViewController {

    override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return productImageStatuses.count
    }

    override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let productImageStatus = productImageStatuses[indexPath.row]
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: productImageStatus.cellReuseIdentifier,
                                                      for: indexPath)
        configureCell(cell, productImageStatus: productImageStatus)
        return cell
    }
}

// MARK: Cell configurations
//
private extension ProductImagesCollectionViewController {
    func configureCell(_ cell: UICollectionViewCell, productImageStatus: ProductImageStatus) {
        switch productImageStatus {
        case .remote(let image):
            configureRemoteImageCell(cell, image: image)
        case .uploading(let asset):
            configureUploadingImageCell(cell, asset: asset)
        }
    }

    func configureRemoteImageCell(_ cell: UICollectionViewCell, image: ProductImage) {
        guard let cell = cell as? ProductImageCollectionViewCell else {
            fatalError()
        }

        cell.imageView.contentMode = .center

        imageService.downloadAndCacheImageForImageView(cell.imageView,
                                                       with: image.src,
                                                       placeholder: .productPlaceholderImage,
                                                       progressBlock: nil) { (image, error) in
                                                        let success = image != nil && error == nil
                                                        if success {
                                                            cell.imageView.contentMode = .scaleAspectFit
                                                        }
        }
    }

    func configureUploadingImageCell(_ cell: UICollectionViewCell, asset: PHAsset) {
        guard let cell = cell as? InProgressProductImageCollectionViewCell else {
            fatalError()
        }

        let manager = PHImageManager.default()
        manager.requestImage(for: asset,
                             targetSize: cell.bounds.size,
                             contentMode: .aspectFit,
                             options: nil,
                             resultHandler: { (result, info) in
            if let result = result {
                cell.imageView.image = result
                cell.imageView.contentMode = .scaleAspectFit
            }
            else {
                cell.imageView.contentMode = .center
            }
        })
    }
}

// MARK: UICollectionViewDelegate
//
extension ProductImagesCollectionViewController {
    override func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let status = productImageStatuses[indexPath.row]
        switch status {
        case .remote(let productImage):
            let productImageViewController = ProductImageViewController(productImage: productImage, onDeletion: onDeletion)
            navigationController?.pushViewController(productImageViewController, animated: true)
        default:
            return
        }
    }
}
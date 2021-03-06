import Foundation

/// Protocol for `ShippingLabelRemote` mainly used for mocking.
public protocol ShippingLabelRemoteProtocol {
    func loadShippingLabels(siteID: Int64, orderID: Int64, completion: @escaping (Result<OrderShippingLabelListResponse, Error>) -> Void)
    func printShippingLabel(siteID: Int64,
                            shippingLabelID: Int64,
                            paperSize: ShippingLabelPaperSize,
                            completion: @escaping (Result<ShippingLabelPrintData, Error>) -> Void)
}

/// Shipping Labels Remote Endpoints.
public final class ShippingLabelRemote: Remote, ShippingLabelRemoteProtocol {
    /// Loads shipping labels and settings for an order.
    /// - Parameters:
    ///   - siteID: Remote ID of the site that owns the order.
    ///   - orderID: Remote ID of the order that owns the shipping labels.
    ///   - completion: Closure to be executed upon completion.
    public func loadShippingLabels(siteID: Int64, orderID: Int64, completion: @escaping (Result<OrderShippingLabelListResponse, Error>) -> Void) {
        let path = "\(Path.shippingLabels)/\(orderID)"
        let request = JetpackRequest(wooApiVersion: .wcConnectV1, method: .get, siteID: siteID, path: path)
        let mapper = OrderShippingLabelListMapper(siteID: siteID, orderID: orderID)
        enqueue(request, mapper: mapper, completion: completion)
    }

    /// Generates shipping label data for printing.
    /// - Parameters:
    ///   - siteID: Remote ID of the site that owns the shipping label.
    ///   - shippingLabelID: Remote ID of the shipping label.
    ///   - paperSize: Paper size option (current options are "label", "legal", and "letter").
    ///   - completion: Closure to be executed upon completion.
    public func printShippingLabel(siteID: Int64,
                                   shippingLabelID: Int64,
                                   paperSize: ShippingLabelPaperSize,
                                   completion: @escaping (Result<ShippingLabelPrintData, Error>) -> Void) {
        let parameters = [
            ParameterKey.paperSize: paperSize.rawValue,
            ParameterKey.labelIDCSV: String(shippingLabelID),
            ParameterKey.captionCSV: "",
            ParameterKey.json: "true" // `json=true` is necessary, otherwise it results in 500 error "no_response_body".
        ]
        let path = "\(Path.shippingLabels)/print"
        let request = JetpackRequest(wooApiVersion: .wcConnectV1, method: .get, siteID: siteID, path: path, parameters: parameters)
        let mapper = ShippingLabelPrintDataMapper()

        enqueue(request, mapper: mapper, completion: completion)
    }
}

// MARK: Constant
private extension ShippingLabelRemote {
    enum Path {
        static let shippingLabels = "label"
    }

    enum ParameterKey {
        static let paperSize = "paper_size"
        static let labelIDCSV = "label_id_csv"
        static let captionCSV = "caption_csv"
        static let json = "json"
    }
}

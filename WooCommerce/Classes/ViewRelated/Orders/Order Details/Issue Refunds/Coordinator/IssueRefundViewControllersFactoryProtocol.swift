import Foundation
import Yosemite

protocol IssueRefundViewControllersFactoryProtocol {
    func makeIssueRefundViewController(order: Order, refunds: [Refund]) -> IssueRefundViewControllerProtocol
}

/// Creates appropriate view controllers for the IssueRefund flow.
///
final class IssueRefundViewControllersFactory: IssueRefundViewControllersFactoryProtocol {

    func makeIssueRefundViewController(order: Order, refunds: [Refund]) ->  IssueRefundViewControllerProtocol {
        IssueRefundViewController(order: order, refunds: refunds)
    }
}

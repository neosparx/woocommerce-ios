import WebKit
import XCTest
import TestKit
import Yosemite

@testable import WooCommerce

/// Test cases for `IssueRefundCoordinatingController`.
///
final class IssueRefundCoordinatingControllerTests: XCTestCase {

    func test_it_loads_IssueRefundViewController_on_start() {
        // Given
        let factory = MockIssueRefundViewControllersFactory()

        // When
        let coordinator = IssueRefundCoordinatingController(order: MockOrders().empty(), refunds: [], viewControllersFactory: factory)

        // Then
        XCTAssertTrue(coordinator.topViewController is IssueRefundViewControllerProtocol)
    }
}

private final class MockIssueRefundViewControllersFactory: IssueRefundViewControllersFactoryProtocol {
    let issueRefundViewController = MockIssueRefundViewController()

    func makeIssueRefundViewController(order: Order, refunds: [Refund]) -> IssueRefundViewControllerProtocol {
        issueRefundViewController
    }
}

private final class MockIssueRefundViewController: IssueRefundViewControllerProtocol {

    var onNextAction: ((RefundConfirmationViewModel) -> Void)?

    var onSelectQuantityAction: ((RefundItemQuantityListSelectorCommand) -> Void)?

    func updateRefundQuantity(quantity: Int, forItemAtIndex index: Int) {

    }
}

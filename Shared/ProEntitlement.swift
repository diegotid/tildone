import Foundation
import StoreKit
import SwiftUI

enum ProFeature: String, Identifiable {
    case singleMemo, textStyling, subtasks, blur, background, focusPrivacy, dimming, gathering

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .singleMemo: "Single memos"
        case .textStyling: "Text styling"
        case .subtasks: "Subtasks"
        case .blur: "Blur Content"
        case .background: "Stay in Background"
        case .focusPrivacy: "Focus & Privacy"
        case .dimming: "Dim notes"
        case .gathering: "Gather notes"
        }
    }
}

/// Pure entitlement state. Only verified, non-revoked transactions may enter this type.
struct ProEntitlementState: Equatable {
    static let productID = "studio.cuatro.tildone.pro"
    private(set) var activeTransactionIDs: Set<UInt64> = []

    var isPro: Bool { !activeTransactionIDs.isEmpty }

    mutating func replaceCurrent(_ transactionIDs: Set<UInt64>) {
        activeTransactionIDs = transactionIDs
    }

    mutating func apply(transactionID: UInt64, revoked: Bool) {
        if revoked { activeTransactionIDs.remove(transactionID) }
        else { activeTransactionIDs.insert(transactionID) }
    }
}

enum ProFeatureAccess {
    /// Existing content remains editable and visible. Only entering or changing a Pro mode is gated.
    static func allows(_ feature: ProFeature, isPro: Bool, isAlreadyActive: Bool = false) -> Bool {
        isPro || isAlreadyActive
    }
}

enum ProAccessError: Error {
    case requiresPro
}

@MainActor
final class ProEntitlement: ObservableObject {
    static let shared = ProEntitlement()

    @Published private(set) var state = ProEntitlementState()
    @Published private(set) var product: Product?
    @Published private(set) var isLoadingProduct = false
    @Published private(set) var isPurchasing = false
    @Published private(set) var message: String?
    @Published var requestedFeature: ProFeature?

    #if DEBUG
    private var testOverride: Bool?

    func setTestOverride(_ value: Bool?) {
        precondition(NSClassFromString("XCTestCase") != nil)
        testOverride = value
    }
    #endif

    var isPro: Bool {
        #if DEBUG
        if let testOverride { return testOverride }
        // Existing hosted repository tests exercise domain operations without
        // contacting StoreKit. They use an explicitly isolated test process.
        if NSClassFromString("XCTestCase") != nil { return true }
        #endif
        return state.isPro
    }
    var localizedPrice: String? { product?.displayPrice }
    private var updatesTask: Task<Void, Never>?
    private var hasStarted = false
    private var entitlementRefreshRevision = 0

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        updatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                if case .verified(let transaction) = result {
                    await self.refreshCurrentEntitlements()
                    if self.isPro {
                        self.message = nil
                        self.requestedFeature = nil
                    }
                    await transaction.finish()
                }
            }
        }
        Task {
            await refreshCurrentEntitlements()
            await loadProduct()
        }
    }

    func refreshCurrentEntitlements() async {
        entitlementRefreshRevision += 1
        let revision = entitlementRefreshRevision
        var IDs = Set<UInt64>()
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  transaction.productID == ProEntitlementState.productID,
                  transaction.revocationDate == nil else { continue }
            IDs.insert(transaction.id)
        }
        if revision == entitlementRefreshRevision { state.replaceCurrent(IDs) }
    }

    func loadProduct() async {
        isLoadingProduct = true
        defer { isLoadingProduct = false }
        do {
            product = try await Product.products(for: [ProEntitlementState.productID])
                .first { $0.id == ProEntitlementState.productID && $0.type == .nonConsumable }
            if product == nil { message = String(localized: "Tildone Pro is currently unavailable. Please try again later.") }
            else { message = nil }
        } catch {
            product = nil
            message = String(localized: "Tildone Pro is currently unavailable. Please try again later.")
        }
    }

    func purchase() async {
        guard let product else { await loadProduct(); return }
        isPurchasing = true
        message = nil
        defer { isPurchasing = false }
        do {
            switch try await product.purchase() {
            case .success(.verified(let transaction)):
                guard transaction.productID == ProEntitlementState.productID,
                      transaction.revocationDate == nil else {
                    message = String(localized: "Purchase could not be verified. Please try Restore Purchases.")
                    return
                }
                state.apply(transactionID: transaction.id, revoked: false)
                await refreshCurrentEntitlements()
                await transaction.finish()
                if isPro { requestedFeature = nil }
            case .success(.unverified):
                message = String(localized: "Purchase could not be verified. Please try Restore Purchases.")
            case .pending:
                message = String(localized: "Purchase pending approval.")
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            message = String(localized: "Purchase could not be completed. Please try again.")
        }
    }

    func restore() async {
        do {
            try await AppStore.sync()
            await refreshCurrentEntitlements()
            message = isPro
                ? String(localized: "Tildone Pro restored.")
                : String(localized: "No Tildone Pro purchase was found for this Apple Account.")
        } catch {
            message = String(localized: "Restore Purchases could not be completed. Please try again.")
        }
    }

    @discardableResult
    func require(_ feature: ProFeature, isAlreadyActive: Bool = false) -> Bool {
        guard ProFeatureAccess.allows(feature, isPro: isPro, isAlreadyActive: isAlreadyActive) else {
            requestedFeature = feature
            return false
        }
        return true
    }
}

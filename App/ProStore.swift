import Foundation
import Recording
import StoreKit

/// The App Store side of Pro (ADR 0004): loads the Pro product, buys it, restores it and keeps what is owned
/// (the operator's own purchase or one shared by Family Sharing) current. The tier is read from the cached state
/// when record is pressed, so nothing at record time waits on the App Store (Show-Safe Promise).
@MainActor
@Observable
final class ProStore {
    /// What the current entitlements mean: whether Pro is owned and when the Trial started.
    private(set) var purchases = ProPurchases(owned: [])
    /// The Pro product, once loaded. Nil until then, or when the App Store doesn't offer it.
    private(set) var proProduct: Product?
    /// The $0 14-day Trial product, once loaded.
    private(set) var trialProduct: Product?
    private(set) var loadingProducts = true
    /// A purchase or restore in progress.
    private(set) var busy = false
    /// A calm note after a purchase or restore: waiting for approval (Ask to Buy), nothing to restore, or a failure.
    private(set) var note: String?
    /// The USB Channels the operator chose to record on Free. Saved as soon as it changes.
    var freeChoice: [Int] = FreeChannelChoice.load() {
        didSet { FreeChannelChoice.save(freeChoice) }
    }

    @ObservationIgnored private var updates: Task<Void, Never>?

    init() {
        updates = Task { [weak self] in
            for await update in Transaction.updates {
                if case .verified(let transaction) = update { await transaction.finish() }
                await self?.refreshOwned()
            }
        }
        Task {
            await refreshOwned()
            await loadProducts()
        }
    }

    func tier(now: Date = Date()) -> Tier { purchases.tier(now: now) }

    func loadProducts() async {
        loadingProducts = true
        defer { loadingProducts = false }
        let products = (try? await Product.products(for: [ProPurchases.proProductID, ProPurchases.trialProductID])) ?? []
        proProduct = products.first { $0.id == ProPurchases.proProductID }
        trialProduct = products.first { $0.id == ProPurchases.trialProductID }
    }

    /// The Trial's disclosure, once Pro's price is known (Guideline 3.1.1 asks for it).
    var trialDisclosure: TrialDisclosure? {
        proProduct.map { TrialDisclosure(proPrice: $0.displayPrice) }
    }

    func buyPro() async {
        guard let proProduct else { return }
        await purchase(proProduct, failure: "Couldn't buy Pro")
    }

    /// Starts the 14-day Trial: a $0 purchase, so its start date is the App Store's and survives reinstalling.
    func startTrial() async {
        guard let trialProduct else { return }
        await purchase(trialProduct, failure: "Couldn't start the Trial")
    }

    private func purchase(_ product: Product, failure: String) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        note = nil
        do {
            switch try await product.purchase() {
            case .success(.verified(let transaction)):
                await transaction.finish()
                await refreshOwned()
            case .success(.unverified):
                note = "The App Store couldn't confirm the purchase. Try Restore Purchases."
            case .pending:
                note = "Waiting for approval. It unlocks when it is approved."
            case .userCancelled:  // spelling: ok (StoreKit's name)
                break
            @unknown default:
                break
            }
        } catch {
            note = "\(failure): \(error.localizedDescription)"
        }
    }

    /// Restore Purchases: asks the App Store to sync (it may ask the operator to sign in), then re-reads what is owned.
    func restore() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        note = nil
        do {
            try await AppStore.sync()
            await refreshOwned()
            if !purchases.ownsPro { note = "No Pro purchase found for this Apple Account." }
        } catch {
            note = "Couldn't restore purchases: \(error.localizedDescription)"
        }
    }

    /// Re-reads every current entitlement, own or Family Shared, so refunds and revocations count too.
    private func refreshOwned() async {
        var owned: [OwnedPurchase] = []
        for await entitlement in Transaction.currentEntitlements {
            guard case .verified(let transaction) = entitlement else { continue }
            owned.append(OwnedPurchase(
                productID: transaction.productID,
                purchaseDate: transaction.purchaseDate,
                revocationDate: transaction.revocationDate))
        }
        purchases = ProPurchases(owned: owned)
    }
}

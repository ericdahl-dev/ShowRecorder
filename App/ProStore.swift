import Foundation
import MixerLink
import Recording
import StoreKit

/// The App Store side of Pro (ADR 0004): loads the Pro product, buys it, restores it and keeps what is owned
/// (the operator's own purchase or one shared by Family Sharing) current. The tier is read from the cached state
/// when record is pressed, so nothing at record time waits on the App Store (Show-Safe Promise).
@MainActor
@Observable
final class ProStore {
    /// On in every build since the Pro and Trial products exist in App Store Connect (#371, 2026-10-11): Settings' Pro
    /// section, the first-launch Trial offer, the paywall, the days-left chip and the Free limit at record. Off, the
    /// License limits nothing, so every USB Channel is recorded with every extra (#60), and hides all of those.
    static let isOffered = true

    /// What the App Store has said: the last known purchases on this device (#316) until it answers this launch.
    private(set) var status = ProStatus(lastKnown: ProStore.debugTrial ?? ProPurchases.lastKnown())
    /// Whether Pro is owned and when the Trial started.
    var purchases: ProPurchases { status.purchases }
    /// Called when the known tier or owned packs change (the App Store answered, a purchase, a refund; #705), so the
    /// recorder can re-Arm between Takes at the rate it may now use.
    @ObservationIgnored var onTierChange: (() -> Void)?
    /// The Armed input's Mixer family, set by the record screen model, so an owned pack counts on its own family (#705).
    @ObservationIgnored var armedFamily: () -> MixerFamily? = { nil }
    /// The Pro product, once loaded. Nil until then, or when the App Store doesn't offer it.
    private(set) var proProduct: Product?
    /// The $0 14-day Trial product, once loaded.
    private(set) var trialProduct: Product?
    /// The mixer pack products, once loaded, only where packs are offered (#705).
    private(set) var packProducts: [MixerFamily: Product] = [:]
    /// The upgrade to Pro for a pack owner, once loaded, only where packs are offered (#705).
    private(set) var upgradeProduct: Product?
    private(set) var loadingProducts = true
    /// A purchase or restore in progress.
    private(set) var busy = false
    /// A calm note after a purchase or restore: waiting for approval (Ask to Buy), nothing to restore, or a failure.
    private(set) var note: String?

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

    /// What the operator may do right now. Every Pro, Free and Trial question goes through it (#439).
    func license(now: Date = Date()) -> License {
        status.license(proOffered: Self.isOffered, armedFamily: armedFamily(), now: now)
    }

    /// The plan as owned, whatever is Armed (#705): for Settings' plan line and offers, so they don't change with the
    /// input and a running Trial isn't hidden by a pack on the Armed family. Record press and limits use `license()`.
    func planLicense(now: Date = Date()) -> License {
        status.license(proOffered: Self.isOffered, now: now)
    }

    /// Debug builds only: `-trialDaysLeft N` acts as if a Trial with N days left is owned (0 has just ended), so the
    /// days-left chip, the last-days offer and the end of the Trial can be checked without waiting two weeks (#324).
    private static let debugTrial: ProPurchases? = {
        #if DEBUG
        guard UserDefaults.standard.object(forKey: "trialDaysLeft") != nil else { return nil }
        let left = UserDefaults.standard.integer(forKey: "trialDaysLeft")
        let started = Date().addingTimeInterval(-Entitlement.trialLength + Double(left) * 86_400 - 60)
        return ProPurchases(owned: [OwnedPurchase(productID: ProPurchases.trialProductID, purchaseDate: started)])
        #else
        return nil
        #endif
    }()

    func loadProducts() async {
        loadingProducts = true
        defer { loadingProducts = false }
        var ids = [ProPurchases.proProductID, ProPurchases.trialProductID]
        if PackAvailability.isAvailableInThisBuild { ids += ProPurchases.packProductIDs.values + [ProPurchases.upgradeProductID] }
        let products = (try? await Product.products(for: ids)) ?? []
        proProduct = products.first { $0.id == ProPurchases.proProductID }
        trialProduct = products.first { $0.id == ProPurchases.trialProductID }
        packProducts = ProPurchases.packProductIDs.compactMapValues { id in products.first { $0.id == id } }
        upgradeProduct = products.first { $0.id == ProPurchases.upgradeProductID }
    }

    /// The Trial's disclosure, once Pro's price is known (Guideline 3.1.1 asks for it).
    var trialDisclosure: TrialDisclosure? {
        proProduct.map { TrialDisclosure(proPrice: $0.displayPrice) }
    }

    func buyPro() async {
        guard let proProduct else { return }
        await purchase(proProduct, failure: "Couldn't buy Pro")
    }

    /// Buys Pro, a mixer pack or the upgrade (#705).
    func buy(_ product: Product) async {
        await purchase(product, failure: "Couldn't buy \(product.displayName)")
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
            note = PackOffer.restoreNote(ownsPro: purchases.ownsPro, ownedPacks: purchases.ownedPacks)
        } catch {
            note = "Couldn't restore purchases: \(error.localizedDescription)"
        }
    }

    /// Re-reads every current entitlement, own or Family Shared, so refunds and revocations count too.
    private func refreshOwned() async {
        guard Self.debugTrial == nil else { return }  // a Debug run pretending a Trial keeps it
        var owned: [OwnedPurchase] = []
        for await entitlement in Transaction.currentEntitlements {
            guard case .verified(let transaction) = entitlement else { continue }
            owned.append(OwnedPurchase(
                productID: transaction.productID,
                purchaseDate: transaction.purchaseDate,
                revocationDate: transaction.revocationDate,
                isFamilyShared: transaction.ownershipType == .familyShared))
        }
        let changed = status.appStoreAnswered(owned, now: Date())
        status.purchases.saveAsLastKnown()
        if changed { onTierChange?() }
    }
}

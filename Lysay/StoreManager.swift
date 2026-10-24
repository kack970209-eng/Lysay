import Foundation
import StoreKit

/// Apple 内购订阅（StoreKit 2）：Lysay Pro 月付 / 年付。
/// 购买后把 Apple 签名的交易交给服务器验证，由服务器开通 Pro。
@MainActor
final class StoreManager: ObservableObject {
    static let shared = StoreManager()
    static let productIDs = ["com.lysay.pro.monthly", "com.lysay.pro.yearly"]

    @Published private(set) var products: [Product] = []
    @Published private(set) var purchasing = false
    @Published var message: String?

    private var updatesTask: Task<Void, Never>?

    private init() {
        // 续订、在其他设备购买、家人共享等，都会从这里收到
        updatesTask = Task.detached { [weak self] in
            for await result in Transaction.updates {
                await self?.handle(result)
            }
        }
    }

    func loadProducts() async {
        guard products.isEmpty else { return }
        do {
            let list = try await Product.products(for: Self.productIDs)
            products = list.sorted { $0.price < $1.price }
        } catch {
            message = "无法载入订阅方案：\(error.localizedDescription)"
        }
    }

    func purchase(_ product: Product) async {
        guard let userId = AccountManager.shared.profile?.user.id, let token = UUID(uuidString: userId) else {
            message = "请先登录再订阅"
            return
        }
        purchasing = true
        defer { purchasing = false }
        do {
            let result = try await product.purchase(options: [.appAccountToken(token)])
            switch result {
            case .success(let verification):
                await handle(verification)
                message = "订阅成功，Lysay Pro 已开通"
            case .pending:
                message = "购买等待确认中（例如需要家长同意）"
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            message = "购买失败：\(error.localizedDescription)"
        }
    }

    /// 恢复购买：同步 App Store，再把目前有效的订阅交给服务器
    func restore() async {
        purchasing = true
        defer { purchasing = false }
        do {
            try await AppStore.sync()
        } catch {
            message = "恢复失败：\(error.localizedDescription)"
            return
        }
        var jws: [String] = []
        for await result in Transaction.currentEntitlements {
            jws.append(result.jwsRepresentation)
        }
        if jws.isEmpty {
            message = "没有找到可恢复的订阅"
            return
        }
        await AccountManager.shared.verifyTransactions(jws)
        message = AccountManager.shared.profile?.ai.pro == true ? "已恢复 Lysay Pro" : "已同步购买记录"
    }

    private func handle(_ result: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = result else { return }
        await AccountManager.shared.verifyTransactions([result.jwsRepresentation])
        await transaction.finish()
    }
}

extension Product {
    var periodText: String {
        guard let unit = subscription?.subscriptionPeriod.unit else { return "" }
        switch unit {
        case .month: return "每月"
        case .year: return "每年"
        case .week: return "每週"
        case .day: return "每天"
        @unknown default: return ""
        }
    }
}

import Foundation

// MARK: - PremiumSlots live API client, v2
// Talks to the Flask JSON blueprint in backend/api_v1.py once it is
// deployed on premiumslots.tech. The live site has no public JSON API
// today, so every call here targets /api/v1/... on that blueprint.
// Auth is the same Flask session cookie the website uses, carried by
// URLSession's shared cookie storage, so login in the app is a login
// on the real site. Admin uses the separate admin session flag on the
// server; the app never stores the admin password and never knows the
// web admin URL prefix.

enum APIError: LocalizedError {
    case notReachable
    case http(Int, String)
    case decoding
    case message(String)

    var errorDescription: String? {
        switch self {
        case .notReachable:
            return "The live PremiumSlots service could not be reached."
        case .http(let code, let message):
            return message.isEmpty ? "Request failed (\(code))." : message
        case .decoding:
            return "The live service returned data this app could not read."
        case .message(let text):
            return text
        }
    }
}

struct APIResponse: Decodable {
    let ok: Bool
    let error: String?
}

struct ServicesResponse: Decodable {
    let ok: Bool
    let services: [APIService]
    let platforms: Int?
    let slots_in_rotation: Int?
}

struct APIService: Decodable, Identifiable {
    let id: Int
    let name: String
    let price: Int
    let description: String
    let icon_name: String
    let inventory_count: Int
    let monthly_cost: Int
    let waitlist_count: Int?

    var platform: Platform {
        Platform(
            id: "live-\(id)",
            name: name,
            tagline: description,
            priceKES: price,
            slotsLeft: inventory_count,
            duration: monthly_cost > 0 ? "1 month" : "1 month",
            systemImage: Platform.systemImage(for: icon_name, name: name),
            accent: "blue",
            liveId: id
        )
    }
}

struct AuthResponse: Decodable {
    let ok: Bool
    let error: String?
    let user_id: Int?
    let name: String?
    let email: String?
}

struct MeResponse: Decodable {
    let ok: Bool
    let user: APIUser?
}

struct APIUser: Decodable {
    let id: Int
    let name: String
    let email: String
    let whatsapp_number: String
    let is_verified: Bool?
    let wallet_balance: Int?
    let loyalty_points: Int?
    let referral_count: Int?
    let loyalty_tier: String?
}

struct SubscriptionsResponse: Decodable {
    let ok: Bool
    let subscriptions: [APISubscription]
}

struct APISubscription: Decodable, Identifiable {
    let id: Int
    let service_requested: String
    let amount_due: Int
    let mpesa_code: String?
    let delivery_type: String?
    let status: String
    let expiry_date: String?
    let viewed: Bool?
    let issue_reported: Bool?
    let account_group: String?

    var orderStatus: OrderStatus {
        switch status {
        case "Approved": return .active
        case "Initiated": return .pendingVerification
        case "Cancelled": return .issue
        default: return .pendingVerification
        }
    }
}

struct VaultResponse: Decodable {
    let ok: Bool
    let error: String?
    let revealed: Bool?
    let vault_email: String?
    let vault_password: String?
    let access_details: String?
    let account_group: String?
    let message: String?
}

struct RequestResponse: Decodable {
    let ok: Bool
    let error: String?
    let subscription_id: Int?
    let status: String?
    let amount_due: Int?
    let service_requested: String?
}

struct WalletResponse: Decodable {
    let ok: Bool
    let wallet_balance: Int?
    let transactions: [WalletTransaction]?
}

struct WalletTransaction: Decodable, Identifiable {
    var id: Int { transactionId }
    let transactionId: Int
    let action_type: String?
    let amount: Int?
    let mpesa_code: String?

    enum CodingKeys: String, CodingKey {
        case transactionId = "id"
        case action_type, amount, mpesa_code
    }
}

struct ReferralsResponse: Decodable {
    let ok: Bool
    let referrals: [[String: AnyCodable]]?
    let leaderboard: [[String: AnyCodable]]?
}

/// Minimal AnyCodable for the referrals payload, which the app only
/// displays as counts and names.
struct AnyCodable: Decodable {
    let value: String
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(String.self) {
            value = text
        } else if let number = try? container.decode(Int.self) {
            value = String(number)
        } else if let flag = try? container.decode(Bool.self) {
            value = flag ? "true" : "false"
        } else {
            value = ""
        }
    }
}

struct AdminStatsResponse: Decodable {
    let ok: Bool
    let pending: Int?
    let approved: Int?
    let issues: Int?
    let users: Int?
    let total_revenue: Int?
    let slots_in_rotation: Int?
}

struct AdminCustomersResponse: Decodable {
    let ok: Bool
    let customers: [APICustomer]
}

struct APICustomer: Decodable, Identifiable {
    let id: Int
    let name: String
    let email: String
    let whatsapp_number: String?
    let is_verified: Bool?
    let is_banned: Bool?
    let wallet_balance: Int?
    let loyalty_points: Int?
    let referral_count: Int?
    let created_at: String?
}

@MainActor
final class APIClient: ObservableObject {
    static let shared = APIClient()

    /// Base URL of the live site. Change only if the site moves.
    var baseURL = URL(string: "https://premiumslots.tech")!

    private var session: URLSession {
        let config = URLSessionConfiguration.default
        config.httpCookieStorage = HTTPCookieStorage.shared
        config.httpShouldSetCookies = true
        return URLSession(configuration: config)
    }

    // MARK: - low level

    private func request<T: Decodable>(
        _ path: String,
        method: String = "GET",
        body: [String: Any]? = nil
    ) async throws -> T {
        let url = baseURL.appendingPathComponent(path)
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = method
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch {
            throw APIError.notReachable
        }
        guard let http = response as? HTTPURLResponse else {
            throw APIError.notReachable
        }
        guard (200...299).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(APIResponse.self, from: data))?.error
            throw APIError.http(http.statusCode, message ?? "")
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw APIError.decoding
        }
    }

    private func postOK(_ path: String, body: [String: Any]? = nil) async throws -> APIResponse {
        try await request(path, method: "POST", body: body)
    }

    // MARK: - public

    func health() async throws {
        let _: APIResponse = try await request("api/v1/health")
    }

    func services() async throws -> ServicesResponse {
        try await request("api/v1/services")
    }

    func service(id: Int) async throws -> APIService {
        struct Wrapper: Decodable { let ok: Bool; let service: APIService }
        let wrapper: Wrapper = try await request("api/v1/services/\(id)")
        return wrapper.service
    }

    // MARK: - auth

    func login(email: String, password: String) async throws -> AuthResponse {
        try await request("api/v1/auth/login", method: "POST",
                          body: ["email": email, "password": password])
    }

    func register(name: String, email: String, password: String,
                  whatsappNumber: String, referralCode: String? = nil) async throws -> AuthResponse {
        var body: [String: Any] = ["name": name, "email": email,
                                    "password": password,
                                    "whatsapp_number": whatsappNumber]
        if let referralCode, !referralCode.isEmpty {
            body["referral_code"] = referralCode
        }
        return try await request("api/v1/auth/register", method: "POST", body: body)
    }

    func logout() async throws {
        let _: APIResponse = try await postOK("api/v1/auth/logout")
    }

    func me() async throws -> APIUser {
        let response: MeResponse = try await request("api/v1/auth/me")
        guard let user = response.user else { throw APIError.decoding }
        return user
    }

    // MARK: - my subscriptions, wallet, referrals

    func mySubscriptions() async throws -> [APISubscription] {
        let response: SubscriptionsResponse = try await request("api/v1/me/subscriptions")
        return response.subscriptions
    }

    func vault(subscriptionId: Int) async throws -> VaultResponse {
        try await request("api/v1/me/subscriptions/\(subscriptionId)/vault")
    }

    func submitRequest(serviceName: String, mpesaCode: String,
                       couponCode: String? = nil) async throws -> RequestResponse {
        var body: [String: Any] = ["service_requested": serviceName,
                                    "mpesa_code": mpesaCode]
        if let couponCode, !couponCode.isEmpty { body["coupon_code"] = couponCode }
        return try await request("api/v1/request", method: "POST", body: body)
    }

    func joinWaitlist(serviceName: String) async throws {
        let _: APIResponse = try await postOK("api/v1/waitlist/join",
                                              body: ["service_requested": serviceName])
    }

    func reportIssue(subscriptionId: Int) async throws {
        let _: APIResponse = try await postOK("api/v1/subscription/\(subscriptionId)/report-issue")
    }

    func toggleAutoRenew(subscriptionId: Int) async throws -> Bool {
        struct Wrapper: Decodable { let ok: Bool; let auto_renew: Bool? }
        let wrapper: Wrapper = try await request(
            "api/v1/subscription/\(subscriptionId)/toggle-auto-renew", method: "POST")
        return wrapper.auto_renew ?? false
    }

    func wallet() async throws -> WalletResponse {
        try await request("api/v1/wallet")
    }

    func walletDeposit(amount: Int, mpesaCode: String) async throws -> APIResponse {
        try await postOK("api/v1/wallet/deposit",
                         body: ["amount": amount, "mpesa_code": mpesaCode])
    }

    func referrals() async throws -> ReferralsResponse {
        try await request("api/v1/referrals")
    }

    // MARK: - admin

    func adminLogin(password: String) async throws {
        let _: APIResponse = try await postOK("api/v1/admin/login",
                                              body: ["password": password])
    }

    func adminLogout() async throws {
        let _: APIResponse = try await postOK("api/v1/admin/logout")
    }

    func adminStats() async throws -> AdminStatsResponse {
        try await request("api/v1/admin/stats")
    }

    func adminSubscriptions(status: String? = nil) async throws -> [APISubscription] {
        let path = status.map { "api/v1/admin/subscriptions?status=\($0)" }
            ?? "api/v1/admin/subscriptions"
        let response: SubscriptionsResponse = try await request(path)
        return response.subscriptions
    }

    func adminApprove(subscriptionId: Int, vaultEmail: String,
                      vaultPassword: String, accountGroup: String) async throws {
        let _: APIResponse = try await postOK(
            "api/v1/admin/subscriptions/\(subscriptionId)/approve",
            body: ["vault_email": vaultEmail, "vault_password": vaultPassword,
                   "account_group": accountGroup])
    }

    func adminReject(subscriptionId: Int) async throws {
        let _: APIResponse = try await postOK(
            "api/v1/admin/subscriptions/\(subscriptionId)/reject")
    }

    func adminCustomers() async throws -> [APICustomer] {
        let response: AdminCustomersResponse = try await request("api/v1/admin/customers")
        return response.customers
    }

    func adminToggleBan(customerId: Int) async throws -> Bool {
        struct Wrapper: Decodable { let ok: Bool; let is_banned: Bool? }
        let wrapper: Wrapper = try await request(
            "api/v1/admin/customers/\(customerId)/toggle-ban", method: "POST")
        return wrapper.is_banned ?? false
    }

    func adminUpdateService(id: Int, fields: [String: Any]) async throws {
        let _: APIResponse = try await request("api/v1/admin/services/\(id)",
                                              method: "PUT", body: fields)
    }

    func adminCreateService(name: String, price: Int, description: String,
                            iconName: String, inventoryCount: Int,
                            monthlyCost: Int) async throws {
        let _: APIResponse = try await postOK("api/v1/admin/services", body: [
            "name": name, "price": price, "description": description,
            "icon_name": iconName, "inventory_count": inventoryCount,
            "monthly_cost": monthlyCost
        ])
    }

    func adminDeleteService(id: Int) async throws {
        let _: APIResponse = try await request("api/v1/admin/services/\(id)",
                                              method: "DELETE")
    }
}

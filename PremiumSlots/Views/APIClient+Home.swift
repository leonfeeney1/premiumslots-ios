import Foundation

// MARK: - Home / My Slots API extras, v5
// Extra per-subscription fields read from GET /api/v1/me/subscriptions
// when the backend returns them. Both fields are optional: the
// workspace backend does not yet return days_remaining or auto_renew
// on the customer subscriptions endpoint (only the admin customer
// detail returns days_remaining), so the app must work with them
// absent and fall back to local values. Nothing here edits
// APIClient.swift; this is an extension plus a small Decodable type,
// using the existing public fetchJSON helper.

/// Server-reported extras for one subscription. Decodes only the
/// fields My Slots needs; every other key in the response is ignored.
struct PSSubscriptionExtras: Decodable {
    let id: Int
    /// Whole days from now to expiry, as computed by the server.
    /// Negative when past expiry. Nil on backends that do not send it.
    let days_remaining: Int?
    /// Current auto-renew flag. Nil on backends that do not send it.
    let auto_renew: Bool?
}

extension APIClient {
    /// Fetches the customer subscriptions once and returns the extras
    /// keyed by subscription id. Missing fields decode as nil, so an
    /// older backend yields entries with nil values, never an error.
    func mySubscriptionExtras() async throws -> [Int: PSSubscriptionExtras] {
        struct Wrapper: Decodable {
            let ok: Bool
            let subscriptions: [PSSubscriptionExtras]?
        }
        let wrapper: Wrapper = try await fetchJSON("api/v1/me/subscriptions")
        var out: [Int: PSSubscriptionExtras] = [:]
        for item in wrapper.subscriptions ?? [] {
            out[item.id] = item
        }
        return out
    }
}

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// IBKR Client Portal Gateway client — the execution rails, built inside
/// the sandbox: v1 is HARD-LOCKED to paper accounts (IDs starting "DU").
/// The code refuses live accounts; going live later is a deliberate,
/// separate unlock that requires the agent's record to have earned it.
///
/// Setup (one-time): download IBKR's "Client Portal Gateway", run it
/// (`bin/run.sh root/conf.yaml`), log in at https://localhost:5000 with the
/// PAPER account, leave it running. Pulse talks to it locally over TLS.
public enum IBKRService {
    public struct GatewayStatus {
        public let authenticated: Bool
        public let accountId: String?
        public var isPaper: Bool { accountId?.hasPrefix("DU") ?? false }
    }

    public struct PlacedOrder {
        public let orderId: String?
        public let messages: [String]
    }

    public struct IBKRError: LocalizedError {
        public let message: String
        public var errorDescription: String? { message }
        public init(message: String) { self.message = message }
    }

    /// Guardrails, pure and testable: paper account only, sane share count,
    /// notional ceiling. Real-money mistakes are prevented at the type of
    /// account, not by a checkbox.
    public static func validatePaperOrder(accountId: String, quantity: Int,
                                          notional: Double,
                                          maxNotional: Double = 1_000) throws {
        guard accountId.hasPrefix("DU") else {
            throw IBKRError(message: "refusing: \(accountId) is not a PAPER account (paper IDs start with DU). Live execution is not built — deliberately.")
        }
        guard quantity >= 1 else {
            throw IBKRError(message: "IBKR stock orders need at least 1 whole share")
        }
        guard notional <= maxNotional else {
            throw IBKRError(message: "order ≈ \(usd(notional)) exceeds the \(usd(maxNotional)) per-order ceiling")
        }
    }

    // The gateway serves self-signed TLS on localhost. Trust is granted for
    // localhost ONLY — never any other host.
    #if canImport(Security)
    private final class LocalhostTrustDelegate: NSObject, URLSessionDelegate {
        func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
            let host = challenge.protectionSpace.host
            if (host == "localhost" || host == "127.0.0.1"),
               let trust = challenge.protectionSpace.serverTrust {
                completionHandler(.useCredential, URLCredential(trust: trust))
            } else {
                completionHandler(.performDefaultHandling, nil)
            }
        }
    }
    private static let session = URLSession(configuration: .default,
                                            delegate: LocalhostTrustDelegate(),
                                            delegateQueue: nil)
    #else
    private static let session = URLSession.shared
    #endif

    static func request(_ gateway: String, _ path: String, method: String = "GET",
                        body: [String: Any]? = nil) async throws -> Data {
        guard let url = URL(string: "\(gateway)/v1/api\(path)") else {
            throw IBKRError(message: "bad gateway URL")
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 12
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }
        guard let (data, resp) = try? await session.data(for: req) else {
            throw IBKRError(message: "gateway not reachable at \(gateway) — start IBKR's Client Portal Gateway and log in with the PAPER account")
        }
        guard let code = (resp as? HTTPURLResponse)?.statusCode, (200..<300).contains(code) else {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw IBKRError(message: "gateway error: \(text.prefix(200))")
        }
        return data
    }

    public static func status(gateway: String) async -> GatewayStatus {
        var authenticated = false
        if let data = try? await request(gateway, "/iserver/auth/status", method: "POST"),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            authenticated = (json["authenticated"] as? Bool) ?? false
        }
        var accountId: String? = nil
        if authenticated,
           let data = try? await request(gateway, "/portfolio/accounts"),
           let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            accountId = list.first?["id"] as? String ?? list.first?["accountId"] as? String
        }
        return GatewayStatus(authenticated: authenticated, accountId: accountId)
    }

    /// IBKR orders address contracts by conid, not symbol.
    public static func findConid(symbol: String, gateway: String) async throws -> Int {
        let data = try await request(gateway, "/iserver/secdef/search?symbol=\(symbol)")
        guard let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw IBKRError(message: "no contract found for \(symbol)")
        }
        for item in list {
            if let conidStr = item["conid"] as? String, let conid = Int(conidStr) { return conid }
            if let conid = item["conid"] as? Int { return conid }
        }
        throw IBKRError(message: "no contract found for \(symbol)")
    }

    /// Place a LIMIT order in the PAPER account (validated above). Handles
    /// the gateway's confirm-reply loop (precautionary messages must be
    /// acknowledged before the order books).
    public static func placePaperOrder(gateway: String, accountId: String,
                                       conid: Int, side: String, quantity: Int,
                                       limitPrice: Double, notional: Double) async throws -> PlacedOrder {
        try validatePaperOrder(accountId: accountId, quantity: quantity, notional: notional)
        let order: [String: Any] = [
            "conid": conid,
            "orderType": "LMT",
            "price": limitPrice,
            "side": side,
            "quantity": quantity,
            "tif": "DAY",
        ]
        var data = try await request(gateway, "/iserver/account/\(accountId)/orders",
                                     method: "POST", body: ["orders": [order]])
        var messages: [String] = []
        // Reply loop: up to 4 precautionary confirmations.
        for _ in 0..<4 {
            guard let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                  let first = list.first else { break }
            if let orderId = first["order_id"] as? String ?? (first["order_id"] as? Int).map(String.init) {
                return PlacedOrder(orderId: orderId, messages: messages)
            }
            if let replyId = first["id"] as? String {
                messages += (first["message"] as? [String]) ?? []
                data = try await request(gateway, "/iserver/reply/\(replyId)",
                                         method: "POST", body: ["confirmed": true])
            } else {
                break
            }
        }
        return PlacedOrder(orderId: nil, messages: messages.isEmpty ? ["order submitted — check the gateway for status"] : messages)
    }
}

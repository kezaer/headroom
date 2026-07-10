import Foundation
import Security

/// Codex credential access (U3). Claude no longer flows through here — it reads the
/// official `/usage` panel via the CLI (see `ClaudeProvider`), so the only remaining
/// credential is Codex's `~/.codex/auth.json` token. An `actor` for data-race-free
/// access under Swift 6 strict concurrency (KTD10).
public actor CredentialStore {
    private let codexReader: CodexAuthReading
    private let apiKeyStore: APIKeyStoring

    public init(
        codexReader: CodexAuthReading = CodexAuthFileReader(),
        apiKeyStore: APIKeyStoring = KeychainAPIKeyStore()
    ) {
        self.codexReader = codexReader
        self.apiKeyStore = apiKeyStore
    }

    public func codexAccessToken() async -> Result<String, FailureReason> {
        do {
            return .success(try codexReader.readCodexCredential().accessToken)
        } catch CredentialError.notLoggedIn {
            return .failure(.notLoggedIn("Codex isn't logged in — run `\(CodexCLI.loginCommand)`"))
        } catch {
            return .failure(.notLoggedIn("Codex credential unreadable"))
        }
    }

    public func apiKey(for provider: APIKeyProvider) async -> Result<String, FailureReason> {
        do {
            let key = try apiKeyStore.readAPIKey(for: provider)
            guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return .failure(.notLoggedIn("\(provider.displayName) API key is empty"))
            }
            return .success(key)
        } catch CredentialError.notLoggedIn {
            return .failure(.notLoggedIn("Add a \(provider.displayName) admin API key in Settings"))
        } catch {
            return .failure(.notLoggedIn("\(provider.displayName) API key unreadable"))
        }
    }

    public func saveAPIKey(_ key: String, for provider: APIKeyProvider) async -> Result<Void, FailureReason> {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .failure(.notLoggedIn("\(provider.displayName) API key is empty"))
        }
        do {
            try apiKeyStore.saveAPIKey(trimmed, for: provider)
            return .success(())
        } catch {
            return .failure(.transient("Couldn't save \(provider.displayName) API key"))
        }
    }

    public func deleteAPIKey(for provider: APIKeyProvider) async -> Result<Void, FailureReason> {
        do {
            try apiKeyStore.deleteAPIKey(for: provider)
            return .success(())
        } catch {
            return .failure(.transient("Couldn't delete \(provider.displayName) API key"))
        }
    }
}

public struct KeychainAPIKeyStore: APIKeyStoring {
    public init() {}

    public func readAPIKey(for provider: APIKeyProvider) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: provider.keychainService,
            kSecAttrAccount as String: provider.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status != errSecItemNotFound else { throw CredentialError.notLoggedIn }
        guard status == errSecSuccess else { throw CredentialError.keychainStatus(status) }
        guard let data = item as? Data, let key = String(data: data, encoding: .utf8) else {
            throw CredentialError.malformed
        }
        return key
    }

    public func saveAPIKey(_ key: String, for provider: APIKeyProvider) throws {
        let data = Data(key.utf8)
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: provider.keychainService,
            kSecAttrAccount as String: provider.rawValue,
        ]
        let update: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(base as CFDictionary, update as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw CredentialError.keychainStatus(status) }

        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let addStatus = SecItemAdd(add as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw CredentialError.keychainStatus(addStatus) }
    }

    public func deleteAPIKey(for provider: APIKeyProvider) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: provider.keychainService,
            kSecAttrAccount as String: provider.rawValue,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CredentialError.keychainStatus(status)
        }
    }
}

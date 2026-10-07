import Foundation
import NetworkExtension
import Security

struct SavedCamera: Identifiable, Codable {
    var id: String { identity.key }
    let identity: CameraIdentity
    let peripheralID: UUID?
    let ssid: String
}

enum CredentialStore {
    private static func query(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "studio.grtransfer.camera-wifi", kSecAttrAccount as String: key]
    }
    static func save(_ password: String, for key: String) throws {
        var item = query(key)
        let data = Data(password.utf8)
        let update = SecItemUpdate(item as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecSuccess { return }
        guard update == errSecItemNotFound else { throw keychainError(update) }
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else { throw keychainError(status) }
    }
    static func load(_ key: String) -> String? {
        var item = query(key); item[kSecReturnData as String] = true
        var output: CFTypeRef?
        guard SecItemCopyMatching(item as CFDictionary, &output) == errSecSuccess, let data = output as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    static func remove(_ key: String) { SecItemDelete(query(key) as CFDictionary) }
    private static func keychainError(_ code: OSStatus) -> Error {
        NSError(domain: NSOSStatusErrorDomain, code: Int(code), userInfo: [NSLocalizedDescriptionKey: "无法安全保存相机密码（\(code)）。"])
    }
}

enum CameraWiFi {
    static func join(ssid: String, password: String) async throws {
        guard !ssid.isEmpty, (8...63).contains(password.utf8.count) else {
            throw BluetoothError.message("请填写相机显示的 Wi‑Fi 名称与 8–63 位密码。")
        }
        let configuration = NEHotspotConfiguration(ssid: ssid, passphrase: password, isWEP: false)
        configuration.joinOnce = false
        do { try await NEHotspotConfigurationManager.shared.apply(configuration) }
        catch let error as NSError {
            if error.domain == NEHotspotConfigurationErrorDomain,
               error.code == NEHotspotConfigurationError.alreadyAssociated.rawValue { return }
            throw error
        }
    }
    static func forget(ssid: String) {
        if !ssid.isEmpty { NEHotspotConfigurationManager.shared.removeConfiguration(forSSID: ssid) }
    }
}

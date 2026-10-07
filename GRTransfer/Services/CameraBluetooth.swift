import CoreBluetooth
import Combine
import Foundation

struct NearbyCamera: Identifiable {
    let id: UUID
    let name: String
    let signal: Int
}
struct CameraCredentials {
    let peripheralID: UUID
    let name: String
    let ssid: String
    let password: String
}

/// CoreBluetooth owns pairing/bonding UI. Never uses private ATT handles or sets a PIN.
@MainActor
final class CameraBluetooth: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    @Published private(set) var nearby: [NearbyCamera] = []
    @Published private(set) var status = "蓝牙尚未启动"
    @Published private(set) var busy = false
    @Published private(set) var scanning = false
    private var central: CBCentralManager!
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var active: CBPeripheral?
    private var chars: [CBUUID: CBCharacteristic] = [:]
    private var continuation: CheckedContinuation<CameraCredentials, Error>?
    private var timeout: Task<Void, Never>?
    private var ssid: String?
    private var password: String?
    private var pendingServices = 0
    private let wlan = CBUUID(string: "F37F568F-9071-445D-A938-5441F2E82399")
    private let camera = CBUUID(string: "4B445988-CAA0-4DD3-941D-37B4F52ACA86")
    private let ssidID = CBUUID(string: "90638E5A-E77D-409D-B550-78F7E1CA5AB4")
    private let passwordID = CBUUID(string: "0F38279C-FE9E-461B-8596-81287E8C9A81")
    private let networkID = CBUUID(string: "9111CDD0-9F01-45C4-A2D4-E09E8FB0424D")
    private let modeID = CBUUID(string: "1452335A-EC7F-4877-B8AB-0F72E18BB295")

    func scan() {
        if central == nil { central = CBCentralManager(delegate: self, queue: .main); return }
        guard central.state == .poweredOn, !busy else { return }
        nearby = []
        scanning = true
        status = "寻找附近的 GR 相机…"
        // Some GR firmware only advertises its name in a scan response.
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        timeout?.cancel()
        timeout = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            guard !Task.isCancelled else { return }
            self?.stopScan()
        }
    }
    func stopScan() {
        central?.stopScan(); scanning = false
        if !busy { status = nearby.isEmpty ? "未发现相机，请在相机中开启蓝牙配对" : "请选择一台相机" }
    }
    func connect(_ id: UUID) async throws -> CameraCredentials {
        guard !busy, let peripheral = peripherals[id] ?? central?.retrievePeripherals(withIdentifiers: [id]).first else {
            throw BluetoothError.message("请先扫描并选择相机。")
        }
        stopScan(); timeout?.cancel()
        if let active, active.identifier != id { central.cancelPeripheralConnection(active) }
        active = peripheral; peripheral.delegate = self; chars = [:]; ssid = nil; password = nil
        busy = true; status = "连接中，请确认系统及相机上的配对提示…"
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                timeout = Task { [weak self] in
                    try? await Task.sleep(nanoseconds: 60_000_000_000)
                    guard !Task.isCancelled else { return }
                    self?.fail("连接超时。请关闭 GR WORLD / Image Sync，并在相机上重新进入配对。")
                }
                if peripheral.state == .connected { peripheral.discoverServices([wlan, camera]) }
                else { central.connect(peripheral, options: nil) }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.fail("连接已取消。") }
        }
    }
    func disconnect() {
        timeout?.cancel(); stopScan()
        if continuation != nil { finish(.failure(CancellationError())) }
        if let active { central?.cancelPeripheralConnection(active) }
        active = nil; status = "蓝牙已断开"
    }
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn: scan()
        case .unauthorized: fail("请在系统设置中允许蓝牙访问。")
        case .poweredOff: fail("请开启手机蓝牙。")
        case .unsupported: fail("此设备不支持蓝牙，请使用手动 Wi‑Fi 连接。")
        default: status = "正在准备蓝牙…"
        }
    }
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name ?? ""
        guard name.uppercased().contains("GR"), name.uppercased().contains("RICOH") else { return }
        peripherals[peripheral.identifier] = peripheral
        guard !nearby.contains(where: { $0.id == peripheral.identifier }) else { return }
        nearby.append(NearbyCamera(id: peripheral.identifier, name: name, signal: RSSI.intValue))
    }
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard peripheral == active, continuation != nil else { return }
        status = "读取相机连接信息…"
        peripheral.discoverServices([wlan, camera])
    }
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        guard peripheral == active else { return }; fail(error?.localizedDescription ?? "无法连接相机。")
    }
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard peripheral == active else { return }
        if continuation != nil { fail("蓝牙连接已断开，请重新配对。") }
        else { status = "蓝牙已断开" }
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard peripheral == active, continuation != nil else { return }
        if let error { fail(error.localizedDescription); return }
        let services = peripheral.services ?? []
        guard services.contains(where: { $0.uuid == wlan }), services.contains(where: { $0.uuid == camera }) else {
            fail("相机未提供兼容的蓝牙服务，请使用手动 Wi‑Fi 连接。"); return
        }
        pendingServices = services.count
        for service in services { peripheral.discoverCharacteristics(nil, for: service) }
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard peripheral == active, continuation != nil else { return }
        if let error { fail(error.localizedDescription); return }
        for item in service.characteristics ?? [] {
            if (service.uuid == wlan && [ssidID, passwordID, networkID].contains(item.uuid)) ||
                (service.uuid == camera && item.uuid == modeID) { chars[item.uuid] = item }
        }
        pendingServices -= 1
        guard pendingServices == 0 else { return }
        guard let ssidChar = chars[ssidID], ssidChar.properties.contains(.read),
              chars[passwordID]?.properties.contains(.read) == true else {
            fail("相机不支持通过蓝牙读取 Wi‑Fi 凭据，请手动连接。"); return
        }
        // Reading protected credentials asks iOS to negotiate security and show pairing UI.
        peripheral.readValue(for: ssidChar)
    }
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard peripheral == active, continuation != nil else { return }
        if let error { fail("蓝牙读取失败：\(error.localizedDescription)。可在相机开启 Wi‑Fi 后手动连接。"); return }
        guard let data = characteristic.value else { fail("相机未返回连接信息。"); return }
        if characteristic.uuid == ssidID {
            ssid = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .controlCharacters)
            peripheral.readValue(for: chars[passwordID]!)
        } else if characteristic.uuid == passwordID {
            password = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .controlCharacters)
            if let mode = chars[modeID], mode.properties.contains(.read) { peripheral.readValue(for: mode) }
            else { finishCredentials() }
        } else if characteristic.uuid == modeID {
            // Only request AP mode while camera is awake in capture mode. Credentials still
            // work with manually enabled Wi-Fi when firmware refuses this documented write.
            if data.first == 0, let network = chars[networkID], network.properties.contains(.write) {
                status = "正在开启相机 Wi‑Fi…"
                peripheral.writeValue(Data([1]), for: network, type: .withResponse)
            } else { finishCredentials() }
        }
    }
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard peripheral == active, continuation != nil, characteristic.uuid == networkID else { return }
        if error != nil { status = "请在相机上手动开启 Wi‑Fi" }
        finishCredentials()
    }
    private func finishCredentials() {
        guard let active, let ssid, !ssid.isEmpty, let password, password.utf8.count >= 8 else {
            fail("未能读取完整 Wi‑Fi 凭据，请使用手动连接。"); return
        }
        finish(.success(CameraCredentials(peripheralID: active.identifier, name: active.name ?? "RICOH GR", ssid: ssid, password: password)))
    }
    private func fail(_ message: String) {
        status = message
        finish(.failure(BluetoothError.message(message)))
        if let active { central?.cancelPeripheralConnection(active) }
    }
    private func finish(_ result: Result<CameraCredentials, Error>) {
        timeout?.cancel(); timeout = nil; busy = false
        let pending = continuation; continuation = nil; pending?.resume(with: result)
    }
}
enum BluetoothError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let message) = self { return message }; return nil }
}

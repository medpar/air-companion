import Foundation
import CoreBluetooth

// Discovery only. Deliberately does not implement a peripheral delegate,
// connection, characteristic access, notifications, or any outbound command.
final class Discovery: NSObject, CBCentralManagerDelegate {
    private var central: CBCentralManager!
    private var deadline: Timer?
    private var observations: [UUID: [String: Any]] = [:]
    private var started = false
    private let output: URL

    init(output: URL) {
        self.output = output
        super.init()
        central = CBCentralManager(delegate: self, queue: .main,
            options: [CBCentralManagerOptionShowPowerAlertKey: false])
        deadline = Timer.scheduledTimer(withTimeInterval: 30, repeats: false) { [weak self] _ in
            self?.finish(reason: "authorization_or_radio_timeout")
        }
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            guard !started else { return }
            started = true
            deadline?.invalidate()
            central.scanForPeripherals(withServices: nil,
                options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
            print("Discovery started: 15 seconds, no connections.")
            deadline = Timer.scheduledTimer(withTimeInterval: 15, repeats: false) { [weak self] _ in
                self?.finish(reason: "completed")
            }
        case .unauthorized: finish(reason: "bluetooth_permission_required")
        case .unsupported: finish(reason: "bluetooth_unsupported")
        case .poweredOff: finish(reason: "bluetooth_powered_off")
        default: break
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let services = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? [])
            .map(\.uuidString)
        let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name ?? ""
        let candidate = name.lowercased().contains("fitbit") || services.contains("FD62") ||
            services.contains("ABBAFF00-E56A-484C-B832-8B17CF6CBFE8")
        // Keep only plausible Fitbit candidates. An advertisement cannot establish ownership/model.
        guard candidate else { return }
        observations[peripheral.identifier] = [
            "localIdentifier": peripheral.identifier.uuidString,
            "advertisedName": name,
            "services": services,
            "rssi": RSSI.intValue,
            "connectable": advertisementData[CBAdvertisementDataIsConnectable] as? Bool ?? false,
            "observedAt": ISO8601DateFormatter().string(from: Date()),
            "classification": "candidate_only_not_verified_air"
        ]
    }

    private func finish(reason: String) {
        deadline?.invalidate()
        central.stopScan()
        let result: [String: Any] = [
            "schemaVersion": 1, "mode": "discovery_only", "result": reason,
            "connectionsAttempted": 0, "writesAttempted": 0,
            "candidates": observations.values.sorted {
                ($0["localIdentifier"] as? String ?? "") < ($1["localIdentifier"] as? String ?? "")
            },
            "limitation": "No advertisement does not establish absence; an already connected band may not advertise."
        ]
        do {
            let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: output, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: output.path)
            print("Result: \(reason); candidate count: \(observations.count). Private report saved.")
            exit(reason == "completed" ? 0 : 2)
        } catch {
            fputs("Cannot save discovery report: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
}

guard CommandLine.arguments.count == 2 else {
    fputs("Usage: air-discovery /absolute/private/output.json\n", stderr)
    exit(64)
}
let output = URL(fileURLWithPath: CommandLine.arguments[1])
let discovery = Discovery(output: output)
RunLoop.main.run()

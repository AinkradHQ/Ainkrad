import Foundation
import Network
import IOKit.ps
import Observation

/// System-side effects backing the full-screen status bar (AIN-109): the
/// clock, network reachability (`NWPathMonitor`), and battery
/// (`IOPSCopyPowerSourcesInfo`). Only runs while the status bar is actually
/// visible — `start()`/`stop()` are called from `HUDBar` as full-screen +
/// the Settings toggle change — so it costs nothing the rest of the time.
@MainActor
@Observable
final class SystemStatusMonitor {
    private(set) var now = Date()
    private(set) var network: NetworkStatus = .offline
    /// `nil` when the machine has no battery (e.g. a desktop Mac).
    private(set) var battery: BatteryInfo?

    private var clockTimer: Timer?
    private var pathMonitor: NWPathMonitor?
    private let pathQueue = DispatchQueue(label: "com.ainkrad.app.status.network")
    private var isRunning = false

    func start() {
        guard !isRunning else { return }
        isRunning = true

        now = Date()
        battery = Self.readBattery()

        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.now = Date()
                self?.battery = Self.readBattery()
            }
        }
        // Tolerance: the status bar shows slightly stale time/battery (off by up to 15s)
        // is harmless — users read the status bar, not glance for the exact second.
        // Letting macOS coalesce this with other timers is a clear win.
        timer.tolerance = 15
        RunLoop.main.add(timer, forMode: .common)
        clockTimer = timer

        // NWPathMonitor cannot be restarted after `cancel()` — it becomes a
        // permanent no-op — so a fresh instance is created on every start().
        pathMonitor?.cancel()
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let status = NetworkStatus.resolve(from: path)
            Task { @MainActor in
                self?.network = status
            }
        }
        monitor.start(queue: pathQueue)
        pathMonitor = monitor
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false

        clockTimer?.invalidate()
        clockTimer = nil
        pathMonitor?.cancel()
        pathMonitor = nil
    }

    /// Reads the first internal battery's charge/state from IOKit's power
    /// source APIs. Returns `nil` when there is none (desktop Macs) or the
    /// description is missing the fields needed to compute a percent.
    private static func readBattery() -> BatteryInfo? {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sourcesRef = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() else {
            return nil
        }
        let sources = sourcesRef as [CFTypeRef]

        for source in sources {
            guard let descriptionRef = IOPSGetPowerSourceDescription(snapshot, source),
                  let description = descriptionRef.takeUnretainedValue() as? [String: AnyObject] else {
                continue
            }
            guard description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
            guard let currentCapacity = description[kIOPSCurrentCapacityKey] as? Int,
                  let maxCapacity = description[kIOPSMaxCapacityKey] as? Int,
                  maxCapacity > 0 else { continue }

            let percent = Int((Double(currentCapacity) / Double(maxCapacity) * 100).rounded())
            let isCharging = description[kIOPSIsChargingKey] as? Bool ?? false
            return BatteryInfo(percent: percent, isCharging: isCharging)
        }
        return nil
    }
}

private extension NetworkStatus {
    static func resolve(from path: NWPath) -> NetworkStatus {
        guard path.status == .satisfied else { return .offline }
        if path.usesInterfaceType(.wifi) { return .wifi }
        if path.usesInterfaceType(.wiredEthernet) { return .ethernet }
        return .other
    }
}

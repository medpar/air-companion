import Foundation
import CallKit

/// USB acceptance only: reports a short incoming test call through CallKit so
/// the real call path (CXCallObserver → alert → band) can be checked with the
/// phone in the background or locked, without anyone dialling. The call can't
/// be answered and ends itself.
final class TestCall: NSObject, CXProviderDelegate {
    static let shared = TestCall()
    private let provider: CXProvider = {
        let configuration = CXProviderConfiguration()
        configuration.supportsVideo = false
        configuration.maximumCallsPerCallGroup = 1
        configuration.supportedHandleTypes = [.generic]
        return CXProvider(configuration: configuration)
    }()
    private var log: [[String: String]] = []

    func ring(after delay: TimeInterval, for duration: TimeInterval) {
        provider.setDelegate(self, queue: .main)
        record("scheduled", "\(Int(delay))s")
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [self] in
            let id = UUID(), update = CXCallUpdate()
            update.remoteHandle = CXHandle(type: .generic, value: "Pebble test call")
            update.localizedCallerName = "Pebble test call"
            update.hasVideo = false
            record("reporting", UIApplicationStateName.current)
            provider.reportNewIncomingCall(with: id, update: update) { [self] error in
                record(error == nil ? "ringing" : "report_failed", error.map { "\($0)" } ?? "")
                guard error == nil else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [self] in
                    provider.reportCall(with: id, endedAt: Date(), reason: .remoteEnded)
                    record("ended", "")
                }
            }
        }
    }

    func providerDidReset(_ provider: CXProvider) { record("reset", "") }
    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) { action.fail(); record("answer_refused", "") }
    func provider(_ provider: CXProvider, perform action: CXEndCallAction) { action.fulfill(); record("declined", "") }

    private func record(_ event: String, _ value: String) {
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        log.append(["event": event, "value": value, "time": formatter.string(from: Date())])
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("call-check.json")
        if let data = try? JSONSerialization.data(withJSONObject: log, options: .prettyPrinted) {
            try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }
}

import UIKit
enum UIApplicationStateName {
    static var current: String {
        switch UIApplication.shared.applicationState {
        case .active: return "active"
        case .inactive: return "inactive"
        default: return "background"
        }
    }
}

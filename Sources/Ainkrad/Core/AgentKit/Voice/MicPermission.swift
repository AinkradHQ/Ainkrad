import AVFoundation
import Foundation

enum MicAuthorization: Equatable { case authorized, denied, notDetermined }

protocol MicPermissionProviding: Sendable {
    var status: MicAuthorization { get }
    func request() async -> Bool
}

struct SystemMicPermission: MicPermissionProviding {
    var status: MicAuthorization {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return .authorized
        case .denied, .restricted: return .denied
        case .notDetermined: return .notDetermined
        @unknown default: return .denied
        }
    }
    func request() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }
}

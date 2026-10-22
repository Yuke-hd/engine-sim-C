import Foundation

/// Events that can temporarily make a requested sound unavailable.
public enum EngineSoundSessionEvent {
    case interruptionBegan
    case interruptionEnded(shouldResume: Bool)
    case outputRouteChanged(isAvailable: Bool)
    case thermalStateChanged(EngineSoundThermalState)
}

public enum EngineSoundThermalState: Equatable {
    case nominal
    case fair
    case serious
    case critical

    /// A neutral recommendation for hosts that can adjust simulation frequency.
    public var simulationFrequencyScale: Double {
        switch self {
        case .nominal, .fair: return 1
        case .serious: return 0.5
        case .critical: return 0
        }
    }
}

/// Sources with adjustable simulation work can opt into the thermal recommendation.
/// Calls are serialized with rendering on the player's producer thread.
public protocol EngineSoundThermalControllable: AnyObject {
    func setSimulationFrequencyScale(_ scale: Double)
}

/// Injectable boundary for process audio-session ownership and device events.
public protocol EngineSoundSession: AnyObject {
    var isOutputAvailable: Bool { get }
    var thermalState: EngineSoundThermalState { get }
    var onEvent: ((EngineSoundSessionEvent) -> Void)? { get set }
    func acquire(policy: AudioSessionMixPolicy) throws
    func release(policy: AudioSessionMixPolicy)
}

#if os(iOS)
import AVFoundation

/// iOS notification adapter. Hosts still decide when playback is requested.
public final class IOSAudioSession: EngineSoundSession {
    private let eventLock = NSLock()
    private var eventHandler: ((EngineSoundSessionEvent) -> Void)?
    public var onEvent: ((EngineSoundSessionEvent) -> Void)? {
        get {
            eventLock.lock()
            defer { eventLock.unlock() }
            return eventHandler
        }
        set {
            eventLock.lock()
            eventHandler = newValue
            eventLock.unlock()
        }
    }
    public var isOutputAvailable: Bool { !AVAudioSession.sharedInstance().currentRoute.outputs.isEmpty }
    public var thermalState: EngineSoundThermalState { Self.mapThermal(ProcessInfo.processInfo.thermalState) }
    private var observers: [NSObjectProtocol] = []

    public init() {
        let session = AVAudioSession.sharedInstance()
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification,
                                            object: session, queue: .main) { [weak self] notification in
            guard let self, let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
            if type == .began {
                self.onEvent?(.interruptionBegan)
            } else {
                let options = AVAudioSession.InterruptionOptions(rawValue:
                    notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0)
                self.onEvent?(.interruptionEnded(shouldResume: options.contains(.shouldResume)))
            }
        })
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification,
                                            object: session, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.onEvent?(.outputRouteChanged(isAvailable: self.isOutputAvailable))
        })
        observers.append(center.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification,
                                            object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.onEvent?(.thermalStateChanged(self.thermalState))
        })
    }

    deinit { observers.forEach(NotificationCenter.default.removeObserver) }

    public func acquire(policy: AudioSessionMixPolicy) throws { try AudioSessionCoordinator.acquire(policy: policy) }
    public func release(policy: AudioSessionMixPolicy) { AudioSessionCoordinator.release(policy: policy) }

    private static func mapThermal(_ state: ProcessInfo.ThermalState) -> EngineSoundThermalState {
        switch state {
        case .nominal: return .nominal
        case .fair: return .fair
        case .serious: return .serious
        case .critical: return .critical
        @unknown default: return .critical
        }
    }
}
#else
final class NoopAudioSession: EngineSoundSession {
    var isOutputAvailable = true
    var thermalState: EngineSoundThermalState = .nominal
    var onEvent: ((EngineSoundSessionEvent) -> Void)?
    func acquire(policy: AudioSessionMixPolicy) throws {}
    func release(policy: AudioSessionMixPolicy) {}
}
#endif

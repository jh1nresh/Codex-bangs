@preconcurrency import Carbon
import Foundation

@MainActor
final class GlobalHotKeyService {
    fileprivate static let signature: OSType = 0x4342_4E47 // "CBNG"
    fileprivate static let identifier: UInt32 = 1

    private let onPressed: @MainActor () -> Void
    private var hotKeyReference: EventHotKeyRef?
    private var eventHandlerReference: EventHandlerRef?

    init(onPressed: @escaping @MainActor () -> Void) {
        self.onPressed = onPressed
    }

    @discardableResult
    func start() -> Bool {
        guard hotKeyReference == nil, eventHandlerReference == nil else {
            return true
        }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let userData = Unmanaged.passUnretained(self).toOpaque()
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            globalHotKeyHandler,
            1,
            &eventType,
            userData,
            &eventHandlerReference
        )
        guard installStatus == noErr else {
            eventHandlerReference = nil
            return false
        }

        let hotKeyID = EventHotKeyID(
            signature: Self.signature,
            id: Self.identifier
        )
        let modifiers = UInt32(controlKey | optionKey)
        let registrationStatus = RegisterEventHotKey(
            UInt32(kVK_Space),
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyReference
        )
        guard registrationStatus == noErr else {
            if let eventHandlerReference {
                RemoveEventHandler(eventHandlerReference)
            }
            eventHandlerReference = nil
            hotKeyReference = nil
            return false
        }

        return true
    }

    func stop() {
        if let hotKeyReference {
            UnregisterEventHotKey(hotKeyReference)
            self.hotKeyReference = nil
        }
        if let eventHandlerReference {
            RemoveEventHandler(eventHandlerReference)
            self.eventHandlerReference = nil
        }
    }

    fileprivate func handlePress() {
        onPressed()
    }
}

@MainActor
private let globalHotKeyHandler: EventHandlerUPP = { _, event, userData in
    guard let event, let userData else {
        return OSStatus(eventNotHandledErr)
    }

    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr,
          hotKeyID.signature == GlobalHotKeyService.signature,
          hotKeyID.id == GlobalHotKeyService.identifier else {
        return OSStatus(eventNotHandledErr)
    }

    let userDataAddress = UInt(bitPattern: userData)
    MainActor.assumeIsolated {
        guard let servicePointer = UnsafeMutableRawPointer(
            bitPattern: userDataAddress
        ) else {
            return
        }
        Unmanaged<GlobalHotKeyService>
            .fromOpaque(servicePointer)
            .takeUnretainedValue()
            .handlePress()
    }
    return noErr
}

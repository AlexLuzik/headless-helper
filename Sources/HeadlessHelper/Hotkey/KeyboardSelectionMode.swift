import Foundation

/// Manages the keyboard selection mode: after the hotkey is pressed and devices are spoken,
/// this listens for a single digit press to select a device, or 4 digits for PIN entry.
final class KeyboardSelectionMode {
    enum Selection {
        case device(Int)  // 0-based index
        case cancelled
        case timeout
    }

    private var isActive = false
    private var timeoutTask: Task<Void, Never>?
    private var completion: ((Selection) -> Void)?
    private var pinCompletion: (([UInt16]?) -> Void)?
    private var pinDigits: [UInt16] = []
    private var isPINMode = false
    private var pendingFirstDigit: UInt16?
    private var multiDigitTask: Task<Void, Never>?

    /// Activate device selection mode. Listens for a single digit (1-9).
    /// Calls completion with the result.
    func activate(deviceCount: Int, completion: @escaping (Selection) -> Void) {
        guard !isActive else { return }
        isActive = true
        isPINMode = false
        self.completion = completion

        // Set up digit handler on the shared HotkeyManager
        // This is wired through AppDelegate
        NotificationCenter.default.post(
            name: .selectionModeActivated,
            object: SelectionModeConfig(
                deviceCount: deviceCount,
                onDigit: { [weak self] digit in
                    self?.handleDeviceDigit(digit, deviceCount: deviceCount)
                },
                onEscape: { [weak self] in
                    self?.cancel()
                }
            )
        )

        // Timeout: 10 sec base + 2 sec per item (for voice to finish reading)
        let timeout = 10 + deviceCount * 2
        timeoutTask = Task {
            try? await Task.sleep(for: .seconds(timeout))
            if self.isActive && !self.isPINMode {
                self.deactivate()
                DispatchQueue.main.async {
                    completion(.timeout)
                }
            }
        }
    }

    /// Activate PIN entry mode. Listens for exactly 4 digits.
    func activatePINMode(completion: @escaping ([UInt16]?) -> Void) {
        isPINMode = true
        pinDigits = []
        self.pinCompletion = completion

        NotificationCenter.default.post(
            name: .selectionModeActivated,
            object: SelectionModeConfig(
                deviceCount: 0,
                onDigit: { [weak self] digit in
                    self?.handlePINDigit(digit)
                },
                onEscape: { [weak self] in
                    self?.cancelPIN()
                }
            )
        )

        // 30-second timeout for PIN
        timeoutTask?.cancel()
        timeoutTask = Task {
            try? await Task.sleep(for: .seconds(30))
            if self.isPINMode {
                self.cancelPIN()
            }
        }
    }

    private func handleDeviceDigit(_ digit: UInt16, deviceCount: Int) {
        guard isActive, !isPINMode else { return }

        if let first = pendingFirstDigit {
            // Second digit arrived — combine into two-digit number
            multiDigitTask?.cancel()
            multiDigitTask = nil
            pendingFirstDigit = nil

            let number = Int(first) * 10 + Int(digit)
            guard number >= 1, number <= deviceCount else { return }
            let completion = self.completion
            deactivate()
            completion?(.device(number - 1))
        } else if deviceCount > 9 && digit >= 1 && digit <= 9 {
            // Could be first digit of a two-digit number — wait briefly for second
            pendingFirstDigit = digit
            multiDigitTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(1))
                guard let self, self.pendingFirstDigit == digit else { return }
                // No second digit came — use single digit
                self.pendingFirstDigit = nil
                self.multiDigitTask = nil
                guard digit >= 1, digit <= deviceCount else { return }
                let completion = self.completion
                self.deactivate()
                DispatchQueue.main.async { completion?(.device(Int(digit) - 1)) }
            }
        } else {
            // Single digit selection (deviceCount <= 9)
            guard digit >= 1, digit <= deviceCount else { return }
            let completion = self.completion
            deactivate()
            completion?(.device(Int(digit) - 1))
        }
    }

    private func handlePINDigit(_ digit: UInt16) {
        guard isPINMode else { return }
        pinDigits.append(digit)
        if pinDigits.count == 4 {
            let digits = pinDigits
            let completion = pinCompletion
            deactivate()
            completion?(digits)
        }
    }

    private func cancel() {
        let completion = self.completion
        deactivate()
        completion?(.cancelled)
    }

    private func cancelPIN() {
        let completion = pinCompletion
        deactivate()
        completion?(nil)
    }

    private func deactivate() {
        isActive = false
        isPINMode = false
        pinDigits = []
        pendingFirstDigit = nil
        multiDigitTask?.cancel()
        multiDigitTask = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        completion = nil
        pinCompletion = nil
        NotificationCenter.default.post(name: .selectionModeDeactivated, object: nil)
    }
}

// MARK: - Notification-based communication with HotkeyManager

extension Notification.Name {
    static let selectionModeActivated = Notification.Name("SelectionModeActivated")
    static let selectionModeDeactivated = Notification.Name("SelectionModeDeactivated")
}

struct SelectionModeConfig {
    let deviceCount: Int
    let onDigit: (UInt16) -> Void
    let onEscape: () -> Void
}

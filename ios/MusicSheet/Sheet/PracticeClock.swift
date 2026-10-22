import Foundation
import Observation
import UIKit

/// Song-time clock for auto-scroll. Runs at an adjustable rate so you can practise slower than the record.
@MainActor
@Observable
final class PracticeClock {
    private(set) var time: Double = 0
    private(set) var isRunning = false
    var rate: Double = 1

    @ObservationIgnored private var lastTick: Date?
    @ObservationIgnored private var task: Task<Void, Never>?

    func start() {
        guard !isRunning else { return }
        isRunning = true
        lastTick = .now
        UIApplication.shared.isIdleTimerDisabled = true
        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
                self?.tick()
            }
        }
    }

    func pause() {
        tick()
        isRunning = false
        task?.cancel()
        task = nil
        lastTick = nil
        UIApplication.shared.isIdleTimerDisabled = false
    }

    func toggle() {
        isRunning ? pause() : start()
    }

    func seek(to newTime: Double) {
        time = max(0, newTime)
        if isRunning { lastTick = .now }
    }

    private func tick() {
        guard isRunning, let last = lastTick else { return }
        let now = Date.now
        time += now.timeIntervalSince(last) * rate
        lastTick = now
    }
}

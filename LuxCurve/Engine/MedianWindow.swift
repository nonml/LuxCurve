//
//  MedianWindow.swift
//  LuxCurve
//
//  The median of the last few samples. Used alongside the EMA to estimate the
//  *current* lighting: the EMA is deliberately slow (it keeps the screen from
//  reacting to every flicker), so right after the room changes it can still
//  report the old lighting for tens of seconds. A short median follows a real
//  change within a few samples while ignoring a brief spike such as a passing
//  shadow.
//

import Foundation

struct MedianWindow {
    let capacity: Int
    private(set) var samples: [Double] = []

    init(capacity: Int) {
        self.capacity = max(1, capacity)
    }

    /// Add a sample, dropping the oldest once the window is full.
    mutating func push(_ sample: Double) {
        samples.append(sample)
        if samples.count > capacity { samples.removeFirst(samples.count - capacity) }
    }

    /// Median of the samples in the window, or nil if it is empty.
    var median: Double? {
        guard !samples.isEmpty else { return nil }
        let sorted = samples.sorted()
        let mid = sorted.count / 2
        return sorted.count % 2 == 1 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2
    }

    mutating func reset() {
        samples.removeAll()
    }
}

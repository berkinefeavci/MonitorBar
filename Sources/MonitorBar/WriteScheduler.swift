import Foundation

@MainActor final class WriteScheduler {
    private var generation = 0

    func schedule(after delay: TimeInterval, action: @escaping @MainActor () -> Void) {
        generation += 1
        let scheduledGeneration = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard self?.generation == scheduledGeneration else { return }
            action()
        }
    }

    func cancel() { generation += 1 }
}

enum WriteOutcome: Equatable {
    case verified
    case mismatch
    case unreadable
}

func writeOutcome(requested: UInt16, readback: HardwareLevels?) -> WriteOutcome {
    guard let readback else { return .unreadable }
    return readback.current == requested ? .verified : .mismatch
}

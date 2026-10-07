import XCTest
@testable import MonitorBar

final class MonitorModelTests: XCTestCase {
    func testOnlyLatestPendingWriteRuns() async throws {
        await MainActor.run {
            TestRetainer.writes = []
            let scheduler = WriteScheduler()
            scheduler.schedule(after: 0.04) { TestRetainer.writes.append(25) }
            scheduler.schedule(after: 0.04) { TestRetainer.writes.append(60) }
            TestRetainer.scheduler = scheduler
        }
        try await Task.sleep(nanoseconds: 150_000_000)
        let values = await MainActor.run { TestRetainer.writes }
        XCTAssertEqual(values, [60])
        await MainActor.run { TestRetainer.scheduler = nil }
    }

    func testDisconnectCancelsPendingWrite() async throws {
        await MainActor.run {
            TestRetainer.writes = []
            let scheduler = WriteScheduler()
            scheduler.schedule(after: 0.04) { TestRetainer.writes.append(52) }
            scheduler.cancel()
            TestRetainer.scheduler = scheduler
        }
        try await Task.sleep(nanoseconds: 150_000_000)
        let count = await MainActor.run { TestRetainer.writes.count }
        XCTAssertEqual(count, 0)
        await MainActor.run { TestRetainer.scheduler = nil }
    }

    func testLiveWritesStartImmediatelyAndCoalesceWhileBusy() async {
        await MainActor.run {
            let queue = LatestWriteQueue()
            TestRetainer.writes = []
            TestRetainer.finishWrite = nil
            queue.submit { finish in
                TestRetainer.writes.append(10)
                TestRetainer.finishWrite = finish
            }
            XCTAssertEqual(TestRetainer.writes, [10])
            queue.submit { finish in TestRetainer.writes.append(20); finish() }
            queue.submit { finish in TestRetainer.writes.append(30); finish() }
            XCTAssertEqual(TestRetainer.writes, [10])
            TestRetainer.finishWrite?()
            XCTAssertEqual(TestRetainer.writes, [10, 30])
            TestRetainer.finishWrite = nil
        }
    }

    func testWriteRequiresMatchingReadback() {
        XCTAssertEqual(writeOutcome(requested: 52, readback: HardwareLevels(current: 52, maximum: 100)), .verified)
        XCTAssertEqual(writeOutcome(requested: 52, readback: HardwareLevels(current: 58, maximum: 100)), .mismatch)
        XCTAssertEqual(writeOutcome(requested: 52, readback: nil), .unreadable)
    }
}

@MainActor private enum TestRetainer {
    static var scheduler: WriteScheduler?
    static var writes: [Int] = []
    static var finishWrite: (@MainActor () -> Void)?
}

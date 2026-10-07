import Foundation

/// Serializes UI updates and PhotoKit reservation callbacks without blocking the main actor.
public final class JobStore: @unchecked Sendable {
    private let lock = NSLock()
    private let journal: TransferJournal
    private var jobs: [TransferJob]
    public init(url: URL) throws {
        journal = TransferJournal(url: url)
        jobs = try journal.load()
    }
    public func snapshot() -> [TransferJob] {
        lock.lock(); defer { lock.unlock() }; return jobs
    }
    public func update(_ change: (inout [TransferJob]) throws -> Void) throws {
        lock.lock(); defer { lock.unlock() }
        var next = jobs
        try change(&next)
        try journal.save(next)
        jobs = next
    }
}

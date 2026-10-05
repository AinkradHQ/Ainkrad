import Foundation

/// Serialises work per volume, in parallel across volumes.
///
/// Two copies fighting over one spinning disk (or one USB bus) are slower than
/// either alone, so same-volume jobs queue. Different volumes have no such
/// contention and run concurrently.
actor VolumeSerializer {
    /// The tail of each volume's chain. A new job awaits the current tail and
    /// then becomes the tail itself, which is what produces FIFO ordering
    /// without an explicit queue structure.
    private var chains: [String: Task<Void, Never>] = [:]

    /// Returns the work's value rather than taking an `inout` or letting the
    /// caller mutate a captured var — the latter is a data race under Swift 6
    /// strict concurrency, since the closure is `@Sendable`.
    func serialize<T: Sendable>(
        volume: String,
        work: @escaping @Sendable () async -> T
    ) async -> T {
        let previous = chains[volume]
        let task = Task<T, Never> {
            await previous?.value
            return await work()
        }
        // The stored tail is type-erased to `Void`: chaining only needs to know
        // when the previous job FINISHED, never what it produced.
        chains[volume] = Task { _ = await task.value }
        return await task.value
    }
}

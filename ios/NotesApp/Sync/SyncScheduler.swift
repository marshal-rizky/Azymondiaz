import Foundation

@Observable
final class SyncScheduler {
    var status: String = "idle"
    private let client: SyncClient
    private var timer: Timer?

    init(client: SyncClient) {
        self.client = client
    }

    func start() {
        timer?.invalidate()
        // Every 5 minutes, spec §6.
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { await self?.syncNow() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    @MainActor
    func syncNow() async {
        status = "syncing"
        do {
            let at = try await client.push()
            status = "synced \(at.formatted(date: .omitted, time: .shortened))"
        } catch {
            status = "error: \(error.localizedDescription)"
        }
    }
}

import Foundation
import VolumeArcCore

/// VOL-286: refreshes the cached remote coach kill switch from the relay's
/// `POST /v1/config` endpoint. Fired once per launch off the critical path;
/// failures keep the last cached value (fail-open to local state) so a
/// network blip can never disable — or re-enable — anything by accident.
enum RemoteCoachKillSwitchRefresher {
    static func refresh(relayBaseURL: URL, session: URLSession = .shared) async {
        var request = URLRequest(url: relayBaseURL.appending(path: "v1/config"))
        request.httpMethod = "POST"
        request.timeoutInterval = 10

        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let payload = try? JSONDecoder().decode(Payload.self, from: data)
        else { return }

        // A 200 that OMITS the flag (relay rollback / schema mismatch) must
        // leave the cache untouched — defaulting to false here would clear
        // an active kill switch mid-incident (PR #363 review, Codex P2).
        // Only an explicit value updates the store.
        guard let fmCoachDisabled = payload.fmCoachDisabled else { return }
        RemoteCoachKillSwitchStore.update(foundationModelCoachKilled: fmCoachDisabled)
    }

    private struct Payload: Decodable {
        let fmCoachDisabled: Bool?
    }
}

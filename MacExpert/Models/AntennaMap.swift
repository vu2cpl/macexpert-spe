import Foundation

/// Stores the antenna-to-band mapping locally, auto-learned from CSV status updates.
/// Each band has a primary antenna (1-4 or "NO") and ATU status.
/// Persisted to UserDefaults so it survives app restarts.
@Observable
@MainActor
final class AntennaMap {
    /// Key: band name ("160m", "80m", etc.), Value: antenna info
    var mapping: [String: BandAntenna] = [:]

    private let storageKey = "antennaMapping"

    struct BandAntenna: Codable, Equatable {
        var antenna: String   // "1", "2", "3", "4", or "NO"
        var atu: String       // "a"=ATU, "b"=bypassed, "t"=tunable, ""=none
    }

    static let allBands = ["160m", "80m", "60m", "40m", "30m", "20m", "17m", "15m", "12m", "10m", "6m", "4m"]

    init() {
        load()
    }

    /// Update the mapping when we receive a status update with a valid band.
    /// Called from the ViewModel whenever amp state changes.
    func learn(band: String, antenna: String, atu: String) {
        guard !band.isEmpty, band != "---", band != "???" else { return }
        guard !antenna.isEmpty, antenna != "0" else { return }

        let entry = BandAntenna(antenna: antenna, atu: atu)
        if mapping[band] != entry {
            mapping[band] = entry
            save()
        }
    }

    /// Get antenna for a band, or nil if not yet learned
    func antenna(for band: String) -> BandAntenna? {
        mapping[band]
    }

    /// Display label for a band's antenna
    func label(for band: String) -> String {
        guard let a = mapping[band] else { return "--" }
        return a.antenna
    }

    /// Display label for ATU status
    func atuLabel(for band: String) -> String {
        guard let a = mapping[band] else { return "" }
        switch a.atu {
        case "a": return "ATU"
        case "b": return "BYP"
        case "t": return "TUN"
        default: return ""
        }
    }

    /// Cycle antenna for a band: NO → 1 → 2 → 3 → 4 → NO
    func cycleAntenna(for band: String) {
        let current = mapping[band]?.antenna ?? "NO"
        let next: String
        switch current {
        case "NO", "0": next = "1"
        case "1": next = "2"
        case "2": next = "3"
        case "3": next = "4"
        default: next = "NO"
        }
        mapping[band] = BandAntenna(antenna: next, atu: mapping[band]?.atu ?? "")
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(mapping) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let saved = try? JSONDecoder().decode([String: BandAntenna].self, from: data) else { return }
        mapping = saved
    }
}

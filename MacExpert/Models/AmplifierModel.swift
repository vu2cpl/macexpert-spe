import Foundation

/// SPE Expert amplifier model, auto-detected from status ID field.
enum AmplifierModel: String, CaseIterable {
    case expert1_3K = "13K"
    case expert1_5K = "15K"
    case expert2K = "20K"
    case unknown = ""

    var displayName: String {
        switch self {
        case .expert1_3K: "Expert 1.3K-FA"
        case .expert1_5K: "Expert 1.5K-FA"
        case .expert2K: "Expert 2K-FA"
        case .unknown: "Expert"
        }
    }

    var maxPower: Int {
        switch self {
        case .expert1_3K: 1300
        case .expert1_5K: 1500
        case .expert2K: 2000
        case .unknown: 1500
        }
    }

    /// Number of bands supported (1.3K has 4m band = 12 bands, 2K has up to 6m = 11)
    var maxBandIndex: Int {
        switch self {
        case .expert1_3K, .expert1_5K: 11
        case .expert2K: 10
        case .unknown: 11
        }
    }

    /// Max TX antennas
    var maxAntennas: Int {
        switch self {
        case .expert1_3K, .expert1_5K: 4
        case .expert2K: 6
        case .unknown: 4
        }
    }

    /// Max power for a given power level setting (L/M/H)
    func maxPowerForLevel(_ level: String) -> Int {
        switch self {
        case .expert1_3K:
            switch level {
            case "L": return 400
            case "M": return 700
            default:  return 1300
            }
        case .expert1_5K:
            switch level {
            case "L": return 500
            case "M": return 800
            default:  return 1500
            }
        case .expert2K:
            switch level {
            case "L": return 600
            case "M": return 1000
            default:  return 2000
            }
        case .unknown:
            switch level {
            case "L": return 500
            case "M": return 800
            default:  return 1500
            }
        }
    }

    static func detect(from id: String) -> AmplifierModel {
        let trimmed = id.trimmingCharacters(in: .whitespaces)
        return AmplifierModel(rawValue: trimmed) ?? .unknown
    }
}

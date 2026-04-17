import Foundation

/// Amplifier state — decoded from serial CSV or WebSocket JSON.
/// Field names match spe-remote JSON keys for WebSocket compatibility.
struct AmplifierState: Equatable, Codable {
    var opStatus: String = "Stby"       // "Oper" or "Stby"
    var txStatus: String = "RX"         // "TX" or "RX"
    var input: String = "0"
    var band: String = "---"
    var txAntenna: String = "0"
    var atuStatus: String = ""          // "t"=tunable, "b"=bypassed, "a"=ATU
    var rxAntenna: String = "0"
    var pLevel: String = "0"            // L/M/H
    var pOut: String = "0"              // Output power in watts
    var swr: String = "0"               // SWR at ATU
    var aswr: String = "0"              // SWR at antenna
    var voltage: String = "0"           // PA supply voltage
    var drain: String = "0"             // PA drain current
    var paTemp: String = "0"            // Upper heatsink temp
    var tempLower: String = "0"         // Lower heatsink temp (2K-FA)
    var tempCombiner: String = "0"      // Combiner temp (2K-FA)
    var memBank: String = ""            // A/B (1.3K) or x (2K)
    var warnings: String = ""
    var error: String = ""              // Alarm field
    var modelId: String = ""            // "20K", "13K" (serial only)

    enum CodingKeys: String, CodingKey {
        case opStatus = "op_status"
        case txStatus = "tx_status"
        case input, band
        case txAntenna = "tx_antenna"
        case atuStatus = "atu_status"
        case rxAntenna = "rx_antenna"
        case pLevel = "p_level"
        case pOut = "p_out"
        case swr, aswr, voltage, drain
        case paTemp = "pa_temp"
        case tempLower = "temp_lower"
        case tempCombiner = "temp_combiner"
        case memBank = "mem_bank"
        case warnings, error
        case modelId = "model_id"
    }

    /// Custom decoder — spe-remote JSON only sends a subset of fields.
    /// Fields not present in the JSON get their default values.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        opStatus = (try? c.decode(String.self, forKey: .opStatus)) ?? "Stby"
        txStatus = (try? c.decode(String.self, forKey: .txStatus)) ?? "RX"
        input = (try? c.decode(String.self, forKey: .input)) ?? "0"
        band = (try? c.decode(String.self, forKey: .band)) ?? "---"
        txAntenna = (try? c.decode(String.self, forKey: .txAntenna)) ?? "0"
        atuStatus = (try? c.decode(String.self, forKey: .atuStatus)) ?? ""
        rxAntenna = (try? c.decode(String.self, forKey: .rxAntenna)) ?? "0"
        pLevel = (try? c.decode(String.self, forKey: .pLevel)) ?? "0"
        pOut = (try? c.decode(String.self, forKey: .pOut)) ?? "0"
        swr = (try? c.decode(String.self, forKey: .swr)) ?? "0"
        aswr = (try? c.decode(String.self, forKey: .aswr)) ?? "0"
        voltage = (try? c.decode(String.self, forKey: .voltage)) ?? "0"
        drain = (try? c.decode(String.self, forKey: .drain)) ?? "0"
        paTemp = (try? c.decode(String.self, forKey: .paTemp)) ?? "0"
        tempLower = (try? c.decode(String.self, forKey: .tempLower)) ?? "0"
        tempCombiner = (try? c.decode(String.self, forKey: .tempCombiner)) ?? "0"
        memBank = (try? c.decode(String.self, forKey: .memBank)) ?? ""
        warnings = (try? c.decode(String.self, forKey: .warnings)) ?? ""
        error = (try? c.decode(String.self, forKey: .error)) ?? ""
        modelId = (try? c.decode(String.self, forKey: .modelId)) ?? ""
    }

    init(
        opStatus: String = "Stby", txStatus: String = "RX",
        input: String = "0", band: String = "---",
        txAntenna: String = "0", atuStatus: String = "",
        rxAntenna: String = "0", pLevel: String = "0",
        pOut: String = "0", swr: String = "0", aswr: String = "0",
        voltage: String = "0", drain: String = "0", paTemp: String = "0",
        tempLower: String = "0", tempCombiner: String = "0",
        memBank: String = "", warnings: String = "", error: String = "",
        modelId: String = ""
    ) {
        self.opStatus = opStatus; self.txStatus = txStatus
        self.input = input; self.band = band
        self.txAntenna = txAntenna; self.atuStatus = atuStatus
        self.rxAntenna = rxAntenna; self.pLevel = pLevel
        self.pOut = pOut; self.swr = swr; self.aswr = aswr
        self.voltage = voltage; self.drain = drain; self.paTemp = paTemp
        self.tempLower = tempLower; self.tempCombiner = tempCombiner
        self.memBank = memBank; self.warnings = warnings; self.error = error
        self.modelId = modelId
    }

    var isActive: Bool {
        txStatus == "TX" || opStatus == "Oper"
    }

    private func num(_ s: String) -> Double {
        Double(s.trimmingCharacters(in: .whitespaces)) ?? 0
    }

    var powerWatts: Int {
        Int(pOut.trimmingCharacters(in: .whitespaces)) ?? 0
    }

    var swrValue: Double {
        let v = num(swr)
        return v > 0 ? v : 1.0
    }

    var antennaSWR: Double {
        let v = num(aswr)
        return v > 0 ? v : 1.0
    }

    var voltageValue: Double { num(voltage) }
    var drainValue: Double { num(drain) }
    var tempValue: Double { num(paTemp) }
}

// NOTE: The 1K-FA binary status / `DisplayContext` structure that used to
// live here has been removed. The 1.5K-FA uses the proprietary 0x6A RCU
// display packet instead; that's parsed by `RCUFrame`. See
// reference_spe_rcu_protocol.md for details.

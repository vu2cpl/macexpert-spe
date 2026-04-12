import Foundation

// MARK: - SPE Expert Serial Protocol
// Reference: SPE Application Programmer's Guide Rev 1.1

/// Commands sent from host to amplifier.
/// Packet format: 0x55 0x55 0x55 [CNT] [DATA...] [CHK]
enum SPECommand: UInt8, CaseIterable {
    case input       = 0x01
    case bandDown    = 0x02
    case bandUp      = 0x03
    case antenna     = 0x04
    case lMinus      = 0x05
    case lPlus       = 0x06
    case cMinus      = 0x07
    case cPlus       = 0x08
    case tune        = 0x09
    case switchOff   = 0x0A
    case power       = 0x0B
    case display     = 0x0C
    case operate     = 0x0D
    case cat         = 0x0E
    case leftArrow   = 0x0F
    case rightArrow  = 0x10
    case set         = 0x11
    case backlightOn = 0x82
    case backlightOff = 0x83
    case status      = 0x90

    /// WebSocket command name (matches spe-remote COMMANDS dict)
    var wsCommandName: String {
        switch self {
        case .input: "input"
        case .bandDown: "band_dn"
        case .bandUp: "band_up"
        case .antenna: "antenna"
        case .lMinus: "l_minus"
        case .lPlus: "l_plus"
        case .cMinus: "c_minus"
        case .cPlus: "c_plus"
        case .tune: "tune"
        case .switchOff: "power_off"
        case .power: "power_level"
        case .display: "display"
        case .operate: "oper"
        case .cat: "cat"
        case .leftArrow: "left"
        case .rightArrow: "right"
        case .set: "set"
        case .backlightOn: "backlight_on"
        case .backlightOff: "backlight_off"
        case .status: "status"
        }
    }

    var displayName: String {
        switch self {
        case .input: "INPUT"
        case .bandDown: "BAND -"
        case .bandUp: "BAND +"
        case .antenna: "ANT"
        case .lMinus: "L -"
        case .lPlus: "L +"
        case .cMinus: "C -"
        case .cPlus: "C +"
        case .tune: "TUNE"
        case .switchOff: "OFF"
        case .power: "POWER"
        case .display: "DISP"
        case .operate: "OPER"
        case .cat: "CAT"
        case .leftArrow: "LEFT"
        case .rightArrow: "RIGHT"
        case .set: "SET"
        case .backlightOn: "BL ON"
        case .backlightOff: "BL OFF"
        case .status: "STATUS"
        }
    }
}

enum SPEProtocol {
    // Sync bytes
    static let hostSync: [UInt8] = [0x55, 0x55, 0x55]
    static let ampSync: [UInt8] = [0xAA, 0xAA, 0xAA]

    // Status response length byte (67 decimal = 0x43)
    static let statusLength: UInt8 = 0x43

    /// Build a command packet to send to the amplifier.
    static func buildPacket(command: SPECommand) -> Data {
        let cmdByte = command.rawValue
        // Single-byte command: CNT=0x01, CHK=cmdByte
        let bytes: [UInt8] = [0x55, 0x55, 0x55, 0x01, cmdByte, cmdByte]
        return Data(bytes)
    }

    /// Build a multi-byte command packet.
    static func buildPacket(data: [UInt8]) -> Data {
        let cnt = UInt8(data.count)
        let chk = UInt8(data.reduce(0) { (Int($0) + Int($1)) % 256 })
        let bytes: [UInt8] = [0x55, 0x55, 0x55, cnt] + data + [chk]
        return Data(bytes)
    }

    // MARK: - Band Map

    static let bandMap: [String: String] = [
        "00": "160m", "01": "80m", "02": "60m", "03": "40m",
        "04": "30m", "05": "20m", "06": "17m", "07": "15m",
        "08": "12m", "09": "10m", "10": "6m", "11": "4m",
    ]

    // MARK: - Warning Map

    static let warningMap: [Character: String] = [
        "M": "ALARM AMPLIFIER",
        "A": "NO SELECTED ANTENNA",
        "S": "SWR ANTENNA",
        "B": "NO VALID BAND",
        "P": "POWER LIMIT EXCEEDED",
        "O": "OVERHEATING",
        "Y": "ATU NOT AVAILABLE",
        "W": "TUNING WITH NO POWER",
        "K": "ATU BYPASSED",
        "R": "POWER SWITCH HELD BY REMOTE",
        "T": "COMBINER OVERHEATING",
        "C": "COMBINER FAULT",
        "N": "",
    ]

    // MARK: - Alarm Map

    static let alarmMap: [Character: String] = [
        "S": "SWR EXCEEDING LIMITS",
        "A": "AMPLIFIER PROTECTION",
        "D": "INPUT OVERDRIVING",
        "H": "EXCESS OVERHEATING",
        "C": "COMBINER FAULT",
        "N": "",
    ]

    // MARK: - Status Parsing

    /// Parse a comma-separated status string from the amplifier.
    /// Example: `C,20K,S,R,x,1,00,1a,0r,L,0000, 0.00, 0.00, 0.0, 0.0, 33,  0,  0,N,N,%^`
    /// Field indices match spe-remote/protocol.py: [0]=prefix, [1]=ID, [2]=Stby/Oper, ...
    static func parseStatus(_ line: String) -> AmplifierState? {
        let data = line.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: ",", omittingEmptySubsequences: false)
            .map { String($0) }

        guard data.count >= 21 else { return nil }

        func f(_ i: Int) -> String { data[i].trimmingCharacters(in: .whitespaces) }

        let id = f(1)                              // "20K" or "13K"
        let opStatus = f(2) == "O" ? "Oper" : "Stby"
        let txStatus = f(3) == "T" ? "TX" : "RX"
        let memBank = f(4)                         // A/B or x
        let input = f(5)                           // 1 or 2
        let bandCode = f(6)                        // 00-11
        let txAntATU = f(7)                        // e.g. "1a"
        let rxAnt = f(8)                           // e.g. "0r"
        let powerLevel = f(9)                      // L/M/H
        let outputPower = f(10)                    // watts
        let swrATU = f(11)                         // SWR at ATU
        let swrANT = f(12)                         // SWR at antenna
        let vPA = f(13)                            // voltage
        let iPA = f(14)                            // drain current
        let tempUpper = f(15)                      // upper heatsink
        let tempLower = f(16)                      // lower heatsink (2K)
        let tempCombiner = f(17)                   // combiner (2K)
        let warningChar = f(18)                    // warning code
        let alarmChar = f(19)                      // alarm code

        let band = bandMap[bandCode] ?? "???"

        // Parse TX antenna number and ATU status from 2-char field
        var txAntNum = "0"
        var atuStat = ""
        if txAntATU.count >= 2 {
            txAntNum = String(txAntATU.prefix(1))
            atuStat = String(txAntATU.suffix(1))
        }

        let warningText = warningChar.first.flatMap { warningMap[$0] } ?? ""
        let alarmText = alarmChar.first.flatMap { alarmMap[$0] } ?? ""

        return AmplifierState(
            opStatus: opStatus,
            txStatus: txStatus,
            input: input,
            band: band,
            txAntenna: txAntNum,
            atuStatus: atuStat,
            rxAntenna: rxAnt,
            pLevel: powerLevel,
            pOut: outputPower,
            swr: swrATU,
            aswr: swrANT,
            voltage: vPA,
            drain: iPA,
            paTemp: tempUpper,
            tempLower: tempLower,
            tempCombiner: tempCombiner,
            memBank: memBank,
            warnings: warningText,
            error: alarmText,
            modelId: id
        )
    }

    /// Extract the status CSV data from a raw serial response.
    /// Strips the 0xAA 0xAA 0xAA sync + length byte prefix and checksum/CRLF suffix.
    static func extractStatusData(from data: Data) -> String? {
        // Look for 0xAA 0xAA 0xAA sync pattern
        guard data.count > 6 else { return nil }

        var startIndex: Int?
        for i in 0..<(data.count - 2) {
            if data[i] == 0xAA && data[i+1] == 0xAA && data[i+2] == 0xAA {
                startIndex = i + 3
                break
            }
        }

        guard let start = startIndex, start < data.count else { return nil }

        let lengthByte = data[start]
        let dataStart = start + 1
        let dataEnd = dataStart + Int(lengthByte)

        guard dataEnd <= data.count else { return nil }

        let statusData = data[dataStart..<dataEnd]
        return String(data: statusData, encoding: .ascii)
    }
}

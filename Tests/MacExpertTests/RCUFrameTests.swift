import XCTest
@testable import MacExpert

/// Regression tests against real RCU frames captured from a 1.5K-FA.
/// Fixtures live in `Tests/MacExpertTests/Fixtures/<name>.bin` and contain
/// the bytes AFTER the `AA AA AA 6A` sync+marker — i.e. what
/// `RCUFrame.parse(_ data: Data)` expects.
///
/// Inspired by FtlC-ian/expert-amp-server's fixture-based testing pattern.
/// To add a new fixture see `Tests/MacExpertTests/Fixtures/README.md`.
final class RCUFrameTests: XCTestCase {

    /// Load a fixture binary by base name (without `.bin`). Crashes loudly
    /// if missing — test will fail with a clear message.
    private func loadFixture(_ name: String) -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: "bin",
                                          subdirectory: "Fixtures")
                ?? Bundle.module.url(forResource: name, withExtension: "bin")
        else {
            XCTFail("Fixture \(name).bin not found in test bundle")
            return Data()
        }
        return (try? Data(contentsOf: url)) ?? Data()
    }

    // MARK: - op_idle.bin
    //
    // Captured 2026-04-16 from a 1.5K-FA in OPERATE mode, sitting idle.
    // The amp's LCD shows the power-meter scale across the top
    // (0 / 125 / 250 / 375 / 500). 367 bytes after the sync+marker.

    func test_opIdle_parsesAsOperateScreen() {
        let data = loadFixture("op_idle")
        XCTAssertEqual(data.count, 367, "Fixture should be the full RCU body length")

        guard let frame = RCUFrame.parse(data) else {
            XCTFail("RCUFrame.parse returned nil for op_idle")
            return
        }

        XCTAssertEqual(frame.screen, .opOperate,
                       "Idle operate screen should classify as .opOperate (got \(frame.screen.rawValue))")
    }

    func test_opIdle_hasPowerScaleInBody() {
        let data = loadFixture("op_idle")
        guard let frame = RCUFrame.parse(data) else { XCTFail(); return }
        // The operate-mode scale renders "125 250 375 500" somewhere in the
        // body. We don't care about exact spacing — just that the decoder
        // surfaces those tick numbers.
        let body = LCDText.decodeTrimmed(frame.raw[0..<min(192, frame.raw.count)])
        XCTAssertTrue(body.contains("125"), "Body should contain '125' tick. Got: \(body)")
        XCTAssertTrue(body.contains("250"), "Body should contain '250' tick. Got: \(body)")
        XCTAssertTrue(body.contains("500"), "Body should contain '500' tick. Got: \(body)")
    }

    func test_opIdle_noFalseSubMenuActivation() {
        // Regression guard: an operate-mode frame must not look like a
        // sub-menu screen, otherwise the view model would force the UI
        // into SETUP whenever the amp goes back to OPERATE.
        let data = loadFixture("op_idle")
        guard let frame = RCUFrame.parse(data) else { XCTFail(); return }

        let subMenuScreens: Set<DetectedScreen> = [
            .setupRoot, .catMenu, .config, .antennaMatrix, .display,
            .alarmsLog, .tempFans, .manualTune, .rxAnt, .tunAnt,
            .yaesuModel, .tenTecModel, .baudRate, .tunAntPort,
        ]
        XCTAssertFalse(subMenuScreens.contains(frame.screen),
                       "Operate idle frame must not classify as a sub-menu (got \(frame.screen.rawValue))")
    }

    func test_opIdle_noInfoScreenFalsePositive() {
        // Regression guard: the operate-mode frame contains the power
        // scale digits which an over-broad info-screen matcher might
        // misclassify. It must NOT be .infoScreen.
        let data = loadFixture("op_idle")
        guard let frame = RCUFrame.parse(data) else { XCTFail(); return }
        XCTAssertNotEqual(frame.screen, .infoScreen,
                          "Operate idle frame must not classify as .infoScreen")
    }

    // MARK: - standby_idle.bin (STANDBY logo screen)

    func test_standbyIdle_classifiesAsStandby() {
        let data = loadFixture("standby_idle")
        guard let frame = RCUFrame.parse(data) else { XCTFail(); return }
        XCTAssertEqual(frame.screen, .opStandby)
    }

    func test_standbyIdle_bodyHasExpectedLogoText() {
        let data = loadFixture("standby_idle")
        guard let frame = RCUFrame.parse(data) else { XCTFail(); return }
        let body = LCDText.decodeTrimmed(frame.raw[0..<min(192, frame.raw.count)])
            .uppercased()
        XCTAssertTrue(body.contains("EXPERT"))
        XCTAssertTrue(body.contains("SOLID STATE"))
        XCTAssertTrue(body.contains("STANDBY"))
    }

    // MARK: - setup_root.bin (SETUP OPTIONS 4×3 grid)

    func test_setupRoot_classifiesAsSetupRoot() {
        let data = loadFixture("setup_root")
        guard let frame = RCUFrame.parse(data) else { XCTFail(); return }
        XCTAssertEqual(frame.screen, .setupRoot)
    }

    func test_setupRoot_cursorDecodesToValidIndex() {
        // The amp always has a cursor on SETUP root. Decoder must return
        // a value in 0..<12 (12 grid cells).
        let data = loadFixture("setup_root")
        guard let frame = RCUFrame.parse(data) else { XCTFail(); return }
        guard let idx = frame.gridCursorNavIndex else {
            XCTFail("SETUP root frame should have a decoded cursor")
            return
        }
        XCTAssertTrue((0..<12).contains(idx),
                      "SETUP cursor index out of range: \(idx)")
    }

    // MARK: - antenna_matrix.bin (SET ANTENNA ON BANK A)

    func test_antennaMatrix_classifiesCorrectly() {
        let data = loadFixture("antenna_matrix")
        guard let frame = RCUFrame.parse(data) else { XCTFail(); return }
        XCTAssertEqual(frame.screen, .antennaMatrix)
    }

    func test_antennaMatrix_parsesAtLeastSomeBands() {
        // The matrix-row regex should pick up multiple bands from a real
        // capture. Exact bands depend on the configuration but we should
        // see at least a couple.
        let data = loadFixture("antenna_matrix")
        guard let frame = RCUFrame.parse(data) else { XCTFail(); return }
        guard let matrix = frame.antennaMatrixValues else {
            XCTFail("antennaMatrixValues should be non-nil on antenna matrix screen")
            return
        }
        XCTAssertGreaterThanOrEqual(matrix.count, 3,
            "Expected at least 3 parsed bands, got \(matrix.count): \(matrix.keys.sorted())")
    }

    func test_antennaMatrix_bankLetterParsedAsA() {
        let data = loadFixture("antenna_matrix")
        guard let frame = RCUFrame.parse(data) else { XCTFail(); return }
        XCTAssertEqual(frame.bankLetter, "A",
                       "Bank letter should be 'A' (got \(String(describing: frame.bankLetter)))")
    }

    // MARK: - cat_settings.bin (CAT SETTING REPORT info screen)

    func test_catSettings_classifiesAsInfoScreen() {
        let data = loadFixture("cat_settings")
        guard let frame = RCUFrame.parse(data) else { XCTFail(); return }
        XCTAssertEqual(frame.screen, .infoScreen,
                       "CAT SETTING REPORT must classify as .infoScreen")
    }

    func test_catSettings_headerContainsCatSetting() {
        let data = loadFixture("cat_settings")
        guard let frame = RCUFrame.parse(data) else { XCTFail(); return }
        XCTAssertTrue(frame.header.uppercased().contains("CAT SETTING"),
                      "Header should contain 'CAT SETTING', got: \(frame.header)")
    }

    // MARK: - system_info.bin (SYSTEM INFO via second CAT press)

    func test_systemInfo_classifiesAsInfoScreen() {
        let data = loadFixture("system_info")
        guard let frame = RCUFrame.parse(data) else { XCTFail(); return }
        XCTAssertEqual(frame.screen, .infoScreen)
    }

    func test_systemInfo_bodyContainsFirmwareRelease() {
        let data = loadFixture("system_info")
        guard let frame = RCUFrame.parse(data) else { XCTFail(); return }
        let body = LCDText.decodeTrimmed(frame.raw[32..<min(192, frame.raw.count)])
            .uppercased()
        XCTAssertTrue(body.contains("REL "),
                      "SYSTEM INFO body should contain firmware 'REL ' marker, got: \(body)")
    }

    // MARK: - tun_ant_port.bin (TUNEABLE ANTENNAS PORT — protocol/baud)

    func test_tunAntPort_classifiesAsTunAntPort() {
        let data = loadFixture("tun_ant_port")
        guard let frame = RCUFrame.parse(data) else { XCTFail(); return }
        XCTAssertEqual(frame.screen, .tunAntPort)
    }

    func test_tunAntPort_extractsProtocolField() {
        let data = loadFixture("tun_ant_port")
        guard let frame = RCUFrame.parse(data) else { XCTFail(); return }
        // Whatever protocol the user has configured, it must be a
        // non-empty word — not nil and not the literal "—".
        guard let proto = frame.tunAntPortProtocol else {
            XCTFail("tunAntPortProtocol should be parsed from real frame")
            return
        }
        XCTAssertFalse(proto.isEmpty)
        XCTAssertTrue(proto.allSatisfy { $0.isLetter || $0.isNumber || $0 == " " },
                      "Protocol value looks garbled: \(proto)")
    }

    func test_tunAntPort_dataAndStopBitArePresent() {
        let data = loadFixture("tun_ant_port")
        guard let frame = RCUFrame.parse(data) else { XCTFail(); return }
        XCTAssertNotNil(frame.tunAntPortDataBit, "DATA BIT field missing")
        XCTAssertNotNil(frame.tunAntPortStopBit, "STOP BIT field missing")
        XCTAssertNotNil(frame.tunAntPortParity,  "PARITY field missing")
    }
}

// MARK: - LCDText regression tests
//
// Locked-in unit tests for the attribute decoder. These don't need a
// fixture — they check known byte→char mappings.

final class LCDTextTests: XCTestCase {

    func test_attributedRange_addsHighBit() {
        // 0x10-0x3F: real ASCII = byte + 0x20.
        // 0x33 should decode to 'S' (0x53).
        XCTAssertEqual(LCDText.decode([0x33]), "S")
        XCTAssertEqual(LCDText.decode([0x11]), "1")
        XCTAssertEqual(LCDText.decode([0x21]), "A")
    }

    func test_normalAsciiRange_passesThrough() {
        // 0x40-0x7E: direct ASCII.
        XCTAssertEqual(LCDText.decode([0x53]), "S")
        XCTAssertEqual(LCDText.decode([0x41]), "A")
        XCTAssertEqual(LCDText.decode([0x7E]), "~")
    }

    func test_nullAndOutOfRange_replacedWithDot() {
        XCTAssertEqual(LCDText.decode([0x00]), ".")
        XCTAssertEqual(LCDText.decode([0xAA]), ".")
        XCTAssertEqual(LCDText.decode([0xFF]), ".")
    }

    func test_decodeTrimmed_collapsesRunsOfDots() {
        // "S.....X" → "S X" (multiple dots collapsed to single space).
        XCTAssertEqual(
            LCDText.decodeTrimmed([0x53, 0x00, 0x00, 0x00, 0x00, 0x00, 0x58]),
            "S X"
        )
    }
}

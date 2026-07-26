import Foundation
import XCTest
@testable import TouchPilot

final class PresetPersistenceTests: XCTestCase {
    func testVersionComparatorRecognizesNewerGitHubRelease() {
        XCTAssertTrue(VersionComparator.isNewer("v0.6.8", than: "0.6.7"))
        XCTAssertTrue(VersionComparator.isNewer("1.0.0", than: "0.9.9"))
        XCTAssertFalse(VersionComparator.isNewer("v0.6.7", than: "0.6.7"))
        XCTAssertFalse(VersionComparator.isNewer("0.6.6", than: "0.6.7"))
    }

    func testPressDragInterceptionRequiresMatchingModifier() {
        let rules = [
            GestureRule(
                name: "Command press drag",
                gesture: .twoFingerPressDragLeft,
                triggerModifier: .command
            )
        ]
        let triggers = PressDragInterceptionPolicy.triggers(from: rules)

        XCTAssertFalse(PressDragInterceptionPolicy.shouldIntercept(
            fingerCount: 2,
            modifier: .none,
            configuredTriggers: triggers
        ))
        XCTAssertTrue(PressDragInterceptionPolicy.shouldIntercept(
            fingerCount: 2,
            modifier: .command,
            configuredTriggers: triggers
        ))
    }

    func testDisabledPressDragRuleDoesNotInstallInterception() {
        let rules = [
            GestureRule(
                name: "Disabled press drag",
                gesture: .twoFingerPressDragLeft,
                isEnabled: false
            )
        ]

        XCTAssertTrue(PressDragInterceptionPolicy.triggers(from: rules).isEmpty)
    }

    func testLegacyPresetWithoutVersionOrAppTargetsStillDecodes() throws {
        let legacyJSON = """
        {
          "rules": [
            {
              "id": "00000000-0000-0000-0000-000000000001",
              "name": "Legacy rule",
              "gesture": "Swipe Left",
              "isEnabled": true,
              "appBundleID": "com.example.legacy",
              "actions": []
            }
          ]
        }
        """

        let preset = try JSONDecoder().decode(PilotPreset.self, from: Data(legacyJSON.utf8))

        XCTAssertEqual(preset.version, 1)
        XCTAssertEqual(preset.rules.count, 1)
        XCTAssertEqual(preset.rules.first?.appBundleID, "com.example.legacy")
        XCTAssertEqual(preset.rules.first?.triggerModifier, GestureTriggerModifier.none)
        XCTAssertTrue(preset.appTargets.isEmpty)
    }

    func testVersionedPresetRoundTripPreservesApplicationTargets() throws {
        let target = AppTarget(name: "Example", bundleID: "com.example.app", iconName: "app")
        let rule = GestureRule(
            name: "Example rule",
            gesture: .threeFingerSwipeUp,
            triggerModifier: .command,
            appBundleID: target.bundleID
        )
        let original = PilotPreset(rules: [rule], appTargets: [target])

        let data = try JSONEncoder.pretty.encode(original)
        let decoded = try JSONDecoder().decode(PilotPreset.self, from: data)

        XCTAssertEqual(decoded.version, PilotPreset.currentVersion)
        XCTAssertEqual(decoded.rules, [rule])
        XCTAssertEqual(decoded.appTargets, [target])
    }

    func testUnreadablePresetIsNotOverwrittenByAutomaticSave() throws {
        let fixture = try makePresetStoreFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let damagedData = Data(#"{"rules":[{"gesture":"Unknown future gesture"}]}"#.utf8)
        try FileManager.default.createDirectory(
            at: fixture.presetURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try damagedData.write(to: fixture.presetURL)

        switch fixture.store.load() {
        case .unreadable(let sourceURL, _):
            XCTAssertEqual(sourceURL, fixture.presetURL)
        default:
            XCTFail("A damaged preset must be reported as unreadable")
        }

        fixture.store.save(.sample)

        XCTAssertEqual(try Data(contentsOf: fixture.presetURL), damagedData)
    }

    func testSuccessfulRecoveryExplicitlyReenablesPresetSaving() throws {
        let fixture = try makePresetStoreFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let damagedData = Data("not-json".utf8)
        try FileManager.default.createDirectory(
            at: fixture.presetURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try damagedData.write(to: fixture.presetURL)

        guard case .unreadable = fixture.store.load() else {
            return XCTFail("A damaged preset must block saving")
        }

        fixture.store.allowSavingAfterRecovery()
        fixture.store.save(.sample)

        let savedData = try Data(contentsOf: fixture.presetURL)
        let savedPreset = try JSONDecoder().decode(PilotPreset.self, from: savedData)
        XCTAssertEqual(savedPreset.rules, PilotPreset.sample.rules)
    }

    func testLegacyApplicationTargetDefaultsToEnabled() throws {
        let data = Data(#"{"name":"Finder","bundleID":"com.apple.finder","iconName":"face.smiling"}"#.utf8)
        let target = try JSONDecoder().decode(AppTarget.self, from: data)

        XCTAssertTrue(target.isEnabled)
    }

    func testDuplicateGestureInSameProfileIsReported() {
        let existing = GestureRule(
            name: "Existing",
            gesture: .threeFingerSwipeUp,
            appBundleID: "com.example.app"
        )
        let candidate = GestureRule(
            name: "Candidate",
            gesture: .threeFingerSwipeUp,
            appBundleID: "com.example.app"
        )

        let messages = ConflictDetector.messages(
            for: candidate,
            among: [existing, candidate],
            openWindowShortcut: "cmd+shift+o",
            language: .en
        )

        XCTAssertEqual(messages.count, 1)
        XCTAssertTrue(messages[0].contains("Existing"))
    }

    func testSameGestureInDifferentProfilesIsAllowed() {
        let finderRule = GestureRule(
            name: "Finder",
            gesture: .threeFingerSwipeUp,
            appBundleID: "com.apple.finder"
        )
        let notesRule = GestureRule(
            name: "Notes",
            gesture: .threeFingerSwipeUp,
            appBundleID: "com.apple.Notes"
        )

        let messages = ConflictDetector.messages(
            for: notesRule,
            among: [finderRule, notesRule],
            openWindowShortcut: "cmd+shift+o",
            language: .en
        )

        XCTAssertTrue(messages.isEmpty)
    }

    func testSameGestureWithDifferentTriggerModifierIsAllowed() {
        let plainRule = GestureRule(
            name: "Plain",
            gesture: .threeFingerSwipeUp
        )
        let commandRule = GestureRule(
            name: "Command",
            gesture: .threeFingerSwipeUp,
            triggerModifier: .command
        )

        let messages = ConflictDetector.messages(
            for: commandRule,
            among: [plainRule, commandRule],
            openWindowShortcut: "cmd+shift+o",
            language: .en
        )

        XCTAssertTrue(messages.isEmpty)
    }

    func testGestureRuleRequiresExactTriggerModifier() {
        let rule = GestureRule(
            name: "Command swipe",
            gesture: .twoFingerSwipeLeft,
            triggerModifier: .command
        )

        XCTAssertTrue(rule.matches(gesture: .twoFingerSwipeLeft, modifier: .command, appBundleID: nil))
        XCTAssertFalse(rule.matches(gesture: .twoFingerSwipeLeft, modifier: .none, appBundleID: nil))
    }

    func testActionShortcutConflictUsesCanonicalModifierNames() {
        let rule = GestureRule(
            name: "Conflict",
            gesture: .twoFingerTap,
            actions: [PilotAction(kind: .keyboardShortcut, title: "Open", value: "command+shift+o")]
        )

        let messages = ConflictDetector.messages(
            for: rule,
            among: [rule],
            openWindowShortcut: "shift+cmd+o",
            language: .en
        )

        XCTAssertEqual(messages.count, 1)
    }

    @MainActor
    func testDryRunDescriptionDoesNotExecuteAction() {
        let action = PilotAction(kind: .openURL, title: "Website", value: "example.com")
        let result = ActionExecutor.dryRunDescription(for: action, language: .en)

        XCTAssertEqual(result, "Test — open URL: example.com")
    }

    @MainActor
    func testSystemActionDryRunDoesNotExecuteAction() {
        let action = PilotAction(
            kind: .systemAction,
            title: "Put Mac to Sleep",
            value: SystemAction.sleepMac.rawValue
        )

        XCTAssertEqual(
            ActionExecutor.dryRunDescription(for: action, language: .en),
            "Test — Put Mac to Sleep"
        )
    }

    func testSystemActionRoundTripPreservesCommand() throws {
        let action = PilotAction(
            kind: .systemAction,
            title: "Увеличить громкость",
            value: SystemAction.volumeUp.rawValue
        )
        let original = PilotPreset(rules: [
            GestureRule(name: "Volume", gesture: .twoFingerTap, actions: [action])
        ])

        let data = try JSONEncoder.pretty.encode(original)
        let decoded = try JSONDecoder().decode(PilotPreset.self, from: data)

        XCTAssertEqual(decoded.rules.first?.actions.first?.kind, .systemAction)
        XCTAssertEqual(decoded.rules.first?.actions.first?.systemAction, .volumeUp)
    }

    func testRecognizesClockwiseCircleDrawing() {
        let gesture = DrawingGestureRecognizer.circleGesture(in: circlePoints(clockwise: true))

        XCTAssertEqual(gesture, .circleClockwise)
    }

    func testRecognizesCounterClockwiseCircleDrawing() {
        let gesture = DrawingGestureRecognizer.circleGesture(in: circlePoints(clockwise: false))

        XCTAssertEqual(gesture, .circleCounterClockwise)
    }

    func testOpenArcIsNotRecognizedAsCircle() {
        let gesture = DrawingGestureRecognizer.circleGesture(
            in: circlePoints(clockwise: true, completedTurns: 0.68)
        )

        XCTAssertNil(gesture)
    }

    func testDiagonalBackAndForthIsNotRecognizedAsCircle() {
        var points: [(x: Float, y: Float)] = []
        for pass in 0..<4 {
            for step in 0...28 {
                let rawProgress = Double(step) / 28
                let progress = pass.isMultiple(of: 2) ? rawProgress : 1 - rawProgress
                let lateralNoise = sin(Double(step) * 0.8 + Double(pass)) * 0.012
                points.append((
                    x: Float(0.25 + progress * 0.5),
                    y: Float(0.30 + progress * 0.4 + lateralNoise)
                ))
            }
        }

        XCTAssertNil(DrawingGestureRecognizer.circleGesture(in: points))
    }

    func testSpiralIsNotRecognizedAsCircle() {
        let points: [(x: Float, y: Float)] = (0...72).map { index in
            let progress = Double(index) / 72
            let angle = -progress * 2 * Double.pi
            let radius = 0.055 + progress * 0.14
            return (
                x: Float(0.5 + cos(angle) * radius),
                y: Float(0.5 + sin(angle) * radius)
            )
        }

        XCTAssertNil(DrawingGestureRecognizer.circleGesture(in: points))
    }

    func testCircleWithDirectionReversalIsNotRecognized() {
        var points = circlePoints(clockwise: true, completedTurns: 0.72)
        points.append(contentsOf: circlePoints(clockwise: false, completedTurns: 0.72))

        XCTAssertNil(DrawingGestureRecognizer.circleGesture(in: points))
    }

    func testRecognizesImperfectHandDrawnCircle() {
        let points: [(x: Float, y: Float)] = (0...58).map { index in
            let progress = Double(index) / 58
            let angle = -progress * 1.88 * Double.pi
            let wobble = sin(progress * 9 * Double.pi) * 0.018
            return (
                x: Float(0.5 + cos(angle) * (0.16 + wobble)),
                y: Float(0.5 + sin(angle) * (0.115 - wobble * 0.35))
            )
        }

        XCTAssertEqual(DrawingGestureRecognizer.circleGesture(in: points), .circleClockwise)
    }

    func testLooseThreeQuarterArcIsNotRecognizedAsCircle() {
        let points: [(x: Float, y: Float)] = (0...42).map { index in
            let progress = Double(index) / 42
            let angle = progress * 1.56 * Double.pi
            let wobble = sin(progress * 7 * Double.pi) * 0.022
            return (
                x: Float(0.5 + cos(angle) * (0.17 + wobble)),
                y: Float(0.5 + sin(angle) * (0.09 - wobble * 0.25))
            )
        }

        XCTAssertNil(DrawingGestureRecognizer.circleGesture(in: points))
    }

    func testAccidentalSemicircleWithReturnIsNotRecognizedAsCircle() {
        var points: [(x: Float, y: Float)] = (0...32).map { index in
            let progress = Double(index) / 32
            let angle = progress * Double.pi
            return (
                x: Float(0.5 + cos(angle) * 0.18),
                y: Float(0.5 + sin(angle) * 0.13)
            )
        }
        points.append(contentsOf: (1...18).map { index in
            let progress = Double(index) / 18
            return (
                x: Float(0.32 + progress * 0.36),
                y: Float(0.5 + sin(progress * Double.pi) * 0.025)
            )
        })

        XCTAssertNil(DrawingGestureRecognizer.circleGesture(in: points))
    }

    func testEdgeSlidesKeepSideAndVerticalDirectionDistinct() {
        XCTAssertEqual(
            EdgeSlideGestureRecognizer.gesture(side: .left, startY: 0.25, currentY: 0.45),
            .leftEdgeSlideUp
        )
        XCTAssertEqual(
            EdgeSlideGestureRecognizer.gesture(side: .left, startY: 0.75, currentY: 0.55),
            .leftEdgeSlideDown
        )
        XCTAssertEqual(
            EdgeSlideGestureRecognizer.gesture(side: .right, startY: 0.25, currentY: 0.45),
            .rightEdgeSlideUp
        )
        XCTAssertEqual(
            EdgeSlideGestureRecognizer.gesture(side: .right, startY: 0.75, currentY: 0.55),
            .rightEdgeSlideDown
        )
    }

    func testEdgeSlideIgnoresSmallVerticalJitter() {
        XCTAssertNil(
            EdgeSlideGestureRecognizer.gesture(side: .left, startY: 0.50, currentY: 0.57)
        )
    }

    func testExpandedTrackpadZonesRemainDistinct() {
        XCTAssertEqual(
            TrackpadZoneGestureRecognizer.gesture(for: (x: 0.25, y: 0.75)),
            .cornerClickTopLeft
        )
        XCTAssertEqual(
            TrackpadZoneGestureRecognizer.gesture(for: (x: 0.75, y: 0.25)),
            .cornerClickBottomRight
        )
        XCTAssertEqual(
            TrackpadZoneGestureRecognizer.gesture(for: (x: 0.31, y: 0.76)),
            .middleClickTop
        )
        XCTAssertNil(
            TrackpadZoneGestureRecognizer.gesture(for: (x: 0.29, y: 0.71))
        )
    }

    func testCleaningUnlockRequiresTwoCommandChordsWithFullRelease() {
        var detector = CleaningUnlockDetector()
        let start = Date()

        XCTAssertEqual(detector.update(leftCommandDown: true, rightCommandDown: false, at: start), .none)
        XCTAssertEqual(detector.update(leftCommandDown: true, rightCommandDown: true, at: start), .progress(1))
        XCTAssertEqual(detector.update(leftCommandDown: false, rightCommandDown: true, at: start), .none)
        XCTAssertEqual(detector.update(leftCommandDown: false, rightCommandDown: false, at: start), .none)
        XCTAssertEqual(detector.update(leftCommandDown: true, rightCommandDown: true, at: start.addingTimeInterval(1)), .progress(2))
        XCTAssertEqual(detector.update(leftCommandDown: false, rightCommandDown: false, at: start.addingTimeInterval(1.1)), .unlocked)
    }

    func testCleaningUnlockChordExpires() {
        var detector = CleaningUnlockDetector()
        let start = Date()

        XCTAssertEqual(detector.update(leftCommandDown: true, rightCommandDown: true, at: start), .progress(1))
        XCTAssertEqual(detector.update(leftCommandDown: false, rightCommandDown: false, at: start), .none)
        XCTAssertEqual(detector.update(leftCommandDown: true, rightCommandDown: true, at: start.addingTimeInterval(5)), .progress(1))
    }

    func testPressDragRecognizerSupportsTwoAndThreeFingers() {
        XCTAssertEqual(
            PressDragGestureRecognizer.gesture(fingerCount: 2, dx: -0.08, dy: 0.01),
            .twoFingerPressDragLeft
        )
        XCTAssertEqual(
            PressDragGestureRecognizer.gesture(fingerCount: 2, dx: 0.08, dy: -0.01),
            .twoFingerPressDragRight
        )
        XCTAssertEqual(
            PressDragGestureRecognizer.gesture(fingerCount: 3, dx: -0.08, dy: 0.01),
            .threeFingerPressDragLeft
        )
        XCTAssertEqual(
            PressDragGestureRecognizer.gesture(fingerCount: 3, dx: 0.08, dy: -0.01),
            .threeFingerPressDragRight
        )
    }

    func testPressDragRecognizerRejectsVerticalMovement() {
        XCTAssertNil(PressDragGestureRecognizer.gesture(fingerCount: 3, dx: 0.03, dy: 0.09))
    }

    private func circlePoints(clockwise: Bool, completedTurns: Double = 1) -> [(x: Float, y: Float)] {
        let sampleCount = 64
        let direction = clockwise ? -1.0 : 1.0
        return (0...sampleCount).map { index in
            let progress = Double(index) / Double(sampleCount)
            let angle = direction * progress * completedTurns * 2 * Double.pi
            return (
                x: Float(0.5 + cos(angle) * 0.16),
                y: Float(0.5 + sin(angle) * 0.13)
            )
        }
    }

    private func makePresetStoreFixture() throws -> (
        root: URL,
        presetURL: URL,
        store: PresetStore
    ) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("TouchPilotPresetTests-\(UUID().uuidString)", isDirectory: true)
        let applicationSupportURL = root.appendingPathComponent("ApplicationSupport", isDirectory: true)
        let documentsURL = root.appendingPathComponent("Documents", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return (
            root,
            applicationSupportURL
                .appendingPathComponent("TouchPilot", isDirectory: true)
                .appendingPathComponent("preset.json"),
            PresetStore(
                applicationSupportBaseURL: applicationSupportURL,
                documentsBaseURL: documentsURL
            )
        )
    }
}

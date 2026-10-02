import AppKit
import Darwin
import XCTest

@MainActor
extension XCUIApplication {
    /// Launches OpenBibleAI for a UI test: saved window state is ignored and
    /// a window must appear. Fails at once, with a clear message, when a copy
    /// of the app is running under a debugger (an Xcode Run session), which
    /// XCUITest cannot terminate (it would wait 60 s, then fail). Other
    /// running copies, e.g. left by a failed test, are terminated as usual.
    func launchForUITest(
        arguments: [String] = [],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        if let blocking = Self.debuggedRunningCopy() {
            XCTFail(
                """
                OpenBibleAI is running under a debugger (pid \(blocking.processIdentifier)), probably an Xcode \
                Run/Debug session, and UI tests can't close it. Stop that session, or run the UI tests \
                with BUNDLE_ID_PREFIX=dev.openbibleai.search-tests to use a separate app.
                """,
                file: file,
                line: line
            )
            return
        }

        launchArguments += arguments + [
            "-ApplePersistenceIgnoreState", "YES",
            "-NSQuitAlwaysKeepsWindows", "NO"
        ]
        launch()
        activate()
        if !windows.firstMatch.waitForExistence(timeout: 5) {
            typeKey("n", modifierFlags: .command)
        }
        XCTAssertTrue(
            windows.firstMatch.waitForExistence(timeout: 10),
            "OpenBibleAI launched without a window; check that the app is not hidden or on a disconnected display",
            file: file,
            line: line
        )
    }

    /// The app's bundle ID, derived from the runner's
    /// (`<prefix>.OpenBibleAIUITests.xctrunner` → `<prefix>.OpenBibleAI`).
    static var appBundleIdentifier: String? {
        let suffix = ".OpenBibleAIUITests.xctrunner"
        guard let runner = Bundle.main.bundleIdentifier, runner.hasSuffix(suffix) else { return nil }
        return runner.dropLast(suffix.count) + ".OpenBibleAI"
    }

    /// A running copy of the app that a debugger is attached to.
    private static func debuggedRunningCopy() -> NSRunningApplication? {
        guard let identifier = appBundleIdentifier else { return nil }
        return NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
            .first { !$0.isTerminated && isTraced($0.processIdentifier) }
    }

    private static func isTraced(_ pid: pid_t) -> Bool {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0) == 0, size > 0 else { return false }
        return info.kp_proc.p_flag & P_TRACED != 0
    }
}

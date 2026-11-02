import SwiftUI
import ServiceManagement

@main
struct SundialApp: App {
    @NSApplicationDelegateAdaptor(SundialAppDelegate.self) private var appDelegate
    @StateObject private var appState: AppState
    private let controller: DDCController
    private let scheduler: Scheduler
    private let auto: AutoController
    private let lamps: LampController

    init() {
        let state = AppState()
        SundialAppDelegate.state = state
        let ctrl = DDCController(
            cliPath: state.cliPath,
            displayName: state.displayName
        )
        let sched = Scheduler()
        let autoCtrl = AutoController()
        let lampCtrl = LampController()

        EditFocus.endOnOtherClicks()

        // Wire callbacks before start so the scheduler can call them on first tick.
        Self.wire(state, sched, autoCtrl, lampCtrl)

        // Start immediately at app launch — registers wake observers and fires the
        // first tick so the correct preset is applied before any menu interaction.
        sched.start(state: state, controller: ctrl)
        autoCtrl.start(state: state, controller: ctrl)
        lampCtrl.start(state: state)

        // Reconcile the login item with the persisted preference. Registration can be
        // lost out from under us — e.g. the bundle moves, or a stale DerivedData
        // registration gets cleared — and the toggle's onChange only fires on user
        // interaction, so without this a "Launch at login: on" preference would
        // silently stop taking effect. DEBUG builds never claim the login item
        // (they run from an ephemeral DerivedData path); see SettingsView.
        #if !DEBUG
        if state.launchAtLogin, SMAppService.mainApp.status != .enabled {
            try? SMAppService.mainApp.register()
        }
        #endif

        _appState  = StateObject(wrappedValue: state)
        controller = ctrl
        scheduler  = sched
        auto       = autoCtrl
        lamps      = lampCtrl
    }

    /// The callbacks views use to reach the scheduler and Auto. Whichever owns
    /// the monitor takes it back when a preview ends.
    private static func wire(_ state: AppState, _ sched: Scheduler, _ auto: AutoController, _ lamps: LampController) {
        state.onPreviewEnded = { [weak state] in
            if state?.autoDrivesMonitor == true { auto.forceApply() } else { sched.reapplyForCurrentTime() }
        }
        state.onScheduleChanged = { sched.recompute() }
        state.onAutoChanged = { auto.refresh() }
        state.onSetBrightness = { auto.setBrightness($0, done: $1) }
        state.onSetContrast = { auto.setContrast($0, done: $1) }
        state.onPairLamps = { lamps.pair() }
        state.onLampsChanged = { lamps.refresh() }
        state.onPreviewLamps = { lamps.preview($0) }
        state.onEndLampPreview = { lamps.endPreview() }
        state.onRenameBulb = { lamps.rename(device: $0, to: $1) }
        state.onOpenWindow = { [weak state] in
            if let state { MainWindow.show(state) }
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appState)
                .onAppear {
                    // Keep controller in sync with any settings changes made since launch.
                    controller.cliPath   = appState.cliPath
                    controller.displayName = appState.displayName
                    // start() is guarded — no-op on every open after the first.
                    scheduler.start(state: appState, controller: controller)
                    auto.start(state: appState, controller: controller)
                }
        } label: {
            Label("Sundial", systemImage: "sun.max")
        }
        .menuBarExtraStyle(.window)
    }
}

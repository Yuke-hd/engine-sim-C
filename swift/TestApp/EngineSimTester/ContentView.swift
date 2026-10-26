import SwiftUI

struct ContentView: View {
    @StateObject private var player = EnginePlayer()
    @State private var engine: EngineChoice = .lsV8
    @State private var leveler: LevelerChoice = .rpmScaled
    @State private var frequency: Int32 = 10000
    @State private var rpm: Double = 1000
    @State private var throttle: Double = 0.5
    @State private var overrun = true
    @State private var overrunGain: Double = 1
    @State private var sweeping = false
    @State private var sweepTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            Form {
                Section("Engine") {
                    Picker("Engine", selection: $engine) {
                        ForEach(EngineChoice.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Picker("Simulation", selection: $frequency) {
                        Text("10 kHz").tag(Int32(10000))
                        Text("5 kHz").tag(Int32(5000))
                    }
                    .pickerStyle(.segmented)
                    Button(player.isRunning ? "Stop" : "Start") {
                        if player.isRunning { stopSweep(); player.stop() } else { start() }
                    }
                }

                Section("Leveler") {
                    Picker("Leveler", selection: $leveler) {
                        ForEach(LevelerChoice.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                Section("RPM") {
                    Text("Target \(Int(rpm)) · actual \(Int(player.actualRpm))")
                        .monospacedDigit()
                    Slider(value: $rpm, in: 800...engine.maxRpm, step: 50)
                        .disabled(sweeping)
                    Button(sweeping ? "Stop sweep" : "Sweep 1000 → \(Int(engine.sweepTopRpm)) rpm (10 s)") {
                        sweeping ? stopSweep() : startSweep()
                    }
                    .disabled(!player.isRunning)
                }

                Section("Throttle") {
                    Text("Throttle \(Int(throttle * 100))%")
                        .monospacedDigit()
                    Slider(value: $throttle, in: 0...1, step: 0.01)
                    // Hold for full throttle; letting go snaps to 0, a lift-off.
                    Text("Hold to rev")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(throttle == 1 ? Color.accentColor : Color.secondary.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .gesture(DragGesture(minimumDistance: 0)
                            .onChanged { _ in throttle = 1 }
                            .onEnded { _ in throttle = 0 })
                }

                Section("Overrun") {
                    Toggle("Pops and crackle on lift-off", isOn: $overrun)
                    Text("Gain \(overrunGain, specifier: "%.1f")x · \(player.overrunActive ? "overrunning" : "idle")")
                        .monospacedDigit()
                    Slider(value: $overrunGain, in: 0...3, step: 0.1)
                    Text("Lift the throttle below 5% above 2000 rpm. Raise it past 20% to re-arm.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Performance") {
                    Text(String(format: "%.2fx real time", player.realTimeFactor))
                        .monospacedDigit()
                        .foregroundStyle(player.isRunning && player.realTimeFactor < 1 ? .red : .primary)
                }
            }
            .navigationTitle("Engine Sim")
        }
        .onChange(of: rpm) { _, value in player.setTargetRpm(value) }
        .onChange(of: throttle) { _, value in player.setThrottle(value) }
        .onChange(of: overrun) { _, value in player.setOverrun(enabled: value, gain: overrunGain) }
        .onChange(of: overrunGain) { _, value in player.setOverrun(enabled: overrun, gain: value) }
        .onChange(of: leveler) { _, value in player.setLeveler(value) }
        .onChange(of: engine) { _, value in
            stopSweep()
            rpm = min(rpm, value.maxRpm)
            if player.isRunning { start() }
        }
        .onChange(of: frequency) { _, _ in if player.isRunning { start() } }
    }

    private func start() {
        player.setTargetRpm(rpm)
        player.setThrottle(throttle)
        player.setOverrun(enabled: overrun, gain: overrunGain)
        player.setLeveler(leveler)
        player.start(engine: engine, frequency: frequency)
    }

    private func startSweep() {
        sweeping = true
        sweepTask = Task { @MainActor in
            let steps = 100
            for i in 0...steps {
                if Task.isCancelled { break }
                rpm = 1000 + (engine.sweepTopRpm - 1000) * Double(i) / Double(steps)
                try? await Task.sleep(for: .milliseconds(100))
            }
            sweeping = false
        }
    }

    private func stopSweep() {
        sweepTask?.cancel()
        sweepTask = nil
        sweeping = false
    }
}

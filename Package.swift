// swift-tools-version: 5.9
import PackageDescription

// SwiftPM wrapper around the engine-sim simulation and synthesizer core, with a
// C API (swift/include/EngineSimCore.h) and a hand-ported GM LS V8. The UI,
// scripting and delta-studio parts of engine-sim are not built here. Initialise
// only the solver submodule:
//   git submodule update --init dependencies/submodules/simple-2d-constraint-solver
let solver = "dependencies/submodules/simple-2d-constraint-solver/src"

let package = Package(
    name: "EngineSim",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "EngineSim", targets: ["EngineSimCore"]),
        // A second product makes SwiftPM expose the `EngineSim-Package` scheme.
        .library(name: "EngineSimCore", targets: ["EngineSimCore"]),
        .library(name: "EngineSound", targets: ["EngineSound"]),
    ],
    targets: [
        .target(name: "EngineSound"),
        .target(
            name: "EngineSimCore",
            path: ".",
            sources: [
            "src/audio_buffer.cpp",
            "src/camshaft.cpp",
            "src/combustion_chamber.cpp",
            "src/connecting_rod.cpp",
            "src/convolution_filter.cpp",
            "src/crankshaft.cpp",
            "src/cylinder_bank.cpp",
            "src/cylinder_head.cpp",
            "src/delay_filter.cpp",
            "src/derivative_filter.cpp",
            "src/direct_throttle_linkage.cpp",
            "src/dynamometer.cpp",
            "src/engine.cpp",
            "src/exhaust_system.cpp",
            "src/feedback_comb_filter.cpp",
            "src/filter.cpp",
            "src/fuel.cpp",
            "src/function.cpp",
            "src/gas_system.cpp",
            "src/gaussian_filter.cpp",
            "src/governor.cpp",
            "src/ignition_module.cpp",
            "src/impulse_response.cpp",
            "src/intake.cpp",
            "src/jitter_filter.cpp",
            "src/leveling_filter.cpp",
            "src/low_pass_filter.cpp",
            "src/part.cpp",
            "src/piston.cpp",
            "src/piston_engine_simulator.cpp",
            "src/simulator.cpp",
            "src/standard_valvetrain.cpp",
            "src/starter_motor.cpp",
            "src/synthesizer.cpp",
            "src/throttle.cpp",
            "src/transmission.cpp",
            "src/utilities.cpp",
            "src/valvetrain.cpp",
            "src/vehicle.cpp",
            "src/vehicle_drag_constraint.cpp",
            "src/vtec_valvetrain.cpp",
                solver,
                "swift/engine_sim_core.cpp",
                "swift/ls_v8_builder.cpp",
                "swift/wav_reader.cpp",
                "swift/ls_v8_impulse_response.cpp",
            ],
            publicHeadersPath: "swift/include",
            cxxSettings: [
                .headerSearchPath("include"),
                .headerSearchPath("swift"),
                .define("__forceinline", to: "inline"),
                // Upstream templates rely on MSVC-style delayed template parsing.
                // The solver submodule uses memset/memcpy without declaring them.
                .unsafeFlags(["-include", "string.h", "-fdelayed-template-parsing"]),
            ],
            linkerSettings: [.linkedLibrary("c++")]
        ),
        .testTarget(
            name: "EngineSimCoreTests",
            dependencies: ["EngineSimCore"],
            path: "swift/Tests/EngineSimCoreTests"
        ),
    ],
    cxxLanguageStandard: .cxx17
)

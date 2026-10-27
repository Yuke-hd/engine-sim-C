# EngineSimTester

An iPhone demo for the `EngineSimCore` C API. It has:

- an engine picker: GM LS V8, Ferrari F136 or Mercedes-AMG M177;
- RPM and throttle sliders, plus a "Hold to rev" button;
- a switch between the RMS and peak levelers;
- an overrun layer (pops and crackle on lift-off), using the samples in
  `EngineSimTester/Overrun/`.

## Build and install

1. Copy `local.env.example` to `local.env`.
2. Fill in your bundle ID, signing identity, team ID and device UDID.
   `local.env` is gitignored.
3. Run one of the two scripts:
   - `./build_manual.sh` builds with `clang++` and `swiftc`, then signs,
     installs and launches the app with `devicectl`. Use it when
     `xcodebuild`'s build service hangs. It needs an existing provisioning
     profile for the bundle ID.
   - `./install.sh` builds with `xcodebuild -allowProvisioningUpdates` and
     installs the result.

Both scripts expect a connected, unlocked device. To regenerate the Xcode
project, run `xcodegen` with `project.yml`.

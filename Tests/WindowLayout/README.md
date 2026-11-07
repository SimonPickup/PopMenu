# Window-layout regression tests

Run on a Mac with Xcode selected:

```sh
python3 scripts/test_window_layout.py
```

The runner first typechecks production sources against the existing CocoaPods/Xcode iOS 10 minimum in Swift 4.2 and Swift 5 modes, then compiles all production Swift files against the host's real Catalyst UIKit. It does not start an app, native window, scene or simulator and does not require signing, provisioning, package installation or network access. Temporary files are removed after execution; `TMPDIR` can select a scratch location.

Coverage includes presentation-local source conversion, optional tap-point placement and bounds fallback, backdrop/blur coverage, repeated resizing, safe-area fitting, natural row heights and scrolling, detached-source retention, nested menus and the actual presentation/dismissal animators.

Production method bodies are not rewritten. A same-file test extension allows installation of a real UIView with explicitly scripted safe-area insets. Layout callbacks are delivered explicitly and the transition-context object is a test fixture. The suite establishes native UIKit method behaviour, not live scene lifecycle, real pointer delivery or visual acceptance on a device. Existing vendor/compiler deprecation warnings are not hidden.

The deployment target and package metadata remain unchanged. Availability of APIs added after the declared minimum must be guarded rather than relying on the test host's newer OS. The pre-existing SwiftPM declaration of iOS 9 is not qualified: the unchanged baseline's Haptics types already require iOS 10. This focused repair does not change that metadata or claim iOS 9 compatibility.

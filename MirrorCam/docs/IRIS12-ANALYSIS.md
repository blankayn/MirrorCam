# Iris12 0.0.2 static analysis

Date: 9 October 2026. Source: Michael Melita's official repository, package `com.michaelmelita1.iris12`, version 0.0.2. SHA-256: `afcbd6936c732eba284fffc22fc6ce1f552e1c8a678bda53b5b05c44c1904282`.

The downloaded Debian package was parsed without executing or loading its dylib. Its package control declares MobileSubstrate and firmware >= 11.0. The binary plist limits injection to bundle `com.apple.camera`. The arm64 Mach-O has 160 bytes in its code section and imports `MSHookMessageEx` and `objc_getClass`. Its constructor hooks:

| Class | Instance method | Replacement behavior |
|---|---|---|
| CAMCaptureCapabilities | isBackIrisSupported | Return YES |
| CAMCaptureCapabilities | isFrontIrisSupported | Return YES |
| AVCaptureDeviceFormat | isIrisSupported | Return YES |

The three replacement functions at addresses `0x7ee8`, `0x7ef0`, and `0x7ef8` each contain `mov w0, #1; ret`. Iris12 provides no encoder, rolling buffer or file-pairing implementation; it exposes an existing camera pipeline through capability overrides.

Run `python scripts/analyze-iris12.py` to repeat the package hash, filter, imported symbol, constructor and constant-return analysis. A small dependency-free arm64 decoder derives each class/selector/replacement association from the constructor at `0x7e60`; it rejects unrecognized instructions. The script writes its report under ignored `build/iris12-analysis`; it does not execute the package. The original third-party dylib and Debian package are not included in MirrorCam or its source archive.

## MirrorCam 1.2 experiment

`IrisCompatibility.m` independently implements the observed capability-return behavior with the Objective-C runtime. It changes methods only in MirrorCam's process, preserves their original implementations, checks signatures, restores them when disabled, and requires no MobileSubstrate. CameraUI classes may be absent from this app; the AVFoundation format hook is attempted when its method exists. The experiment is restricted to iOS 12 and is off at launch.

After the opt-in hook, MirrorCam configures the photo preset and checks AVFoundation's `isLivePhotoCaptureSupported`/enabled flags. If accepted, the LIVE shutter uses `AVCapturePhotoOutput`'s native JPEG/MOV capture, preserving Apple's original resource pairing/orientation metadata. This route uses full 4:3 framing and maximum photo resolution; software LIVE retains all framing controls. Objective-C exceptions, reported capture/session errors and a ten-second capture timeout return to the software route. Interrupted/background captures are cancelled.

This does not inject code into Apple Camera, modify system files, or jailbreak the phone. An app-only capability override may still be rejected by the capture services. A true capability flag and a successful build do not establish successful native capture on an iPhone 6. Photos pairing, front/rear framing, audio, performance and interruption handling must be tested on the actual device. If the private method is absent or the native pipeline rejects capture, use software LIVE.

References: [Michael Melita's repository](https://michaelmelita1.github.io/), [Apple camera compatibility table](https://developer.apple.com/library/archive/documentation/DeviceInformation/Reference/iOSDeviceCompatibility/Cameras/Cameras.html), [Apple native Live Photo capture](https://developer.apple.com/documentation/avfoundation/capturing-and-saving-live-photos).

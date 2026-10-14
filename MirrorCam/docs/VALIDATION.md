# Validation record

Date: 9 October 2026 (Asia/Manila). Local environment: Windows, Python 3.11. Cloud build: GitHub-hosted macOS, Xcode 15.4.

Executed successfully:

- `python scripts/generate-icons.py`: generated eight opaque RGB PNG app icons; inspected the rendered icon visually.
- `python scripts/validate-project.py`: **100 structural/syntax checks passed across eight Swift source files** using tree-sitter 0.25.2 / tree-sitter-swift 0.7.4.
- `bash -n scripts/build-ipa.sh`: Bash script parses successfully using the installed Git Bash.

The validator parses the OpenStep project, resolves object references and source-phase membership, checks all deployment configurations, parses plist/storyboard/scheme XML, verifies privacy descriptions, and checks icon pixel dimensions. Swift parsing detects syntax errors only. It does not resolve Apple framework types, validate API availability, compile code, or exercise camera/PhotoKit behavior.

The [GitHub Actions run 37889696067](https://github.com/blankayn/MirrorCam/actions/runs/37889696067) successfully compiled the Release iOS app with Xcode 15.4 at commit `b6a3bb491de26685edca5c56537b6644d61093b4`. The log reports `BUILD SUCCEEDED`, a minimum OS version of `12.0`, and an `arm64` app executable. The build script packaged an unsigned IPA, including the embedded Swift compatibility libraries. The downloaded artifact ZIP matched GitHub's SHA-256 digest: `8f51304e5767b0637fc92e1eaabffe6721ebae081e84fa72ae3e6f0248644bb8`.

**Not performed:** code signing, installation, simulator execution, or any physical iPhone test. Hardware encoder behavior, camera format selection, photo mirroring metadata, audio sync, rolling-buffer timing and interruption recovery require the physical-device checklist in `DEVICE-TESTS.md`. A successful compilation does not establish these runtime behaviors.

## Version 1.1

- Local validation: **110 structural/syntax checks passed across ten Swift files**.
- [Cloud run 37899096832](https://github.com/blankayn/MirrorCam/actions/runs/37899096832) at commit `ac1b0abb2d16ed841f459348329f60df360df94b`: Xcode 15.4 Release iphoneos build succeeded; minimum OS 12.0, arm64, app version 1.1 (build 2).
- **172 synthetic media assertions passed** on macOS using the actual `FrameGeometry`, `RollingBuffer`, `ClipWriter` and `PhotoFraming` implementations. Checks covered portrait/landscape crops, no resolution upscaling, even encoder dimensions, four JPEG orientation values, normalized mirrored pixels, output sizes, bounded pre-roll, three-second clip duration, matching JPEG/MOV content identifiers, key-photo time at 1.4667 seconds, and PhotoKit recognition of 4:3, square and 16:9 pairs as Live Photos.
- Downloaded IPA archive integrity and Info.plist/version/arm64 checks passed. Artifact ZIP SHA-256: `8a38d5a2ed8c6e4e3b1e35b1c68f3fc5d220ffd78cba9882919c4d979d88ac43`, matching GitHub's digest.

The user confirmed version 1.0 installs and launches on the iPhone. No simulator test or physical-device test of version 1.1 was performed. Synthetic PhotoKit recognition on macOS does not establish iOS 12 Photos-library import, touch-and-hold playback, actual camera field of view, microphone sync or device performance. Run `DEVICE-TESTS.md` on the iPhone 6 after installation.

## Version 1.2

- Local validation: **118 structural/syntax checks passed across ten Swift files**. This includes Objective-C source membership and bridging-header references; Objective-C compilation is not validated on Windows.
- Iris12 0.0.2 was statically analyzed from the author's repository without executing its code. Package hash, filter, arm64 code and observed hook targets are recorded in `IRIS12-ANALYSIS.md`.
- Native Live Photo delegates, session reconfiguration, error cleanup and bridging were reviewed. No native-hook execution, simulator execution or physical iPhone test has been performed. The existing synthetic media tests exercise the software path, not the Iris12 hook or native camera pipeline.
- [Cloud run 37902485260](https://github.com/blankayn/MirrorCam/actions/runs/37902485260) at commit `fa9c41449822ead203973c8d5f8af684ec064f67`: Xcode 15.4 Release iphoneos build succeeded, including Objective-C runtime hooks and Swift bridging. Cloud structural validation passed 108 checks; all **172 software media assertions passed**. The local parser adds ten Swift syntax checks.
- Downloaded IPA: version 1.2 (build 3), arm64, minimum OS 12.0 in both Info.plist and Mach-O, embedded Swift libraries present, archive integrity verified. Artifact ZIP SHA-256: `3a9752f063497178faeb27c09ab4f0da31b8af5e0ea9c592b89c7cc549969659`, matching GitHub's digest.

## Version 1.3

- Windows validation passed **123 structural/syntax checks across eleven Swift files**.
- Camera layout follows a 44 + 500 + 123-point photo layout at standard iPhone 6 display size. No UIKit runtime/layout or physical-device check has been performed yet.
- [Cloud run 37947966167](https://github.com/blankayn/MirrorCam/actions/runs/37947966167) at commit `48a3c26bcb943978b906b4a3d8dfb7b051be4dad`: Xcode 15.4 Release iphoneos build succeeded. Cloud project validation passed 112 checks; all **194 synthetic media assertions passed** (172 existing media assertions and 22 added HDR assertions/fixture checks).
- New HDR checks executed the actual processor: horizontal and vertical translation, merge/tone mapping, clipped-highlight recovery, shadow detail, EXIF exposure ratios, mirror normalization, all three aspect crops, incomplete brackets and the 1600-pixel processing bound. Registration uses a bounded search on exposure-normalized 160-pixel thumbnails; full output framing remains anchored to the normal exposure.
- Downloaded IPA archive integrity passed; Info.plist and Mach-O verify version 1.3 (build 4), arm64 and minimum OS 12.0. Embedded Swift libraries are present. Artifact ZIP SHA-256 `3e00e2b0d0c14d9a5a5f40847f29ce628133a891b99262e4dcf5fd6613e1f493` matches GitHub's digest.

No simulator or physical iPhone 6 test of version 1.3 has been performed. Synthetic HDR inputs do not establish actual camera bracketing support, handheld image quality, latency, memory use or Photos saving. Screen geometry and library-header visibility require the device checklist.

## Version 1.4

- Windows validation passed **123 structural/syntax checks across eleven Swift files** on 11 October 2026.
- Mirror On/Off now sets the front preview and capture connections together. The UI waits for the engine to accept the setting and remembers it in UserDefaults. Rear preview remains unmirrored; software LIVE clears its buffer when the setting changes.
- [Cloud run 38128559126](https://github.com/blankayn/MirrorCam/actions/runs/38128559126) at commit `1c71d540307d194815a17eaad7dcea75e83b9d7a`: Xcode 15.4 Release iphoneos build succeeded; all **194 existing synthetic media assertions passed**. Cloud project validation passed 112 checks.
- Downloaded IPA archive integrity passed: version 1.4 (build 5), arm64, minimum OS 12.0 in Info.plist and Mach-O, and 17 embedded Swift libraries. Artifact ZIP SHA-256 `9145f150d2dd8e8725c34f703d8773d19f7b9921fe5a52f907e7963872d2eed1` matches GitHub's digest. IPA SHA-256: `68020c113642b6c142c208e2a3e5b78c161352ddf6750a0d75c7386c8dd69503`.

No simulator or physical-device check of version 1.4 was performed. Existing software media tests cover geometry, image orientation, HDR and LIVE resource generation; they do not exercise the live camera preview, hardware mirroring or preference persistence. Verify readable text in preview and saved media with Mirror Off, then relaunch and switch modes/lenses using `DEVICE-TESTS.md`.

## Version 1.5

- Added Photos import and a horizontal-flip preview in Library. Create flipped copy stores a new still image without modifying the source or a LIVE clip. All EXIF orientations normalize before the horizontal transform; JPEG copies retain the full frame and decode at up to 2048 pixels.
- Windows structural/syntax validation passed **123 checks across eleven Swift files**.
- [Cloud run 38129097788](https://github.com/blankayn/MirrorCam/actions/runs/38129097788) at commit `2ce0d92701d417dc608822b99e8f32eff41956ab`: Xcode 15.4 Release iphoneos build succeeded; **245 synthetic media assertions passed**. These include the previous 194 and 51 additional fixture/editing assertions covering all eight EXIF orientations, horizontal reversal without vertical inversion, two flips restoring composition, full framing, removal of pairing metadata, bounded decoding and invalid input.
- Downloaded IPA verified: version 1.5 (build 6), arm64, minimum OS 12.0 in Info.plist and Mach-O, 17 embedded Swift libraries and valid ZIP integrity. Artifact ZIP SHA-256 `3bded68ca94a59808af955099b7a4de78e27d02dcfc242da8a8bbfd8b704e6ec` matches GitHub's digest. IPA SHA-256: `c6c206301ae4f3a67a532059d51be500d5f1b56eb708619cc6c5c8318f655507`.

No simulator or physical-device execution of version 1.5 was performed. Photos import (including iCloud/HEIC), permission recovery, UI preview, device memory use and saving the new copy into iOS 12 Photos remain pending in `DEVICE-TESTS.md`.

## Version 1.6

14 October 2026: Windows validation passed **122 structural/syntax checks across twelve Swift files**. The app target has no Objective-C hook source, bridging header or Iris capability calls. The new public-API helper validates generated resources, times out preview loading and records bounded logs. Saved Photos identifiers and subtype verification state are optional fields for backward-compatible local JSON.

[Cloud run 38509868184](https://github.com/blankayn/MirrorCam/actions/runs/38509868184) at commit `1340dd0e2ee305903a71c21914147955a75aa6b3`: Xcode 15.4 Release iphoneos build succeeded. Cloud validation passed 110 structural checks; **270 synthetic media assertions passed** (245 earlier assertions plus 25 additional LIVE checks). These exercised actual generated JPEG/MOV pairing, typed key-photo timing, rejection of mismatched/missing identifiers and absent timed tracks, pre-roll discontinuity recovery, marker requirements and three-second H.264/AAC writing with a shared audio/video timeline. Existing macOS `PHLivePhoto` resource recognition also passed for all three aspects. macOS deprecation warnings for synchronous AVFoundation APIs are expected because the implementation retains iOS 12 APIs.

Downloaded IPA verification passed: version 1.6 (build 7), arm64, minimum OS 12.0 in both Info.plist and Mach-O, ZIP integrity valid, 17 embedded Swift libraries. The former Iris hook/class marker strings were absent from the app executable. Artifact ZIP SHA-256 `47092b8e4f83261b54e20ee869cf7a2adc585d2836ad2eb6ba29eac6867bc413` matches GitHub's digest. IPA SHA-256: `7ee4007c8d140cd38a11cec1d9a1e56a560187bd40bd159b966d0b4e2db48abe`.

No simulator execution, iOS 12 Photos asset import/subtype verification, physical-device playback or Instagram test has been performed. Follow `LIVE-PHOTOS.md` for the separate device acceptance checks; the historical records above describe older builds, including the removed experiment.

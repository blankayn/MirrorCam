# MirrorCam

A native Swift / UIKit camera project for **iPhone 6, iOS 12.0 or later**. Uses AVFoundation, PhotoKit and AVKit; no SwiftUI, package manager, network service, or third-party runtime dependency.

**Build status:** Xcode 15.4 successfully built the Release arm64 iOS app on GitHub's macOS runner on 9 October 2026. [Download the unsigned IPA artifact](https://github.com/blankayn/MirrorCam/actions/runs/37889696067/artifacts/11597787130), extract its ZIP, and sign/install the IPA with Sideloadly. This artifact expires on 16 October; run the workflow again for a fresh download. Structural checks and Swift syntax parsing also passed. No simulator or physical-device tests have been performed. See `docs/VALIDATION.md`.

## What is implemented

| Mode / feature | Behavior |
|---|---|
| Photo | Full-resolution JPEG capture using `AVCapturePhotoOutput` and the photo preset. The front camera's resolution is limited by its hardware. |
| Mirror | Front preview is always mirrored. **Mirror On/Off** controls saved front-camera JPEGs and videos. Rear-camera output remains normal. |
| Video | H.264 MP4, target 720p / 30 fps, AAC microphone audio when permitted, start/stop shutter, elapsed timer. Rear flash On uses the torch during recording. |
| Motion | JPEG + MP4 pair. VGA video at a target 15 fps, approximately 1.5 seconds before and after shutter. A small rolling buffer continuously runs only in Motion mode. |
| Controls | Front/back switch, thirds grid, 0 / 3 / 10 second countdown, flash Off/Auto/On for photos where supported, flash Off/On for video, pinch zoom capped at 4× or the hardware limit. |
| Library | Local persistent gallery, still preview, video playback, sharing, save to Photos, and local deletion. |
| Permissions | Camera required. Microphone requested on first entering Video/Motion; denial allows silent recording. Photos requested when **Save to Photos** is pressed; denial preserves the local capture. |

The iPhone 6 does not support native Live Photo capture. Motion is deliberately a compatible **still + separate video**, displayed together inside MirrorCam. Saving a Motion item creates two assets in Photos. It does not create Apple's press-and-hold Live Photo format.

The UI stays in portrait for a stable camera layout. Device rotation controls the saved photo/video orientation, and recording locks orientation and mirroring until capture finishes. Video buffers are physically rotated/mirrored by the data-output connection; photo mirroring/orientation is carried by the JPEG's standard metadata. Preview fills the screen and crops its edges; saved media uses the full capture frame, so the saved framing can be wider than the preview. Apple's [capture-connection documentation](https://developer.apple.com/documentation/avfoundation/avcaptureconnection/isvideomirrored) describes these output differences.

## Project files

```text
MirrorCam/
├── MirrorCam.xcodeproj/
│   ├── project.pbxproj
│   └── xcshareddata/xcschemes/MirrorCam.xcscheme
├── MirrorCam/
│   ├── AppDelegate.swift
│   ├── CameraEngine.swift
│   ├── ClipWriter.swift
│   ├── RollingBuffer.swift
│   ├── CameraViewController.swift
│   ├── CameraViews.swift
│   ├── MediaStore.swift
│   ├── GalleryViewController.swift
│   ├── Info.plist
│   ├── LaunchScreen.storyboard
│   └── Assets.xcassets/             # Includes all required iPhone icons
├── scripts/
│   ├── build-ipa.sh
│   ├── validate-project.py
│   └── generate-icons.py
└── docs/
    ├── DEVICE-TESTS.md
    └── VALIDATION.md
```

Main app UI is programmatic Auto Layout. The storyboard is only the launch screen. Swift automatically links imported Apple frameworks. Deployment target is set to 12.0 in both project and target Debug/Release configurations; device family is iPhone. Signing team is intentionally empty for you to select.

## Edit on Windows

Open this `MirrorCam` directory in VS Code. Edit `.swift` sources, plist, and the checked-in Xcode project. If you add Swift files, also add their file/build references in Xcode on the Mac. Windows cannot compile UIKit/AVFoundation or produce an iOS IPA.

With Python 3 installed:

```powershell
python scripts/validate-project.py
```

The optional syntax parser can be installed entirely inside the ignored build directory:

```powershell
python -m pip install --target build/validation-tools --only-binary=:all: tree-sitter==0.25.2 tree-sitter-swift==0.7.4
python scripts/validate-project.py
```

The default VS Code test task runs this validation. This parser checks syntax, not Apple API signatures or deployment availability. The icons are already included; regenerating them uses `python scripts/generate-icons.py` with Pillow installed.

Run `python scripts/package-source.py` to create `build/MirrorCam-source.zip` for transfer to the Mac. This includes the complete source project and excludes build products and local validation dependencies.

## Build on macOS

**No Mac of your own?** Use the included GitHub Actions cloud build from Windows. A project push to main starts a build, and a manual Run workflow button is also available. Follow [`docs/CLOUD-BUILD.md`](docs/CLOUD-BUILD.md), download the resulting IPA, then install with Sideloadly. The compatible GitHub runner currently retires on 2 November 2026, so check the guide's availability note.

Use a Mac you own or a macOS build host. Copy the entire project directory, including assets and shared scheme, from Windows. Use **Xcode 15.4 on a supported macOS Sonoma installation**, or Xcode 14 on its supported macOS version. These versions support an iOS 12 deployment target. Current Xcode generations raise the minimum supported deployment target; do not change this project's target to match them. Consult Apple's [Xcode system requirements](https://developer.apple.com/xcode/system-requirements/) and [Xcode downloads](https://developer.apple.com/download/all/) for the matching archive.

Select your Xcode installation for the current terminal (adjust the path to the actual app):

```bash
export DEVELOPER_DIR=/Applications/Xcode_15.4.app/Contents/Developer
xcodebuild -version
```

Open `MirrorCam.xcodeproj`, choose the **MirrorCam** scheme, and verify the target's iOS Deployment Target is **12.0**. For direct device running, add your Apple ID in Xcode Settings → Accounts, select a signing Team under Signing & Capabilities, and replace `com.example.MirrorCam` with your unique bundle identifier. Connect/trust the iPhone and build/run. A simulator can inspect the UI but cannot validate this camera pipeline.

### Route A: unsigned build, sign with Sideloadly on Windows

This route works without setting a development team on the Mac. Run from the project directory:

```bash
bash scripts/build-ipa.sh sideload
```

The script builds **Release for iphoneos/arm64**, checks the product exists, and packages `Payload/MirrorCam.app` into `build/MirrorCam-unsigned.ipa`. Embedded Swift libraries are included by the target for early iOS 12 releases. The IPA is not installable until Sideloadly signs it. The script stops if `xcodebuild` fails; keep the full build log if an SDK/compiler error needs fixing.

### Route B: signed development IPA on macOS

For a developer team with a valid development certificate/provisioning profile and the iPhone's UDID registered:

```bash
bash scripts/build-ipa.sh signed ABCDE12345 com.yourname.MirrorCam
```

Replace the example team ID and bundle ID. Xcode must have access to your account/certificate in its account settings/keychain. The script archives and exports a signed development IPA to `build/Signed/MirrorCam.ipa` using automatic signing. Export can require paid developer membership and a matching registered device; a Personal Team's export options are restricted. Use Route A and Sideloadly for a free-account workflow.

The same archive/export can be done through Product → Archive → Organizer → Distribute App → Development (or Debugging in the newer Xcode 15 export UI), selecting the team/profile. A signed development IPA only installs as-is on devices allowed by its profile. Sideloadly can re-sign it for its selected account/device.

## Install from Windows with Sideloadly

1. Download [Sideloadly from its official site](https://sideloadly.io/). Follow that site's Windows prerequisites, including its linked Apple web installers for iTunes/iCloud if needed. Its [official FAQ](https://sideloadly.io/faq.html) documents driver/detection issues and confirms iOS 12 support.
2. Copy the built IPA from the Mac to Windows. Connect the unlocked iPhone 6 with USB, approve **Trust This Computer**, and confirm iTunes/Sideloadly detects it.
3. Select the device in Sideloadly, choose the MirrorCam IPA, and enter your Apple ID directly in Sideloadly. Press **Start** and complete any login/verification prompt there.
4. After installation, on iOS 12 go to Settings → General → Profiles & Device Management (wording varies slightly), select the developer profile, and trust it.
5. Open MirrorCam and grant Camera. Enter Video/Motion to grant Microphone. Take a capture, open Library, and press Save to Photos to grant Photos access.

Free-account signing normally expires after 7 days and is subject to Apple's app limits. Refresh/reinstall with the same Apple ID and bundle ID to preserve the app container; save important captures to Photos first. The [Sideloadly FAQ](https://sideloadly.io/faq.html) describes expiry and overwrite behavior. Deleting the app deletes captures stored only in its local library.

## Motion and performance details

All capture-session mutation and sample-buffer handling runs on one serial queue. Heavy disk work uses a separate media queue; UI updates run on the main queue. Motion copies YUV pixels out of capture's reusable pool, retaining at most 25 VGA frames (around 12 MB plus padding) and a bounded audio window. The writer drains bounded queues to preserve pre-roll while the hardware encoder starts; video backpressure can drop frames rather than accumulate memory indefinitely. JPEG thumbnails are downsampled for the gallery.

Entering Motion, switching lenses, rotating, toggling mirroring, or returning from the background resets the pre-roll. Wait for **Motion ready** for a full lead-in; early captures have a shorter lead-in. High-resolution photo processing is used in Photo mode; Motion uses the active capture format's ordinary still resolution to reduce video stalls. Flash is disabled in Motion. Slow hardware, interruptions, and dropped frames can affect the exact clip length; the target is approximately three seconds, not frame-accurate native Live Photo timing.

Leaving the app stops video and attempts to finalize it with a short background task. In-progress Motion capture is cancelled on interruptions/backgrounding. The app does not continue camera capture in the background. Captures are stored under Application Support/Captures, each with media, a thumbnail, and JSON metadata. Save to Photos is explicit and retries retain the local copy. Local deletion does not delete assets already in Photos.

Before calling this ready for use, successfully build it and run `docs/DEVICE-TESTS.md` on the actual iPhone 6/iOS 12 device, including audio sync, all orientations, pre-roll, and interruption behavior.

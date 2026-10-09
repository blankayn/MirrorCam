# MirrorCam

A native Swift / UIKit camera project for **iPhone 6, iOS 12.0 or later**. Uses AVFoundation, PhotoKit and AVKit; no SwiftUI, package manager, network service, or third-party runtime dependency.

**Build status:** [Version 1.3 compiled successfully with Xcode 15.4](https://github.com/blankayn/MirrorCam/actions/runs/37947966167) for arm64 / iOS 12.0 and passed all **194 synthetic media assertions**, including actual HDR merging and horizontal/vertical alignment. [Download the unsigned IPA artifact](https://github.com/blankayn/MirrorCam/actions/runs/37947966167/artifacts/11624368967), extract its ZIP and sign with Sideloadly; the artifact expires on 16 October 2026. Version 1.0 was installed and launched by the user. Actual HDR camera capture, the new layout, the Iris12 experiment and Photos saving/playback need checks on the iPhone 6. See `docs/VALIDATION.md`.

## What is implemented

| Mode / feature | Behavior |
|---|---|
| Photo | Full-resolution JPEG capture using `AVCapturePhotoOutput` and the photo preset. The front camera's resolution is limited by its hardware. |
| HDR | Photo-only Off/On control where three-exposure bracketing is supported. Combines dark/normal/bright exposures, translation alignment and tone mapping into one JPEG. Flash stays off, HDR has a 1600-pixel maximum long edge; a failed merge saves a regular photo with a message. |
| Mirror | Front preview is always mirrored. **Mirror On/Off** controls saved front-camera JPEGs and videos. Rear-camera output remains normal. |
| Video | H.264 MP4, target 720p / 30 fps, AAC microphone audio when permitted, start/stop shutter, elapsed timer. Rear flash On uses the torch during recording. |
| LIVE | Software-created JPEG + MOV Live Photo, VGA video at 15 fps, approximately 1.5 seconds before and after shutter. Touch and hold in Library to animate; Save to Photos imports a single Live Photo asset. |
| Iris12 experiment | Optional iOS 12 capability overrides reverse engineered from Michael Melita's Iris12 0.0.2. Tries native `AVCapturePhotoOutput` Live Photos inside MirrorCam, reverting to software LIVE on a reported rejection/error/timeout. Physical-device outcome is unverified. |
| Controls | Front/back switch, thirds grid, 0 / 3 / 10 second countdown, flash Off/Auto/On for photos where supported, flash Off/On for video, pinch zoom capped at 4× or the hardware limit. |
| Library | Local persistent gallery with “by kirtdmno” in its header, still preview, video playback, sharing, save to Photos, and local deletion. |
| Permissions | Camera required. Microphone requested on first entering Video/LIVE; denial allows silent recording. Photos requested when **Save to Photos** is pressed; denial preserves the local capture. |

Apple does not advertise native Live Photo capture on iPhone 6. The default LIVE mode uses a rolling video buffer and builds a JPEG + QuickTime MOV pair with a shared content identifier and timed key-photo marker, using public frameworks without a jailbreak. PhotoKit imports these resources as one Live Photo. The optional Iris12 experiment uses private runtime capability overrides inside this app; it is off at launch. See [`docs/IRIS12-ANALYSIS.md`](docs/IRIS12-ANALYSIS.md) for the binary findings and experiment limits. If PhotoKit rejects an import, the local capture remains available and **Save photo + video** provides an explicit fallback. Older Motion captures remain readable as separate-media pairs. Photos playback/import still needs verification on your iPhone 6.

The UI stays in portrait, while device rotation controls the saved media orientation. On iPhone 6 at standard display size (375 × 667 points), the default photo layout has a 44-point toolbar, full-width 375 × 500-point 4:3 preview and 123-point shutter area, modeled on the original Camera. The size/zoom bar overlays the preview. Video uses a full-width 16:9 preview behind the controls. Smaller displays adapt to available space. The default 4:3 frame retains the full sensor view; square and 16:9 intentionally crop both preview and output. Resolution choices only downsample and never add zoom. Still/video stabilization is disabled to avoid stabilization crops. Saved photos normalize orientation/mirroring into upright pixels. The gallery uses aspect-fit display, so its display size can differ while relative framing stays the same. Mirror Off deliberately reverses the saved front image relative to the mirrored preview.

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
│   ├── FrameGeometry.swift
│   ├── PhotoFraming.swift
│   ├── HDRProcessor.swift
│   ├── IrisCompatibility.h
│   ├── IrisCompatibility.m
│   ├── MirrorCam-Bridging-Header.h
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
│   ├── analyze-iris12.py
│   └── generate-icons.py
└── docs/
    ├── DEVICE-TESTS.md
    ├── IRIS12-ANALYSIS.md
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

Open `MirrorCam.xcodeproj`, choose the **MirrorCam** scheme, and verify the target's iOS Deployment Target is **12.0**. For direct device running, add your Apple ID in Xcode Settings → Accounts, select a signing Team under Signing & Capabilities, and replace `com.example.MirrorCam` with your unique bundle identifier. Connect/trust the iPhone and build/run. A simulator can inspect the UI but cannot validate this camera pipeline. The workflow also runs `scripts/run-media-checks.sh` on macOS to check crop geometry and encode synthetic Live Photo resources with the actual app writer, then validate them with PhotoKit.

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
5. Open MirrorCam and grant Camera. Enter Video/LIVE to grant Microphone. Take a capture, open Library, and press Save to Photos to grant Photos access.

Free-account signing normally expires after 7 days and is subject to Apple's app limits. Refresh/reinstall with the same Apple ID and bundle ID to preserve the app container; save important captures to Photos first. The [Sideloadly FAQ](https://sideloadly.io/faq.html) describes expiry and overwrite behavior. Deleting the app deletes captures stored only in its local library.

## LIVE and performance details

All capture-session mutation and sample-buffer handling runs on one serial queue. Heavy disk work uses a separate media queue; UI updates run on the main queue. Motion copies YUV pixels out of capture's reusable pool, retaining at most 25 VGA frames (around 12 MB plus padding) and a bounded audio window. The writer drains bounded queues to preserve pre-roll while the hardware encoder starts; video backpressure can drop frames rather than accumulate memory indefinitely. JPEG thumbnails are downsampled for the gallery.

Entering LIVE, switching lenses, rotating, toggling mirroring, or returning from the background resets the pre-roll. Wait for **LIVE ready** for a full lead-in; early captures have a shorter lead-in. Photo mode uses high-resolution still capture. LIVE extracts its key photo from the buffered video frame at shutter time to preserve framing and avoid a photo-output stall; the still is therefore limited to VGA resolution. Flash is disabled in LIVE. Changing framing or zoom also resets the lead-in buffer. Slow hardware, interruptions, and dropped frames can affect the exact clip length; the target is approximately three seconds, not frame-accurate native Live Photo timing.

Leaving the app stops video and attempts to finalize it with a short background task. In-progress Motion capture is cancelled on interruptions/backgrounding. The app does not continue camera capture in the background. Captures are stored under Application Support/Captures, each with media, a thumbnail, and JSON metadata. Save to Photos is explicit and retries retain the local copy. Local deletion does not delete assets already in Photos.

After installing an update, run `docs/DEVICE-TESTS.md` on the actual iPhone 6/iOS 12 device, including edge-to-edge framing comparisons, audio sync, all orientations, pre-roll, Live Photo import and interruption behavior.

## Version 1.1 update

Install the new IPA over MirrorCam through Sideloadly using the same Apple ID and bundle ID. Save important captures to Photos first; avoid uninstalling if you want to keep the local library. Tap **4:3 · Max** to open Photo Size and Zoom Adjustment, use the zoom slider or pinch, and tap the zoom number to reset to 1× (the widest hardware view). Select **LIVE**, wait for **LIVE ready**, capture, open Library, then touch and hold the image. **Save to Photos** imports one Live Photo; **Save photo + video** is the explicit compatibility fallback.

## Version 1.2 Iris12 experiment

In **LIVE**, tap **4:3 · Max** → **Try Iris12 native capture (iOS 12)**. The setting lasts for this launch. **LIVE capture status** reports installed hooks, native configuration acceptance, or the last rejection. An accepted configuration does not prove a successful capture; take a photo, open Library, touch and hold, then save to Photos and verify playback there. Try both cameras. Native capture preserves Apple's original JPEG/MOV and uses 4:3 at maximum resolution; aspect and size choices remain available in software mode. Zoom remains adjustable.

On a reported exception, capture error, session error or ten-second timeout, MirrorCam restores the original capability methods and returns to software LIVE. Wait for **LIVE ready** and take a new capture. Tap **Turn Iris12 experiment off** to use software explicitly. If the app exits unexpectedly, reopen it; the experiment starts off. This app-only implementation does not enable Live Photos in Apple's Camera app. Native output mirroring, framing, audio and runtime stability require iPhone 6 testing.

## Version 1.3 HDR and layout

Select **PHOTO**, tap **HDR Off** to enable it, and hold the camera still while taking the photo. HDR is disabled in Video/LIVE and on formats without three-exposure bracket support. It uses public iOS 12 APIs, not a private Apple still-HDR switch or video-HDR setting. This is MirrorCam's own HDR processing; it does not reproduce Apple's proprietary Camera algorithm. Capture uses biases near −1.5 / 0 / +1.5 EV, aligns exposure-normalized thumbnails to the normal exposure with a bounded translation search, uses actual EXIF exposure ratios when available, then merges/tone-maps with Core Image. Strong movement or missing exposures can cause a regular-photo fallback. HDR maximum resolution is 1600 pixels on the long edge to bound decoded image memory on iPhone 6; lower selected sizes and aspect crops still apply. HDR Off retains full-resolution photo capture. Your name appears in the library header and is not burned into captured images.

# MirrorCam 1.6: public-API Live Photo generation

MirrorCam creates a JPEG and QuickTime MOV with Live Photo pairing metadata, imports them in one PhotoKit request, and fetches the saved asset to check `PHAssetMediaSubtype.photoLive`. This is a resource-based Live Photo implementation. It does not enable Apple's native camera capture capability on iPhone 6. No jailbreak, private selectors, method swizzling, or MobileSubstrate is used. The earlier Iris12 experiment and its Objective-C bridge have been removed from the application.

The implementation is complete in the checked-in Xcode project. A successful metadata check or `PHLivePhoto` load does **not** prove an iOS 12 Photos-library import or Instagram compatibility. Until the physical-device procedure below passes, those outcomes remain unverified.

## Reference repository study

Reviewed on 14 October 2026:

- [genadyo/LivePhotoDemo](https://github.com/genadyo/LivePhotoDemo/tree/e36bfeafc3f95411223f8d2db923ab06a59faa36): its root [JPEG.swift](https://github.com/genadyo/LivePhotoDemo/blob/e36bfeafc3f95411223f8d2db923ab06a59faa36/JPEG.swift) writes MakerApple key `17`; [QuickTimeMov.swift](https://github.com/genadyo/LivePhotoDemo/blob/e36bfeafc3f95411223f8d2db923ab06a59faa36/QuickTimeMov.swift) writes the movie identifier and boxed timed metadata. Its [ViewController](https://github.com/genadyo/LivePhotoDemo/blob/e36bfeafc3f95411223f8d2db923ab06a59faa36/LivePhotoDemoSwift/ViewController.swift) extracts a key image from video, loads `PHLivePhoto` and imports `.photo` plus `.pairedVideo`. The author's reported iPhone 6 test belongs to that demo, not to MirrorCam.
- [LimitPoint/LivePhoto](https://github.com/LimitPoint/LivePhoto/tree/0263052d14e2fc8399b9f6d0ef73e31054ae9427): [LivePhoto.swift](https://github.com/LimitPoint/LivePhoto/blob/0263052d14e2fc8399b9f6d0ef73e31054ae9427/LivePhoto.swift) can extract or accept a still, writes matching identifiers, adds a timed marker near the key-photo position, requests a `PHLivePhoto`, and imports both resources. Its README describes `0xFF` for the marker, but the reviewed Swift writer emits signed int8 `0`; the reviewed genadyo writer also emits `0`. MirrorCam emits int8 `0` and accepts `0`/`-1` when inspecting older pairs. The marker's timed-group start locates the key photo; the byte value is not a timestamp.

Both references operate on resources after recording. MirrorCam reuses its existing rolling-buffer writer to avoid a second full movie transcode on iPhone 6. It retains its own bounded queues, error handling and actual shutter-relative marker, rather than the demo's dummy time range. Neither repository's save completion checks the saved asset's `photoLive` subtype; MirrorCam now does. Reference source is studied for the metadata format, not installed as a dependency or copied wholesale.

Apple's public interfaces: [PHAssetCreationRequest](https://developer.apple.com/documentation/photos/phassetcreationrequest), [pairedVideo](https://developer.apple.com/documentation/photos/phassetresourcetype/pairedvideo), [photoLive](https://developer.apple.com/documentation/photos/phassetmediasubtype/photolive), [PHLivePhotoView](https://developer.apple.com/documentation/photosui/phlivephotoview).

## Capture and resource flow

1. `CameraEngine` uses one `AVCaptureSession`. In LIVE it delivers VGA YUV camera frames at a target 15 fps, with optional microphone samples. `RollingBuffer` deep-copies video frames, retains about 1.5 seconds and at most 25 frames, and bounds audio to 100 buffers. Backward timestamps or video gaps over 0.5 seconds reset the buffer.
2. The front preview and video connection follow **Mirror On/Off**; automatic mirroring and stabilization are disabled. Use **Mirror On** for mirrored JPEG/MOV output. The same oriented, mirrored video pixels supply the JPEG. Rear-camera output stays unmirrored.
3. The shutter requires a warmed buffer (at least 1.35 seconds) and a recent frame. The latest buffered frame is the key photo and provides the marker timestamp. Controls lock while the capture completes; framing, zoom, orientation and mirror changes cannot alter the in-progress pair.
4. `ClipWriter` generates one UUID, writes pre-roll video/audio into an H.264/AAC MOV, and appends about 1.5 seconds of post-roll. It has bounded pending queues and drain timeouts. Interrupted or incomplete captures report an error; they are not advertised as successfully generated Live Photos.
5. `PhotoFraming.still` creates an upright JPEG at the selected framing and size, and writes `[kCGImagePropertyMakerAppleDictionary: ["17": uuid]]`. LIVE still resolution is limited to the VGA buffered frame; choosing Max does not upscale. This preserves the existing lightweight capture path. Ordinary Photo mode retains full-resolution `AVCapturePhotoOutput` capture and optional HDR.
6. MOV file-level metadata contains `com.apple.quicktime.content.identifier = uuid`, key space `mdta`, UTF-8 type. A metadata track uses a boxed format description with identifier `mdta/com.apple.quicktime.still-image-time`, data type `com.apple.metadata.datatype.int8`. An `AVAssetWriterInputMetadataAdaptor` appends int8 `0` at the buffered shutter frame's source time for one video-frame duration. Starting the writer session at the first buffered frame makes the exported marker relative to the clip origin, near 1.5 seconds.
7. `LivePhotoSupport.validate` reads the generated JPEG/MOV, checks the identifier equality, video track, full-frame aspect consistency, typed timed marker and marker location inside the video track. The local store validates on capture and again before paired Photos import.
8. Library playback requests a `PHLivePhoto` from both local resources, ignores degraded callbacks and has a ten-second timeout. `PHLivePhotoView` supports touch-and-hold playback. A failure is logged and shown; local files remain available. Play clip is an explicit movie viewer, not proof of Live Photo playback.
9. **Save to Photos** calls `PHPhotoLibrary.performChanges`, attaches `.photo` and `.pairedVideo` to the **same** `PHAssetCreationRequest`, and records `placeholderForCreatedAsset.localIdentifier`.
10. After creation completes, `MediaStore` fetches that identifier (with bounded visibility retries), checks image media type and `mediaSubtypes.contains(.photoLive)`, and persists the result. **LIVE verified in Photos** is shown only after this check passes. Failure or inability to fetch produces a clear verification message. Creation success is retained even if verification cannot run, avoiding an automatic duplicate import. **LIVE details → Verify in Photos** repeats only the fetch/check.

Camera interruptions, backgrounding and capture timeouts cancel unfinished LIVE capture. Microphone denial produces a silent pair with a message. Photos denial preserves the local pair. Changing lens, framing, mirror, zoom or orientation rebuilds the buffer; wait for LIVE ready again.

## Integration and build

The project already integrates all changes. Open `MirrorCam.xcodeproj`, select MirrorCam, keep deployment **iOS 12.0**, choose a signing team/bundle ID if running from Xcode, and build with Xcode 15.4. There is no new package or CocoaPods dependency. The existing cloud build creates an unsigned arm64 IPA for signing with Sideloadly on Windows.

If integrating these files into another checkout:

- Add `LivePhotoSupport.swift` to the app Sources phase. It contains pair inspection, bounded preview requests and diagnostics. Retain `CameraEngine`, `RollingBuffer`, `ClipWriter`, `PhotoFraming`, `FrameGeometry`, `MediaStore`, and `GalleryViewController` changes together.
- Remove `IrisCompatibility.m/.h`, `MirrorCam-Bridging-Header.h`, their project references and the `SWIFT_OBJC_BRIDGING_HEADER` setting. Use `AVCapturePhotoOutput.capturePhoto` directly for ordinary Photo/HDR capture. Do not set `livePhotoMovieFileURL` or override native capability flags.
- Keep camera, microphone, photo-library and add-to-library privacy descriptions in Info.plist. iOS 12 uses `PHPhotoLibrary.requestAuthorization`; the app's limited-access handling is guarded for iOS 14+.
- Saved `MediaItem` adds optional Photos identifier, verification, export-kind and message fields. Missing keys in older library JSON are accepted. Existing Photo, Video, Motion and LIVE media remains readable. Older saved LIVE items lack a Photos identifier and cannot be retroactively verified automatically.
- **Save photo + video** remains an explicitly separate export for compatibility with the existing app. It does not meet the Live Photo test and is never marked verified. Flipping an existing LIVE key photo creates only a still-photo copy, preserving the original paired resources.

From the project directory on macOS:

```bash
export DEVELOPER_DIR=/Applications/Xcode_15.4.app/Contents/Developer
python3 scripts/validate-project.py
bash scripts/build-ipa.sh sideload
bash scripts/run-media-checks.sh
```

See `CLOUD-BUILD.md` for cloud builds and the README for Sideloadly signing. Install the update using the same Apple ID and bundle ID to retain the local library. No native Windows iOS compiler is used.

## Diagnostics

Camera configuration, buffer readiness, shutter lead-in, writer start/finish/errors, pair validation, permissions, Photos import, subtype verification and playback results are logged to the device console with `[MirrorCam LIVE]` and to a bounded file under Application Support. The log contains timings, dimensions, pairing UUIDs and errors, not camera images, microphone recordings or Apple ID credentials.

Open **Library → LIVE item → LIVE details** to inspect the actual pair, verify the saved asset, or share the log. Before a capture exists, **Photo Size and Zoom Adjustment → Share LIVE diagnostics** is available. Logs are shared only through the user-initiated activity sheet. A truncated/rotated log is expected after sustained use.

## On-device acceptance procedure

Record the device model, iOS patch, MirrorCam version/build, signing bundle ID and each result. Use a physical iPhone 6 on iOS 12, without jailbreak. A build pass and macOS synthetic checks are not a device pass.

1. Install 1.6 over the existing app. Confirm prior captures remain visible. Exercise Photo, HDR, Video/audio, framing/zoom, mirror preference and existing-image import/flip to check regressions.
2. Enter LIVE and grant Microphone. Front camera → Mirror On → 4:3 → 1×. Wait for LIVE ready. Hold a readable word and a numbered card at the frame edges. Move/change the card before the shutter, press, continue moving/speaking afterward, and hold the phone until capture finishes.
3. Open the captured item. Confirm the JPEG is mirrored and matches the movie's framing/orientation. Touch and hold; confirm `PHLivePhotoView` plays the pair, rather than pressing Play clip alone. Check sound. Repeat with Mirror Off, rear camera, square/wide frames and both landscape orientations.
4. In LIVE details, inspect the pair. Confirm the same UUID is in the JPEG/MOV, duration is approximately three seconds, marker is near the center, and audio is present when permitted. Export diagnostics with the result.
5. Press **Save to Photos**, grant access, and wait. Require **LIVE verified in Photos** and log `asset-verification photoLive=true`. This check proves the fetched asset's subtype on that device, not third-party compatibility.
6. Open Apple Photos independently. Find exactly one new asset, check its LIVE badge, touch and hold to play, and verify motion before/after the still, mirroring, orientation and audio. Record this separately from the programmatic subtype result. Repeat the save flow for both cameras and all framing/orientation combinations.
7. Relaunch MirrorCam; confirm saved/verified state survives. Press Verify in Photos again: it must not create another asset. Delete the Photos copy externally, then verify again; expect an unavailable-asset message and preservation of the local files. Do not silently reimport a deleted asset.
8. Deny Photos on a clean permission state; capture must remain local and save must show a clear error. Regrant in Settings and retry once. After a successful import, revoke access and verify: it must report unavailable rather than duplicate. Deny Microphone and confirm silent LIVE still works with the explicit warning.
9. Tap the shutter before warm-up; expect guidance without a partial pair. Change mirror/lens/frame/zoom and immediately capture; require warm-up again. Interrupt/background during post-roll and test rapid shutter taps; require cancellation/recovery without stale frames, duplicate items or stuck controls. Simulate low storage where practical and retain error logs.
10. Verify a small imported photo still flips without upscaling and an older saved LIVE item reports that its identifier was not recorded. Confirm separate export creates a photo plus video and **does not** display LIVE verified.
11. Instagram is a separate optional manual test: record Instagram version and the exact picker/share workflow. Confirm whether it offers the imported LIVE asset and whether it preserves or converts motion. Do not report Instagram support unless that observed workflow actually passes. Ordinary JPEG/MOV sharing alone does not establish it.

Use Instruments on a Mac when available to check repeated captures, copied pixel-buffer memory, encoder startup and thermal behavior. Archive the log with the test outcomes; do not label an unsupported operation successful based only on metadata inspection.

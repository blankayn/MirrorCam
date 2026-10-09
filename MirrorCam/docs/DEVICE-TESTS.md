# Device acceptance checklist

Version 1.0: the user reports successful installation and launch. The following detailed checks and version 1.1/1.2/1.3 runtime checks remain pending.

Use a physical iPhone 6 on iOS 12. Record the OS patch, Xcode version, build log, and results. A successful Windows structural/syntax check is not an iOS build or runtime pass.

| Check | Expected result |
|---|---|
| Clean Release iphoneos build | Xcode build succeeds, minimum OS 12.0, arm64 binary, launch screen/assets compile. |
| IPA signing/installation | Sideloadly or a valid registered-device profile installs the app; it opens without a Swift runtime error. |
| First launch, Camera allowed | Front preview appears, mirrored in real time; no main-thread freeze from session startup. |
| Camera denied/restricted | Clear access message and Settings route; local library remains accessible. |
| Return from Settings | Camera resumes after access is granted; permission changes do not crash. |
| Front photo Mirror On | Hold readable text in view: saved JPEG and Photos preview match the mirrored preview. |
| Front photo Mirror Off | Preview stays mirrored; saved photo's readable text is normal. |
| Rear photo | Normal orientation/mirroring; high-resolution still capture; flash controls become available. |
| Camera layout | At standard iPhone 6 display size, default 4:3 preview spans screen width (375 × 500 points), compact toolbar and shutter remain usable. Size/zoom bar overlays preview. Check Display Zoom and mode changes for clipping or constraint problems. |
| Library signature | Header displays MirrorCam and by kirtdmno; Camera/Edit remain accessible and media has no added watermark. |
| HDR capture | PHOTO → HDR On, hold still, capture bright window + dark room on both cameras where bracket support exists. One JPEG saves; dark and bright scene detail improve. Flash is disabled; Video/LIVE do not use HDR. |
| HDR frame/resolution | Selected aspect and mirror state match preview; maximum long edge is 1600 pixels (or hardware/selected size if lower); no added zoom or crop for alignment. HDR Off returns to full-resolution stills. |
| HDR recovery | Move during bracket, interrupt/background, and retry. Failed merge reports regular-photo fallback; capture failures/timeouts release controls. Compare fallback message to saved result. |
| Grid/countdown | Thirds lines toggle; 3/10 second countdown captures once; second shutter tap cancels. |
| Switch/zoom | Switch front/back repeatedly in every mode; pinch clamps to hardware limit; no crash. |
| Photo flash | Rear Off/Auto/On behave as supported; front flash is unavailable. |
| Video with mic allowed | Start/stop controls and timer work; saved MP4 has audible audio and sensible A/V sync. |
| Video with mic denied | Explicit silent-recording message; valid playable silent MP4; Photo still works. |
| Video mirroring | Front On and Off produce the requested saved mirroring; rear remains normal. |
| Video torch | Rear Flash On illuminates during recording and turns off at stop/background. |
| Motion full pre-roll | Wait for LIVE ready, move a numbered card before shutter and after; resulting clip shows both sides of shutter and is roughly 3 s long. |
| Motion early shutter | Just after mode entry, either warming-up feedback or a shorter lead-in; never a crash. |
| LIVE pair | JPEG still and MOV show consistent orientation and mirror state; gallery displays still and plays clip. |
| Iris12 default | After a fresh launch the experiment is off; software LIVE still works. |
| Iris12 enable/status | In LIVE, tap 4:3 · Max → Try Iris12 native capture. LIVE capture status reports hook/configuration results; unsupported capture returns to software with a reason. |
| Iris12 front/rear | If accepted, capture on each camera, verify pre/post-shutter motion and audio, hold in Library, save to Photos and hold there. Acceptance flags alone do not pass this check. |
| Iris12 framing/mirror | Native mode shows a 4:3 maximum-resolution frame, disables alternate sizes, preserves 1× framing and saved Mirror On/Off in portrait/landscape. |
| Iris12 recovery | Exercise lens/mode changes, background/interruption, native rejection and timeout. UI recovers, original methods restore on disable, and software captures remain available. Record any unexpected exit and reopen with the experiment off. |
| Buffer reset | Switch, rotate or toggle mirror in Motion; no stale frames from the previous configuration. |
| Rotation | Capture photos and videos held portrait, upside-down and both landscapes; saved files appear upright in Photos and playback. Change orientation while recording: clip dimensions stay stable. |
| Fast shutter taps | No duplicate photos, overlapping writers, stuck recording state or unexpected mode changes. |
| Gallery lifecycle | Open/close Library repeatedly; camera resumes. Clip audio stops after dismissing playback. |
| Gallery persistence | Kill/relaunch app after completed saves; all local items and thumbnails reappear. |
| Photos allowed | Explicit save adds one photo/video, or one Live Photo for LIVE captures; legacy Motion adds two assets; already-saved button prevents ordinary duplicate saves. |
| Photos denied | Permission message, local capture preserved, retry works after granting access. |
| Sharing | Share JPEG, MP4, and Motion pair using activity sheet; receiver can open them. |
| Local deletion | Delete confirmation removes only the local item; exported Photos copies remain. |
| Background while recording | Recording stops, torch off, completed MP4 appears on return if finalization succeeds. |
| Background during Motion | Motion cancels cleanly; return rebuilds rolling buffer; next capture works. |
| Call/camera interruption | Feedback shown, interrupted session recovers when available; no corrupted item added. |
| Low storage / encoder errors | Error feedback, capture controls recover, failed item does not appear as a valid gallery item. |
| Sustained use | Repeated Photo/Video/Motion captures do not produce unbounded memory growth or thermal instability. Check Instruments on the Mac. |

Inspect video properties (duration, dimensions, audio track) on macOS with AVAsset or a media inspector. Compare saved orientations in Photos as well as MirrorCam: previews alone do not prove exported media correctness.

## Version 1.1 framing and LIVE checks

- Front/rear, Photo/LIVE: at 1×, hold a card with marks at each visible frame edge. The same marks must remain at corresponding saved-image edges in Library and Photos. Repeat at each aspect ratio, size and supported zoom, in portrait and both landscapes.
- Switch mode at 2×: the zoom readout and actual framing stay consistent. Switching lenses resets both to 1×. Tap the zoom number to restore the full 1× view. Front camera zoom may be unavailable; the slider must disable and show 1×.
- Default 4:3 full framing must not crop; square/wide crops must be visible before capture. Smaller output resolution must preserve the same composition.
- LIVE: capture motion and sound, hold the Library photo to animate, release to stop, and play the clip separately. Save to Photos must create one asset showing the LIVE badge and press-and-hold animation.
- LIVE fallback: if import fails, local JPEG/MOV remain playable. Save photo + video must create two assets only when explicitly chosen.
- Old version 1.0 Photo/Video/Motion captures must still load after installing the update over the app with the same signing account and bundle ID.

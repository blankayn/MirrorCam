# Device acceptance checklist (not yet executed)

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
| Grid/countdown | Thirds lines toggle; 3/10 second countdown captures once; second shutter tap cancels. |
| Switch/zoom | Switch front/back repeatedly in every mode; pinch clamps to hardware limit; no crash. |
| Photo flash | Rear Off/Auto/On behave as supported; front flash is unavailable. |
| Video with mic allowed | Start/stop controls and timer work; saved MP4 has audible audio and sensible A/V sync. |
| Video with mic denied | Explicit silent-recording message; valid playable silent MP4; Photo still works. |
| Video mirroring | Front On and Off produce the requested saved mirroring; rear remains normal. |
| Video torch | Rear Flash On illuminates during recording and turns off at stop/background. |
| Motion full pre-roll | Wait for Motion ready, move a numbered card before shutter and after; resulting clip shows both sides of shutter and is roughly 3 s long. |
| Motion early shutter | Just after mode entry, either warming-up feedback or a shorter lead-in; never a crash. |
| Motion pair | JPEG still and MP4 show consistent orientation and mirror state; gallery displays still and plays clip. |
| Buffer reset | Switch, rotate or toggle mirror in Motion; no stale frames from the previous configuration. |
| Rotation | Capture photos and videos held portrait, upside-down and both landscapes; saved files appear upright in Photos and playback. Change orientation while recording: clip dimensions stay stable. |
| Fast shutter taps | No duplicate photos, overlapping writers, stuck recording state or unexpected mode changes. |
| Gallery lifecycle | Open/close Library repeatedly; camera resumes. Clip audio stops after dismissing playback. |
| Gallery persistence | Kill/relaunch app after completed saves; all local items and thumbnails reappear. |
| Photos allowed | Explicit save adds one photo/video, or two independent Motion assets; already-saved button prevents ordinary duplicate saves. |
| Photos denied | Permission message, local capture preserved, retry works after granting access. |
| Sharing | Share JPEG, MP4, and Motion pair using activity sheet; receiver can open them. |
| Local deletion | Delete confirmation removes only the local item; exported Photos copies remain. |
| Background while recording | Recording stops, torch off, completed MP4 appears on return if finalization succeeds. |
| Background during Motion | Motion cancels cleanly; return rebuilds rolling buffer; next capture works. |
| Call/camera interruption | Feedback shown, interrupted session recovers when available; no corrupted item added. |
| Low storage / encoder errors | Error feedback, capture controls recover, failed item does not appear as a valid gallery item. |
| Sustained use | Repeated Photo/Video/Motion captures do not produce unbounded memory growth or thermal instability. Check Instruments on the Mac. |

Inspect video properties (duration, dimensions, audio track) on macOS with AVAsset or a media inspector. Compare saved orientations in Photos as well as MirrorCam: previews alone do not prove exported media correctness.

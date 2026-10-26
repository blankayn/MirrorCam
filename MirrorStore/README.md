# MirrorStore for iOS 12

MirrorStore is an experimental iOS 12 compatibility fork of SideStore 0.4.0. It uses SideStore's on-device refresh architecture: the app signs app packages with a free Apple development identity, then installs/refreshes them through the local VPN loopback transport. A computer is needed for the initial install and pairing-file generation. Once that setup works, refreshes are intended to run on the iPhone.

This repository currently contains a compatibility patch and packaging tools. It has **not** been compiled with Xcode or tested on an iPhone 6. The iOS 12 backport and WireGuard transport remain on-device validation gates.

## Limits and requirements

- Free Apple ID signatures expire after seven days. MirrorStore can renew them, but cannot make an app permanent.
- The iPhone must have a WireGuard-compatible app signed by the App Store and a working MirrorStore tunnel profile. If the App Store will not offer an iOS 12-compatible WireGuard version for this iPhone, the on-phone refresh route cannot work.
- The first installation uses Sideloadly on Windows. Pair the unlocked iPhone by USB and generate a `.mobiledevicepairing` record with the Windows `jitterbugpair` utility. Keep this pairing file private.
- Build the app on macOS with Xcode. Windows cannot compile an iOS app. The generated IPA can then be transferred to Windows for local pairing-file injection and Sideloadly signing.
- The pairing file is a private host identity. `prepare_device_ipa.py` embeds it into the app's Info.plist so MirrorStore can refresh itself. The prepared IPA is device-specific and must not be published or shared.
- The app requests Anisette headers from the HTTPS server configured in Info.plist (default: `https://ani.sidestore.io`). That is a separate service from Apple. Review and trust the selected server before signing in. Diagnostic logs in this fork redact Anisette values.

## Build on macOS

If you have access to a Mac, install Xcode, command-line tools, Git, Python 3, `wget`, and `ldid`. Then from this repository:

```sh
MirrorStore/scripts/build_unsigned.sh
```

The script checks out the exact SideStore source commit used as the base, initializes its pinned Git submodules, applies the iOS 12.2 patch, and runs the upstream build and packaging steps. The upstream project fetches Rust prebuilt transport artifacts during Xcode builds. The script checks their declared minimum OS version and stops if a device library requires newer than iOS 12.2. This metadata check does not prove runtime compatibility; pin and rebuild the transport artifacts before relying on a distributable release.

Without a Mac, push the source to GitHub, then run **Actions → Build MirrorStore for iOS 12 → Run workflow**. Download the `MirrorStore-unsigned` artifact to Windows. That workflow is included in this repository but has not been run yet.

## Prepare and sign on Windows

Copy `MirrorStore-unsigned.ipa` and your private `.mobiledevicepairing` file to the same Windows folder. With Python 3 installed, run:

```powershell
py -3 .\MirrorStore\scripts\prepare_device_ipa.py .\MirrorStore-unsigned.ipa .\YOUR-IPHONE-UDID.mobiledevicepairing
```

This creates `MirrorStore-unsigned-device.ipa`. Select that IPA in Sideloadly, sign it with your Apple ID, connect the iPhone by USB, and install it. Do not upload the prepared IPA to GitHub; it contains the pairing identity.

## First-run and refresh procedure

1. Unlock and trust the Windows computer on the iPhone, then generate a fresh pairing file with `jitterbugpair`.
2. Install the prepared IPA with Sideloadly and open MirrorStore once while connected to Wi-Fi.
3. Install WireGuard from the iPhone App Store if a compatible version is offered. Transfer `MirrorStore/resources/MirrorStore-VPN.conf` to the iPhone, open it in WireGuard, add the tunnel, and allow the VPN configuration prompt. Enable **MirrorStore VPN** before refreshing.
4. Open MirrorStore and sign in with the free Apple ID. Apple may ask for two-factor verification.
5. Import a test IPA, install it, then refresh it manually while the VPN is enabled and MirrorStore is open.
6. Verify in Settings → General → VPN & Device Management that the test app is signed and launches. Reopen after a device restart and repeat refresh with the iPhone disconnected from the computer.
7. Let a test signing profile approach expiry only after a working refresh is proven. Confirm the refreshed app still launches and retains its app data.

Record the iOS version, WireGuard version, pairing-file source, MirrorStore logs, and exact failure message. Do not include Apple passwords, Anisette values, or the pairing file in a bug report.

## Source and license

The upstream SideStore source is licensed under AGPL-3.0. This project is a derivative fork and preserves that license; third-party dependencies retain their own licenses. The upstream commit is pinned in `scripts/patch_ios12.py`.

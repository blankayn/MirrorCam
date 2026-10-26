# iOS 12 app refresh research

Research updated: 25 October 2026.

## Two different signing architectures

AltStore Classic uses AltServer on a Windows or Mac computer for signing and installing. Its refresh flow needs that computer to be reachable. The official Windows guide documents the iTunes/iCloud components, USB trust, and Wi-Fi sync setup: [AltStore Windows guide](https://github.com/altstoreio/FAQ/blob/main/altstore-world/how-to-install-altstore-windows.md).

SideStore 0.4.0 is a separate, older design. It moved the refresh transport onto the iPhone by using a pairing record plus a local VPN loopback transport. Its README describes the design as not requiring a paid developer account: [SideStore source](https://github.com/SideStore/SideStore). This is the architecture MirrorStore is attempting to backport for iOS 12. The historical base is pinned at [SideStore commit b3abf69](https://github.com/SideStore/SideStore/commit/b3abf69a0280b4e86b56026e2741f43d6ef53c31).

MirrorStore still needs a computer once to build and initially install the app and generate the iPhone pairing record. The goal is for later refreshes to run on the iPhone when its VPN transport is available. That goal is not proven on iOS 12 or iPhone 6 yet.

## Free signing limit

A free Apple development identity does not make an app permanent. The signing profile has a limited validity period, so the app must be refreshed or reinstalled before it expires. MirrorStore cannot extend Apple's validity period or keep an expired signature valid. See [Apple's developer account overview](https://developer.apple.com/help/account/basics/about-your-developer-account/) and [Apple's provisioning profile documentation](https://developer.apple.com/documentation/technotes/tn3125-inside-code-signing-provisioning-profiles).

## iOS 12 feasibility

The SideStore 0.4.0 app declared iOS 14 as its minimum. MirrorStore changes the app, Core, and transport targets to iOS 12.2, replaces the iOS 14 document picker, removes unsupported free-team entitlements, and prepares a device pairing record locally. A lower deployment target alone does not establish runtime compatibility. The code still needs a successful Xcode build and real iPhone 6 test.

The on-device route also depends on an App Store-signed WireGuard app that still installs on the iPhone's iOS 12 version. Availability of a compatible historical WireGuard release is a device-specific gate. If the App Store cannot install one, the on-phone transport will not work on that device.

## Current project status

- MirrorStore source and a manual macOS GitHub Actions build workflow are in the workspace.
- The workflow creates an unsigned IPA artifact; it does not sign or install an IPA.
- A Windows helper embeds the user's private pairing record into a device-specific IPA before Sideloadly signing. That IPA must not be published.
- The macOS workflow has not run, and there is no iOS build or device test result yet.
- SideStore 0.4.0 downloads transport prebuilt binaries through a `latest` release URL. Pinning and checking those binaries' minimum OS versions remains necessary before a reproducible release.

References for the distinct SideStore setup flow: [SideStore installation prerequisites](https://github.com/SideStore/SideStore-Docs/blob/main/docs/installation/prerequisites.mdx). The SideStore setup model is a research input, not evidence that this iOS 12 backport works.

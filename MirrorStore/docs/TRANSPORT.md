# iPhone-only refresh transport

MirrorStore uses SideStore 0.4.0's pre-iOS-15 architecture: `minimuxer` talks to the local device over a pairing record, while `em_proxy` reflects the local TCP traffic through a VPN app. The VPN capability comes from an already App Store-signed WireGuard app; MirrorStore itself does not request a packet-tunnel entitlement. The upstream README describes this design as working without a paid developer account.

The refresh client can operate on the phone once it is installed, paired, and the VPN tunnel is available. Initial installation and pairing still need a computer. This design does not avoid Apple's seven-day expiry for free Personal Team profiles; it renews them.

The repository includes the upstream loopback tunnel profile as `resources/MirrorStore-VPN.conf`. It routes only the local `10.7.0.0/24` range to `127.0.0.1:51820`; it is a local transport profile, not a general-purpose VPN. The configuration uses upstream's shared test key material, so keep it attached only to this local tunnel. The account pairing record remains private and is not part of that profile.

## iOS 12 status

The upstream app at commit `b3abf69a0280b4e86b56026e2741f43d6ef53c31` declared iOS 14 for its main app. This fork changes the app, Core framework, and transport targets to iOS 12.2, backports the pairing document picker, disables unsupported free-team entitlements, and fixes the test UDID placeholder at packaging time.

This is still a source-level experiment. It is not yet confirmed that all iOS 13/14-guarded UI code and every linked binary run on iOS 12.2, or that the current App Store distribution offers a WireGuard build installable on an iPhone 6. Those are hard gates requiring a real device. If either fails, this route needs further porting or will not work on that phone.

## Build inputs that still need pinning

The base project pins SideStore and Git submodules, but its Xcode build phase downloads `minimuxer` and `em_proxy` prebuilt artifacts from each project's latest GitHub release. That makes transport builds non-reproducible. The build script now inspects device static libraries' declared minimum OS version and fails if it finds a requirement newer than iOS 12.2. This metadata check cannot prove that the binaries avoid newer APIs at runtime. Before distributing an IPA, replace the moving downloads with source builds from reviewed commit hashes and test on an iPhone 6. No pairing file or device-specific IPA belongs in GitHub Actions artifacts or public releases.

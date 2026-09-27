# Install Application Atlas

Requires macOS 14 Sonoma or later. The universal download supports Apple Silicon and Intel Macs.

1. Download `Application-Atlas-VERSION-macOS-universal.zip` from [GitHub Releases](https://github.com/WagnerJon/application-atlas/releases). GitHub's automatic “Source code” downloads are for building the app yourself.
2. Unzip it and drag **Application Atlas.app** into **Applications**.
3. Open the app. This community release is ad-hoc signed, without an Apple Developer ID certificate or Apple notarization. macOS will normally block the first launch of a downloaded copy.
4. If you trust the release, follow [Apple's instructions for opening an app from an unknown developer](https://support.apple.com/guide/mac-help/mh40616/mac): after attempting to open it, go to **System Settings → Privacy & Security → Open Anyway**, then confirm. Managed Macs may prohibit this exception.

Keep Gatekeeper enabled. If macOS reports malware or a damaged app, stop and check the download/source rather than disabling security protections. Building from source is also supported; see the repository README.

## Verify the download

Download `SHA256SUMS.txt` into the same folder as the ZIP, then run this there:

```sh
shasum -a 256 -c SHA256SUMS.txt
```

This detects a corrupted or mismatched download; it does not replace developer identity verification.

## Update or uninstall

Create a backup through **Settings → Create backup…**, quit the app, and replace the old app with the newer copy. There is no automatic updater. Data stays in `~/Library/Application Support/ApplicationAtlas`, independently of the app bundle. Deleting the app leaves that data intact.

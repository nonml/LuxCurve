# Distributing LuxCurve

LuxCurve calls private Apple frameworks (the ambient light sensor via IOKit,
`DisplayServices` for brightness), so it cannot be distributed through the Mac App
Store. Builds also ship **ad-hoc signed and un-notarized** by project decision, so
no paid Apple Developer account is required to build or release. The trade-off is a
one-time Gatekeeper approval on first launch (see below).

## Creating a release

```sh
./Scripts/release.sh        # → build/LuxCurve.dmg  and  build/LuxCurve.zip
```

Attach both files to a GitHub Release. The `.dmg` supports drag-to-install; the
`.zip` is provided as an alternative download.

## Installing (for users)

1. **Install:** open the `.dmg` and drag **LuxCurve** onto the **Applications**
   shortcut. (Or unzip the `.zip` and move the app into `/Applications`.)
2. **First launch:** because the build is not notarized, macOS Gatekeeper blocks a
   plain double-click. Instead:
   - **Right-click LuxCurve → Open**, then confirm **Open** in the dialog.
     (Only right-click → Open offers this option.)
   - If macOS still refuses, go to **System Settings ▸ Privacy & Security**,
     scroll to the LuxCurve message, and click **Open Anyway**.

   This is a one-time step per machine; afterward the app launches normally.

## Notes

- LuxCurve is a menu-bar agent (`LSUIElement`) and has no Dock icon. Look for the
  sun glyph in the menu bar.
- "Open at login" uses `SMAppService`, which is most reliable once the app is in
  `/Applications`.
- Turn off *System Settings → Displays → "Automatically adjust brightness"* so that
  macOS and LuxCurve do not both control the display.

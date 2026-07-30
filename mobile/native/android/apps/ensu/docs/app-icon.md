# Updating the Android app icon

The Android app icon is an adaptive icon: a transparent foreground PNG padded to ~50% of the canvas (so it fits circular and squircle masks without clipping), plus a solid background color.

## Steps

1. Start from the transparent source PNG. Center it on a square canvas with the foreground taking ~50% of the width (current safe-zone scale: `0.50`).
2. Export the adaptive foreground as `ic_launcher_foreground.png` (432×432) into [`res/drawable/`](../app/src/main/res/drawable/).
3. Export legacy icons as both `ic_launcher.png` and `ic_launcher_round.png` (same image) at the following sizes into the matching [mipmap folders](../app/src/main/res/):
   - `mipmap-mdpi/` at 48×48
   - `mipmap-hdpi/` at 72×72
   - `mipmap-xhdpi/` at 96×96
   - `mipmap-xxhdpi/` at 144×144
   - `mipmap-xxxhdpi/` at 192×192
4. Set the adaptive background color in [`res/values/colors.xml`](../app/src/main/res/values/colors.xml):
   ```xml
   <color name="ic_launcher_background">#FDCE13</color>
   ```
5. Install on a device and check the icon under circle, squircle, and themed launcher masks. If it clips, reduce the safe-zone (e.g. `0.45`).

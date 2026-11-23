# iPad App Store screenshots for 1.2

Captioned 13" iPad screenshots (2064×2752 PNG, no alpha), made on 2026-11-23 to match the iPhone 1.2 set in [`../app-store-iphone-1.2/`](../app-store-iphone-1.2/) (#1259). They replace the uncaptioned 1.1 iPad set. Upload them, in this order, to the iPad 13" set of the next 1.2.x App Store version.

1. Every channel of your mixer. Its own WAV. (32 channels, generic USB mixer, Free)
2. Any class-compliant USB mixer. Free. (Sunlight, 18 channels)
3. XR18 or X32? Files named from the mixer. With Pro.
4. A second copy on a USB drive. With Pro. (XR18)
5. Ready for your DAW. Named files and Markers. With Pro.

Taken in the iPad Pro 13-inch (M5) Simulator from a Debug build, not on a real iPad. Shots 1 and 2 play generated test tones as USB Channels (`-demoStems`); shots 3 to 5 use the Demo signal linked to tools/mixer-sim's `xr18-band.json`. The iPad set has no Pro shot (Eric, 2026-11-23): on the iPad the Pro sheet is a small form sheet that cut off its first line, so it was dropped; the description gives the price.

For the shots only, a local change (not committed) showed "USB Mixer" or "X18/XR18" in the header where a Debug build says "Demo signal" or "Demo stems", "iPad Microphone" for the Simulator's "MicrophoneBuiltIn", hid the Simulator's own channel-count warning, and owned Pro for shots 3 to 5.

The captions are drawn by `scripts/caption-screenshots.swift`, with the fonts, colors and layout measured from the iPhone set:

```sh
swift scripts/caption-screenshots.swift ipad13 <folder with 01.png … 06.png> docs/images/app-store-ipad-1.2
```

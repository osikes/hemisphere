# Hemisphere

A macOS menu bar app that sets your desktop wallpaper to a live weather radar map.

## Overview

Hemisphere generates a map of the continental US with real-time weather radar overlay and sets it as your desktop wallpaper across all Spaces. It runs in the menu bar and auto-refreshes every 10 minutes.

## Architecture

```
weather-wallpaper/
├── Hemisphere/                # Swift menu bar app
│   ├── Package.swift
│   └── Sources/
│       └── main.swift         # Menu bar app, space change detection, wallpaper setting
├── generate.js                # Node.js script that renders the map using Puppeteer
├── map.html                   # Leaflet.js map with radar overlay
├── package.json
└── wallpaper.png              # Generated wallpaper image
```

## How It Works

1. **Map Generation** (`generate.js` + `map.html`):
   - Uses Puppeteer to render a headless browser
   - Leaflet.js displays the map with configurable tile layers
   - RainViewer API provides real-time radar overlay
   - Screenshots the rendered map at screen resolution (Retina 2x)

2. **Menu Bar App** (`WeatherWallpaper/Sources/main.swift`):
   - Runs as a menu bar app with cloud icon
   - Listens for `NSWorkspace.activeSpaceDidChangeNotification`
   - Calls Node.js script to generate wallpaper
   - Uses AppleScript `tell every desktop` to set wallpaper on ALL Spaces
   - Auto-refreshes every 10 minutes

3. **Wallpaper Setting**:
   - AppleScript method works across all Spaces: `tell application "System Events" tell every desktop set picture to "path"`
   - Re-applies on every space change to ensure consistency

## Map Styles

Three tile layer options:
- **Satellite**: ESRI World Imagery + labels overlay
- **Dark**: CartoDB Dark Matter
- **Light**: CartoDB Positron

## Key Files

### generate.js
- Launches Puppeteer with caching disabled
- Detects screen resolution via `system_profiler`
- Waits for all tile layers to report loaded
- Writes to temp file then renames (fixes Puppeteer overwrite bug)
- Accepts `--style=satellite|dark|light` and `--no-set` flags

### map.html
- Leaflet.js map centered on continental US (39.8, -98.5), zoom 5
- RainViewer API for radar: `https://api.rainviewer.com/public/weather-maps.json`
- Cache-busting on API calls with `?_=Date.now()`
- Sets `window.mapReady = true` when all tiles loaded

### main.swift
- SwiftUI app with `@NSApplicationDelegateAdaptor`
- `WallpaperManager` class handles generation and setting
- Prevents concurrent generations with `isGenerating` lock
- Captures style at generation start to prevent race conditions

## Dependencies

**Node.js:**
- puppeteer

**Swift:**
- AppKit (macOS 13+)
- SwiftUI

## Building

```bash
# Install Node dependencies
npm install

# Build Swift app
cd Hemisphere
swift build

# Run
.build/debug/Hemisphere
```

## Known Issues / Fixes Applied

1. **Puppeteer not overwriting files**: Fixed by writing to temp file then renaming
2. **Style changing mid-generation**: Fixed by capturing style at start of async operation
3. **Wallpaper not setting on all Spaces**: Use AppleScript `tell every desktop` method
4. **Stale radar data**: Added cache-busting to RainViewer API and disabled Puppeteer cache
5. **Menu bar icon color**: Dark wallpapers can cause macOS to pick poor menu bar contrast

## Future Ideas

- Apple Maps integration (requires Developer account for MapKit JS)
- More map styles
- Configurable refresh interval
- Location-based zoom/center
- Weather alerts overlay

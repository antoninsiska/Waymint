<p align="center">
  <img src="docs/waymint-logo.png" alt="Waymint logo" width="160" height="160">
</p>

<h1 align="center">Waymint</h1>

<p align="center">
  A private, local-first home for planning trips from the first idea to the journey home.
</p>

Waymint is a local-first trip planner for iPhone and iPad. It keeps itineraries, stops, tickets, checklists, maps, and trip summaries together without requiring an account or a backend.

The repository also contains a complete static web experience in [`docs/`](docs/): an animated product landing page and a browser-based trip planner. It can be published directly with GitHub Pages and can exchange Waymint export files with the iOS app.

## Highlights

- SwiftUI interface for iPhone and iPad
- SwiftData persistence stored locally on the device
- trip, city, stop, ticket, and checklist planning
- MapKit routes and maps
- local notifications and Live Activities
- import and export of `.way` and `.waymint` files
- animated responsive landing page with a direct entry into the web planner
- static web planner with browser-local storage and no account requirement
- address search and automatic estimates for transfers between stops
- shared `.way` and `.waymint` import/export formats across the native and web versions

## Requirements

- Xcode 26 or newer
- iOS 26 or newer
- macOS with a recent Swift toolchain

## Run the iOS app

1. Clone the repository and open `Waymint.xcodeproj` in Xcode.
2. Select the **Waymint** target.
3. In **Signing & Capabilities**, choose your Apple development team.
4. Replace the example bundle identifiers for the app and Live Activity extension with identifiers owned by your team.
5. Select a simulator or device and run the app.

The checked-in project intentionally does not contain a development-team identifier, provisioning profile, private signing certificate, or enabled iCloud container. Data remains local unless the user explicitly exports a file.

## Run the website

```sh
python3 -m http.server 8080 -d docs
```

Then open `http://localhost:8080`.

The website opens on the Waymint landing page. Select **Vstup do aplikace** to enter the browser planner. From the planner, use the Waymint logo or **Úvodní stránka** in the sidebar to return to the landing page.

See [`docs/README.md`](docs/README.md) for GitHub Pages setup, supported file formats, and notes about the public geocoding and routing services used by the web version.

### Web features

- responsive animated landing page
- cities, trips, timed stops, notes, and checklists
- address suggestions and map previews
- estimated walking, cycling, public-transport, and driving transfers
- local persistence in the current browser
- import and export of individual trips, cities, or the complete library
- light and dark planner themes

## Privacy

The native app has no backend, analytics, advertising SDK, or account system. The web planner stores app data in the browser's `localStorage`; clearing browser storage removes that local library unless it has first been exported. Address suggestions and route calculations can send location queries to the third-party services described in [`docs/README.md`](docs/README.md).

## Contributions

Ideas, bug reports, design feedback, and code contributions to Waymint are welcome. If you would like to help:

1. Open an issue describing the problem or proposed improvement.
2. Discuss the intended approach before starting a larger change.
3. Fork the repository for the sole purpose of preparing the agreed contribution.
4. Submit a focused pull request with a clear description and testing notes.

By submitting a contribution, you confirm that you have the right to submit it and grant the Waymint copyright holder a perpetual, worldwide, irrevocable, royalty-free licence to use, modify, reproduce, distribute, sublicense, and incorporate that contribution into Waymint. The project owner may accept, modify, or decline any contribution.

The permission to prepare and submit a contribution does not grant permission to reuse Waymint or its source code in another project. The terms in [LICENSE](LICENSE) continue to apply.

## License

Copyright (c) 2026 antoninsiska. All rights reserved.

Waymint is proprietary, source-available software and is **not open source**. The code may be viewed for evaluation only. Use, copying, modification, redistribution, creation of derivative works, and commercial or non-commercial incorporation into another project are prohibited without prior express written permission. See [LICENSE](LICENSE) for the complete terms.

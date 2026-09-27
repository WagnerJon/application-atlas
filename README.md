# Application Atlas

[Source](https://github.com/WagnerJon/application-atlas) · [Downloads](https://github.com/WagnerJon/application-atlas/releases) · [Buy me a coffee](https://buymeacoffee.com/wagnerjon)

A native SwiftUI macOS app for tracking job and PhD applications. Requires macOS 14 or newer.

## Download and install

Download the universal app ZIP from [GitHub Releases](https://github.com/WagnerJon/application-atlas/releases). It supports Apple Silicon and Intel Macs running macOS 14 or later. Drag the extracted app into Applications.

**Downloads are ad-hoc signed, without Apple notarization or a Developer ID certificate.** macOS normally blocks the first launch. Follow the per-app procedure in [Installation instructions](docs/INSTALL.md), which links to Apple's guidance. No Apple Developer account is required to build or maintain the project.

## Build from source

Install Apple's Command Line Tools (`xcode-select --install`) or Xcode, then:

```sh
./scripts/build.sh
```

Open **build/Application Atlas.app** in Finder. This builds for your Mac's architecture. To package a universal release for Apple Silicon and Intel:

```sh
./scripts/release.sh
```

Release assets are written to `dist/`. [Maintainer instructions](docs/RELEASING.md) describe the automated GitHub Releases workflow.

## License and support

[MIT License](LICENSE) · Made with ♥ by Jonas (2026).

If Application Atlas is useful to you, you can [buy me a coffee](https://buymeacoffee.com/wagnerjon). Support is optional; all features are free. The same link is available in **Settings → About & license…** and GitHub's **Sponsor** button.

## Features

- Overview with counts and a proportional Sankey: all applications → your categories → successive recorded steps.
- Searchable application list with type and status filters. Click **Status** to sort by application stage or **Sent** to sort by sent date; click again to reverse. The arrow shows the direction. Unsent applications stay last within each status group or date sort.
- Role, organization, location, opportunity URL, notes, sent date, and optional deadline.
- Draft, awaiting response, response received, interview, offer, rejected, and withdrawn statuses.
- Dated application journeys: open a record, choose **Next step**, set its date, click **Add step**, then **Save application**. For example, Interview → Rejected retains both events. Multiple interviews are supported. Click an existing journey step to edit its status and date, choose **Apply changes**, then **Save application**. Editing the final step updates the current status. Editing dates keeps steps in their recorded order.
- Click any Sankey status node or label to filter and scroll to applications that reached that status. **Clear filter** restores the list. The status dropdown filters current status instead.
- Multiple attachments per application, including cover letters and motivation letters; originals are copied to preserve the submitted version.
- Applications awaiting a reply show **Sent today**, **Waiting 1 day**, or **Waiting N days**, based on the sent date and local calendar. The label refreshes while the app is open and disappears after the status changes.
- Edit records, open documents, and delete with confirmation. Command-N adds an application.

The Sankey shows recorded transitions in step order. Existing records start at their previously saved status; earlier dates and steps are not invented. Status clicks match any recorded step (including earlier interviews); the current-status dropdown and summary counts refer to the latest status. A status can appear in multiple step columns, and clicking any occurrence matches all applications that reached it. Responses include response received, interview, offer, and rejected. Drafts are included in total applications. No sample records are added to your real data.

The app includes a smiling globe with an academic cap as its Finder, Dock, and sidebar icon. The source image and generation prompt are in `Assets/`.

## Categories

**Settings → Manage categories…** lets you add categories, rename them, and remove categories you no longer need. Click the icon beside a category to choose a symbol or enter one emoji (including combined emoji and flags). **Apply icon**, then **Save** updates the sidebar, application rows, editor picker, and Sankey. **Use default** restores the original icon. Icons are preserved in backups, and older categories keep their existing defaults. Job and PhD remain the defaults. Save applies changes to the sidebar, application editor, Sankey, CSV exports, and backups together. A new application starts in the category currently selected in the sidebar (or the first category from the overview).

Names must be unique, nonempty, and no longer than 40 characters. Removing a used category prompts you to move its applications to another category; documents and journey history are retained. Cancel discards category edits. Keep at least one category. The Sankey shows categories with applications and expands vertically when needed.

Existing databases and older backups load with Job and PhD automatically. The updated database saves categories and applications together, with stable category IDs so renaming does not change application assignments.

## Map

Select **Map** below the application categories. Heidelberg is the initial home base; choose **Change home…**, search a city and country, and select a result to save another home. Add **city, country** to each application’s Location field to draw an arrow from home. Routes use current status colors. Select a destination or a row to highlight a route, filter by status, and use **Fit all routes** to reset the view. Unresolved cities are listed with **Locate…**, **Edit**, and retry controls; multiple matches require choosing the correct city. Records without a city remain in your ledger and are counted beneath the map.

Map settings and resolved city coordinates are cached in `map-settings.json` beside the main database. Map tiles and uncached lookups need an internet connection; application records and cached route coordinates remain local. The app does not request your device’s location. Arcs are illustrative connections, not actual airline itineraries.

## Local data

Records are saved atomically in `~/Library/Application Support/ApplicationAtlas/applications.json`. Documents are in its `Attachments` subfolder. The top-right **Settings → Show local data** menu opens this directory. Back up the whole directory to preserve records and documents together. No account is required. The Map tab uses Apple map tiles and city geocoding services; city lookup sends location text, never roles, organizations, notes, or attachments. This is a single-Mac app; it does not sync or send applications.

If existing data cannot be loaded, saving is disabled to prevent overwriting it. Restore valid data from backup and reopen the app.

## Export, backup, and restore

Use the small **Settings** menu at the top right:

- **Export all applications (CSV)…** exports every record, including category names, dates, waiting days, notes, document names, and journey steps. Quoting preserves commas/newlines; formula-like text is exported as literal text. CSV exports do not contain document files and are not restorable backups.
- **Create backup…** saves a single JSON file containing all applications, journey history, copied documents, categories, and map settings. Documents are embedded in the backup (up to 512 MB total). Missing documents cause a visible error rather than an incomplete backup.
- **Restore backup…** validates the file and shows its creation date and record/document counts before confirmation. Restore replaces the live dataset (including categories), retaining the complete previous data folder alongside it as a recovery copy; **Show in Finder** reveals that copy. Cancel leaves current data untouched. Map settings reload after restore.
- **About & license…** displays the version, **Made with ♥ by Jonas (2026)**, the full MIT license, and an optional Buy Me a Coffee link.

## Validate storage

```sh
./scripts/test.sh
```

The build is locally ad-hoc signed, not notarized for public distribution.

Build scripts detect a duplicate SwiftBridging definition left by some Command Line Tools upgrades and apply a compiler-only overlay. They do not modify system files.

For UI validation, `./scripts/preview.sh` builds a separate **build/Atlas Preview.app** with sample journeys in a temporary directory. It never uses the real application database.

## Privacy and contributions

There are no analytics, ads, accounts, or automatic update checks. Application data and documents stay on your Mac; Apple map services require network access as described above. Clicking the support link opens Buy Me a Coffee in your browser, subject to that service's own privacy policy. Backups contain your personal data and documents and are not encrypted by the app; store them somewhere private.

See [CONTRIBUTING.md](CONTRIBUTING.md) for development guidance. The app icon was generated with AI; its source and generation notes are in `Assets/`. Project code, documentation, and bundled original assets are offered under the MIT license.

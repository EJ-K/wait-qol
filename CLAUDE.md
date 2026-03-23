# WaitQOL - Development Notes

## Project Overview

WaitQOL is a World of Warcraft addon (retail) that provides Quality of Life tools for raiders. It features a modular architecture where each QOL tool is implemented as a separate module with its own configuration panel.

## Architecture

### Core Components

- **Core/Init.lua**: Main addon initialization, database setup, and module registry
- **Core/Modules.lua**: Helper functions for modules (LSM font/border fetching, etc.)
- **Config/GUI.lua**: Configuration UI system with profile management

### Module System

Modules register themselves via `WaitQOL:RegisterModule(name, moduleTable)`. Each module should provide:

- `displayName`: Display name for the module in the config UI
- `order`: Display order (lower numbers appear first)
- `GetDefaults()`: Function returning default settings table
- `OnInitialize(savedVars)`: Called when addon loads, receives saved settings
- `OnEnable(savedVars)`: Called when the module is enabled (optional)
- `CreateConfigPanel(container, savedVars)`: Creates the AceGUI config panel

### Existing Modules

1. **CombatTimer**: Displays a timer showing how long you've been in combat. Ported from WaitRaidTools.
2. **RangeDisplay**: Displays a warning with range information when your target is out of range during combat. Ported from RangeDisplay addon with spec-based spell range checking.
3. **Profiles**: Profile management with export/import functionality. Three tabs: Profiles (manage profiles, global profiles, spec-specific profiles), Export (export profile to shareable string), Import (import profile from string).

## Database Structure

Uses AceDB with profile support:

```lua
WaitQOLDB = {
    profile = {
        modules = {
            [moduleName] = { module-specific settings }
        }
    },
    global = {
        UseGlobalProfile = false,
        GlobalProfile = nil,
    }
}
```

## Profile System

- Per-character profiles
- Profile copy/delete/reset operations
- Global profile option (same profile across all characters)
- Spec-specific profiles (dual-spec support)

## Release & Versioning

- **Versioning:** Semantic versioning (`vMAJOR.MINOR.PATCH`). The `.toc` file uses `@project-version@`, which is replaced at package time by the BigWigsMods packager.
- **Release process:** Push a git tag matching `v*` (e.g. `v1.0.0`). The GitHub Actions workflow runs the BigWigsMods packager, which builds the zip and publishes to configured platforms.
- **Distribution:** Can be published to wago.io and/or CurseForge (TOC fields need to be added).
- **Packaging:** Configured via `.pkgmeta`. The packager fetches Ace3 and LibSharedMedia libraries and strips development files.

## Dependencies

- Ace3 (AceAddon-3.0, AceDB-3.0, AceConsole-3.0, AceEvent-3.0, AceGUI-3.0, AceConfig-3.0)
- LibSharedMedia-3.0
- AceGUI-3.0-SharedMediaWidgets
- LibDualSpec-1.0 (for spec-specific profile support)
- LibDeflate (optional, for profile export/import compression - not included, uses existing installation if available)

All dependencies are externals managed by the BigWigsMods packager. For local development, libs can be copied from existing WoW addons or fetched via the packager.

## Git Configuration

- **Committer:** `EJ-K <elliot@clerwood.dev>`
- **Default branch:** `main`
- **Commit style:** Concise conventional commit messages (e.g. `feat: add innervate tracker`). Do not include `Co-Authored-By` or any AI attribution in commits.

## Adding New Modules

1. Create a new file in `Modules/` directory
2. Implement the module table with required functions
3. Call `WaitQOL:RegisterModule(name, moduleTable)` at the end
4. Add the module file to `WaitQOL.toc` in the Modules section

## WoW API

An MCP tool is available for looking up WoW API functions, events, enums, widgets, and namespaces.

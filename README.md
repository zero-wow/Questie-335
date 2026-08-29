# Questie-335

Questie 9.5.2 fork adapted for Project Ascension's WoW 3.3.5a-based client, including Conquest of Azeroth compatibility.

This is not a Retail addon and does not target Wrath Classic 3.4.x.

## Installation

1. Place the repository folder at `Interface\AddOns\Questie-335`.
2. Confirm that `Questie-335.toc` remains directly inside that folder.
3. Restart the client after a new installation, or use `/reload` after updating existing Lua files.

## Commands

- `/q335` opens the legacy Questie configuration.
- `/qc` opens the custom Questie configuration panel.

## Ascension Notes

- The active load path is `Questie-335.toc`, targeting interface `30300`.
- Other TOC files are retained from the upstream source but are not supported install targets for this Ascension build.
- Ascension-specific compatibility is isolated from unsupported Retail and Wrath Classic APIs.
- Tracker, map, minimap, quest-database, custom-class, and Ascension objective behavior have targeted compatibility changes.

## Attribution

This project is based on the Questie addon and retains upstream author attribution in its TOC files. Third-party notices and licenses distributed with embedded assets and libraries remain in `Icons/` and `Libs/`.

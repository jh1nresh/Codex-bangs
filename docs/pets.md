# Custom pet packages

Codex-bangs supports one local pet library per macOS user. Imported pets live
under:

```text
~/.codex/pets/<pet-id>/
├── pet.json
└── spritesheet.webp
```

## Shareable `.codexpet` format

A `.codexpet` is a macOS package directory, not a ZIP parser or executable.
Finder presents the directory as one document. Its required contents are a
`pet.json` manifest and the single PNG or WebP atlas named by that manifest.

```text
my-pet.codexpet/
├── pet.json
└── spritesheet.webp
```

```json
{
  "id": "my-pet",
  "displayName": "My Pet",
  "description": "A friendly local Codex companion.",
  "spriteVersionNumber": 2,
  "spritesheetPath": "spritesheet.webp"
}
```

The importer copies only those two validated files. It rejects symlinked
packages or assets, unsafe IDs or paths, malformed or oversized manifests,
unsupported image formats, incorrect atlas dimensions, and an ID that is
already installed. It never overwrites an existing pet.

## V2 atlas contract

- `1536 × 2288` PNG or WebP
- `8 × 11` cells
- each cell is `192 × 208`
- rows 0–8: idle, running right, running left, waving, jumping, failed,
  waiting, working, and review
- rows 9–10: sixteen clockwise look directions from `000` through `337.5`

A new pet is complete only after the full v2 generation, direction,
continuity, transparency, and visual QA gates pass. A partial nine-row sheet is
not installable as a new Codex-bangs pet.

## Create with Codex

Choose `Settings → Create My Pet…` and describe the character. A fresh app
download includes the Apache-2.0 `$hatch-pet` runtime. When the skill is absent,
select `Install Skill & Continue in Codex`; Codex-bangs copies only the bundled
runtime allowlist into `~/.codex/skills/hatch-pet` through a private staging
directory and an exclusive final rename. It rejects symlinks and never changes
an existing item at that path. When the skill already exists, the button reads
`Continue in Codex` and uses it without modification.

Codex-bangs then opens a reviewable prompt asking the verified local Codex
desktop app to use `$hatch-pet`, finish the full v2 QA contract, and install the
final package under `~/.codex/pets`. Return to Codex-bangs and use Reload if the
new pet was installed after the app was already open.

Pet files remain local unless the user explicitly shares the `.codexpet`
package.

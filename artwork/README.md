# App icon — wave to upright lowercase i

Selected concept: `AppIcon-approved-concept.png`. Production transparent tile: `AppIcon-source.png`, copied byte-for-byte to `MiniTypelessSecure/AppIcon.icon/Assets/Approved.png`. Generated with built-in image_gen; not an SF Symbol. User approved the connected asymmetric wave / upright lowercase i concept. Menu-bar and in-window symbols remain unchanged.

The native Icon Composer pipeline remains in place, with Assets.car and fallback ICNS. Glass appearance is baked into the icon, not live desktop blur. The prior A artwork remains recoverable through Git (c9c8e8a and earlier). See [CHG-20261025-01](../docs/changes/CHG-20261025-01.md).

## Production extraction prompt (built-in image_gen)

Precise extraction of approved app icon, NOT redesign. Extract ONLY the large blue glass rounded-square icon from the reference presentation card, preserving its exact silver rim, blue glass texture, lighting, and white waveform connecting via tight elbow to perfectly VERTICAL lowercase i with centered dot. Remove the surrounding white presentation background, top-left label, and small black glyph beneath completely. Output a single square PNG with TRUE transparent alpha outside the rounded icon. Enlarge the extracted tile so its outer square bounds nearly fill the canvas, approximately 96% of canvas width and height, centered with equal tiny transparent margins. No extra pedestal, no new background, no separate dark glyph, no labels. Preserve left asymmetric two wave crests, short flat transition, crisp upright i exactly from source. Preserve original style and proportions, not a new interpretation. This will be a production macOS icon artwork; only isolate and scale the approved large tile.

Generation: exec-6e5a8b93-594a-4545-b3e5-4284bdbc0c3b.png. Approved concept: exec-bc9abec2-5a40-4616-85df-958fbc963113.png. Source files are stored in the repository, independent of external generation paths.

## Historical artwork documentation (superseded)

# App icon — selected A concept

`AppIcon-source.png` is the imagegen-generated artwork selected by the user on 2026-10-23: dark graphite blue-gray glass, three unequal crests, silver-white continuous waveform. It is not an exported SF Symbol. The transparent-background B exploration was not selected. This provenance is not trademark clearance.

Built-in image_gen tool; edit reference was the earlier two-column A/B concept board. Original selected generation filename: `exec-5afc029f-7652-4246-a595-753c199cc20d.png`. This project copy is the packaging source, not a link to a temporary external file.

The approved raster is copied unchanged into `MiniTypelessSecure/AppIcon.icon/Assets/Approved.png`. Xcode compiles this Icon Composer document into `Assets.car` for macOS 26+ and a fallback `AppIcon.icns` for older systems. Build with the normal Xcode scheme; do not replace the native catalog with the former hand-packed ICNS. The native layer scale (1.03) and vertical translation (6 pt) account for the source canvas margin and align its glass tile to the system mask. Additional layer glass/specular/shadow effects are disabled to preserve the approved baked artwork. A matching dark fill covers any subpixel seam at the mask edge.

Source has transparent exterior; glass texture is baked artwork, not live desktop blur. The former ICNS-only delivery (Preview 6) triggered the extra macOS 26 plate; see CHG-20261023-07. System-rendered before/after images are saved under docs/assets, not simulated Dock mockups.

## Generation prompt (verbatim)

Edit the supplied reference into ONE isolated macOS app icon. Use ONLY option A on the LEFT: preserve its dark graphite blue-gray frosted glass rounded-square tile, subtle precise silver rim, restrained shallow depth, luminous silver-white waveform, refined quiet aesthetic. Discard B and all board labels, backdrop, Dock strip and other objects. Transparent background OUTSIDE the rounded icon silhouette, generous narrow transparent margin, front-facing centered square composition. The glass tile itself remains dark graphite translucent-looking material, readable silver-white mark. Change the original two-crest waveform to THREE closely grouped, distinctly ASYMMETRIC rounded crests in a single continuous monoline. From left to right: a small low first crest, a taller second crest offset slightly left of center, and a medium-height third crest at a slightly different spacing, with unequal trough depths and minimal short end tails. Tallest crest must NOT sit at geometric center; left and right sides must not mirror. Organic audio vibration, controlled purposeful rhythm, total mark width about 55 percent of tile, height about 30 percent. Maintain clear open gaps between oscillations at small sizes, smooth round ends, substantial elegant consistent line thickness. No symmetry, no three mountain peaks, no sharp ECG zigzag, no disconnected equalizer bars, no Apple SF Symbols. Preserve A's material and palette faithfully, no bright blue, no white tile, no extra decorative effects. No text. This is the refined single icon artwork for a quiet personal voice dictation utility.

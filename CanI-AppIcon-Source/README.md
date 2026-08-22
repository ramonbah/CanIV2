# CanI app icon source

This package contains flat, gradient-free source artwork for recreating the CanI icon in Apple Icon Composer.

## Layers

Import the SVG files in this order, back to front:

1. `01-gauge.svg` — budget-capacity C, `#12A7AA`
2. `02-markers.svg` — separated gauge markers, `#79D8C2`
3. `03-clock.svg` — Time Effort hands and hub, `#FFF1D6`

Set the Icon Composer background to solid navy `#071B4A`. Do not import a canvas mask; the system applies it.

## Suggested Icon Composer treatment

- Platform: iOS only
- Maximum groups: three, one group for each supplied layer
- Fill: preserve the solid source colors
- Specular: Automatic or Inside, kept restrained
- Refraction: low
- Translucency: low to moderate
- Blur: low
- Shadow: low, enough only to separate the layers
- Composition: keep the supplied alignment and scale unless a small-size preview reveals clipping

Preview Default, Dark, Mono, Clear, and Tinted appearances at Home Screen, Spotlight, Settings, and notification sizes. The C, markers, and clock must remain visually separate in every appearance.

Apple recommends applying blur, refraction, translucency, shadow, and specular treatment inside Icon Composer rather than baking those effects into the source artwork.

## Included fallback

`AppIcon-1024.png` is an opaque, flattened, gradient-free fallback for the existing asset catalog or repository documentation. Xcode and iOS apply the icon mask; do not round its corners manually.

`app-icon-preview.svg` is the combined vector preview used to export the fallback PNG.

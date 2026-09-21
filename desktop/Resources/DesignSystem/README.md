# Protegia.sys → Semantic native mapping

Source: https://design.protegia.io and the local Protegia repository, `src/styles/theme.css`, `src/styles/fonts.css`, `src/app/components/ui/button.tsx`, and `src/app/components/ui/input.tsx` (snapshot 2026-09-20).

`protegia-theme.css` is an unchanged source snapshot. `Sources/ProtegiaTheme.swift` maps the dark semantic values into reusable native colors, typography, buttons, inputs, and dividers. Updates are explicit; this is not a live package dependency.

- Base / level 1 / level 2: neutral 900 / 800 / 700.
- Text: neutral 50 / 300 / 500; accent: primary green (#00ff77).
- Primary buttons: white fill, black text, 36 pt height, 8 pt radius (the current Button component uses rounded-md).
- Cards and fields: 8 pt corners; panel/picker: 14 pt corners.
- Lato Regular/Bold bundled under SIL Open Font License; 10/12/14/18/24/28 pt typography, with system monospace reserved for code references.
- Spacing: 8/12/16/24 pt, translated from the CSS pixel scale for the desktop interface.
- Native adaptation: input focus uses the secondary text color for a visible outline; system keyboard focus and checkbox behavior are preserved. The app explicitly uses the dark Protegia theme.

The Semantic name and # mark remain the app identity. The earlier browser prototype is unchanged.

## Browser use

Use the browser within Codex for website interactions. Do not control Chrome, Safari, or Edge. If a site or session is unavailable in the Codex browser, ask the user to open or sign in there.

## Design system

Protegia is the default design system for every UI change. Reuse its components and tokens; do not introduce ad hoc settings controls or platform-default field styling. For the native macOS app, use and extend the reusable SwiftUI counterparts in `desktop/Sources/ProtegiaTheme.swift`, with source mappings documented in `desktop/Resources/DesignSystem/README.md`. Consult the Protegia component source before adding a new counterpart. Do not claim a native adaptation is a direct React component import. Use shared list/list-item, input, select, and button components in settings and forms.

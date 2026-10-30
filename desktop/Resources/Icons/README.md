# Offline icon artwork

`artwork.json` contains static SVG geometry from public packages, including their exported aliases. Generate it with `desktop/scripts/generate-icon-artwork.py` from unpacked packages. The generator reads data literals without executing JavaScript. The app reads repository semantic mappings and validated provider path strings; it never executes imported TypeScript.

Pinned inputs (SHA-256):

- lucide-react 0.577.0: `272da56bc93890182e33b78647ef87cff10ad8f2369bc1387c4aa44d66beded5` (ISC).
- react-icons 5.6.0: `b5250edccb950df3fe49057d888f3ad2707fbec558a54678e139a574facf0ae9` (MIT; GitHub Octicons artwork MIT).

The official `rotate-cw-fading-clock.svg` backport is from https://github.com/lucide-icons/lucide/blob/main/icons/rotate-cw-fading-clock.svg, downloaded 2026-10-30; SHA-256 `a91ad6c9725d58d3146b82178cb507d0ce196d59f30488b4974ca449d3ebbccd`. It matches the catalog's backport geometry. Lucide's license applies.

License texts are included alongside the artwork. No private repository source or semantic-name mapping is bundled here.

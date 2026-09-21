# DesignSnippets

A local-first workspace for referencing design-system tokens in coding-agent prompts. Built with React, TypeScript, and Vite.

## Native menu bar app

The new macOS implementation is in `desktop/`. It connects a GitHub App, indexes selected repositories, and provides an opt-in system-wide `#` picker. See [desktop setup and testing](desktop/README.md).

```sh
npm run desktop:build
npm run desktop:open
```

## Web prototype

### Run

```sh
npm install
npm run dev
```

## How it works

- Explore the clearly labeled example codebase, or connect a local project folder.
- Import CSS custom properties and CSS classes from CSS, SCSS, Sass, and Less files. Generated folders and files larger than 2 MB are skipped.
- Search and filter the token library. Type `#` in the composer to search tokens from the selected codebase; use arrow keys and Enter/Tab, or click, to insert one. Escape closes suggestions.
- Prepare and copy a prompt containing exact token values, source paths, and CSS variable references.
- Imports persist in browser localStorage. Re-import to refresh; disconnect through Settings.

## Scope

This version reads local stylesheets in the browser and prepares prompts; it does not authenticate to GitHub, watch files, invoke an AI model, or modify connected codebases. Token extraction is a lightweight text parser, not a full CSS/SCSS compiler. It records declarations, not computed theme values, and does not parse JavaScript theme configurations or JSON token files. With duplicate token names, the last declaration wins.

## Checks

```sh
npm run build
npm run lint
```

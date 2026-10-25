---
layout: default
title: "Aster Calculator Documentation and Developer Guides"
description: "Find Aster's Windows setup instructions, calculator modes, numeric precision reference, development guide and component test methodology."
permalink: /documentation/
---

# Aster Calculator Documentation

Choose the reference for the calculation model, local build or portable Windows package you are working with.

<a id="source-and-related-projects"></a>

## 🧭 Choose a guide

| Task | Guide |
|---|---|
| Install and use the calculator | [README quick start](README.md#readme-quick-start) and [mode examples](README.md#readme-usage) |
| Understand precision and range limits | [Numeric behavior](docs/numeric-behavior.md) |
| Build and run engine tests | [Development guide](docs/development.md) |
| Interpret hidden UI reports | [WinForms component-check methodology](tests/ModernCalculator.UiChecks/README.md) |
| Verify, package, update or remove the app | [Portable release guide](docs/release-guide.md) |

## 🔗 Source references

[Solution](https://github.com/gcfernando/aster-windows-calculator/blob/main/ModernCalculator.sln) · [SDK selection](https://github.com/gcfernando/aster-windows-calculator/blob/main/global.json) · [Windows verification workflow](https://github.com/gcfernando/aster-windows-calculator/blob/main/.github/workflows/verify.yml)

Engine tests, hidden component snapshots and visible manual walkthroughs prove different things. Follow the development guide before interpreting an artifact as acceptance evidence.

## 🌐 Published documentation

This index is also rendered by the repository's GitHub Pages site. Relative links above point to the authored repository documents; package READMEs target NuGet readers and may use absolute GitHub links.

[Repository](https://github.com/gcfernando/aster-windows-calculator) · [Project overview](README.md)

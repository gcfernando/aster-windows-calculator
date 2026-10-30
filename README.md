# Aster

Aster is an offline Windows calculator for everyday arithmetic, scientific expressions, programmer calculations, unit conversions and date arithmetic.

[![Repository standards](https://github.com/gcfernando/aster-windows-calculator/actions/workflows/repository-standards.yml/badge.svg)](https://github.com/gcfernando/aster-windows-calculator/actions/workflows/repository-standards.yml) [![Verify Aster](https://github.com/gcfernando/aster-windows-calculator/actions/workflows/verify.yml/badge.svg)](https://github.com/gcfernando/aster-windows-calculator/actions/workflows/verify.yml)

Use Aster to check a percentage, evaluate a formula, inspect an integer in four bases, repeat a conversion or compare dates. Calculations run locally without an account, payment or activation key. The application is written in C# 14 with .NET 10 and Windows Forms.

## Features

- Five modes: Standard, Scientific, Programmer, Converter and Dates.
- Searchable local history, reusable results and Standard decimal memory.
- Light, dark and system themes, keyboard navigation and compact layouts.
- Different precision models for different tasks: bounded decimal arithmetic in Standard, approximate binary64 arithmetic in Scientific and Converter, and fixed-width integers in Programmer.

![Aster Scientific mode with a light theme](docs/images/scientific-light.png)

The existing capture shows Scientific mode. See the [interface and screenshot guide](docs/user-guide.md#guide-desktop-interface) for the other modes.

## Download and run

Open the [application releases](https://github.com/gcfernando/aster-windows-calculator/releases) and select a release containing **Aster-win-x64.zip** and **SHA256SUMS.txt**. The existing [legacy main preview](https://github.com/gcfernando/aster-windows-calculator/releases/tag/latest) also contains a Windows package. GitHub's source-code ZIP and tarball are source archives, not the application.

1. Install the [.NET 10 Desktop Runtime for Windows x64](https://dotnet.microsoft.com/en-us/download/dotnet/10.0).
2. Download the application ZIP and its checksum file from the same release.
3. Compare the ZIP's SHA-256 with its entry in `SHA256SUMS.txt`:

   ```powershell
   Get-FileHash .\Aster-win-x64.zip -Algorithm SHA256
   ```

4. Extract the entire ZIP to a writable folder and run `Aster.exe`. Keep its companion files together.

Release notes state whether a package is signed. Without a configured trusted signing identity, releases are **unsigned** and Windows may show **Unknown publisher** or a SmartScreen warning. The portable package does not bundle the .NET runtime. Use a Windows x64 edition supported by .NET 10; see Microsoft's [supported operating systems](https://github.com/dotnet/core/blob/main/release-notes/10.0/supported-os.md). Download only packages you trust. See the [release guide](docs/release-guide.md) for updates, rollback and removal.

## Use Aster

Choose a mode from the sidebar, enter the values and use the result in place or copy it for another task.

| Task | Start with |
| --- | --- |
| Everyday arithmetic and percentages | Standard; `Enter` or `=` calculates, `F9` changes sign |
| Formulas and trigonometry | Scientific; choose degrees or radians before evaluating |
| Binary, octal, decimal and hexadecimal integers | Programmer; choose width, signed interpretation and input base |
| Measurements and temperatures | Converter; choose the category and source/destination units |
| Add/subtract calendar periods or compare dates | Dates; enter dates or use the calendar |

`Ctrl+1` through `Ctrl+5` switch modes, `Ctrl+H` opens history and memory, and `F1` opens built-in help. Preferences also offers `Ctrl+Alt+1` through `Ctrl+Alt+5` for mode switching. See the [complete shortcuts and usage guide](docs/user-guide.md#readme-shortcuts).

Standard accepts up to 100 significant input digits and rounds division and square root to 100 significant digits. Scientific uses approximate real-number calculations; it is not symbolic algebra and has no complex-number mode. Programmer arithmetic wraps modulo the chosen integer width. Dates uses Gregorian dates from year 0001 through 9999 without time zones. Read the [numeric behavior reference](docs/numeric-behavior.md) before relying on rounding, conversion or range boundaries.

## Configuration and local data

Preferences controls the theme, density, startup mode and shortcuts. Use Scientific's angle selector to choose degrees or radians. Settings and conversion favorites are stored locally in `%LOCALAPPDATA%\AsterCalculator\state.json`; history persistence is off by default and memory is session-only. `ASTER_DATA_DIRECTORY` selects a separate data folder. The app does not require a calculation service. Back up your state file before replacing or clearing local data; [configuration and recovery details](docs/user-guide.md#guide-configuration-and-local-data) explain state behavior.

## Development and testing

Build on Windows with PowerShell 7 and the .NET 10 SDK selected by [global.json](global.json). Run these commands from the repository root:

```powershell
dotnet restore ModernCalculator.sln
dotnet build ModernCalculator.sln -c Release
dotnet run --project src/ModernCalculator.WinForms -c Release
dotnet test tests/ModernCalculator.Tests -c Release
```

For complete release verification and a portable candidate:

```powershell
./tools/Verify-Release.ps1
# Use the manifest path printed by verification:
./tools/Publish-Portable.ps1 -VerificationManifest artifacts/ReleaseVerification/<run>/manifest.json
```

The placeholder `<run>` must be replaced with that run's actual directory name. Verification restores and builds the app, discovers and runs all engine tests, runs the hidden Windows Forms component harness, and records matching source/binary/report hashes before packaging. Hidden component checks do not establish physical keyboard/mouse behavior, assistive-technology output or every monitor configuration. See [development instructions](docs/development.md) and the [component harness guide](tests/ModernCalculator.UiChecks/README.md).

## Automated releases

The [verification workflow](https://github.com/gcfernando/aster-windows-calculator/actions/workflows/verify.yml) publishes a separate preview for every successful push to `main`, after verification, packaging and publication-policy tests pass. Builds remain unsigned while signing is disabled. Maintainers can enable the [public-trust signing pipeline](docs/code-signing.md) after configuring a trusted identity; enabled signing must succeed before publication. The release tag is `v<base-version>-main.<run-id>.<full-commit-sha>`. Different pushes retain different releases; no branch-level concurrency cancels or discards an earlier push. Application version remains **1.0.0**.

Packages and their SHA-256 manifest are uploaded to a draft first. Publication follows successful upload verification. A rerun can recover its own interrupted draft; an already published release is verified and retained. Pull requests and manual runs produce artifacts without publication. Existing versioned releases and the legacy rolling `latest` preview are preserved. The [release guide](docs/release-guide.md) describes permissions, signing and remaining manual acceptance checks.

## Troubleshooting

- **The app does not start:** install the .NET 10 **Desktop** Runtime for x64 and extract all ZIP contents. The SDK is needed only for building.
- **Windows protected your PC / Unknown publisher:** check the release's signing status. Signing support requires a configured trusted publisher; a GitHub release label or checksum cannot remove this warning. A newly signed app may still need to establish reputation. See [signing and SmartScreen](docs/code-signing.md).
- **A result differs from another calculator:** check the active mode, degree/radian setting, integer width and [precision rules](docs/numeric-behavior.md).
- **Preferences or history cannot be saved:** check that the local data folder is writable and review the recovery guidance before changing `state.json`.
- **A release or asset is missing:** use a complete earlier release and inspect the [workflow runs](https://github.com/gcfernando/aster-windows-calculator/actions/workflows/verify.yml). A failed build does not publish a partial application release.

The [detailed user guide](docs/user-guide.md) preserves the full interface, architecture, keyboard, troubleshooting and publishing reference.

## Contributing and support

Read [CONTRIBUTING.md](CONTRIBUTING.md) before changing code or documentation. Report reproducible problems through [GitHub issues](https://github.com/gcfernando/aster-windows-calculator/issues); use [SECURITY.md](SECURITY.md) for vulnerability reports. [All documentation](documentation.md) provides further entry points, and [repository standards](REPOSITORY_STANDARDS.md) explains maintenance checks.

## License

Developed by Gehan Fernando and released under the [MIT License](LICENSE). The separately installed Microsoft .NET runtime retains its own terms.

<a id="-aster--offline-windows-calculator"></a>
<a id="-features-and-real-world-use-cases"></a>
<a id="readme-features"></a>
<a id="readme-gui"></a>
<a id="guide-desktop-interface"></a>
<a id="readme-gallery"></a>
<a id="readme-quick-start"></a>
<a id="guide-quick-start"></a>
<a id="-configuration-privacy-and-local-data"></a>
<a id="readme-configuration"></a>
<a id="-usage-guide"></a>
<a id="readme-usage"></a>
<a id="readme-shortcuts"></a>
<a id="readme-numeric-behavior"></a>
<a id="guide-numeric-behavior-and-limits"></a>
<a id="-architecture-and-technology"></a>
<a id="readme-architecture"></a>
<a id="️-architecture-and-technology"></a>
<a id="-testing-and-development"></a>
<a id="readme-development"></a>
<a id="guide-development-and-testing"></a>
<a id="readme-publishing"></a>
<a id="-troubleshooting-and-faq"></a>
<a id="readme-troubleshooting"></a>
<a id="readme-contributing"></a>
<a id="-license-and-resources"></a>
<a id="readme-license"></a>
<a id="readme-documentation"></a>

[Open the complete preserved user reference](docs/user-guide.md).

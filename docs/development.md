# Building and Testing Aster — .NET 10 and Windows Forms

Build the Windows calculator, run the engine and persistence tests, inspect hidden WinForms component reports, and prepare a local distributable folder. Run commands from the repository root in PowerShell unless a section says otherwise.

[Aster overview and quick start](../README.md) · [Numeric behavior](numeric-behavior.md) · [Component-check methodology](../tests/ModernCalculator.UiChecks/README.md)

## Prerequisites

- Windows for the application, component harness and visible desktop walkthrough.
- The [.NET 10 SDK](https://dotnet.microsoft.com/en-us/download/dotnet/10.0). [global.json](https://github.com/gcfernando/aster-windows-calculator/blob/main/global.json) selects `10.0.100` with `latestFeature` roll-forward, so later installed .NET 10 feature bands can satisfy it.
- Git for cloning the repository, and NuGet access on initial restore. [NuGet.Config](https://github.com/gcfernando/aster-windows-calculator/blob/main/NuGet.Config) configures nuget.org; the xUnit project declares the external test packages.
- For IDE development, Visual Studio 2026 (18+) with .NET desktop development support. Match the SDK/IDE combination to Microsoft's [SDK and Visual Studio compatibility rules](https://learn.microsoft.com/en-us/dotnet/core/porting/versioning-sdk-msbuild-vs).

Check the selected SDK from inside the checkout:

```powershell
dotnet --version
dotnet --list-sdks
```

[Directory.Build.props](https://github.com/gcfernando/aster-windows-calculator/blob/main/Directory.Build.props) sets C# 14, nullable reference types, implicit usings, deterministic builds and warnings as errors. Application projects have no third-party package references. Keep the existing project and package settings when following these commands.

## Restore and build

```powershell
dotnet restore ModernCalculator.sln
dotnet build ModernCalculator.sln -c Release --no-restore -m:1
```

The solution builds Core, Infrastructure, the Windows Forms application, the xUnit suite and the hidden component executable. It does not include `ModernCalculator.DesktopAudit`; that optional project builds separately.

To launch the application after the build:

```powershell
dotnet run --project src/ModernCalculator.WinForms -c Release --no-build
```

For experiments that should use a fresh local profile, set `ASTER_DATA_DIRECTORY` before launch as shown in [configuration and local data](../README.md#readme-configuration).

## Choose the appropriate verification tool

| Tool | Checks | Evidence limits |
|---|---|---|
| `ModernCalculator.Tests` | Calculation engines, input/state contracts and persistence | Does not open the application or exercise native controls. |
| `ModernCalculator.UiChecks` | Hidden WinForms controls, handlers, layout, snapshots and relative-scale simulations | Does not show windows or prove physical input, desktop composition, monitor transitions or screen-reader behavior. |
| `ModernCalculator.DesktopAudit` | A visible production MainForm for a manual walkthrough | Sends no automated input and produces no automatic pass/fail verdict. |

`dotnet test` runs the xUnit suite. Run the component executable separately with `dotnet run`; it is not a test-framework project.

## Run the engine and persistence tests

```powershell
dotnet test tests/ModernCalculator.Tests -c Release --no-restore --logger "console;verbosity=minimal"
```

Coverage includes decimal precision/state, scientific grammar/domains, base/bit operations, conversion round trips, date boundaries, culture-aware input, memory/history, restorable calculator snapshots and persistence recovery. The WinForms component harness separately exercises the view-level undo/redo behavior. Engine tests do not open a window.

The packaging report validator has a separate dependency-free PowerShell regression script:

```powershell
pwsh -NoProfile -File tests/PackageEvidence.Tests.ps1
```

It checks complete passing and incomplete, aborted or inconsistent TRX evidence without creating archives.

To retain a machine-readable result:

```powershell
dotnet test tests/ModernCalculator.Tests -c Release --no-restore --logger "trx;LogFileName=engine-tests.trx" --results-directory artifacts/TestResults
```

Use the actual result count and outcome in that TRX report. The suite can grow; a hard-coded count in a README or packaging default is not evidence that the current checkout passed.

## Run the hidden component harness

After the solution build:

```powershell
dotnet run --project tests/ModernCalculator.UiChecks -c Release --no-build -- artifacts/UiChecks
```

Every run creates a unique child directory containing `report.json`, `report.txt`, isolated state and PNG snapshots. A second positional argument filters check names. A filter that selects no checks fails explicitly. A filtered run or exit code `0` alone is not a complete acceptance record: inspect `focus`, `passed`, `failed` and `skipped` in the JSON report.

The [component guide](../tests/ModernCalculator.UiChecks/README.md) explains filter behavior, diagnostics, DPI terminology and the limits of hidden rendering. Keep the report and snapshots together when reporting a regression.

## Run a visible manual walkthrough

```powershell
dotnet run --project tests/ModernCalculator.DesktopAudit -c Release
```

DesktopAudit hosts the production MainForm and engines with a fresh session under its executable output folder's `sessions/` directory. It starts in Dark/Standard with history persistence disabled. It does not use the normal user profile or send automated input. Close the window to end the walkthrough.

Use it to investigate actual focus, keyboard/mouse routes, resize/maximize behavior, clipboard actions, high contrast, screen-reader behavior and monitor transitions. Record the observed Windows version, monitor working area, scaling, theme, window size and steps; the hidden PNGs cannot establish those outcomes.

## Publish a local Windows folder

Use the [README's framework-dependent or self-contained publish commands](../README.md#readme-publishing). The framework-dependent application needs the matching .NET 10 Desktop Runtime on the destination computer; the self-contained option includes its selected runtime. Keep the complete output folder together.

These commands produce local artifacts. Signing, an installer and an in-app update service are not implemented by these tools. The separate CI publication step below uploads an unsigned preview.

For the complete reproducible verification-to-package workflow, follow [the portable release guide](release-guide.md). `Verify-Release.ps1` discovers the engine count, requires complete passing engine/component reports and binds source inputs, test reports and application/test binaries by SHA-256 before and after execution. `Publish-Portable.ps1` validates that evidence, includes LICENSE and documentation, and verifies every archive entry. It produces a fresh local unsigned framework-dependent x64 candidate and does not upload it. Run `tests/ReleaseEvidence.Tests.ps1` for negative evidence-boundary regressions.

The [Windows CI workflow](https://github.com/gcfernando/aster-windows-calculator/blob/main/.github/workflows/verify.yml) runs these helpers and retains successful packages for 30 days and verification reports for 14 days. Only a passing push to the current `main` commit reaches its separate `contents: write` publication job. `Publish-MainBuild.ps1` checks the downloaded ZIP checksum, verifies the current branch head, and creates or updates the reserved `latest` prerelease. Its tag moves to the published commit; versioned releases are untouched. No personal access token is needed: the job uses GitHub's scoped workflow token. Run `tests/MainBuildRelease.Tests.ps1` for mocked publication-policy regressions; those tests never call GitHub. See the release guide for the permanent link and recovery from failed uploads.

## Specialized audit packaging

[Package-Audited.ps1](https://github.com/gcfernando/aster-windows-calculator/blob/main/tools/Package-Audited.ps1) is a separate acceptance/archive helper. It does not build or run checks. It now requires the same fresh verification manifest as the portable publisher, plus its historical prepared reports, published binaries and corresponding build outputs. It rejects stale source/binaries/reports, compares binary hashes and verifies ZIP entries against their sources.

| Parameter | Current script behavior |
|---|---|
| `VerificationManifest` | Required repository-relative path to a matching manifest produced by `Verify-Release.ps1`. Reports and published application bytes must match it. |
| `UiReport` | Required repository-relative path to a completed `report.json`. It must have an empty `focus`, zero failed/skipped checks and at least `MinimumUiChecks` passed checks. |
| `EngineReport` | Repository-relative TRX path; defaults to `artifacts/TestResults/audit-final.trx`. |
| `ExpectedEngineTests` | Required total, executed and passed count; its historical default is `283`. The report must be completed, contain that many passing result entries, and have no nonzero failure, skip, abort or other outcome counters. |
| `MinimumUiChecks` | Minimum passed-check count; its historical default is `205`. |
| `Edition` | Archive/release label, default `Audited`. |
| `BuildOutput` | Build-directory suffix under project `bin/` folders, default `AuditAcceptance`. |

The helper expects an already prepared `artifacts/Aster-<Edition>/` folder, compares its four application binaries with `src/ModernCalculator.WinForms/bin/<BuildOutput>/`, and compares the Core/Infrastructure libraries with those in `tests/ModernCalculator.Tests/bin/<BuildOutput>/`. It also checks for a Windows x64 app host and copies five specifically named dark/100%-simulation screenshots from the UI report directory. Existing archive paths cause it to stop rather than overwrite them. Source enumeration requires `rg` on `PATH`.

Confirm the exact paths, expected counts and screenshot names against the script and the approved run before using it. Ordinary Release output from the commands above does not automatically satisfy these packaging assumptions.

### Packaged evidence and documentation

Generated `START-HERE.txt` links to this development guide, the numeric behavior reference and the reports copied into `verification/`. The package's label does not expand what those reports prove: hidden component snapshots do not establish physical-input, window-manager, screen-reader or native monitor-transition behavior. Review the actual reports and supply any required external validation before distribution.

## Contributing

Preserve the [numeric contracts](numeric-behavior.md), keep changes focused and run the appropriate engine/component checks. For a regression report, include the exact input, mode, regional settings and environment, plus relevant TRX or component artifacts. See the [contribution section](../README.md#readme-contributing) for the issue tracker and UI-reporting details.

## Related documentation

[Documentation index](../documentation.md) · [Portable release guide](release-guide.md) · [Numeric contracts](numeric-behavior.md)

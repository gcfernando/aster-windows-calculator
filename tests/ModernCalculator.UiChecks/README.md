# Aster Windows Forms component checks

This Windows-only console harness checks Aster's forms and controls without opening application windows. Use it while changing layout, calculations, navigation or persistence; start with the [Aster project README](../../README.md) for application setup.

## Run the checks

Use Windows, PowerShell 7 and the .NET 10 SDK selected by the repository's `global.json`. From the repository root:

```powershell
dotnet run --project tests/ModernCalculator.UiChecks -c Release -- artifacts/UiChecks
```

The harness writes a JSON report and PNG snapshots under the supplied output directory and returns a nonzero exit code when checks fail. A complete release run should use [Verify-Release.ps1](../../tools/Verify-Release.ps1), which builds the application, runs engine and component tests and records source/binary/report hashes together.

## What it checks

- Five modes, light/dark themes, layout bounds, text fit and accessible control names.
- Mode switching, history and memory, converter paging and date workflows.
- Relative scaling and calculated workspace geometry, with actual device DPI recorded in reports.
- Calculation, state, dialog and result-display regressions using isolated test data.

See the [complete harness reference](../../docs/component-checks-reference.md) for output fields, focused debugging options, snapshot names and detailed coverage. Retained anchor links in this document lead to that reference entry point.

## Read the results carefully

The harness creates hidden handles and invokes component behavior in-process. It does not run a Windows desktop message loop, inject physical input, activate the clipboard, navigate external pages or demonstrate screen-reader behavior. Scaling simulations do not change Windows DPI or verify monitor transitions. PNG snapshots can differ from a shown native window.

Do not treat a focused/debugging run as complete release verification. Inspect failures and the recorded scope before relying on a report. Visible acceptance needs the [manual walkthrough and development guide](../../docs/development.md).

## Related documentation

- [Aster overview](../../README.md)
- [Build, tests and manual walkthroughs](../../docs/development.md)
- [Numeric behavior](../../docs/numeric-behavior.md)
- [Portable releases and remaining acceptance checks](../../docs/release-guide.md)
- [Contribution guidance](../../CONTRIBUTING.md) and [MIT License](../../LICENSE)

<a id="hidden-winforms-component-checks"></a>
<a id="aster-winforms-component-checks--running-tests-and-reading-reports"></a>
<a id="guide-run-the-hidden-checks"></a>
<a id="guide-read-the-results"></a>
<a id="guide-scope-and-limitations"></a>

[Open the complete component-check reference](../../docs/component-checks-reference.md).

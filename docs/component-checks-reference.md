<a id="hidden-winforms-component-checks"></a>

[Aster calculator](../README.md)

<a id="aster-winforms-component-checks--running-tests-and-reading-reports"></a>

# Aster WinForms Component Checks

This is a dependency-free Windows-only console harness targeting .NET 10 and Windows Forms. It references the application project directly and does not require a test framework or NuGet package.

> **In this guide:** [Get started](#guide-run-the-hidden-checks) · [Walk through the example](#guide-read-the-results) · [Check the limits](#guide-scope-and-limitations)

The harness covers calculator input/state, mode switching, stored results, conversion and date workflows, preferences, layout and rendering. Results belong to a specific executable and run: use that run's `report.json` for counts and outcomes. See [packaged evidence and documentation](development.md#packaged-evidence-and-documentation) for how the packaging helper uses these reports and their limits.

For a separate visible walkthrough, [DesktopAudit](development.md#run-a-visible-manual-walkthrough) hosts the production MainForm with fresh isolated data under its output `sessions/` directory. It sends no input and does not access the user's normal Aster data. It is optional and separate from this hidden-check executable.

[Run the checks](#run-the-hidden-checks) · [Read the results](#read-the-results) · [Scope and limitations](#scope-and-limitations) · [Scale and DPI](#interpreting-scale-and-dpi)

<a id="guide-run-the-hidden-checks"></a>

## Run the hidden checks

From the repository root on Windows, after restoring and building the solution as described in the [development guide](development.md#restore-and-build):

```powershell
dotnet run --project tests/ModernCalculator.UiChecks/ModernCalculator.UiChecks.csproj -c Release --no-build -- artifacts/UiChecks
```

The first optional argument is the output directory, resolved from the process working directory. Every run creates a unique child directory. The second argument is a case-insensitive substring filter for check names.

For a focused top-level memory check:

```powershell
dotnet run --project tests/ModernCalculator.UiChecks -c Release --no-build -- artifacts/UiChecks "Standard exact"
```

Filtering applies as each check is reached. A nested matrix check is reached only when its parent setup runs, so a child-only substring may select nothing. A filter that selects no checks records a `Check selection` failure and returns exit code `1`. Treat a focused run as diagnostic evidence, not as the complete suite.

<a id="guide-read-the-results"></a>

## Read the results

| Output | Contents |
|---|---|
| `report.json` | Run metadata, check outcomes, screenshot count, DPI/simulation descriptions and layout/render diagnostics. |
| `report.txt` | Check names, status and detail in a text log. |
| PNG files | Hidden component snapshots associated with the run. |
| `state/` and other state subdirectories | Isolated profiles created by the checks; some additional fixtures use temporary directories outside the output folder and clean them up. The normal user profile is not used. |

Use the exact child directory printed by the executable. For example, replace `<run-directory>` below with that directory name:

```powershell
$runDirectory = 'artifacts/UiChecks/<run-directory>'
$report = Get-Content -LiteralPath (Join-Path $runDirectory 'report.json') -Raw | ConvertFrom-Json
$report | Select-Object generatedUtc, focus, passed, failed, skipped, screenshots, actualDeviceDpi
$report.checks | Where-Object Status -eq 'FAIL'
```

Exit code `1` means one or more checks failed, including an empty selection. Exit code `0` means selected checks had no failures; it does not prove rendering was supported. For an unfiltered run, inspect `focus` (empty), `passed` (nonzero), `failed` and `skipped`. Unsupported snapshot rendering is recorded as a skip rather than a successful render. Compare counts with the actual run and source revision, not a permanent README count.

A filtered run can record `actualDeviceDpi=0` when it bypasses the main matrix that populates the field. That is missing run data, not a statement about the monitor's DPI.

### Display and window diagnostics

`report.json` also records every result display's child bounds, client rectangles, text, fonts, padding/margins, actual `DeviceDpi`, table row styles and computed row heights. Initial hidden preparation and each snapshot are labelled separately to help investigate clipped captions or handle-creation layout changes. `actualWindowDiagnostics` records physical window/client/minimum sizes, the monitor working area, border style, startup state and relative simulation factor. These measurements distinguish an actual-DPI default/minimum case from a relative scaling simulation.

## Layout visibility and snapshot method

Layout eligibility uses the current WinForms runtime's named `Control.GetState(...Visible)` flag and each ancestor's own visibility, excluding the deliberately hidden top-level host. This preserves checks for intended visible controls while excluding collapsed result captions, unnecessary pager buttons and unused unit-page slots. It does not use `Control.Visible`, which is false for every child of a hidden form. If the runtime's visibility-state API cannot be identified, checks fail explicitly. Display diagnostics also record this component visibility.

The harness explicitly creates hidden handles for newly attached modes before rendering. Main-form preparation calls the same public working-area sizing method used by the real launch path after hidden handle creation and before relative scaling; it does not invoke `Show` or claim to execute the full form-load lifecycle. MainForm PNGs capture its client-layout root directly. Native style bits retained for Windows snap/resize can cause hidden `Form.DrawToBitmap` to synthesize an OS caption absent from the displayed borderless form; client-root capture avoids presenting that artifact as application chrome. Window/client sizing and viewport assertions still inspect the actual form. Snapshot render probes sample enabled text-bearing custom button regions inside the expected mode, excluding headers/navigation, and fail when the expected center content is blank. Disabled buttons remain covered by accessibility and layout checks but are excluded from the paint-contrast probe. If coarse two-pixel sampling finds fewer than eight contrasting pixels, the same inset region receives full-pixel sampling before declaring it blank; the eight-pixel threshold remains unchanged so tiny chevrons cannot disappear between sample points. `renderDiagnostics` records probe counts; PNGs are retained even when the probe fails. Native-textbox-only font snapshots have no custom button probe and are identified accordingly.

<a id="guide-scope-and-limitations"></a>

## Scope and limitations

The harness creates forms and their handles **without showing windows**, running a Windows message loop, automating the desktop, or injecting keyboard/mouse input. For hidden button component tests it invokes the protected click event handler in-process because `Button.PerformClick()` depends on visibility. It does not activate the physical clipboard, external navigation, or modal dialogs. Preferences tests construct isolated hidden dialogs and directly exercise save/cancel, draft changes, defaults and staged history-clear handlers; no user history or preferences are read or cleared.

## Mode, history and paging coverage

It covers all five modes through the named mode selector, light/dark preferences, no dropdown or context-menu controls, accessible names, positive control bounds, immediate-parent containment and non-overlap. Every mounted interactive control must also fit all ancestor viewports through the form; offscreen content does not satisfy accessibility. Current-page controls in a paged panel are allowed, while scrollbars are rejected. Checks include `AutoScroll`, managed scrollbar configuration and native horizontal/vertical scrollbar window styles on the harness's hidden controls. Converter tests traverse every source/destination unit page in every category and require every unit to be reachable without changing the selected unit merely by paging. Explicitly unused slots on a partial final unit page are excluded from interactive-layout assertions. Standard 100-digit exact memory, repeated result-font reuse/resize/theme rendering, scientific function/angle selectors, programmer base synchronization, and converter choices/history are exercised separately.

Light and dark stored-result checks seed 200 records in isolated state, open the secondary panel at the declared minimum window size and traverse every history page. Every stored result must remain reachable, current-page actions must fit all ancestor viewports, and scrolling must remain disabled. The check returns to the previous page and retains a component snapshot. This pagination check does not activate deletion. Separate commercial UI checks exercise record deletion and confirmed bulk clearing in isolated fixtures.

A separate result-display check pages through a bounded numeric value of about 2,000 characters in a compact hidden host. It reconstructs all page text and requires exact character order and coverage, unchanged `FullValue`, stable page counts, correct previous/next states, visible final text-line bounds and no scrollbar. Replacing that value with a short result must reset paging and hide both pager buttons. Result-page controls are excluded from the calculator keypad when checking memory-row placement.

## Workspace geometry simulations

Fifty **effective workspace geometry simulation** cases exercise all five modes using 1366×768 and 1920×1080 target working areas at target DPIs 96, 120, 144, 168 and 192. Each target policy's physical initial/minimum dimensions are converted to equivalent actual-DPI dimensions (`target size × actual DPI / target DPI`), then applied to a fresh hidden form without changing Windows DPI. Both initial and minimum geometry are checked (100 states), including viewport/text fit, no scrollbars, memory placement, retained 100-digit Standard input, Scientific `sin(30)`, editable Programmer value `255`, live conversion and populated date difference. Visible result fields check native first/last character positions after resizing. Compact Programmer uses its editable base row when its redundant main display is collapsed. Fonts and native controls still use the actual device DPI. The worst 1366×768/192-DPI minimum cases retain client-root PNGs for all five modes.

## Caption and short-result regressions

Caption handler regressions use fresh forms before native HWND creation: minimize must set `WindowState.Minimized`, maximize must toggle to maximized and back to normal, and close must dispose an isolated form. The checks require that these state-only actions do not create a native window. They do not claim to exercise native desktop minimize/maximize/close composition or keyboard shortcuts.

A short-result regression sets `0` or `0.5` once and resizes 650×160 → 480×80 → 650×160 without refreshing the value. It checks native edit formatting bounds, last-character advance/right alignment, complete glyph height, viewport containment and scrollbar absence, allowing four physical pixels for native formatting rounding.

## Startup, minimum size and memory layout

Each mode/theme/scale case creates a fresh form with that mode saved in isolated preferences, verifies startup selection, applies its sizing policy, scales once if requested, and renders/checks that startup view. It then switches to an alternate mode and back to verify selector events without claiming to render the reused hidden HWNDs. Removing and reattaching a view while its top-level host is never shown can leave its native child HWND hidden despite managed own-visibility, so event checks deliberately follow rendering. Fresh forms avoid inheriting Standard's size in modes with different minimum requirements or accumulating scale changes across detached views. Each theme also exercises all five modes at that mode's declared minimum window size. Default and minimum windows at the actual `DeviceDpi` must fit the monitor working area and agree exactly with the sizing policy. The main form must be frameless, start in the normal state and provide keyboard-accessible minimize/maximize/close controls. All six memory actions must share equal heights and widths (allowing one physical pixel of table-column rounding), with Standard memory between its display and keypad and Scientific memory below its keys. `memoryBarDiagnostics` records row bounds, computed table row heights and each memory action's local/view bounds. Compact responsive layouts may reduce button size, but every button must retain at least 16 logical pixels per edge and enough height for its actual font and measured text glyphs. Essential short labels must fit horizontally. Thresholds use actual `DeviceDpi` to convert logical pixels to physical pixels. Every nonempty result caption/detail label must have enough text height for both `Font.Height` and its measured single-line glyph height. These checks catch thin clipped captions that positive bounds alone would miss.

## Interpreting scale and DPI

The 100%, 125%, 150%, **175%**, and 200% cases use relative `Control.Scale(SizeF)` layout simulations. The report also records the **actual** Windows `DeviceDpi`; when it is 144, the unscaled default/minimum cases exercise real 144-DPI hidden controls. Target-DPI sizing-policy calculations cover 96, 120, 144, 168 and 192 DPI against 1920×1080, 1366×768 and 2560×1440 physical-pixel working areas, for all five modes with the secondary panel both open and closed (150 cases). Policy cases are pure calculations, not monitor changes or rendered per-DPI forms. Neither type of simulation changes Windows DPI or proves native per-monitor transitions. Hidden `DrawToBitmap` snapshots do not verify desktop composition, real focus, physical input or screen-reader output. Caption checks verify the managed frameless configuration and available controls, not visible window-manager behavior. Some native rendering can differ from a shown window.

## Related documentation

Commercial regressions also cover atomic Scientific length rejection/Undo, field-specific date recovery, malformed UTF-16 search, selected compact units, confirmed bulk clearing, retained drawer actions, privacy-allowlisted support metadata, lazily created modes and result-fit cache invalidation. These checks use isolated profiles and hidden controls; clipboard/browser adapters are injected rather than sending data externally. They do not establish live screen-reader behavior.

- [Aster overview and quick start](../README.md)
- [Build, engine tests and manual walkthroughs](development.md)
- [Numeric behavior and precision](numeric-behavior.md)

[Documentation index](../documentation.md) collects the user, numeric and release guides.

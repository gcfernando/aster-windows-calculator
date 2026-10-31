<a id="fully-enabled-portable-distribution"></a>

# Aster Portable Release Guide

Prepare, inspect and install an unsigned Windows x64 candidate with evidence tied to its source and binaries. Maintainers should read the prerequisites below before running the verification helpers.

Aster works locally without an account, payment, key, activation or feature restrictions. It retains the MIT license. Application projects have no third-party NuGet dependencies; the framework-dependent portable package uses a separately installed Microsoft .NET Desktop Runtime. It contains no bundled runtime. The local workflow below neither signs nor publishes a release.

## Download an automated main build

Choose a complete application release from the [releases index](https://github.com/gcfernando/aster-windows-calculator/releases). Download **Aster-win-x64.zip** and **SHA256SUMS.txt** from the same release, compare the ZIP's SHA-256, extract all contents and run Aster.exe. GitHub's source-code archives are not runnable applications. The [legacy rolling preview](https://github.com/gcfernando/aster-windows-calculator/releases/tag/latest) remains available as an earlier download; new automation leaves it unchanged.

The verification workflow publishes a separate preview for each successful main push, **unsigned until a public-trust signing identity is configured**. It runs repository checks, publication-policy tests, release-helper regressions, complete engine/hidden component verification and evidence-bound packaging before publication. Tags use `v<base-version>-main.<run-id>.<full-commit-sha>`. The full source commit and passing run are linked in release notes. No branch-level concurrency group cancels or discards earlier pushes, and older commits are not skipped simply because main has advanced.

The publisher uploads the application and checksum to an owned private draft, verifies upload sizes and SHA-256 digests, and only then publishes it. A failed build publishes nothing. An interrupted upload can leave a private draft; rerun the same workflow to recover it. A rerun verifies and retains an already published release rather than overwriting its bytes. Tag collisions, unrelated releases and API/checksum errors stop publication. The former rolling helper remains in the repository for its regression coverage but is no longer called by the workflow.

Successful runs retain an **Aster-win-x64** artifact for 30 days and verification reports for 14 days on the [Actions page](https://github.com/gcfernando/aster-windows-calculator/actions/workflows/verify.yml). Downloading Actions artifacts requires a GitHub login. Pull requests and manual runs create artifacts without publishing. GitHub's `/releases/latest` route selects stable releases, so use the releases index to find these previews.

Build jobs use `contents: read`; only publication receives the scoped token's `contents: write`. Checkout credentials are not persisted and actions are pinned to immutable commits. Repository policy must permit release/tag writes. No trusted signing identity is currently configured, so releases remain unsigned. The proposed [Code signing policy](code-signing.md#code-signing-policy) documents free SignPath Foundation enrollment, which is pending, and the existing optional Azure route. Separate main-only Windows jobs use the selected provider; only Azure receives OIDC permission, while SignPath uses its scoped submitter secret. Both verify the publisher, timestamps and unchanged application content before producing a signed package. Enabled signing failure blocks publication without an unsigned fallback. Aster does not require a paid certificate to use it, and neither provider guarantees immediate SmartScreen reputation.

## Prerequisites

- Windows x64, PowerShell 7 and the .NET 10 SDK selected by [global.json](https://github.com/gcfernando/aster-windows-calculator/blob/main/global.json).
- A complete repository checkout and access to NuGet for an initial restore.
- A Windows desktop session for the hidden WinForms harness; see its [methodology and limitations](../tests/ModernCalculator.UiChecks/README.md).

## Prepare and verify a candidate

Use Windows x64, PowerShell 7 and the .NET 10 SDK. Start in the checkout root. First run the complete local verification:

```powershell
pwsh -NoProfile -File tools/Verify-Release.ps1
```

It restores and builds Release for `win-x64`, discovers the current engine test count, runs all engine tests and the unfiltered hidden WinForms harness, and compares source/binary hashes before and after. It stops for any failed, skipped, incomplete or changed evidence. Inspect its unique `artifacts/ReleaseVerification/<run>/` reports. A manifest is written only after success. It includes file hashes and the evidence limits; it is not a signed or tamper-proof attestation.

Pass the actual repository-relative manifest path to the publisher:

```powershell
pwsh -NoProfile -File tools/Publish-Portable.ps1 -VerificationManifest artifacts/ReleaseVerification/<run>/manifest.json
```

Publishing validates the manifest against the current source, reports and binaries, uses `dotnet publish --no-build --no-restore`, compares published application bytes with verified bytes, includes LICENSE/documentation/reports, and verifies every ZIP entry. Each run creates a new `artifacts/ReleaseCandidates/<run>/` directory without replacing an existing candidate. `package-manifest.json` records actual product version and file hashes; `SHA256SUMS.txt` covers the ZIP. The package manifest cannot list its own final hash; the ZIP checksum covers it. The old specialized audit helper remains for its existing prepared-output workflow; prefer this end-to-end workflow for new candidates.

## Install and first run

Use a currently supported Windows x64 edition from Microsoft's [.NET 10 supported-OS matrix](https://github.com/dotnet/core/blob/main/release-notes/10.0/supported-os.md). “Windows 10” alone is not a sufficient compatibility specification. Install the matching [.NET 10 Desktop Runtime](https://dotnet.microsoft.com/en-us/download/dotnet/10.0), extract the complete ZIP into a user-writable application folder and run `Aster.exe`. Keep every extracted file together. Standard defaults to a light theme; F1 opens local help. The portable package does not modify the registry, add services or require an installer.

Keep Windows and the installed runtime patched. Framework-dependent applications use the installed compatible runtime; a separately created self-contained publish would bundle its runtime and require a new application package to service that bundled runtime. See [Microsoft's deployment guidance](https://learn.microsoft.com/en-us/dotnet/core/deploying/). This portable tool deliberately produces one explicit framework-dependent x64 format.

## Data, privacy and support

The normal profile is `%LOCALAPPDATA%/AsterCalculator/state.json`, or the `ASTER_DATA_DIRECTORY` override. History persistence defaults to off; memory is session-only. Preferences are local. There is no calculation service, automatic telemetry or background update/activation connection. Keep profile backups private if you opt to retain history. A future unsupported schema is preserved and saving is refused, allowing a compatible newer app to reopen it.

F1's Support information exposes local version/build/runtime/culture/theme/DPI information for a user-initiated report. Review copied diagnostics before sharing; calculations, saved history, memory, usernames and profile paths are excluded. Use [the existing issue tracker](https://github.com/gcfernando/aster-windows-calculator/issues), providing reproducible sample inputs. No report is sent automatically.

## Update, rollback and removal

1. Close Aster before replacing its application files. Download only a trusted complete package and verify its supplied SHA-256 checksum. A checksum detects differences from the supplied manifest; it does not authenticate the publisher.
2. Keep the previous application folder and, if needed, make a private backup of the profile while Aster is closed. Extract the new version into a separate folder. Run it using the same profile and verify the relevant workflows before retiring the previous folder. Never copy only the EXE between versions.
3. For rollback, close Aster and reopen the previous complete folder. If that version refuses a newer profile schema, retain the file and return to the compatible app; alternatively use a separate `ASTER_DATA_DIRECTORY`. Do not discard unknown profile data to bypass this protection.
4. To uninstall, close Aster, delete its extracted application folder and remove any shortcuts you created. This retains the separate profile. Remove the named profile directory only if you intentionally want to erase its settings and any saved history. Never delete a shared override directory wholesale.

## Required external release gates

The local workflow prepares an unsigned candidate and CI exposes it as a preview. Engine/component passes alone do not justify unrestricted commercial-release claims. Before promoting a preview to a stable release, record:

- Clean-machine extraction/startup on the chosen supported Windows editions, including runtime installation/detection, offline calculation and non-admin profile access.
- Upgrade and rollback with legacy/current/future profiles; interrupted/write-denied storage recovery; full-folder removal with intentional profile retention.
- Physical keyboard/mouse and clipboard workflows in all modes, Narrator/stateful control semantics, real high contrast, IME/RTL expectations and real monitor-DPI transitions.
- The owner's authentic publisher/signing and distribution policy, package provenance and reputation review. No certificate or release identity is fabricated by these tools.
- Version/release notes, numeric limitations, known issues, support ownership and runtime/security update responsibility.

The tested development host and actual results belong in the audit evidence. They do not substitute for a supported-OS matrix or clean-machine run. Check the linked CI run for the actual remote build, verification and preview-publication result.

## Related documentation

[Documentation index](../documentation.md) · [Development and evidence contracts](development.md) · [Numeric behavior](numeric-behavior.md)

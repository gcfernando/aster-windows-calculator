# Aster code signing

SmartScreen checks the publisher signature and download reputation before Aster starts. Application startup code, assembly company metadata, a GitHub Latest badge and ZIP checksums do not establish a trusted publisher. A self-signed development certificate does not establish public trust either.

## Current distribution

Signing is disabled until the owner configures a public-trust signing identity. With signing disabled, successful main pushes continue to publish explicitly unsigned previews. Windows may display **Unknown publisher** and **Windows protected your PC**. These builds retain application version **1.0.0**; unique workflow-run tags distinguish packages without changing the application version.

The proposed no-cost route is [SignPath Foundation's free program for qualifying open-source projects](https://signpath.org/). Enrollment has not been submitted and no provider approval exists; no SignPath certificate, approved project or active signing service is claimed here. Aster remains free to use without buying a certificate. The existing Azure integration remains an optional alternative for maintainers with an eligible account. Neither integration creates an account, enrolls an identity or changes Windows protection settings.

Signing helpers and their regression tests require **PowerShell 7.6 or newer on .NET 10** for ZIP CRC/encryption inspection. Installing the .NET SDK does not upgrade the PowerShell host. The workflow uses the Windows Server 2025 runner, which supplies this runtime.

## Apply for free SignPath signing

1. Read the [Foundation conditions](https://signpath.org/terms) and [apply for a free subscription](https://signpath.org/apply) with this repository and its release/download information. Acceptance is the Foundation's decision. Keep signing disabled until it approves the project and its signing configuration.
2. After approval, link the exact repository `https://github.com/gcfernando/aster-windows-calculator` to SignPath's GitHub trusted-build integration. Configure origin verification for reviewed builds from `main`, a release-signing policy with a human approver, and an artifact configuration restricted to the four application binaries listed below. Enforce their product name/version metadata as required by the provider. Do not sign unrelated or upstream binaries with this project's identity.
3. Use the approved organization's real identifiers and submitter token in the following Actions settings. Do not invent IDs or reuse another project's policy. The token belongs in a repository secret; the other entries are repository variables.

| Setting | Value |
| --- | --- |
| `ASTER_SIGNING_PROVIDER` | Exactly `signpath`; absent/empty defaults to the existing `azure` route for compatibility |
| `ASTER_SIGNPATH_ORGANIZATION_ID` | Approved SignPath organization ID |
| `ASTER_SIGNPATH_PROJECT_SLUG` | Approved project slug for this repository |
| `ASTER_SIGNPATH_POLICY_SLUG` | Approved release-signing policy slug |
| `ASTER_SIGNPATH_ARTIFACT_SLUG` | Approved artifact configuration slug restricting the submitted files |
| `ASTER_SIGNPATH_API_TOKEN` **secret** | Token with submitter permission for that project/policy |
| `ASTER_SIGNING_PUBLISHER` | Exact approved certificate subject distinguished name; obtain it from the provider rather than guessing |
| `ASTER_SIGNING_ENABLED` | Exactly `true`, set **last** after approval and configuration; empty or `false` keeps unsigned releases |

4. Review and approve each release request in SignPath. The workflow uploads the verified four-file payload as a GitHub Actions artifact for origin verification, waits for the signed result, and applies the same Windows trust and unchanged-content checks used by the Azure route. Denial, timeout, missing configuration or an invalid result blocks publication; there is no unsigned fallback when signing is enabled. See [SignPath's GitHub integration](https://docs.signpath.io/trusted-build-systems/github) for provider setup.

## Code signing policy

**Status: enrollment not submitted; proposed policy only.** No release is represented as SignPath-signed until approval, configuration and a successful verified signing run exist. The proposed author, reviewer and release-signing approver is [gcfernando](https://github.com/gcfernando), the repository maintainer; these roles require confirmation during enrollment. Before activation, the maintainer must confirm MFA for all participants' GitHub and SignPath access and the required release-review/approval process. This document does not attest to account security settings or completed approvals. Provider credit will be added only after the service is approved and active.

### Privacy and network behavior

Aster calculates and stores preferences locally; its application source has no automatic telemetry or update client. The Support action opens GitHub in the user's browser, and diagnostic information is copied locally for the user to review before sharing. It does not automatically send calculations, history or profile data. Browser and Windows certificate/reputation checks have their own network behavior. CI signing sends the release binaries and build-origin metadata to the selected signing service; it does not run on an end user's calculator data. See the [release guide](release-guide.md#data-privacy-and-support) for local data and removal.

## Configure a trusted signing identity

This section preserves the optional **Azure** route; it is not required to use Aster or apply to the free Foundation program. Microsoft's [current eligibility requirements](https://learn.microsoft.com/en-us/azure/artifact-signing/quickstart) limit Public Trust individual enrollment to the US and Canada. An individual based in Sweden is therefore not currently eligible through that route; EU organization eligibility is separate. Azure service costs are not a prerequisite for using Aster.

1. For an already eligible Azure account, complete identity validation and create a **Public Trust** certificate profile. A private-trust/test profile is not suitable for public downloads.
2. Configure a Microsoft Entra workload identity with a GitHub OIDC federated credential. Restrict its issuer to `https://token.actions.githubusercontent.com`, audience to `api://AzureADTokenExchange` and subject to `repo:gcfernando/aster-windows-calculator:ref:refs/heads/main`. Do not authorize pull-request subjects or wildcard branches. Changes to trusted main workflows must be reviewed.
3. Give that identity the **Artifact Signing Certificate Profile Signer** role scoped to the selected certificate profile, following the provider's current role naming and setup instructions. Do not grant subscription-wide owner access for signing.
4. Add the following GitHub Actions repository variables. Client/tenant/subscription IDs are identifiers; this flow does not require a client secret or private key in the repository.

| Variable | Value |
| --- | --- |
| `ASTER_SIGNING_PROVIDER` | Exactly `azure`, or leave empty for compatibility with existing Azure configuration |
| `ASTER_SIGNING_CLIENT_ID` | Workload identity client ID |
| `ASTER_SIGNING_TENANT_ID` | Microsoft Entra tenant ID |
| `ASTER_SIGNING_SUBSCRIPTION_ID` | Signing subscription ID |
| `ASTER_SIGNING_ENDPOINT` | Account's regional HTTPS endpoint, for example `https://weu.codesigning.azure.net/` |
| `ASTER_SIGNING_ACCOUNT` | Artifact Signing account name |
| `ASTER_SIGNING_PROFILE` | Public Trust certificate profile name |
| `ASTER_SIGNING_PUBLISHER` | Exact complete certificate subject returned by `Get-AuthenticodeSignature`, including its `CN=`, `O=` and other fields as applicable |
| `ASTER_SIGNING_ENABLED` | Set to the exact string `true` **last**, after the identity and all other variables are configured |

The workflow validates configuration before authentication. Select exactly one provider: only `azure` and `signpath` are accepted. Enabled signing must complete successfully before publication; missing settings, signature errors, a different publisher or signing-job failure block publication. There is no unsigned fallback while signing is enabled. Only the Azure job receives OIDC permission; the SignPath job uses its scoped submitter secret. Both jobs are restricted to main pushes. Pull requests and manual verification runs do not sign or publish releases.

## Package and evidence order

The existing build job runs verification and creates the unsigned package. Its evidence and hashes remain unchanged. The separate Windows signing job then:

1. Checks the ZIP checksum, safe entry paths and the original package file manifest before extracting a new staging folder.
2. Records unsigned file hashes and Authenticode content hashes outside the folder that is sent to the signing action.
3. Signs and timestamps exactly `Aster.exe`, `Aster.dll`, `ModernCalculator.Core.dll` and `ModernCalculator.Infrastructure.dll` using SHA-256. It does not recursively sign documentation or arbitrary extra executables.
4. Requires trusted Windows Authenticode validation, the exact configured publisher, a code-signing certificate and a timestamp for every application binary. Compares application content before and after signing while excluding the PE checksum, certificate-directory entry and appended certificate table that Authenticode updates. Rejects other file changes, additions or omissions.
5. Preserves the original unsigned test manifest, adds signing evidence with hashes before and after signing, updates package labels and writes the final file manifest.
6. Creates the signed ZIP and its final SHA-256 checksum, uploads the signed artifact and publishes it only after all checks pass.

`.github/scripts/publish_main_release.py --signed` also checks the signed package's manifest and file hashes before upload. Windows performs cryptographic signature validation; Linux publication checks the resulting artifact/evidence consistency. A published run cannot be rerun to silently change its signed/unsigned classification or replace its original bytes.

## Verification and remaining limits

Check a downloaded, extracted package on Windows:

```powershell
Get-AuthenticodeSignature .\Aster.exe | Format-List Status, StatusMessage, SignerCertificate, TimeStamperCertificate
Get-FileHash .\Aster-win-x64.zip -Algorithm SHA256
```

For a signed release, the first command must report `Valid` and the intended publisher. Compare the ZIP hash with that release's checksum file. A checksum detects differences; it does not authenticate an unsigned publisher.

Even a valid new signing identity or file may still receive a SmartScreen reputation warning. Signing does not complete the manual desktop acceptance checks in the [release guide](release-guide.md). Never claim that a new or EV certificate guarantees an immediate warning-free launch. Do not disable SmartScreen as part of the application's installation or startup.

## References

- [Microsoft SmartScreen reputation guidance](https://learn.microsoft.com/windows/apps/package-and-deploy/smartscreen-reputation)
- [Artifact Signing setup and identity validation](https://learn.microsoft.com/en-us/azure/artifact-signing/quickstart)
- [Artifact Signing GitHub action and authentication](https://github.com/Azure/artifact-signing-action)
- [Azure Login OIDC configuration](https://github.com/Azure/login#login-with-openid-connect-oidc-recommended)

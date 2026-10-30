# Aster code signing

SmartScreen checks the publisher signature and download reputation before Aster starts. Application startup code, assembly company metadata, a GitHub Latest badge and ZIP checksums do not establish a trusted publisher. A self-signed development certificate does not establish public trust either.

## Current distribution

Signing is disabled until the owner configures a public-trust signing identity. With signing disabled, successful main pushes continue to publish explicitly unsigned previews. Windows may display **Unknown publisher** and **Windows protected your PC**. These builds retain application version **1.0.0**; unique workflow-run tags distinguish packages without changing the application version.

The repository includes optional Microsoft Artifact Signing integration using OpenID Connect (OIDC). This change does not create an Azure account, enroll an identity, purchase a service, install a certificate or change Windows protection settings. Eligibility, identity validation and service costs must be resolved with the provider before enabling it.

Signing helpers and their regression tests require **PowerShell 7.6 or newer on .NET 10** for ZIP CRC/encryption inspection. Installing the .NET SDK does not upgrade the PowerShell host. The workflow uses the Windows Server 2025 runner, which supplies this runtime.

## Configure a trusted signing identity

1. Check the provider's [current eligibility requirements](https://learn.microsoft.com/en-us/azure/artifact-signing/quickstart), create an eligible Artifact Signing account, complete identity validation and create a **Public Trust** certificate profile. Individual and organization eligibility differ; do not assume that an eligible country for organizations also supports individual enrollment. A private-trust/test profile is not suitable for public downloads.
2. Configure a Microsoft Entra workload identity with a GitHub OIDC federated credential. Restrict its issuer to `https://token.actions.githubusercontent.com`, audience to `api://AzureADTokenExchange` and subject to `repo:gcfernando/aster-windows-calculator:ref:refs/heads/main`. Do not authorize pull-request subjects or wildcard branches. Changes to trusted main workflows must be reviewed.
3. Give that identity the **Artifact Signing Certificate Profile Signer** role scoped to the selected certificate profile, following the provider's current role naming and setup instructions. Do not grant subscription-wide owner access for signing.
4. Add the following GitHub Actions repository variables. Client/tenant/subscription IDs are identifiers; this flow does not require a client secret or private key in the repository.

| Variable | Value |
| --- | --- |
| `ASTER_SIGNING_CLIENT_ID` | Workload identity client ID |
| `ASTER_SIGNING_TENANT_ID` | Microsoft Entra tenant ID |
| `ASTER_SIGNING_SUBSCRIPTION_ID` | Signing subscription ID |
| `ASTER_SIGNING_ENDPOINT` | Account's regional HTTPS endpoint, for example `https://weu.codesigning.azure.net/` |
| `ASTER_SIGNING_ACCOUNT` | Artifact Signing account name |
| `ASTER_SIGNING_PROFILE` | Public Trust certificate profile name |
| `ASTER_SIGNING_PUBLISHER` | Exact complete certificate subject returned by `Get-AuthenticodeSignature`, including its `CN=`, `O=` and other fields as applicable |
| `ASTER_SIGNING_ENABLED` | Set to the exact string `true` **last**, after the identity and all other variables are configured |

The workflow validates configuration before authentication. Enabled signing must complete successfully before publication; missing settings, signature errors, a different publisher or signing-job failure block publication. There is no unsigned fallback while signing is enabled. Pull requests and manual verification runs do not receive the signing job's OIDC permission and do not publish releases.

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

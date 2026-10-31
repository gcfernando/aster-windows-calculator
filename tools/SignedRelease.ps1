# Optional Authenticode finalization. Dot-sourcing never runs an application or signs files.
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'ReleaseEvidence.ps1')
$script:AsterAuthenticodeTargets = @('Aster.exe', 'Aster.dll', 'ModernCalculator.Core.dll', 'ModernCalculator.Infrastructure.dll')

if (-not ('Aster.ReleaseSigningBinary' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Security.Cryptography;

namespace Aster {
    public sealed class PeSigningContent {
        public string Sha256 { get; set; }
        public int CertificateOffset { get; set; }
        public int CertificateSize { get; set; }
    }

    public static class ReleaseSigningBinary {
        static readonly uint[] Table = MakeTable();
        static uint[] MakeTable() {
            var table = new uint[256];
            for (uint i = 0; i < 256; i++) {
                uint value = i;
                for (int bit = 0; bit < 8; bit++)
                    value = (value & 1) != 0 ? 0xedb88320U ^ (value >> 1) : value >> 1;
                table[i] = value;
            }
            return table;
        }

        public static uint CopyWithCrc(Stream input, Stream output, long length) {
            uint crc = 0xffffffffU;
            long count = 0;
            byte[] buffer = new byte[65536];
            int read;
            while ((read = input.Read(buffer, 0, buffer.Length)) != 0) {
                count = checked(count + read);
                if (count > length) throw new InvalidDataException("ZIP entry exceeds its declared length.");
                for (int i = 0; i < read; i++) crc = Table[(crc ^ buffer[i]) & 255] ^ (crc >> 8);
                output.Write(buffer, 0, read);
            }
            if (count != length) throw new InvalidDataException("ZIP entry length does not match its metadata.");
            return crc ^ 0xffffffffU;
        }

        static ushort U16(byte[] bytes, int offset) {
            if (offset < 0 || offset > bytes.Length - 2) throw new InvalidDataException("Truncated PE field.");
            return BitConverter.ToUInt16(bytes, offset);
        }
        static uint U32(byte[] bytes, int offset) {
            if (offset < 0 || offset > bytes.Length - 4) throw new InvalidDataException("Truncated PE field.");
            return BitConverter.ToUInt32(bytes, offset);
        }
        static int Position(uint value) {
            if (value > Int32.MaxValue) throw new InvalidDataException("PE field exceeds supported file size.");
            return (int)value;
        }


        public static PeSigningContent Inspect(byte[] bytes) {
            if (bytes.Length < 64 || U16(bytes, 0) != 0x5a4d) throw new InvalidDataException("Not a DOS/PE image.");
            int pe = Position(U32(bytes, 60));
            if (pe < 64 || pe > bytes.Length - 24 || U32(bytes, pe) != 0x00004550)
                throw new InvalidDataException("Invalid PE header.");
            int optional = pe + 24;
            int optionalSize = U16(bytes, pe + 20);
            int magic = U16(bytes, optional);
            int directory;
            int directoryCount;
            if (magic == 0x10b) { directory = optional + 128; directoryCount = optional + 92; }
            else if (magic == 0x20b) { directory = optional + 144; directoryCount = optional + 108; }
            else throw new InvalidDataException("Unsupported PE optional header.");
            if (optionalSize < directory - optional + 8 || optional + (long)optionalSize > bytes.Length ||
                U32(bytes, directoryCount) <= 4)
                throw new InvalidDataException("PE security directory is missing or truncated.");
            int checksum = optional + 64;
            int sections = U16(bytes, pe + 6);
            int sectionTable = optional + optionalSize;
            int headers = Position(U32(bytes, optional + 60));
            if (sections == 0 || sectionTable + (long)sections * 40 > headers || headers > bytes.Length)
                throw new InvalidDataException("Invalid PE section table.");
            long covered = headers;
            for (int i = 0; i < sections; i++) {
                int section = sectionTable + i * 40;
                long size = U32(bytes, section + 16);
                long start = U32(bytes, section + 20);
                if (size != 0 && (start < headers || start + size > bytes.Length))
                    throw new InvalidDataException("Invalid PE section range.");
                if (size != 0) covered = Math.Max(covered, start + size);
            }
            int certificate = Position(U32(bytes, directory));
            int certificateSize = Position(U32(bytes, directory + 4));
            int contentLength = bytes.Length;
            if (certificate != 0 || certificateSize != 0) {
                if (certificate == 0 || certificateSize < 8 || certificate % 8 != 0 || certificateSize % 8 != 0 ||
                    certificate < covered || certificate + (long)certificateSize != bytes.Length)
                    throw new InvalidDataException("Certificate table must be aligned, outside sections, and at EOF.");
                long cursor = certificate;
                long end = certificate + (long)certificateSize;
                while (cursor < end) {
                    if (end - cursor < 8) throw new InvalidDataException("Truncated WIN_CERTIFICATE entry.");
                    long length = U32(bytes, (int)cursor);
                    if (length < 8 || length > end - cursor || U16(bytes, (int)cursor + 4) != 0x200 ||
                        U16(bytes, (int)cursor + 6) != 2)
                        throw new InvalidDataException("Invalid Authenticode certificate entry.");
                    cursor += (length + 7) & ~7L;
                    if (cursor > end) throw new InvalidDataException("Certificate padding exceeds its table.");
                }
                contentLength = certificate;
            }
            if (directory + 8 > contentLength) throw new InvalidDataException("Certificate table overlaps PE headers.");
            byte[] hash;
            using (SHA256 sha = SHA256.Create()) {
                sha.TransformBlock(bytes, 0, checksum, null, 0);
                sha.TransformBlock(bytes, checksum + 4, directory - checksum - 4, null, 0);
                sha.TransformFinalBlock(bytes, directory + 8, contentLength - directory - 8);
                hash = sha.Hash;
            }
            return new PeSigningContent {
                Sha256 = Convert.ToHexString(hash).ToLowerInvariant(),
                CertificateOffset = certificate,
                CertificateSize = certificateSize
            };
        }
    }
}
'@
}

function Resolve-SigningMember([string]$Root, [string]$Name) {
    if ([string]::IsNullOrWhiteSpace($Name) -or [IO.Path]::IsPathRooted($Name) -or $Name.Contains('\') -or
        $Name -match '[\x00-\x1f\x7f:<>"|?*]') { throw 'Unsafe signing archive member name.' }
    foreach ($part in $Name.Split('/')) {
        if ($part -in @('', '.', '..') -or $part.EndsWith('.') -or $part.EndsWith(' ') -or
            ($part.Split('.')[0] -match '^(?i:CON|PRN|AUX|NUL|CONIN\$|CONOUT\$|COM[1-9\u00b9\u00b2\u00b3]|LPT[1-9\u00b9\u00b2\u00b3])$')) { throw 'Unsafe signing archive path segment.' }
    }
    $rootPath = [IO.Path]::GetFullPath($Root).TrimEnd([IO.Path]::DirectorySeparatorChar)
    $full = [IO.Path]::GetFullPath((Join-Path $rootPath $Name))
    if (-not $full.StartsWith($rootPath + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Signing archive member escapes its destination.' }
    return $full
}

function Assert-SigningDirectory([string]$Directory) {
    $cursor = [IO.Path]::GetFullPath($Directory)
    while ($cursor) {
        if (Test-Path -LiteralPath $cursor) {
            if (((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Signing paths must not traverse reparse points.' }
        }
        $cursor = [IO.Path]::GetDirectoryName($cursor)
    }
}

function Get-SigningPeContent([string]$Path) {
    return [Aster.ReleaseSigningBinary]::Inspect([IO.File]::ReadAllBytes($Path))
}

function Get-SigningFileRecords([string]$Folder) {
    @(Get-ChildItem -LiteralPath $Folder -Recurse -Force | Sort-Object FullName | ForEach-Object {
        if (($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Reparse points are not valid signing payloads.' }
        if (-not $_.PSIsContainer) { Get-ReleaseFileRecord $Folder $_.FullName }
    })
}

function Expand-VerifiedSigningPackage([string]$Archive, [string]$Checksum, [string]$Destination) {
    $archivePath = [IO.Path]::GetFullPath($Archive)
    $folder = [IO.Path]::GetFullPath($Destination)
    $snapshotPath = $folder + '.signing-input.json'
    Assert-SigningDirectory $folder
    if ((Test-Path -LiteralPath $folder) -or (Test-Path -LiteralPath $snapshotPath)) { throw 'Preserve the existing signing destination and snapshot.' }
    $checksumLine = [IO.File]::ReadAllText([IO.Path]::GetFullPath($Checksum)).Trim()
    if ($checksumLine -cnotmatch '^([a-f0-9]{64})  ([^/\\\r\n]+)$') { throw 'Invalid unsigned ZIP checksum manifest.' }
    $expectedHash = $Matches[1]
    if ($Matches[2] -cne [IO.Path]::GetFileName($archivePath) -or
        (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant() -cne $expectedHash) { throw 'Unsigned ZIP checksum mismatch.' }
    if ((Get-Item -LiteralPath $archivePath).Length -gt 536870912) { throw 'Signing archive exceeds the 512 MiB input limit.' }
    $zip = [IO.Compression.ZipFile]::OpenRead($archivePath)
    try {
        if ($zip.Entries.Count -eq 0 -or $zip.Entries.Count -gt 10000) { throw 'Unexpected signing archive entry count.' }
        $members = [Collections.Generic.Dictionary[string,object]]::new([StringComparer]::OrdinalIgnoreCase)
        [long]$total = 0
        foreach ($entry in $zip.Entries) {
            [void](Resolve-SigningMember $folder $entry.FullName)
            $kind = ($entry.ExternalAttributes -shr 16) -band 0xf000
            if ($kind -notin @(0, 0x8000) -or $entry.Name -eq '') { throw 'Signing archives must contain ordinary files only.' }
            if ($null -eq $entry.PSObject.Properties['Crc32'] -or $null -eq $entry.PSObject.Properties['IsEncrypted']) { throw 'Signing helpers require PowerShell 7.6 with its .NET 10 ZIP integrity APIs.' }
            if ($entry.IsEncrypted -or -not $members.TryAdd($entry.FullName, $entry)) { throw 'Encrypted or duplicate signing archive member.' }
            $total += $entry.Length
            if ($total -gt 536870912) { throw 'Signing archive exceeds the 512 MiB staging limit.' }
        }
        if (-not $members.ContainsKey('package-manifest.json')) { throw 'Unsigned package manifest is missing.' }
        $manifestEntry = $members['package-manifest.json']
        if ($manifestEntry.FullName -cne 'package-manifest.json' -or $manifestEntry.Length -gt 4194304) { throw 'Invalid unsigned package manifest entry.' }
        $stream = $manifestEntry.Open()
        $buffer = [IO.MemoryStream]::new()
        try { $crc = [Aster.ReleaseSigningBinary]::CopyWithCrc($stream, $buffer, $manifestEntry.Length) } finally { $stream.Dispose() }
        try {
            if ($crc -ne $manifestEntry.Crc32) { throw 'Unsigned package manifest CRC mismatch.' }
            $manifestText = [Text.Encoding]::UTF8.GetString($buffer.ToArray()).TrimStart([char]0xfeff)
            $package = $manifestText | ConvertFrom-Json -Depth 20
        } finally { $buffer.Dispose() }
        if ($package.schemaVersion -ne 1 -or $package.runtimeIdentifier -cne 'win-x64' -or $package.selfContained -ne $false -or
            $package.signing -isnot [string] -or $package.signing -cne 'Unsigned preview candidate' -or [string]::IsNullOrWhiteSpace($package.version)) { throw 'Unsupported unsigned package manifest.' }
        $expected = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($record in @($package.files)) {
            [void](Resolve-SigningMember $folder $record.path)
            if ($record.path -ceq 'package-manifest.json' -or $record.sha256 -cnotmatch '^[a-f0-9]{64}$' -or
                -not $expected.Add($record.path) -or -not $members.ContainsKey($record.path) -or $members[$record.path].FullName -cne $record.path) { throw 'Invalid unsigned package file record.' }
        }
        if ($expected.Count -eq 0 -or $members.Count -ne $expected.Count + 1) { throw 'Unsigned package file coverage is incomplete.' }
        foreach ($required in @($script:AsterAuthenticodeTargets) + @('LICENSE', 'START-HERE.txt', 'verification/manifest.json')) {
            if (-not $expected.Contains($required)) { throw "Required unsigned payload is missing: $required" }
        }
        [void][IO.Directory]::CreateDirectory($folder)
        foreach ($entry in $zip.Entries) {
            $target = Resolve-SigningMember $folder $entry.FullName
            [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target))
            $source = $entry.Open()
            $output = [IO.File]::Open($target, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write)
            try { $crc = [Aster.ReleaseSigningBinary]::CopyWithCrc($source, $output, $entry.Length) } finally { $output.Dispose(); $source.Dispose() }
            if ($crc -ne $entry.Crc32) { throw "ZIP CRC mismatch: $($entry.FullName)" }
        }
    } finally { $zip.Dispose() }
    Assert-ReleaseRecords $folder @($package.files)
    if ((Get-FileHash -LiteralPath (Join-Path $folder 'verification/manifest.json')).Hash.ToLowerInvariant() -cne $package.verificationManifestSha256) { throw 'Original verification manifest hash does not match.' }
    $peRecords = @(foreach ($name in $script:AsterAuthenticodeTargets) {
        $path = Join-Path $folder $name
        $content = Get-SigningPeContent $path
        if ($content.CertificateSize -ne 0) { throw 'Signing input must contain unsigned PE files.' }
        [pscustomobject]@{ path=$name; unsignedSha256=(Get-FileHash -LiteralPath $path).Hash.ToLowerInvariant(); authenticodeContentSha256=$content.Sha256 }
    })
    $snapshot = [ordered]@{ schemaVersion=1; folder=$folder; archiveSha256=$expectedHash; packageVersion=$package.version; files=@(Get-SigningFileRecords $folder); peFiles=$peRecords }
    $json = $snapshot | ConvertTo-Json -Depth 10
    $snapshotStream = [IO.File]::Open($snapshotPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write)
    try { $bytes=[Text.UTF8Encoding]::new($false).GetBytes($json); $snapshotStream.Write($bytes,0,$bytes.Length) } finally { $snapshotStream.Dispose() }
    return [pscustomobject]@{ Folder=$folder; SnapshotPath=$snapshotPath; Files=@($script:AsterAuthenticodeTargets | ForEach-Object { Join-Path $folder $_ }) }
}

function Assert-TrustedSigningSignature([string]$Path, [string]$ExpectedPublisher) {
    if ([string]::IsNullOrWhiteSpace($ExpectedPublisher)) { throw 'Expected signing publisher must be configured.' }
    $signature = Get-AuthenticodeSignature -LiteralPath $Path
    if ($signature.Status -ne 'Valid' -or $signature.SignatureType -ne 'Authenticode' -or $null -eq $signature.SignerCertificate -or $null -eq $signature.TimeStamperCertificate) { throw 'A valid embedded, timestamped Authenticode signature is required.' }
    $certificate = $signature.SignerCertificate
    if (-not [string]::Equals($certificate.Subject, $ExpectedPublisher, [StringComparison]::Ordinal) -or
        [string]::Equals($certificate.Subject, $certificate.Issuer, [StringComparison]::Ordinal)) { throw 'Unexpected or self-issued signing publisher.' }
    $hasCodeSigning = $false
    foreach ($extension in $certificate.Extensions) {
        if ($extension.Oid.Value -eq '2.5.29.37') {
            foreach ($usage in $extension.EnhancedKeyUsages) { if ($usage.Value -eq '1.3.6.1.5.5.7.3.3') { $hasCodeSigning=$true } }
        }
    }
    if (-not $hasCodeSigning) { throw 'Signing certificate lacks the code-signing enhanced key usage.' }
    return $signature
}

function Import-SignPathPayload([string]$Archive, [string]$Folder) {
    # Provider output is untrusted until finalization validates trust and content.
    # Read and validate every entry before replacing any staged application file.
    $folderPath = [IO.Path]::GetFullPath($Folder)
    Assert-SigningDirectory $folderPath
    if (-not (Test-Path -LiteralPath ($folderPath+'.signing-input.json') -PathType Leaf)) { throw 'Verified signing snapshot is missing.' }
    $archivePath = [IO.Path]::GetFullPath($Archive)
    if ((Get-Item -LiteralPath $archivePath).Length -gt 536870912) { throw 'SignPath archive exceeds the input limit.' }
    $payload = [Collections.Generic.Dictionary[string,byte[]]]::new([StringComparer]::Ordinal)
    $zip = [IO.Compression.ZipFile]::OpenRead($archivePath)
    try {
        if ($zip.Entries.Count -ne $script:AsterAuthenticodeTargets.Count) { throw 'SignPath must return exactly the four application binaries.' }
        [long]$total = 0
        foreach ($entry in $zip.Entries) {
            if ($entry.FullName -cnotin $script:AsterAuthenticodeTargets -or $payload.ContainsKey($entry.FullName)) { throw 'Unexpected or duplicate SignPath member.' }
            $target = Resolve-SigningMember $folderPath $entry.FullName
            if (-not (Test-Path -LiteralPath $target -PathType Leaf)) { throw 'Original signing target is missing.' }
            $kind = ($entry.ExternalAttributes -shr 16) -band 0xf000
            if ($kind -notin @(0, 0x8000) -or $entry.IsEncrypted) { throw 'SignPath members must be unencrypted ordinary files.' }
            $total += $entry.Length
            if ($entry.Length -le 0 -or $total -gt 536870912) { throw 'SignPath payload exceeds staging limits.' }
            $inputStream = $entry.Open()
            $buffer = [IO.MemoryStream]::new()
            try {
                $crc = [Aster.ReleaseSigningBinary]::CopyWithCrc($inputStream, $buffer, $entry.Length)
                if ($crc -ne $entry.Crc32) { throw 'SignPath member CRC mismatch.' }
                $payload.Add($entry.FullName, $buffer.ToArray())
            } finally { $buffer.Dispose(); $inputStream.Dispose() }
        }
    } finally { $zip.Dispose() }
    foreach ($name in $script:AsterAuthenticodeTargets) {
        $target = Resolve-SigningMember $folderPath $name
        if ((Get-Item -LiteralPath $target).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Signing targets must not be links.' }
    }
    foreach ($name in $script:AsterAuthenticodeTargets) {
        [IO.File]::WriteAllBytes((Resolve-SigningMember $folderPath $name), $payload[$name])
    }
    # Complete-SignedRelease must run next, before packaging or executing these bytes.
}

function Complete-SignedRelease([string]$Folder, [string]$ArchivePath, [string]$ExpectedPublisher) {
    if ([string]::IsNullOrWhiteSpace($ExpectedPublisher)) { throw 'Expected signing publisher must be configured.' }
    $folderPath = [IO.Path]::GetFullPath($Folder)
    Assert-SigningDirectory $folderPath
    $archive = [IO.Path]::GetFullPath($ArchivePath)
    $checksum = Join-Path ([IO.Path]::GetDirectoryName($archive)) 'SHA256SUMS.txt'
    if ($archive.StartsWith($folderPath.TrimEnd([IO.Path]::DirectorySeparatorChar)+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) { throw 'Signed ZIP must be outside its input payload.' }
    Assert-SigningDirectory ([IO.Path]::GetDirectoryName($archive))
    if ((Test-Path -LiteralPath $archive) -or (Test-Path -LiteralPath $checksum)) { throw 'Preserve the existing signed archive and checksum.' }
    $snapshot = [IO.File]::ReadAllText($folderPath+'.signing-input.json') | ConvertFrom-Json -Depth 20
    if ($snapshot.schemaVersion -ne 1 -or $snapshot.folder -cne $folderPath) { throw 'Signing input snapshot does not match this payload.' }
    $actual = @(Get-SigningFileRecords $folderPath)
    $names = @($snapshot.files.path | Sort-Object)
    if ($names.Count -ne $actual.Count -or (Compare-Object $names @($actual.path | Sort-Object) -CaseSensitive)) { throw 'Signing payload files were added, removed or renamed.' }
    $signingFiles = @(foreach ($name in $script:AsterAuthenticodeTargets) {
        $path = Join-Path $folderPath $name
        $prior = @($snapshot.peFiles | Where-Object path -CEQ $name)
        if ($prior.Count -ne 1 -or $prior[0].unsignedSha256 -cnotmatch '^[a-f0-9]{64}$' -or $prior[0].authenticodeContentSha256 -cnotmatch '^[a-f0-9]{64}$') { throw 'Signing PE snapshot is invalid.' }
        $originalFile = @($snapshot.files | Where-Object path -CEQ $name)
        if ($originalFile.Count -ne 1 -or $originalFile[0].sha256 -cne $prior[0].unsignedSha256) { throw 'Signing PE and original file snapshots disagree.' }
        $content = Get-SigningPeContent $path
        if ($content.CertificateSize -eq 0 -or $content.Sha256 -cne $prior[0].authenticodeContentSha256) { throw "Signing changed executable content or no signature was added: $name" }
        $signature = Assert-TrustedSigningSignature $path $ExpectedPublisher
        [pscustomobject]@{ path=$name; unsignedSha256=$prior[0].unsignedSha256; signedSha256=(Get-FileHash -LiteralPath $path).Hash.ToLowerInvariant(); authenticodeContentSha256=$content.Sha256; signerThumbprint=$signature.SignerCertificate.Thumbprint; timestampSignerSubject=$signature.TimeStamperCertificate.Subject }
    })
    if (@($snapshot.peFiles).Count -ne 4) { throw 'Exactly four signed PE records are required.' }
    foreach ($record in $snapshot.files) {
        [void](Resolve-SigningMember $folderPath $record.path)
        if ($record.path -cnotin $script:AsterAuthenticodeTargets) {
            $current = @($actual | Where-Object path -CEQ $record.path)
            if ($current.Count -ne 1 -or $current[0].sha256 -cne $record.sha256) { throw "Non-PE signing input changed: $($record.path)" }
        }
    }
    $manifestPath = Join-Path $folderPath 'package-manifest.json'
    $package = [IO.File]::ReadAllText($manifestPath) | ConvertFrom-Json -Depth 20
    if ($package.version -cne $snapshot.packageVersion) { throw 'Application version changed during signing.' }
    $start = Join-Path $folderPath 'START-HERE.txt'
    $text = [IO.File]::ReadAllText($start)
    $old = 'This unsigned preview candidate is not a certificate of stable-release readiness.'
    if (-not $text.Contains($old)) { throw 'Unsigned candidate label was not found in START-HERE.txt.' }
    $text = $text.Replace($old,'This Authenticode-signed preview candidate still requires the documented manual acceptance checks.')
    $text += "`nPublisher: $ExpectedPublisher`nSigning does not guarantee SmartScreen reputation or remove all security warnings.`n"
    [IO.File]::WriteAllText($start,$text,[Text.UTF8Encoding]::new($false))
    $package.signing = [pscustomobject]@{ status='Authenticode signed'; publisher=$ExpectedPublisher; files=$signingFiles }
    $package.files = @(Get-SigningFileRecords $folderPath | Where-Object path -CNE 'package-manifest.json')
    [IO.File]::WriteAllText($manifestPath,($package | ConvertTo-Json -Depth 12),[Text.UTF8Encoding]::new($false))
    Assert-ReleaseRecords $folderPath @($package.files)
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($archive))
    Write-ReleaseArchive $folderPath $archive
    Assert-ReleaseRecords $folderPath @($package.files)
    $hash = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
    [IO.File]::WriteAllText($checksum,"$hash  $([IO.Path]::GetFileName($archive))`n",[Text.UTF8Encoding]::new($false))
    return $archive
}

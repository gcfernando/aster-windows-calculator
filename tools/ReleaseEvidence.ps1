# Shared local release checks. Dot-sourcing this file performs no build or packaging.
Set-StrictMode -Version Latest

function Resolve-ReleasePath([string]$Root, [string]$Relative) {
    if ([IO.Path]::IsPathRooted($Relative)) { throw 'Evidence paths must be relative to the checkout.' }
    $path = [IO.Path]::GetFullPath((Join-Path $Root $Relative))
    $relativePath = [IO.Path]::GetRelativePath($Root, $path)
    if ($relativePath -eq '..' -or $relativePath.StartsWith('../') -or $relativePath.StartsWith('..\')) { throw 'Evidence path escapes the checkout.' }
    return $path
}

function Get-ReleaseFileRecord([string]$Root, [string]$Path) {
    [pscustomobject]@{
        path = [IO.Path]::GetRelativePath($Root, $Path).Replace('\', '/')
        sha256 = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    }
}

function Get-ReleaseSourceRecords([string]$Root) {
    $files = @(foreach ($folder in @('src', 'tests', 'tools', 'docs', '.github')) {
        $path = Join-Path $Root $folder
        if (Test-Path -LiteralPath $path -PathType Container) {
            Get-ChildItem -LiteralPath $path -File -Recurse -Force | Where-Object {
                [IO.Path]::GetRelativePath($path, $_.FullName) -notmatch '(^|[\\/])(bin|obj|sessions)([\\/]|$)'
            }
        }
    })
    $files += Get-ChildItem -LiteralPath $Root -File -Force | Where-Object {
        $_.Name -match '\.(sln|slnx|props|targets|json|config|md)$' -or $_.Name -eq 'LICENSE'
    }
    @($files | Sort-Object FullName -Unique | ForEach-Object { Get-ReleaseFileRecord $Root $_.FullName })
}

function Assert-ReleaseRecords([string]$Root, [object[]]$Records) {
    if ($Records.Count -eq 0) { throw 'An empty file manifest is not valid evidence.' }
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($record in $Records) {
        if (-not $seen.Add($record.path) -or $record.sha256 -notmatch '^[a-f0-9]{64}$') { throw 'Invalid or duplicate evidence file record.' }
        $path = Resolve-ReleasePath $Root $record.path
        if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $record.sha256) {
            throw "Release evidence is stale or missing: $($record.path)"
        }
    }
}

function Assert-ReleaseSources([string]$Root, [object[]]$Records) {
    Assert-ReleaseRecords $Root $Records
    $current = @(Get-ReleaseSourceRecords $Root)
    if ($current.Count -ne $Records.Count -or (Compare-Object @($Records.path | Sort-Object) @($current.path | Sort-Object))) {
        throw 'Source inputs were added or removed after verification.'
    }
}

function Assert-ReleaseEngineReport([xml]$Report, [int]$ExpectedCount) {
    $summary = $Report.TestRun.ResultSummary
    $counters = $summary.Counters
    if ($ExpectedCount -le 0 -or $null -eq $counters -or $summary.outcome -ne 'Completed') { throw 'A complete passing engine run is required.' }
    foreach ($name in @('total', 'executed', 'passed')) {
        $count = 0
        if (-not [int]::TryParse($counters.GetAttribute($name), [ref]$count) -or $count -ne $ExpectedCount) { throw "Incomplete engine count: $name" }
    }
    foreach ($counter in $counters.Attributes) {
        if ($counter.Name -in @('total', 'executed', 'passed')) { continue }
        $count = 0
        if (-not [int]::TryParse($counter.Value, [ref]$count) -or $count -ne 0) { throw "Non-passing engine outcome: $($counter.Name)" }
    }
    $results = @($Report.TestRun.Results.UnitTestResult)
    if ($results.Count -ne $ExpectedCount -or @($results | Where-Object outcome -ne 'Passed').Count -ne 0) { throw 'Incomplete engine results.' }
    $executions = [Collections.Generic.HashSet[Guid]]::new()
    foreach ($result in $results) {
        $id = [Guid]::Empty
        if (-not [Guid]::TryParse($result.executionId, [ref]$id) -or $id -eq [Guid]::Empty -or -not $executions.Add($id)) { throw 'Engine result execution IDs must be valid and unique.' }
    }
}

function Assert-ReleaseUiReport([object]$Report) {
    if ($Report.focus -ne '' -or $Report.failed -ne 0 -or $Report.skipped -ne 0 -or $Report.passed -le 0 -or
        @($Report.checks).Count -ne $Report.passed -or @($Report.checks | Where-Object Status -ne 'PASS').Count -ne 0) {
        throw 'A complete, unfiltered, passing component run is required.'
    }
}

function Assert-ReleaseManifest([string]$Root, [object]$Manifest) {
    if ($Manifest.schemaVersion -ne 1 -or $Manifest.runtimeIdentifier -ne 'win-x64' -or $Manifest.selfContained -ne $false -or
        $Manifest.verificationKind -ne 'Aster complete local engine and hidden component run') { throw 'Unsupported release evidence.' }
    Assert-ReleaseSources $Root @($Manifest.sources)
    Assert-ReleaseRecords $Root @($Manifest.binaries)
    Assert-ReleaseRecords $Root @($Manifest.reports)
    if (@($Manifest.reports).Count -ne 2) { throw 'Both engine and component reports are required.' }
    [xml]$engine = Get-Content -LiteralPath (Resolve-ReleasePath $Root $Manifest.reports[0].path) -Raw
    $ui = Get-Content -LiteralPath (Resolve-ReleasePath $Root $Manifest.reports[1].path) -Raw | ConvertFrom-Json
    Assert-ReleaseEngineReport $engine $Manifest.discoveredEngineTests
    Assert-ReleaseUiReport $ui
    foreach ($name in @('Aster.dll', 'ModernCalculator.Core.dll', 'ModernCalculator.Infrastructure.dll')) {
        $app = @($Manifest.binaries | Where-Object path -eq "src/ModernCalculator.WinForms/bin/Release/net10.0-windows/win-x64/$name")
        $component = @($Manifest.binaries | Where-Object path -eq "tests/ModernCalculator.UiChecks/bin/Release/net10.0-windows/win-x64/$name")
        if ($app.Count -ne 1 -or $component.Count -ne 1 -or $app[0].sha256 -ne $component[0].sha256) { throw "Component-tested binary does not match application: $name" }
        if ($name -ne 'Aster.dll') {
            $engineBinary = @($Manifest.binaries | Where-Object path -eq "tests/ModernCalculator.Tests/bin/Release/net10.0/win-x64/$name")
            if ($engineBinary.Count -ne 1 -or $engineBinary[0].sha256 -ne $app[0].sha256) { throw "Engine-tested binary does not match application: $name" }
        }
    }
}

function Assert-ReleasePayload([string]$Folder, [object[]]$Binaries) {
    $prefix = 'src/ModernCalculator.WinForms/bin/Release/net10.0-windows/win-x64/'
    $expected = @($Binaries | Where-Object { $_.path.StartsWith($prefix, [StringComparison]::Ordinal) })
    $actual = @(Get-ChildItem -LiteralPath $Folder -File -Recurse | Where-Object Extension -in @('.dll', '.exe', '.json'))
    if ($expected.Count -eq 0 -or $actual.Count -ne $expected.Count) { throw 'Published runtime payload differs from the verified dependency closure.' }
    foreach ($file in $actual) {
        $relative = [IO.Path]::GetRelativePath($Folder, $file.FullName).Replace('\', '/')
        $record = @($expected | Where-Object path -eq ($prefix + $relative))
        if ($record.Count -ne 1 -or (Get-FileHash -LiteralPath $file.FullName).Hash -ne $record[0].sha256) { throw "Published runtime file was not verified: $relative" }
    }
    foreach ($required in @('Aster.exe', 'Aster.dll', 'Aster.deps.json', 'Aster.runtimeconfig.json', 'ModernCalculator.Core.dll', 'ModernCalculator.Infrastructure.dll')) {
        if (@($expected | Where-Object path -eq ($prefix + $required)).Count -ne 1) { throw "Verified payload is missing $required" }
    }
}

function Copy-ReleaseDocumentation([string]$Root, [string]$Folder) {
    foreach ($name in @('LICENSE', 'README.md', 'documentation.md')) { Copy-Item -LiteralPath (Join-Path $Root $name) -Destination $Folder }
    $docs = Join-Path $Folder 'docs'
    [void][IO.Directory]::CreateDirectory($docs)
    Get-ChildItem -LiteralPath (Join-Path $Root 'docs') -Force | ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $docs -Recurse -Force }
    $guide = Join-Path $Folder 'tests/ModernCalculator.UiChecks'
    [void][IO.Directory]::CreateDirectory($guide)
    Copy-Item -LiteralPath (Join-Path $Root 'tests/ModernCalculator.UiChecks/README.md') -Destination $guide
    # Binary packages retain local user guides. Source-only links lead to the repository.
    foreach ($file in Get-ChildItem -LiteralPath $Folder -Filter '*.md' -File -Recurse) {
        $relative = [IO.Path]::GetRelativePath($Folder, $file.FullName)
        $source = Join-Path $Root $relative
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { continue }
        $content = [IO.File]::ReadAllText($file.FullName)
        $content = [regex]::Replace($content, '(\[[^\]\r\n]*\]\()([^\s\)]+)(\))', [Text.RegularExpressions.MatchEvaluator]{ param($match)
            $link = $match.Groups[2].Value
            if ($link.StartsWith('#') -or $link -match '^[a-zA-Z][a-zA-Z0-9+.-]*:' -or $link.StartsWith('//')) { return $match.Value }
            $parts = $link.Split('#', 2)
            $local = [IO.Path]::GetFullPath((Join-Path $file.DirectoryName ([Uri]::UnescapeDataString($parts[0]))))
            if (Test-Path -LiteralPath $local) { return $match.Value }
            $original = [IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetDirectoryName($source)) ([Uri]::UnescapeDataString($parts[0]))))
            $repoPath = [IO.Path]::GetRelativePath($Root, $original).Replace('\', '/')
            if ($repoPath -eq '..' -or $repoPath.StartsWith('../') -or -not (Test-Path -LiteralPath $original)) { throw "Broken documentation target in $relative : $link" }
            $kind = if (Test-Path -LiteralPath $original -PathType Container) { 'tree' } else { 'blob' }
            $encoded = ($repoPath.Split('/') | ForEach-Object { [Uri]::EscapeDataString($_) }) -join '/'
            $fragment = if ($parts.Count -gt 1) { '#' + $parts[1] } else { '' }
            return $match.Groups[1].Value + "https://github.com/gcfernando/aster-windows-calculator/$kind/main/$encoded$fragment" + $match.Groups[3].Value
        })
        [IO.File]::WriteAllText($file.FullName, $content, [Text.UTF8Encoding]::new($false))
    }
}

function Write-ReleaseArchive([string]$Folder, [string]$ArchivePath) {
    if (Test-Path -LiteralPath $ArchivePath) { throw "Preserve the existing archive: $ArchivePath" }
    Add-Type -AssemblyName System.IO.Compression
    $files = @(Get-ChildItem -LiteralPath $Folder -File -Recurse | Sort-Object FullName)
    $stream = [IO.File]::Open($ArchivePath, [IO.FileMode]::CreateNew)
    $archive = [IO.Compression.ZipArchive]::new($stream, [IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($file in $files) {
            $entry = $archive.CreateEntry([IO.Path]::GetRelativePath($Folder, $file.FullName).Replace('\', '/'), [IO.Compression.CompressionLevel]::Optimal)
            $inputFile = [IO.File]::OpenRead($file.FullName)
            $outputFile = $entry.Open()
            try { $inputFile.CopyTo($outputFile) } finally { $inputFile.Dispose(); $outputFile.Dispose() }
        }
    } finally { $archive.Dispose(); $stream.Dispose() }
    $archive = [IO.Compression.ZipFile]::OpenRead($ArchivePath)
    try {
        if ($archive.Entries.Count -ne $files.Count) { throw 'Archive entry count mismatch.' }
        foreach ($file in $files) {
            $entry = $archive.GetEntry([IO.Path]::GetRelativePath($Folder, $file.FullName).Replace('\', '/'))
            if ($null -eq $entry) { throw 'Archive is missing an input file.' }
            $entryStream = $entry.Open()
            try { $hash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($entryStream)) } finally { $entryStream.Dispose() }
            if ($hash -ne (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash) { throw 'Archive content hash mismatch.' }
        }
        foreach ($required in @('Aster.exe', 'LICENSE', 'START-HERE.txt', 'verification/manifest.json')) {
            if ($null -eq $archive.GetEntry($required)) { throw "Archive is missing required entry: $required" }
        }
    } finally { $archive.Dispose() }
}

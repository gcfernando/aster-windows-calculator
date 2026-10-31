# Inert PE fixtures and mocked signature metadata; no certificate is created and no application executes.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '../tools/SignedRelease.ps1')
$script:checks = 0
$script:caseNumber = 0
$script:mockSignature = $null
$script:fixtureRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot ('../artifacts/SigningEvidenceTests/'+[Guid]::NewGuid().ToString('N'))))
[void][IO.Directory]::CreateDirectory($script:fixtureRoot)

function Assert-True([bool]$Condition,[string]$Message) {
    if (-not $Condition) { throw $Message }
    $script:checks++
}
function Assert-Rejected([scriptblock]$Action,[string]$Message) {
    $rejected=$false
    try { & $Action | Out-Null } catch { $rejected=$true }
    Assert-True $rejected $Message
}
function Set-U16([byte[]]$Bytes,[int]$Offset,[uint16]$Value) { [BitConverter]::GetBytes($Value).CopyTo($Bytes,$Offset) }
function Set-U32([byte[]]$Bytes,[int]$Offset,[uint32]$Value) { [BitConverter]::GetBytes($Value).CopyTo($Bytes,$Offset) }
function New-PeBytes([switch]$Pe32) {
    $bytes=[byte[]]::new(1024)
    Set-U16 $bytes 0 0x5a4d
    Set-U32 $bytes 60 128
    Set-U32 $bytes 128 0x4550
    Set-U16 $bytes 132 0x8664
    Set-U16 $bytes 134 1
    $optional=152
    $size=if($Pe32){224}else{240}
    Set-U16 $bytes 148 $size
    Set-U16 $bytes $optional $(if($Pe32){0x10b}else{0x20b})
    Set-U32 $bytes ($optional+60) 512
    Set-U32 $bytes ($optional+$(if($Pe32){92}else{108})) 16
    Set-U32 $bytes ($optional+$size+16) 512
    Set-U32 $bytes ($optional+$size+20) 512
    for($i=512;$i -lt $bytes.Length;$i++){$bytes[$i]=[byte]($i % 251)}
    return ,$bytes
}
function Add-SyntheticCertificateTable([byte[]]$Original,[switch]$Pe32) {
    $bytes=[byte[]]::new($Original.Length+16)
    $Original.CopyTo($bytes,0)
    $directory=152+$(if($Pe32){128}else{144})
    Set-U32 $bytes (152+64) 0xabcdef
    Set-U32 $bytes $directory $Original.Length
    Set-U32 $bytes ($directory+4) 16
    Set-U32 $bytes $Original.Length 16
    Set-U16 $bytes ($Original.Length+4) 0x200
    Set-U16 $bytes ($Original.Length+6) 2
    for($i=8;$i -lt 16;$i++){$bytes[$Original.Length+$i]=[byte]$i}
    return ,$bytes
}
function New-MockSignature {
    [pscustomobject]@{
        Status='Valid';SignatureType='Authenticode'
        SignerCertificate=[pscustomobject]@{
            Subject='CN=Mock Publisher';Issuer='CN=Mock Issuer';Thumbprint=('a'*40)
            Extensions=@([pscustomobject]@{Oid=[pscustomobject]@{Value='2.5.29.37'};EnhancedKeyUsages=@([pscustomobject]@{Value='1.3.6.1.5.5.7.3.3'})})
        }
        TimeStamperCertificate=[pscustomobject]@{Subject='CN=Mock Timestamp'}
    }
}
function Get-AuthenticodeSignature([string]$LiteralPath) {
    if($null -ne $script:mockSignature){return $script:mockSignature}
    return Microsoft.PowerShell.Security\Get-AuthenticodeSignature -LiteralPath $LiteralPath
}
function Update-FixtureChecksum($Case) {
    $hash=(Get-FileHash -LiteralPath $Case.Archive).Hash.ToLowerInvariant()
    [IO.File]::WriteAllText($Case.Checksum,"$hash  $([IO.Path]::GetFileName($Case.Archive))`n")
}
function New-PackageCase {
    $script:caseNumber++
    $root=Join-Path $script:fixtureRoot ('case-'+$script:caseNumber)
    $source=Join-Path $root 'unsigned'
    [void][IO.Directory]::CreateDirectory((Join-Path $source 'verification'))
    foreach($name in $script:AsterAuthenticodeTargets){[IO.File]::WriteAllBytes((Join-Path $source $name),(New-PeBytes))}
    [IO.File]::WriteAllText((Join-Path $source 'LICENSE'),'MIT fixture')
    [IO.File]::WriteAllText((Join-Path $source 'START-HERE.txt'),'This unsigned preview candidate is not a certificate of stable-release readiness.')
    [IO.File]::WriteAllText((Join-Path $source 'verification/manifest.json'),'Unchanged verification fixture')
    $package=[ordered]@{
        schemaVersion=1;version='1.0.0';runtimeIdentifier='win-x64';selfContained=$false;signing='Unsigned preview candidate'
        verificationManifestSha256=(Get-FileHash -LiteralPath (Join-Path $source 'verification/manifest.json')).Hash.ToLowerInvariant()
        files=@(Get-SigningFileRecords $source)
    }
    [IO.File]::WriteAllText((Join-Path $source 'package-manifest.json'),($package|ConvertTo-Json -Depth 8))
    $case=[pscustomobject]@{Root=$root;Source=$source;Archive=(Join-Path $root 'Aster-win-x64.zip');Checksum=(Join-Path $root 'SHA256SUMS.txt');Destination=(Join-Path $root 'staged');SignedArchive=(Join-Path $root 'signed/Aster-win-x64.zip')}
    Write-ReleaseArchive $source $case.Archive
    Update-FixtureChecksum $case
    return $case
}
function Stage-Case($Case) {
    return Expand-VerifiedSigningPackage -Archive $Case.Archive -Checksum $Case.Checksum -Destination $Case.Destination
}
function Add-CaseSignatureTables($Case) {
    foreach($name in $script:AsterAuthenticodeTargets){
        $path=Join-Path $Case.Destination $name
        [IO.File]::WriteAllBytes($path,(Add-SyntheticCertificateTable ([IO.File]::ReadAllBytes($path))))
    }
}
function Finish-Case($Case) {
    return Complete-SignedRelease -Folder $Case.Destination -ArchivePath $Case.SignedArchive -ExpectedPublisher 'CN=Mock Publisher'
}

# The normalized digest accepts only the Authenticode envelope changes in PE32 and PE32+.
foreach($pe32 in @($false,$true)){
    $unsigned=New-PeBytes -Pe32:$pe32
    $signed=Add-SyntheticCertificateTable $unsigned -Pe32:$pe32
    $before=[Aster.ReleaseSigningBinary]::Inspect($unsigned)
    $after=[Aster.ReleaseSigningBinary]::Inspect($signed)
    Assert-True ($before.Sha256 -ceq $after.Sha256) 'Signature envelope changed the content digest.'
    $changed=[byte[]]$signed.Clone();$changed[700]=$changed[700] -bxor 1
    Assert-True (([Aster.ReleaseSigningBinary]::Inspect($changed)).Sha256 -cne $before.Sha256) 'Executable-byte mutation was hidden.'
    $changed=[byte[]]$signed.Clone();$changed[32]=1
    Assert-True (([Aster.ReleaseSigningBinary]::Inspect($changed)).Sha256 -cne $before.Sha256) 'Unrelated header mutation was hidden.'
}
$signed=Add-SyntheticCertificateTable (New-PeBytes)
foreach($mutator in @(
    {param($b) Set-U32 $b (152+144) 1025},
    {param($b) Set-U32 $b (152+144) 512;Set-U32 $b (152+148) 528},
    {param($b) Set-U32 $b 1024 7},
    {param($b) Set-U16 $b 1030 1},
    {param($b) Set-U32 $b (152+144) 0x7fffffff},
    {param($b) Set-U32 $b 60 0x7fffffff}
)){
    $changed=[byte[]]$signed.Clone(); & $mutator $changed
    Assert-Rejected {[Aster.ReleaseSigningBinary]::Inspect($changed)} 'Malformed PE certificate layout was accepted.'
}
$withOverlay=[byte[]]::new($signed.Length+8);$signed.CopyTo($withOverlay,0)
Assert-Rejected {[Aster.ReleaseSigningBinary]::Inspect($withOverlay)} 'Data after the certificate table was accepted.'

$case=New-PackageCase
$staged=Stage-Case $case
Assert-True (@($staged.Files).Count -eq 4 -and (Test-Path -LiteralPath $staged.SnapshotPath)) 'Signing stage contract is incomplete.'
Assert-True (-not $staged.SnapshotPath.StartsWith($case.Destination+[IO.Path]::DirectorySeparatorChar)) 'Snapshot was placed inside the signing payload.'
Assert-Rejected {Stage-Case $case} 'An existing destination was overwritten.'
Assert-Rejected {Finish-Case $case} 'Unsigned PE files were accepted for finalization.'
Assert-Rejected {Assert-TrustedSigningSignature (Join-Path $case.Destination 'Aster.exe') 'CN=Mock Publisher'} 'Real unsigned input passed signature verification.'

$bad=New-PackageCase
[IO.File]::WriteAllText($bad.Checksum,('0'*64)+'  Aster-win-x64.zip')
Assert-Rejected {Stage-Case $bad} 'Wrong transport checksum was accepted.'

# Names are rejected before extraction, including Windows canonicalization and ADS.
foreach($name in @('../escape.txt','/absolute.txt','C:/drive.txt','dir/../escape.txt','dir//file.txt','dir/./file.txt','dir\file.txt','file.txt:stream','CON.txt','NUL','trailing.','trailing /file','file?.txt')){
    $script:caseNumber++
    $root=Join-Path $script:fixtureRoot ('unsafe-'+$script:caseNumber)
    [void][IO.Directory]::CreateDirectory($root)
    $archive=Join-Path $root 'Aster-win-x64.zip'
    $zip=[IO.Compression.ZipFile]::Open($archive,[IO.Compression.ZipArchiveMode]::Create)
    try{$entry=$zip.CreateEntry($name);$s=$entry.Open();try{$s.WriteByte(1)}finally{$s.Dispose()}}finally{$zip.Dispose()}
    $bad=[pscustomobject]@{Archive=$archive;Checksum=(Join-Path $root 'SHA256SUMS.txt');Destination=(Join-Path $root 'staged')}
    Update-FixtureChecksum $bad
    Assert-Rejected {Stage-Case $bad} "Unsafe archive name was accepted: $name"
    Assert-True (-not(Test-Path -LiteralPath $bad.Destination)) 'Unsafe archive created a staging destination.'
}

foreach($mode in @('extra','duplicate','symlink','crc','filehash')){
    $bad=New-PackageCase
    if($mode -eq 'crc'){
        $bytes=[IO.File]::ReadAllBytes($bad.Archive)
        for($i=0;$i -lt $bytes.Length-20;$i++){
            if([BitConverter]::ToUInt32($bytes,$i) -eq 0x02014b50){$bytes[$i+16]=$bytes[$i+16] -bxor 1;break}
        }
        [IO.File]::WriteAllBytes($bad.Archive,$bytes)
    }else{
        $zip=[IO.Compression.ZipFile]::Open($bad.Archive,[IO.Compression.ZipArchiveMode]::Update)
        try{
            if($mode -eq 'filehash'){$entry=$zip.GetEntry('LICENSE');$s=$entry.Open();try{$s.SetLength(0);$s.WriteByte(42)}finally{$s.Dispose()}}
            else{
                $name=if($mode -eq 'duplicate'){'ASTER.EXE'}else{'unexpected.txt'}
                $entry=$zip.CreateEntry($name)
                if($mode -eq 'symlink'){$entry.ExternalAttributes=([int]0xa000 -shl 16)}
                $s=$entry.Open();try{$s.WriteByte(42)}finally{$s.Dispose()}
            }
        }finally{$zip.Dispose()}
    }
    Update-FixtureChecksum $bad
    Assert-Rejected {Stage-Case $bad} "Invalid archive was accepted: $mode"
}

# Signature metadata policy is exercised without generating a certificate.
$case=New-PackageCase; $null=Stage-Case $case; Add-CaseSignatureTables $case
foreach($change in @('publisher','timestamp','status','catalog','selfissued','eku')){
    $script:mockSignature=New-MockSignature
    switch($change){
        'publisher' {$script:mockSignature.SignerCertificate.Subject='CN=Wrong Publisher'}
        'timestamp' {$script:mockSignature.TimeStamperCertificate=$null}
        'status' {$script:mockSignature.Status='HashMismatch'}
        'catalog' {$script:mockSignature.SignatureType='Catalog'}
        'selfissued' {$script:mockSignature.SignerCertificate.Issuer='CN=Mock Publisher'}
        'eku' {$script:mockSignature.SignerCertificate.Extensions[0].EnhancedKeyUsages[0].Value='1.3.6.1.5.5.7.3.1'}
    }
    Assert-Rejected {Finish-Case $case} "Invalid signature metadata was accepted: $change"
}
foreach($change in @('nonpe','pe','extra','missing')){
    $case=New-PackageCase; $null=Stage-Case $case; Add-CaseSignatureTables $case
    $script:mockSignature=New-MockSignature
    switch($change){
        'nonpe' {[IO.File]::AppendAllText((Join-Path $case.Destination 'LICENSE'),'changed')}
        'pe' {$p=Join-Path $case.Destination 'Aster.dll';$b=[IO.File]::ReadAllBytes($p);$b[700]=$b[700] -bxor 1;[IO.File]::WriteAllBytes($p,$b)}
        'extra' {[IO.File]::WriteAllText((Join-Path $case.Destination 'extra.txt'),'extra')}
        'missing' {[IO.File]::Delete((Join-Path $case.Destination 'LICENSE'))}
    }
    Assert-Rejected {Finish-Case $case} "Changed signing payload was accepted: $change"
}

$case=New-PackageCase; $null=Stage-Case $case; Add-CaseSignatureTables $case
$script:mockSignature=New-MockSignature
$before=(Get-FileHash -LiteralPath (Join-Path $case.Destination 'verification/manifest.json')).Hash
$result=Finish-Case $case
$package=[IO.File]::ReadAllText((Join-Path $case.Destination 'package-manifest.json'))|ConvertFrom-Json
Assert-True ($result -ceq $case.SignedArchive -and (Test-Path -LiteralPath $result)) 'Final ZIP output contract failed.'
Assert-True ($package.version -ceq '1.0.0' -and $package.signing.status -ceq 'Authenticode signed' -and $package.signing.publisher -ceq 'CN=Mock Publisher') 'Final signing metadata/version is wrong.'
Assert-True (@($package.signing.files).Count -eq 4) 'Final metadata does not list exactly four PE files.'
foreach($record in $package.signing.files){
    Assert-True ($record.path -cin $script:AsterAuthenticodeTargets -and $record.unsignedSha256 -cne $record.signedSha256 -and $record.authenticodeContentSha256 -cmatch '^[a-f0-9]{64}$') 'Final signing evidence is incomplete.'
}
Assert-True ((Get-FileHash -LiteralPath (Join-Path $case.Destination 'verification/manifest.json')).Hash -ceq $before) 'Unsigned verification evidence was changed.'
Assert-ReleaseRecords $case.Destination @($package.files);$script:checks++
Assert-True (@($package.files | Where-Object path -CEQ 'package-manifest.json').Count -eq 0) 'Package manifest attempted to hash itself.'
$line=[IO.File]::ReadAllText((Join-Path ([IO.Path]::GetDirectoryName($result)) 'SHA256SUMS.txt')).Trim()
Assert-True ($line -ceq ((Get-FileHash -LiteralPath $result).Hash.ToLowerInvariant()+'  Aster-win-x64.zip')) 'Final archive checksum is wrong.'
Assert-Rejected {Finish-Case $case} 'An existing signed archive/checksum was overwritten.'
$script:mockSignature=$null
# Provider archives cannot replace metadata or partially change staged files on rejection.
foreach($mode in @('valid','missing','extra','case','duplicate','traversal','symlink','crc')) {
    $case=New-PackageCase; $null=Stage-Case $case
    $returned=Join-Path $case.Root 'provider.zip'
    $zip=[IO.Compression.ZipFile]::Open($returned,[IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach($name in $script:AsterAuthenticodeTargets) {
            if($mode -eq 'missing' -and $name -ceq 'Aster.exe'){continue}
            $member=if($mode -eq 'case' -and $name -ceq 'Aster.exe'){'ASTER.EXE'}elseif($mode -eq 'traversal' -and $name -ceq 'Aster.exe'){'../Aster.exe'}else{$name}
            $entry=$zip.CreateEntry($member)
            if($mode -eq 'symlink' -and $name -ceq 'Aster.exe'){$entry.ExternalAttributes=([int]0xa000 -shl 16)}
            $stream=$entry.Open()
            try {$bytes=Add-SyntheticCertificateTable (New-PeBytes);$stream.Write($bytes,0,$bytes.Length)} finally {$stream.Dispose()}
        }
        if($mode -in @('extra','duplicate')) {
            $entry=$zip.CreateEntry($(if($mode -eq 'duplicate'){'Aster.exe'}else{'package-manifest.json'}))
            $stream=$entry.Open();try{$stream.WriteByte(42)}finally{$stream.Dispose()}
        }
    } finally {$zip.Dispose()}
    if($mode -eq 'crc') {
        $bytes=[IO.File]::ReadAllBytes($returned)
        for($i=0;$i -lt $bytes.Length-20;$i++) {
            if([BitConverter]::ToUInt32($bytes,$i) -eq 0x02014b50){$bytes[$i+16]=$bytes[$i+16] -bxor 1;break}
        }
        [IO.File]::WriteAllBytes($returned,$bytes)
    }
    $before=@(Get-SigningFileRecords $case.Destination)|ConvertTo-Json -Compress
    if($mode -eq 'valid') {
        Import-SignPathPayload -Archive $returned -Folder $case.Destination
        $script:mockSignature=New-MockSignature
        $null=Finish-Case $case
        $package=[IO.File]::ReadAllText((Join-Path $case.Destination 'package-manifest.json'))|ConvertFrom-Json
        Assert-True ($package.version -ceq '1.0.0' -and $package.signing.status -ceq 'Authenticode signed') 'Imported provider output failed final content validation.'
        $script:mockSignature=$null
    } else {
        Assert-Rejected {Import-SignPathPayload -Archive $returned -Folder $case.Destination} "Invalid provider output accepted: $mode"
        Assert-True ((@(Get-SigningFileRecords $case.Destination)|ConvertTo-Json -Compress) -ceq $before) 'Rejected provider ZIP changed staged content.'
    }
}
Write-Output "PASS: $script:checks signing evidence checks. No certificate created, no application executed; positive signing metadata was mocked. Fixtures: $script:fixtureRoot"

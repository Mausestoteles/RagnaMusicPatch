<#
.SYNOPSIS
  Baut dist\RagnaMusicPatch.zip und dist\RagnaMusicPatch.zip.sha256 für ein Release.

.DESCRIPTION
  Die Zip enthält einen Ordner RagnaMusicPatch/ mit genau den Dateien, die der Patcher
  braucht (gleiche Liste wie $PatcherFiles in patch.ps1). Pfade mit „/“, damit jeder
  Entpacker sie versteht. Die .sha256-Datei prüft patch.ps1 -Update vor dem Installieren.
#>
param(
    [string]$OutDir = (Join-Path $PSScriptRoot '..\dist')
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem

$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$files = 'patch.ps1', 'README.md', 'ragna.ico', 'Start Patch.bat', 'Update Patch.bat', 'Uninstall Patch.bat', 'theme'

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$OutDir = [IO.Path]::GetFullPath($OutDir)
$zip = Join-Path $OutDir 'RagnaMusicPatch.zip'
if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }

$stream = [IO.File]::Open($zip, 'CreateNew')
$archive = New-Object IO.Compression.ZipArchive($stream, [IO.Compression.ZipArchiveMode]::Create)
try {
    foreach ($item in $files) {
        $path = Join-Path $root $item
        if (-not (Test-Path -LiteralPath $path)) { throw "Fehlt: $item" }
        $entries = if ((Get-Item -LiteralPath $path).PSIsContainer) { Get-ChildItem -LiteralPath $path -Recurse -File } else { Get-Item -LiteralPath $path }
        foreach ($file in $entries) {
            $name = 'RagnaMusicPatch/' + $file.FullName.Substring($root.Length).TrimStart('\').Replace('\', '/')
            [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, $file.FullName, $name, [IO.Compression.CompressionLevel]::Optimal)
        }
    }
}
finally {
    $archive.Dispose()
    $stream.Dispose()
}

$hash = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLower()
[IO.File]::WriteAllText("$zip.sha256", "$hash  RagnaMusicPatch.zip`n", (New-Object Text.UTF8Encoding $false))

$version = (Select-String -LiteralPath (Join-Path $root 'patch.ps1') -Pattern "^\`$PatchVersion = '(.+)'").Matches[0].Groups[1].Value
Write-Host "RagnaMusic Patch $version -> $zip"
Write-Host "SHA256 $hash"

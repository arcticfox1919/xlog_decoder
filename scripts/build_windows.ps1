# Run on Windows with Flutter and Visual Studio's Desktop development with C++.
# FLUTTER_BIN may point to a specific flutter.bat executable.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$project = Split-Path $PSScriptRoot -Parent
Push-Location $project
try {
    $pubspec = Get-Content 'pubspec.yaml' -Raw
    $match = [regex]::Match($pubspec, '(?m)^version:\s*[''"]?(\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?)[''"]?\s*$')
    if (-not $match.Success) {
        throw 'pubspec.yaml must contain a version such as 1.0.0.'
    }
    $version = $match.Groups[1].Value
    $flutter = if ($env:FLUTTER_BIN) { $env:FLUTTER_BIN } else { 'flutter' }
    # Flutter 3.35 selects the Windows target from the host architecture.
    # The workflow uses an x64 runner; --target-platform is not supported.
    & $flutter build windows --release --build-name $version --build-number 1
    if ($LASTEXITCODE -ne 0) { throw "Flutter build failed: $LASTEXITCODE" }

    $release = Join-Path $project 'build/windows/x64/runner/Release'
    $output = Join-Path $project 'build/windows/dist'
    New-Item -ItemType Directory -Path $output -Force | Out-Null
    $staging = Join-Path $output ('.package.' + [guid]::NewGuid().ToString('N'))
    $bundle = Join-Path $staging 'XlogDecoder'
    New-Item -ItemType Directory -Path $bundle -Force | Out-Null
    try {
        Copy-Item "$release/*" $bundle -Recurse -Force

        # Bundle the app-local VC++ runtime so users need no separate installer.
        $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
        $vs = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
        if ($LASTEXITCODE -ne 0 -or -not $vs) { throw 'Visual Studio C++ tools not found.' }
        $crt = Get-ChildItem (Join-Path $vs 'VC/Redist/MSVC') -Directory -Recurse |
            Where-Object { $_.Name -like 'Microsoft.VC*.CRT' -and $_.Parent.Name -eq 'x64' } |
            Sort-Object FullName -Descending |
            Select-Object -First 1
        if (-not $crt) { throw 'Visual C++ x64 redistributable DLLs not found.' }
        Copy-Item (Join-Path $crt.FullName '*.dll') $bundle -Force
        Copy-Item 'README.md', 'README_EN.md', 'THIRD_PARTY_NOTICES' $bundle

        foreach ($required in @('xlog_decoder.exe', 'flutter_windows.dll', 'data/app.so', 'data/icudtl.dat', 'msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll')) {
            if (-not (Test-Path (Join-Path $bundle $required))) {
                throw "Missing required package file: $required"
            }
        }
        $archive = Join-Path $output "Xlog-Decoder-$version-Windows-x64.zip"
        Compress-Archive -Path $bundle -DestinationPath $archive -Force
        Write-Host "Packaging complete: $archive"
    }
    finally {
        Remove-Item $staging -Recurse -Force
    }
}
finally {
    Pop-Location
}

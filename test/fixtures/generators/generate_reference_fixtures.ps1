param(
    [string]$MarsRoot = (Join-Path $PSScriptRoot '../../../../../c++/xlog/mars'),
    [string]$Compiler = 'clang'
)

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../../..')).Path
$marsPath = (Resolve-Path -LiteralPath $MarsRoot).Path
$zlibPath = Join-Path $marsPath 'comm/windows/zlib'
$zstdPath = Join-Path $marsPath 'zstd/lib'
$eccPath = Join-Path $marsPath 'xlog/crypt/micro-ecc-master'
$buildPath = Join-Path $projectRoot '.dart_tool/reference'
New-Item -ItemType Directory -Force $buildPath | Out-Null
$executable = Join-Path $buildPath 'generate.exe'

$zlibSources = @('crc32.c', 'deflate.c', 'trees.c', 'zutil.c') |
    ForEach-Object { Join-Path $zlibPath $_ }
$zstdSources = Get-ChildItem -LiteralPath (Join-Path $zstdPath 'common'), (Join-Path $zstdPath 'compress') -Filter '*.c' |
    Select-Object -ExpandProperty FullName
$compilerArgs = @(
    '-O2', '-DuECC_WORD_SIZE=4', '-Wno-deprecated-non-prototype',
    '-I', $zlibPath, '-I', $zstdPath, '-I', (Join-Path $zstdPath 'common'), '-I', $eccPath,
    (Join-Path $PSScriptRoot 'generate_reference_fixtures.c'),
    (Join-Path $eccPath 'uECC.c'), (Join-Path $marsPath 'comm/adler32.c')
) + $zlibSources + $zstdSources + @('-ladvapi32', '-o', $executable)
& $Compiler @compilerArgs
if ($LASTEXITCODE -ne 0) { throw 'Reference fixture generator compilation failed' }
$fixture = & $executable
if ($LASTEXITCODE -ne 0) { throw 'Reference fixture generation failed' }
$fixture | Set-Content -Encoding ascii (Join-Path $projectRoot 'test/fixtures/mars_reference.json')

param([switch]$WithoutFix)
$ErrorActionPreference = 'Stop'
$work = Join-Path ([IO.Path]::GetTempPath()) ('m2-internal-wait-' + [guid]::NewGuid())
New-Item -ItemType Directory -Path $work | Out-Null
Push-Location (Join-Path $PSScriptRoot '..')
try {
    & ghdl -a --std=08 "--workdir=$work" t80_pack.vhd t80_mcode.vhd t80_alu.vhd `
        t80_reg.vhd t80.vhd g80a.vhd test\tb_hw_m2_internal_cycle_wait.vhd
    if ($LASTEXITCODE -ne 0) { throw 'GHDL analysis failed.' }
    $release = if ($WithoutFix) { 'false' } else { 'true' }
    $output = & ghdl -r --std=08 "--workdir=$work" tb_hw_m2_internal_cycle_wait `
        "-gRelease_Internal=$release" --assert-level=error 2>&1
    $code = $LASTEXITCODE
    $output | Select-String -Pattern 'PASS|FAIL' | ForEach-Object { Write-Host $_.Line }
    if ($code -ne 0 -or -not ($output -match 'PASS: M2 bank01')) {
        throw 'M2 internal-cycle WAIT regression failed.'
    }
} finally {
    Pop-Location
    Get-ChildItem -LiteralPath $work | Remove-Item
    Remove-Item -LiteralPath $work
}

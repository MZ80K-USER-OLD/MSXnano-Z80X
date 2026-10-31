$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$work = Join-Path ([IO.Path]::GetTempPath()) ('m2sp-com-' + [guid]::NewGuid())
$com = Join-Path $root 'hardware_test\M2SPTest\bin\m2sptest.com'
if (-not (Test-Path -LiteralPath $com)) { throw 'Build M2SPTEST.COM first.' }
New-Item -ItemType Directory -Path $work | Out-Null
Push-Location (Join-Path $PSScriptRoot '..')
try {
    & ghdl -a --std=08 "--workdir=$work" t80_pack.vhd t80_mcode.vhd `
        t80_alu.vhd t80_reg.vhd t80.vhd test\tb_ld24mi_com.vhd
    if ($LASTEXITCODE -ne 0) { throw 'GHDL analysis failed.' }
    foreach ($cpu in 0, 1) {
        foreach ($wait in 'false', 'true') {
            $output = & ghdl -r --std=08 "--workdir=$work" tb_ld24mi_com `
                "-gCom_File=$com" '-gM2_SP_Test=true' "-gCpu_Mode=$cpu" `
                "-gWait_Enabled=$wait" --assert-level=error 2>&1
            $exitCode = $LASTEXITCODE
            if ($exitCode -ne 0) { $output | Write-Output; throw "COM simulation failed (CPU=$cpu, WAIT=$wait)." }
            if (-not ($output | Select-String -SimpleMatch 'PASS=58 FAIL=00')) {
                $output | Write-Output
                throw "Missing M2SP summary (CPU=$cpu, WAIT=$wait)."
            }
            Write-Output "PASS: CPU=$cpu WAIT=$wait PASS=58 FAIL=00"
        }
    }
} finally {
    Pop-Location
    $library = Join-Path $work 'work-obj08.cf'
    if (Test-Path -LiteralPath $library) { Remove-Item -LiteralPath $library }
    Remove-Item -LiteralPath $work
}

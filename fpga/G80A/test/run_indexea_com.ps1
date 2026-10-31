$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$work = Join-Path ([IO.Path]::GetTempPath()) ('indexea-com-' + [guid]::NewGuid())
$com = Join-Path $root 'hardware_test\IndexEATest\bin\indexea.com'
if (-not (Test-Path -LiteralPath $com)) { throw 'Build INDEXEA.COM first.' }
New-Item -ItemType Directory -Path $work | Out-Null
Push-Location (Join-Path $PSScriptRoot '..')
try {
    & ghdl -a --std=08 "--workdir=$work" t80_pack.vhd t80_mcode.vhd `
        t80_alu.vhd t80_reg.vhd t80.vhd test\tb_ld24mi_com.vhd
    if ($LASTEXITCODE -ne 0) { throw 'GHDL analysis failed.' }
    foreach ($cpu in 0, 1) {
        foreach ($wait in 'false', 'true') {
            foreach ($fault in 'false', 'true') {
                $expected = if ($fault -eq 'true') {
                    'PASS=65 FAIL=04 FIRST CASE=60 OFFSET=00'
                } else { 'PASS=69 FAIL=00' }
                $output = & ghdl -r --std=08 "--workdir=$work" tb_ld24mi_com `
                    "-gCom_File=$com" '-gIndex_EA_Test=true' "-gCpu_Mode=$cpu" `
                    "-gWait_Enabled=$wait" "-gInject_Fault=$fault" --assert-level=error 2>&1
                if ($LASTEXITCODE -ne 0) {
                    $output | Write-Output
                    throw "COM simulation failed (CPU=$cpu, WAIT=$wait, FAULT=$fault)."
                }
                if (-not ($output | Select-String -SimpleMatch $expected)) {
                    $output | Write-Output
                    throw "Missing INDEXEA summary (CPU=$cpu, WAIT=$wait, FAULT=$fault)."
                }
                Write-Output "PASS: CPU=$cpu WAIT=$wait FAULT=$fault $expected"
            }
        }
    }
} finally {
    Pop-Location
    $library = Join-Path $work 'work-obj08.cf'
    if (Test-Path -LiteralPath $library) { Remove-Item -LiteralPath $library }
    Remove-Item -LiteralPath $work
}

param([switch]$Transfer24, [switch]$M2)
$ErrorActionPreference = 'Stop'
$width = if ($Transfer24) { 24 } else { 16 }
$name = if ($M2) { "i${width}m2" } else { "index$width" }
$recordName = if ($M2) { "index${width}_m2_com" } else { "index${width}_com" }
$entrySource = if ($M2) { "index${width}_m2.asm" } else { "index${width}_test.asm" }
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$work = Join-Path ([IO.Path]::GetTempPath()) ('index16-com-' + [guid]::NewGuid())
$data = Join-Path $root "verification_data\$recordName"
New-Item -ItemType Directory -Path $work | Out-Null
New-Item -ItemType Directory -Force -Path $data | Out-Null
$com = Join-Path $root "hardware_test\Index${width}Test\bin\$name.com"
if (-not (Test-Path $com)) { throw "Build $name.COM first." }
Push-Location (Join-Path $PSScriptRoot '..')
try {
    & ghdl -a --std=08 "--workdir=$work" t80_pack.vhd t80_mcode.vhd `
        t80_alu.vhd t80_reg.vhd t80.vhd test\tb_ld24mi_com.vhd
    if ($LASTEXITCODE -ne 0) { throw 'GHDL analysis failed.' }
    foreach ($fault in 'false', 'true') {
        $output = & ghdl -r --std=08 "--workdir=$work" tb_ld24mi_com `
            "-gCom_File=$com" "-gIndex${width}_Test=true" "-gInject_Fault=$fault" `
            "-gM2_Test=$($M2.IsPresent.ToString().ToLowerInvariant())" --assert-level=error 2>&1
        $exitCode = $LASTEXITCODE
        $output | Set-Content -Encoding utf8 (Join-Path $data "fault-$fault.log")
        if ($exitCode -ne 0) { $output | Write-Output; throw "COM regression failed: fault=$fault" }
        $expected = if ($fault -eq 'true') { 'PASS=00 FAIL=18' } else { 'PASS=18 FAIL=00' }
        if (-not ($output | Select-String -SimpleMatch $expected)) { throw 'Missing summary.' }
        Write-Output "PASS: fault=$fault $expected"
    }
    $hashes = @{}
    foreach ($file in @("hardware_test\Index${width}Test\bin\$name.com",
                        "hardware_test\Index${width}Test\$entrySource",
                        'hardware_test\Index16Test\index16_test.asm',
                        'fpga\G80A\t80.vhd', 'fpga\G80A\t80_mcode.vhd',
                        'fpga\G80A\t80_pack.vhd', 'fpga\G80A\t80_alu.vhd', 'fpga\G80A\t80_reg.vhd',
                        'fpga\G80A\test\tb_ld24mi_com.vhd', 'fpga\G80A\test\run_index16_com.ps1')) {
        $hashes[$file] = (Get-FileHash -Algorithm SHA256 (Join-Path $root $file)).Hash
    }
    @{
        completed_utc = [DateTime]::UtcNow.ToString('o')
        engine = (& ghdl --version | Select-Object -First 1)
        measurement_mode = $(if ($M2) { 'M2' } else { 'M1' })
        normal_expected = 'PASS=18 FAIL=00'; fault_expected = 'PASS=00 FAIL=18'
        memory_banks = @('00', '01', '02'); complete = $true; source_sha256 = $hashes
    } | ConvertTo-Json -Depth 5 | Set-Content -Encoding utf8 (Join-Path $data 'summary.json')
} finally {
    Pop-Location
    $library = Join-Path $work 'work-obj08.cf'
    if (Test-Path $library) { Remove-Item -LiteralPath $library }
    Remove-Item -LiteralPath $work
}

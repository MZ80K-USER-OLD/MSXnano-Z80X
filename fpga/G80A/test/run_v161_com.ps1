$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$work = Join-Path ([IO.Path]::GetTempPath()) ('v161-com-' + [guid]::NewGuid())
$data = Join-Path $root 'verification_data\v161_com'
$com = Join-Path $root 'hardware_test\V161Test\bin\v161test.com'
if (-not (Test-Path -LiteralPath $com)) { throw 'Build V161TEST.COM first.' }
$hardwareReport = @{ hardware_tested = $false }
$summaryPath = Join-Path $data 'summary.json'
if (Test-Path -LiteralPath $summaryPath) {
    $previous = Get-Content -LiteralPath $summaryPath -Raw | ConvertFrom-Json
    if ($previous.hardware_tested -and
        $previous.source_sha256.'hardware_test\V161Test\bin\v161test.com' -eq
        (Get-FileHash -LiteralPath $com).Hash) {
        foreach ($property in $previous.PSObject.Properties | Where-Object { $_.Name -like 'hardware_*' }) {
            $hardwareReport[$property.Name] = $property.Value
        }
    }
}
New-Item -ItemType Directory -Path $work | Out-Null
New-Item -ItemType Directory -Force -Path $data | Out-Null
$started = [DateTime]::UtcNow.ToString('o')
(@{ complete = $false; started_utc = $started } + $hardwareReport) |
    ConvertTo-Json | Set-Content -Encoding utf8 (Join-Path $data 'summary.json')
Push-Location (Join-Path $PSScriptRoot '..')
try {
    & ghdl -a --std=08 "--workdir=$work" t80_pack.vhd t80_mcode.vhd `
        t80_alu.vhd t80_reg.vhd t80.vhd test\tb_ld24mi_com.vhd
    if ($LASTEXITCODE -ne 0) { throw 'GHDL analysis failed.' }
    $results = @()
    foreach ($cpu in 0, 1) {
        foreach ($wait in 'false', 'true') {
            foreach ($fault in 'false', 'true') {
                $log = "cpu-$cpu-wait-$wait-fault-$fault.log"
                $output = & ghdl -r --std=08 "--workdir=$work" tb_ld24mi_com `
                    "-gCom_File=$com" '-gV161_Control_Test=true' "-gCpu_Mode=$cpu" `
                    "-gWait_Enabled=$wait" "-gInject_Fault=$fault" --assert-level=error 2>&1
                $exitCode = $LASTEXITCODE
                $output | Set-Content -Encoding utf8 (Join-Path $data $log)
                if ($exitCode -ne 0) { $output | Write-Output; throw "COM failed: $log" }
                $expected = if ($fault -eq 'true') { 'PASS=02 FAIL=18' } else { 'PASS=1A FAIL=00' }
                if (-not ($output | Select-String -SimpleMatch $expected)) { throw "Missing summary: $log" }
                foreach ($case in 0..25) {
                    $id = $case.ToString('X2')
                    $line = if ($fault -eq 'true' -and $case -lt 24) {
                        "Case ${id}: FAIL offset=00 got=A5 want=5A"
                    } else {
                        "Case ${id}: PASS"
                    }
                    if (@($output | Where-Object { "$_".EndsWith($line) }).Count -ne 1) {
                        throw "Missing or duplicate case result: $log $line"
                    }
                }
                $results += @{
                    cpu_mode = $cpu; wait_enabled = ($wait -eq 'true')
                    inject_fault = ($fault -eq 'true'); expected = $expected
                    log = $log; log_sha256 = (Get-FileHash -LiteralPath (Join-Path $data $log)).Hash
                    passed = $true; exit_code = $exitCode
                }
                Write-Output "PASS: $log $expected"
            }
        }
    }
    $hashes = @{}
    foreach ($file in @('hardware_test\V161Test\v161_test.asm',
                        'hardware_test\V161Test\makefile',
                        'hardware_test\V161Test\bin\v161test.com',
                        'fpga\G80A\t80.vhd', 'fpga\G80A\t80_mcode.vhd',
                        'fpga\G80A\t80_pack.vhd', 'fpga\G80A\t80_alu.vhd', 'fpga\G80A\t80_reg.vhd',
                        'fpga\G80A\test\tb_ld24mi_com.vhd', 'fpga\G80A\test\run_v161_com.ps1')) {
        $hashes[$file] = (Get-FileHash -LiteralPath (Join-Path $root $file)).Hash
    }
    (@{
        complete = $true; started_utc = $started; completed_utc = [DateTime]::UtcNow.ToString('o')
        engine = (& ghdl --version | Select-Object -First 1); source_sha256 = $hashes
        memory_banks = @('00', '01', '02'); results = $results
    } + $hardwareReport) | ConvertTo-Json -Depth 6 | Set-Content -Encoding utf8 (Join-Path $data 'summary.json')
} finally {
    Pop-Location
    $library = Join-Path $work 'work-obj08.cf'
    if (Test-Path -LiteralPath $library) { Remove-Item -LiteralPath $library }
    Remove-Item -LiteralPath $work
}

param([switch]$NoInterrupt, [switch]$Smoke)
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$work = Join-Path ([IO.Path]::GetTempPath()) ('v161-irq-com-' + [guid]::NewGuid())
$record = if ($NoInterrupt) { 'v161_irq_com_no_irq' } elseif ($Smoke) { 'v161_irq_com_smoke' } else { 'v161_irq_com' }
$data = Join-Path $root "verification_data\$record"
$assemblerCommand = Get-Command z88dk-z80asm -ErrorAction SilentlyContinue
if (-not $assemblerCommand) {
    throw 'z88dk-z80asm is required to assemble the accelerated simulation COM.'
}
New-Item -ItemType Directory -Path $work | Out-Null
New-Item -ItemType Directory -Force -Path $data | Out-Null
$objectDirectory = Join-Path $work 'obj'
New-Item -ItemType Directory -Path $objectDirectory | Out-Null
$com = Join-Path $objectDirectory 'i161test_simulation.com'
$assemblyDirectory = Join-Path $root 'hardware_test\V161IRQTest'
Push-Location $assemblyDirectory
try {
    & $env:ComSpec /c ('"{0}" -DSIMULATION -O"{1}" -oi161test_simulation.com -b i161_test.asm' -f `
        $assemblerCommand.Source, $objectDirectory)
    if ($LASTEXITCODE -ne 0) { throw 'Accelerated simulation COM assembly failed.' }
} finally {
    Pop-Location
}
$simulationComHash = (Get-FileHash -LiteralPath $com).Hash
$started = [DateTime]::UtcNow.ToString('o')
@{ complete = $false; started_utc = $started } |
    ConvertTo-Json | Set-Content -Encoding utf8 (Join-Path $data 'summary.json')
Push-Location (Join-Path $PSScriptRoot '..')
try {
    & ghdl -a --std=08 "--workdir=$work" t80_pack.vhd t80_mcode.vhd `
        t80_alu.vhd t80_reg.vhd t80.vhd test\tb_ld24mi_com.vhd
    if ($LASTEXITCODE -ne 0) { throw 'GHDL analysis failed.' }
    $results = @()
    $cores = if ($NoInterrupt -or $Smoke) { @(0) } else { @(0, 1) }
    $waits = if ($NoInterrupt -or $Smoke) { @('false') } else { @('false', 'true') }
    $faults = if ($NoInterrupt -or $Smoke) { @('false') } else { @('false', 'true') }
    foreach ($cpu in $cores) {
        foreach ($wait in $waits) {
            foreach ($fault in $faults) {
                $log = "cpu-$cpu-wait-$wait-fault-$fault.log"
                $output = & ghdl -r --std=08 "--workdir=$work" tb_ld24mi_com `
                    "-gCom_File=$com" '-gV161_IRQ_Test=true' "-gCpu_Mode=$cpu" `
                    "-gWait_Enabled=$wait" "-gInject_Fault=$fault" `
                    "-gSuppress_VDP_IRQ=$($NoInterrupt.IsPresent.ToString().ToLowerInvariant())" `
                    --assert-level=error 2>&1
                $exitCode = $LASTEXITCODE
                $output | Set-Content -Encoding utf8 (Join-Path $data $log)
                if ($exitCode -ne 0) { $output | Write-Output; throw "COM failed: $log" }
                $expected = if ($fault -eq 'true' -or $NoInterrupt) { 'PASS=00 FAIL=04' } else { 'PASS=04 FAIL=00' }
                if (-not ($output | Select-String -SimpleMatch $expected)) { throw "Missing summary: $log" }
                foreach ($case in 0..3) {
                    $id = $case.ToString('X2')
                    $line = if ($NoInterrupt) {
                        "Case ${id}: FAIL offset=00 got=00 want=02"
                    } elseif ($fault -eq 'true') {
                        "Case ${id}: FAIL offset=13 got=A5 want=5A"
                    } else {
                        "Case ${id}: PASS"
                    }
                    if (@($output | Where-Object { "$_".EndsWith($line) }).Count -ne 1) {
                        throw "Missing or duplicate case result: $log $line"
                    }
                }
                $results += @{
                    cpu_mode = $cpu; wait_enabled = ($wait -eq 'true')
                    inject_fault = ($fault -eq 'true'); suppress_irq = $NoInterrupt.IsPresent
                    expected = $expected; log = $log
                    log_sha256 = (Get-FileHash -LiteralPath (Join-Path $data $log)).Hash
                    passed = $true; exit_code = $exitCode
                }
                Write-Output "PASS: $log $expected"
            }
        }
    }
    $hashes = @{}
    foreach ($file in @('hardware_test\V161IRQTest\i161_test.asm',
                        'hardware_test\V161IRQTest\makefile',
                        'hardware_test\V161IRQTest\bin\i161test.com',
                        'fpga\G80A\t80.vhd', 'fpga\G80A\t80_mcode.vhd',
                        'fpga\G80A\t80_pack.vhd', 'fpga\G80A\t80_alu.vhd', 'fpga\G80A\t80_reg.vhd',
                        'fpga\G80A\test\tb_ld24mi_com.vhd', 'fpga\G80A\test\run_v161_irq_com.ps1')) {
        $hashes[$file] = (Get-FileHash -LiteralPath (Join-Path $root $file)).Hash
    }
    @{
        complete = $true; started_utc = $started; completed_utc = [DateTime]::UtcNow.ToString('o')
        engine = (& ghdl --version | Select-Object -First 1); source_sha256 = $hashes
        simulation_com_sha256 = $simulationComHash
        simulation_wait_ticks = 4096
        memory_banks = @('00', '01', '02'); results = $results; hardware_tested = $false
    } | ConvertTo-Json -Depth 6 | Set-Content -Encoding utf8 (Join-Path $data 'summary.json')
} finally {
    Pop-Location
    $library = Join-Path $work 'work-obj08.cf'
    if (Test-Path -LiteralPath $library) { Remove-Item -LiteralPath $library }
    Remove-Item -LiteralPath $work -Recurse -Force
}

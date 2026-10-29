param([switch]$Smoke, [switch]$NoInterrupt)
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$work = Join-Path ([IO.Path]::GetTempPath()) ('v161-halt-com-' + [guid]::NewGuid())
$record = if ($NoInterrupt) { 'v161_halt_com_no_irq' } elseif ($Smoke) { 'v161_halt_com_smoke' } else { 'v161_halt_com' }
$data = Join-Path $root "verification_data\$record"
$assembler = Get-Command z88dk-z80asm -ErrorAction Stop
New-Item -ItemType Directory -Path $work | Out-Null
New-Item -ItemType Directory -Force -Path $data | Out-Null
$started = [DateTime]::UtcNow.ToString('o')
@{ complete = $false; started_utc = $started } |
    ConvertTo-Json | Set-Content -Encoding utf8 (Join-Path $data 'summary.json')
try {
    Push-Location (Join-Path $root 'hardware_test\V161HALTTest')
    try {
        & $assembler.Source "-O=$work" '-o=h161test.com' -b h161_test.asm
        if ($LASTEXITCODE -ne 0) { throw 'HALT COM assembly failed.' }
    } finally { Pop-Location }
    $com = Join-Path $work 'h161test.com'
    Push-Location (Join-Path $PSScriptRoot '..')
    try {
        & ghdl -a --std=08 "--workdir=$work" t80_pack.vhd t80_mcode.vhd `
            t80_alu.vhd t80_reg.vhd t80.vhd test\tb_ld24mi_com.vhd
        if ($LASTEXITCODE -ne 0) { throw 'GHDL analysis failed.' }
        $results = @()
        $cores = if ($Smoke -or $NoInterrupt) { @(0) } else { @(0, 1) }
        $waits = if ($Smoke -or $NoInterrupt) { @('false') } else { @('false', 'true') }
        $faults = if ($Smoke -or $NoInterrupt) { @('false') } else { @('false', 'true') }
        $blockedModes = if ($NoInterrupt) { @(0, 1, 2) } else { @(0) }
        foreach ($cpu in $cores) {
            foreach ($wait in $waits) {
                foreach ($fault in $faults) {
                  foreach ($blockedMode in $blockedModes) {
                    $log = "cpu-$cpu-wait-$wait-fault-$fault-blocked-$blockedMode.log"
                    $output = & ghdl -r --std=08 "--workdir=$work" tb_ld24mi_com `
                        "-gCom_File=$com" '-gHALT_IRQ_Test=true' "-gCpu_Mode=$cpu" `
                        "-gWait_Enabled=$wait" "-gInject_Fault=$fault" `
                        "-gSuppress_VDP_IRQ=$($NoInterrupt.IsPresent.ToString().ToLowerInvariant())" `
                        "-gSuppress_HALT_Mode=$blockedMode" `
                        --assert-level=error 2>&1
                    $exitCode = $LASTEXITCODE
                    $output | Set-Content -Encoding utf8 (Join-Path $data $log)
                    if ($NoInterrupt) {
                        if ($exitCode -eq 0 -or -not ($output | Select-String -SimpleMatch "HALT no-IRQ control: held in M$blockedMode HALT without handler or resume")) {
                            $output | Write-Output
                            throw 'HALT no-IRQ control did not remain halted as expected.'
                        }
                    } else {
                        if ($exitCode -ne 0) { $output | Write-Output; throw "HALT COM failed: $log" }
                        foreach ($mode in 0..2) {
                            $id = $mode.ToString('X2')
                            $line = if ($fault -eq 'true' -and $mode -eq 2) {
                                "HALT M${id}: FAIL offset=15 got=A5 want=5A"
                            } else { "HALT M${id}: PASS" }
                            if (@($output | Where-Object { "$_".EndsWith($line) }).Count -ne 1) {
                                throw "Missing or duplicate HALT result: $log $line"
                            }
                        }
                        $expected = if ($fault -eq 'true') { 'PASS=02 FAIL=01' } else { 'PASS=03 FAIL=00' }
                        if (-not ($output | Select-String -SimpleMatch $expected)) { throw "Missing HALT summary: $log" }
                    }
                    $results += @{
                        cpu_mode = $cpu; wait_enabled = ($wait -eq 'true')
                        inject_fault = ($fault -eq 'true'); suppress_irq = $NoInterrupt.IsPresent
                        blocked_mode = $blockedMode
                        passed = $true; exit_code = $exitCode; log = $log
                        log_sha256 = (Get-FileHash -LiteralPath (Join-Path $data $log)).Hash
                    }
                    Write-Output "PASS: $log"
                  }
                }
            }
        }
        $hashes = @{}
        foreach ($file in @('hardware_test\V161HALTTest\h161_test.asm',
                            'fpga\G80A\test\run_v161_halt_com.ps1', 'fpga\G80A\test\tb_ld24mi_com.vhd',
                            'fpga\G80A\t80.vhd', 'fpga\G80A\t80_mcode.vhd',
                            'fpga\G80A\t80_pack.vhd', 'fpga\G80A\t80_alu.vhd', 'fpga\G80A\t80_reg.vhd')) {
            $hashes[$file] = (Get-FileHash -LiteralPath (Join-Path $root $file)).Hash
        }
        @{
            complete = $true; started_utc = $started; completed_utc = [DateTime]::UtcNow.ToString('o')
            engine = (& ghdl --version | Select-Object -First 1)
            source_sha256 = $hashes; com_sha256 = (Get-FileHash -LiteralPath $com).Hash
            results = $results; hardware_tested = $false
        } | ConvertTo-Json -Depth 6 | Set-Content -Encoding utf8 (Join-Path $data 'summary.json')
    } finally { Pop-Location }
} finally {
    Remove-Item -LiteralPath $work -Recurse -Force
}

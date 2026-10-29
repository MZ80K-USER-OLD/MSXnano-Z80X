param([switch]$Transfer24, [switch]$FastBoundaryOnly)
$ErrorActionPreference = 'Stop'
$width = if ($Transfer24) { 24 } else { 16 }
$scenarioList = if ($Transfer24) { @(0,1,2,3,4) } else { @(0,1,2,3) }
$expectedCases = if ($Transfer24) { 528 } else { 432 }
if ($FastBoundaryOnly) {
    $scenarioList = @(0)
    $expectedCases = 48
}
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$data = Join-Path $root "verification_data\v15_index$width"
if ($FastBoundaryOnly) { $data = Join-Path $root "verification_data\v161_interrupt\index${width}_fast" }
New-Item -ItemType Directory -Force -Path $data | Out-Null
$encoding = [Text.UTF8Encoding]::new($false)
$cases = [IO.StreamWriter]::new((Join-Path $data 'cases.jsonl'), $false, $encoding)
$results = [IO.StreamWriter]::new((Join-Path $data 'results.jsonl'), $false, $encoding)
$started = [DateTime]::UtcNow.ToString('o')
$passed = 0
$work = Join-Path ([IO.Path]::GetTempPath()) ('v15-index16-' + [guid]::NewGuid())
New-Item -ItemType Directory -Path $work | Out-Null
Push-Location (Join-Path $PSScriptRoot '..')
try {
    & ghdl -a --std=08 "--workdir=$work" t80_pack.vhd t80_mcode.vhd `
        t80_alu.vhd t80_reg.vhd t80.vhd test\tb_v15_index16.vhd
    if ($LASTEXITCODE -ne 0) { throw 'GHDL analysis failed.' }
    $count = 0
    $cpuList = if ($FastBoundaryOnly) { @(1) } else { @(0,1) }
    $modeList = if ($FastBoundaryOnly) { @(1,2) } else { @(0,1,2) }
    foreach ($cpu in $cpuList) {
        foreach ($mode in $modeList) {
            foreach ($iy in 'false', 'true') {
                foreach ($pair in 0, 1, 2) {
                    foreach ($store in 'false', 'true') {
                        foreach ($scenario in $scenarioList) {
                            if ($mode -eq 0 -and $scenario -ne 0) { continue }
                            foreach ($wait in 'false', 'true') {
                                $output = & ghdl -r --std=08 "--workdir=$work" tb_v15_index16 `
                                    "-gCpu_Mode=$cpu" "-gMode24_Value=$mode" "-gIndex_IY=$iy" `
                                    "-gPair_Number=$pair" "-gStore_Pair=$store" `
                                    "-gTransfer24=$($Transfer24.IsPresent.ToString().ToLowerInvariant())" `
                                    "-gScenario=$scenario" "-gWith_Wait=$wait" -gDump_Records=true --assert-level=error 2>&1
                                $exitCode = $LASTEXITCODE
                                $id = "cpu$cpu-m$mode-iy$iy-pair$pair-store$store-s$scenario-wait$wait"
                                $programLine = $output | Select-String 'INPUT_PROGRAM ([0-9A-F]+)' | Select-Object -First 1
                                $programHex = if ($programLine) { $programLine.Matches[0].Groups[1].Value } else { $null }
                                $base = @(65535, 0, 32896, 65408, 65534)[$scenario]
                                $target = @(131071, 65535, 98304, 131071, 131070)[$scenario]
                                $expected = if ($mode -eq 0) {
                                    @{ comparison = 'unprefixed-z80-reference'; state_bytes = 'BC_LE,DE_LE,HL_LE,F,A' }
                                } else {
                                    @{ pair = 'BEEF'; index = ('{0:X4}' -f $base); flags = 'D7'
                                       pair_bank = $(if ($Transfer24 -and $store -eq 'false') { 'A5' } else { '67' }); index_bank = '01'
                                       target_writes = $(if ($store -eq 'true') { $width / 8 } else { 0 }) }
                                }
                                $case = [ordered]@{
                                    id = $id; cpu_mode = $cpu; mode24 = $mode
                                    index = $(if ($iy -eq 'true') { 'IY' } else { 'IX' })
                                    pair = @('BC','DE','HL')[$pair]; store = ($store -eq 'true')
                                    transfer_bits = $width
                                    displacement_hex = @('00','FF','80','7F','00')[$scenario]
                                    target_address = ('{0:X6}' -f $target)
                                    wait = @{ enabled = ($wait -eq 'true'); rule = 'WAIT_n=0 when ticks%5<2; ticks increments each rising edge' }
                                    initial = @{ reset = $true; program_address = '000000'; program_hex = $programHex
                                        memory_default = '00'; memory_00FFFF = 'EF'
                                        target_read_bytes = $(if ($mode -ne 0 -and $store -eq 'false') { if ($Transfer24) { 'EFBEA5' } else { 'EFBE' } } else { $null })
                                        clock_period_ns = 20; reset_release_ns = 45 }
                                    expected = $expected
                                }
                                $cases.WriteLine(($case | ConvertTo-Json -Depth 8 -Compress))
                                $actual = @{}
                                $stateLine = $output | Select-String 'RESULT_M12 (.+)' | Select-Object -First 1
                                if ($stateLine) {
                                    foreach ($match in [regex]::Matches($stateLine.Matches[0].Groups[1].Value, '(\w+)=(\w+)')) {
                                        $actual[$match.Groups[1].Value] = $match.Groups[2].Value
                                    }
                                }
                                $referenceLine = $output | Select-String 'RESULT_M0 reference=(\w+) actual=(\w+)' | Select-Object -First 1
                                if ($referenceLine) {
                                    $actual.reference = $referenceLine.Matches[0].Groups[1].Value
                                    $actual.state = $referenceLine.Matches[0].Groups[2].Value
                                }
                                $hasRecord = ($null -ne $stateLine) -or ($null -ne $referenceLine)
                                $ok = $exitCode -eq 0 -and $hasRecord -and $null -ne $programHex
                                $results.WriteLine((@{
                                    id = $id; passed = $ok; exit_code = $exitCode; actual = $actual
                                    diagnostics = @($output | Where-Object { "$_" -match 'assertion failure|error:|Timeout' } | ForEach-Object { "$_" })
                                } | ConvertTo-Json -Depth 8 -Compress))
                                if (-not $ok) {
                                    $output | Write-Output
                                    throw "Failed cpu=$cpu mode=$mode iy=$iy pair=$pair store=$store scenario=$scenario wait=$wait"
                                }
                                $count++
                                $passed++
                            }
                        }
                    }
                }
            }
        }
    }
    Write-Output "PASS: $count V15 indexed$width cases"
} finally {
    $cases.Dispose()
    $results.Dispose()
    $hashes = @{}
    foreach ($file in @('fpga\G80A\t80.vhd', 'fpga\G80A\t80_mcode.vhd', 'fpga\G80A\t80_pack.vhd',
                        'fpga\G80A\t80_alu.vhd', 'fpga\G80A\t80_reg.vhd',
                        'fpga\G80A\test\tb_v15_index16.vhd', 'fpga\G80A\test\run_v15_index16.ps1')) {
        $hashes[$file] = (Get-FileHash -Algorithm SHA256 (Join-Path $root $file)).Hash
    }
    $summary = @{
        schema = "msxnano-v15-index$width-v1"; started_utc = $started
        completed_utc = [DateTime]::UtcNow.ToString('o')
        expected_cases = $expectedCases; passed = $passed; complete = ($passed -eq $expectedCases)
        fast_boundary_only = $FastBoundaryOnly.IsPresent
        engine = (& ghdl --version | Select-Object -First 1)
        source_sha256 = $hashes
    }
    [IO.File]::WriteAllText((Join-Path $data 'summary.json'), ($summary | ConvertTo-Json -Depth 8), $encoding)
    Pop-Location
    $library = Join-Path $work 'work-obj08.cf'
    if (Test-Path $library) { Remove-Item -LiteralPath $library }
    Remove-Item -LiteralPath $work
}

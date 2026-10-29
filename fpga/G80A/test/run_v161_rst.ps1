param([switch]$LongRST)
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$work = Join-Path ([IO.Path]::GetTempPath()) ('v161-rst-' + [guid]::NewGuid())
$folder = if ($LongRST) { 'v161_rst_l' } else { 'v161_rst' }
$data = Join-Path $root "verification_data\$folder"
New-Item -ItemType Directory -Path $work | Out-Null
New-Item -ItemType Directory -Force -Path $data | Out-Null
$passed = 0
$vectors = 0
$expectedCases = if ($LongRST) { 160 } else { 96 }
$started = [DateTime]::UtcNow.ToString('o')
$records = [IO.StreamWriter]::new((Join-Path $data 'results.jsonl'), $false)
Push-Location (Join-Path $PSScriptRoot '..')
try {
    & ghdl -a --std=08 "--workdir=$work" t80_pack.vhd t80_mcode.vhd `
        t80_alu.vhd t80_reg.vhd t80.vhd test\tb_v161_rst.vhd
    if ($LASTEXITCODE -ne 0) { throw 'GHDL analysis failed.' }
    foreach ($mode in 0..2) {
        foreach ($cpu in 0,1) {
            foreach ($bank in 1,2) {
                foreach ($boundary in 'false','true') {
                    foreach ($wait in 'false','true') {
                        foreach ($enabled in 'false','true') {
                          $jumpModes = if ($LongRST -and $mode -eq 2) { @(0,1,2) } else { @(0) }
                          foreach ($jumpMode in $jumpModes) {
                            $output = & ghdl -r --std=08 "--workdir=$work" tb_v161_rst `
                                "-gMode_Value=$mode" "-gCpu_Mode=$cpu" "-gCode_Bank=$bank" `
                                "-gBoundary=$boundary" "-gWith_Wait=$wait" "-gEnabled=$enabled" `
                                "-gLong_RST=$($LongRST.IsPresent.ToString().ToLowerInvariant())" `
                                "-gJump_Mode=$jumpMode" --assert-level=error 2>&1
                            $exitCode = $LASTEXITCODE
                            $marker = if ($LongRST) { 'PASS: V16.1 RST.L' } else { 'PASS: eight ordinary RST' }
                            $ok = $exitCode -eq 0 -and ($output -match $marker)
                            $records.WriteLine((@{
                                mode24 = $mode; cpu_mode = $cpu; code_bank = $bank
                                boundary = ($boundary -eq 'true'); wait_enabled = ($wait -eq 'true')
                                iff_enabled = ($enabled -eq 'true'); passed = [bool]$ok
                                long_rst = $LongRST.IsPresent
                                jump_mode = $jumpMode
                                exit_code = $exitCode; output = @($output | ForEach-Object { "$_" })
                            } | ConvertTo-Json -Depth 4 -Compress))
                            if (-not $ok) {
                                $output | Write-Output
                                throw "Failed mode=$mode cpu=$cpu bank=$bank boundary=$boundary wait=$wait IFF=$enabled"
                            }
                            $passed++
                            if (-not $LongRST -or $mode -eq 2) { $vectors += 8 }
                          }
                        }
                    }
                }
            }
        }
    }
    Write-Output "PASS: $passed RST scenarios (LongRST=$LongRST)"
} finally {
    $records.Dispose()
    $hashes = @{}
    foreach ($file in @('t80_pack.vhd','t80_mcode.vhd','t80_alu.vhd','t80_reg.vhd','t80.vhd',
                        'test\tb_v161_rst.vhd','test\run_v161_rst.ps1')) {
        $hashes["fpga\G80A\$file"] = (Get-FileHash -Algorithm SHA256 $file).Hash
    }
    @{
        started_utc = $started; completed_utc = [DateTime]::UtcNow.ToString('o')
        expected_cases = $expectedCases; passed = $passed; complete = ($passed -eq $expectedCases)
        vector_executions = $vectors
        long_rst = $LongRST.IsPresent
        engine = (& ghdl --version | Select-Object -First 1); source_sha256 = $hashes
        results_sha256 = (Get-FileHash -Algorithm SHA256 (Join-Path $data 'results.jsonl')).Hash
    } | ConvertTo-Json -Depth 4 | Set-Content -Encoding utf8 (Join-Path $data 'summary.json')
    Pop-Location
    $library = Join-Path $work 'work-obj08.cf'
    if (Test-Path $library) { Remove-Item -LiteralPath $library }
    Remove-Item -LiteralPath $work
}

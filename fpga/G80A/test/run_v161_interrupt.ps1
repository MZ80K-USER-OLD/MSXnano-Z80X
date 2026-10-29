param([switch]$Syscall)
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$work = Join-Path ([IO.Path]::GetTempPath()) ('v161-irq-' + [guid]::NewGuid())
$folder = if ($Syscall) { 'v161_syscall' } else { 'v161_interrupt' }
$expectedCases = if ($Syscall) { 208 } else { 512 }
$data = Join-Path $root "verification_data\$folder"
New-Item -ItemType Directory -Path $work | Out-Null
New-Item -ItemType Directory -Force -Path $data | Out-Null
$passed = 0
$started = [DateTime]::UtcNow.ToString('o')
$records = [IO.StreamWriter]::new((Join-Path $data 'results.jsonl'), $false)
Push-Location (Join-Path $PSScriptRoot '..')
try {
    & ghdl -a --std=08 "--workdir=$work" t80_pack.vhd t80_mcode.vhd `
        t80_alu.vhd t80_reg.vhd t80.vhd test\tb_v161_interrupt.vhd
    if ($LASTEXITCODE -ne 0) { throw 'GHDL analysis failed.' }
    foreach ($mode in 0..2) {
      $banks = if ($mode -eq 2) { @(0,1,2) } else { @(2) }
      $boundaries = if ($mode -eq 2) { @('false','true') } else { @('false') }
      foreach ($cpu in 0,1) {
        foreach ($ibr in $banks) {
            $ims = if ($Syscall) { @(2) } else { @(0,1,2) }
            $nmis = if ($Syscall) { @('false') } else { @('false','true') }
            foreach ($im in $ims) {
                foreach ($nmi in $nmis) {
                    $tables = if ($Syscall -and $mode -eq 2) { @(0,1,2,3) }
                              elseif (-not $Syscall -and $im -eq 2 -and $nmi -eq 'false') { @(0,1,2) }
                              else { @(0) }
                    foreach ($table in $tables) {
                        foreach ($boundary in $boundaries) {
                            foreach ($wait in 'false','true') {
                                foreach ($enabled in 'false','true') {
                                    $output = & ghdl -r --std=08 "--workdir=$work" tb_v161_interrupt `
                                        "-gCpu_Mode=$cpu" "-gMode_Value=$mode" "-gIBR_Value=$ibr" "-gInitial_IM=$im" `
                                        "-gNMI_Test=$nmi" "-gTable_Case=$table" "-gBoundary=$boundary" `
                                        "-gWith_Wait=$wait" "-gEnabled=$enabled" `
                                        "-gSyscall_Test=$($Syscall.IsPresent.ToString().ToLowerInvariant())" --assert-level=error 2>&1
                                    $exitCode = $LASTEXITCODE
                                    $marker = if ($Syscall) { 'PASS: V16.1 SYSCALL' } else { 'PASS: V16.1 IBR interrupt' }
                                    $ok = $exitCode -eq 0 -and ($output -match $marker)
                                    $records.WriteLine((@{
                                        cpu_mode = $cpu; mode24 = $mode; ibr = $ibr; initial_im = $im
                                        syscall = $Syscall.IsPresent
                                        nmi = ($nmi -eq 'true'); table_case = $table
                                        boundary = ($boundary -eq 'true'); wait_enabled = ($wait -eq 'true')
                                        iff_enabled = ($enabled -eq 'true'); passed = [bool]$ok
                                        exit_code = $exitCode; output = @($output | ForEach-Object { "$_" })
                                    } | ConvertTo-Json -Depth 4 -Compress))
                                    if (-not $ok) {
                                        $output | Write-Output
                                        throw "Failed mode=$mode cpu=$cpu IBR=$ibr IM=$im NMI=$nmi table=$table boundary=$boundary wait=$wait IFF=$enabled"
                                    }
                                    $passed++
                                }
                            }
                        }
                    }
                }
            }
        }
        Write-Output "PASS through mode=$mode cpu=$cpu : $passed scenarios (Syscall=$Syscall)"
      }
    }
} finally {
    $records.Dispose()
    $hashes = @{}
    foreach ($file in @('t80_pack.vhd','t80_mcode.vhd','t80_alu.vhd','t80_reg.vhd','t80.vhd',
                        'test\tb_v161_interrupt.vhd','test\run_v161_interrupt.ps1')) {
        $hashes["fpga\G80A\$file"] = (Get-FileHash -Algorithm SHA256 $file).Hash
    }
    @{
        started_utc = $started; completed_utc = [DateTime]::UtcNow.ToString('o')
        expected_cases = $expectedCases; passed = $passed; complete = ($passed -eq $expectedCases)
        syscall = $Syscall.IsPresent
        engine = (& ghdl --version | Select-Object -First 1); source_sha256 = $hashes
        results_sha256 = (Get-FileHash -Algorithm SHA256 (Join-Path $data 'results.jsonl')).Hash
    } | ConvertTo-Json -Depth 4 | Set-Content -Encoding utf8 (Join-Path $data 'summary.json')
    Pop-Location
    $library = Join-Path $work 'work-obj08.cf'
    if (Test-Path $library) { Remove-Item -LiteralPath $library }
    Remove-Item -LiteralPath $work
}

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$work = Join-Path ([IO.Path]::GetTempPath()) ('v161-im0-' + [guid]::NewGuid())
$data = Join-Path $root 'verification_data\v161_im0'
New-Item -ItemType Directory -Path $work | Out-Null
New-Item -ItemType Directory -Force -Path $data | Out-Null
$passed = 0
$started = [DateTime]::UtcNow.ToString('o')
$records = [IO.StreamWriter]::new((Join-Path $data 'results.jsonl'), $false)
Push-Location (Join-Path $PSScriptRoot '..')
try {
    & ghdl -a --std=08 "--workdir=$work" t80_pack.vhd t80_mcode.vhd `
        t80_alu.vhd t80_reg.vhd t80.vhd test\tb_v161_im0.vhd
    if ($LASTEXITCODE -ne 0) { throw 'GHDL analysis failed.' }
    foreach ($entry in 0..8) {
        foreach ($im in 0..2) {
            foreach ($mirror in 0..4) {
                foreach ($enabled in 'false','true') {
                    $output = & ghdl -r --std=08 "--workdir=$work" tb_v161_im0 `
                        "-gEntry_Path=$entry" "-gInitial_IM=$im" "-gMirror=$mirror" `
                        "-gEnabled=$enabled" --assert-level=error 2>&1
                    $exitCode = $LASTEXITCODE
                    $ok = $exitCode -eq 0 -and ($output -match 'PASS: V16.1')
                    $records.WriteLine((@{
                        entry_path = $entry; initial_im = $im; mirror = $mirror
                        iff_enabled = ($enabled -eq 'true'); passed = [bool]$ok
                        output = @($output | ForEach-Object { "$_" })
                    } | ConvertTo-Json -Depth 4 -Compress))
                    if (-not $ok) { $output | Write-Output; throw "Failed entry=$entry IM=$im mirror=$mirror IFF=$enabled" }
                    $passed++
                }
            }
        }
    }
    Write-Output "PASS: $passed V16.1 IM0 cases"
} finally {
    $records.Dispose()
    $hashes = @{}
    foreach ($file in @('t80_pack.vhd','t80_mcode.vhd','t80_alu.vhd','t80_reg.vhd','t80.vhd',
                        'test\tb_v161_im0.vhd','test\run_v161_im0.ps1')) {
        $hashes["fpga\G80A\$file"] = (Get-FileHash -Algorithm SHA256 $file).Hash
    }
    @{
        started_utc = $started; completed_utc = [DateTime]::UtcNow.ToString('o')
        expected_cases = 270; passed = $passed; complete = ($passed -eq 270)
        engine = (& ghdl --version | Select-Object -First 1); source_sha256 = $hashes
    } | ConvertTo-Json -Depth 4 | Set-Content -Encoding utf8 (Join-Path $data 'summary.json')
    Pop-Location
    $library = Join-Path $work 'work-obj08.cf'
    if (Test-Path $library) { Remove-Item -LiteralPath $library }
    Remove-Item -LiteralPath $work
}

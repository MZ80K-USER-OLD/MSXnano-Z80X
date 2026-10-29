$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$iverilog = Get-Command iverilog -ErrorAction SilentlyContinue
if ($iverilog) {
    $compiler = $iverilog.Source
} else {
    $compiler = Join-Path $env:LOCALAPPDATA 'iverilog\bin\iverilog.exe'
}
if (-not (Test-Path $compiler)) {
    throw 'Icarus Verilog is required.'
}
$vvp = Join-Path (Split-Path $compiler) 'vvp.exe'
$temp = Join-Path ([IO.Path]::GetTempPath()) ('cpu-request-' + [guid]::NewGuid())
New-Item -ItemType Directory -Path $temp | Out-Null
try {
    $top = Get-Content -Raw (Join-Path $root 'fpga\top.v')
    $start = $top.IndexOf('localparam [1:0] WS_IDLE')
    $end = $top.IndexOf('// memory_bus blocks', $start)
    if ($start -lt 0 -or $end -le $start) {
        throw 'Cannot locate the top.v request/WAIT block.'
    }
    # Compile the actual top.v block, not a manually maintained copy.
    $header = @'
module cpu_request_frontend (
    input clk_54m, bus_reset_n, update_addr, clk_falling_3m6_54,
    input [7:0] mmu_physical_bank,
    input [23:0] extended_addr,
    input extended_mreq_n, bus_rd_n, bus_wr_n, bus_rfsh_n,
    input cpu_sdram_done,
    output request, writing,
    output [23:0] address
);
localparam [7:0] CPU_SDRAM_BANK_MAX = 8'h1b;
localparam [23:0] CPU_SDRAM_BASE = 24'h640000;
reg update_addr_prev, update_addr_prev2;
'@
    $block = $top.Substring($start, $end - $start)
    $block = $block.Replace('wire cpu_sdram_done;', '')
    $footer = @'
assign request = cpu_sdram_req;
assign writing = cpu_sdram_write;
assign address = cpu_sdram_addr;
endmodule
'@
    $source = Join-Path $temp 'frontend.v'
    Set-Content -Encoding ascii -Path $source -Value ($header + "`n" + $block + "`n" + $footer)
    $image = Join-Path $temp 'timing.vvp'
    & $compiler -g2012 -s tb_cpu_sdram_request_timing -o $image $source `
        (Join-Path $root 'fpga\src\memory.v') `
        (Join-Path $PSScriptRoot 'tb_cpu_sdram_request_timing.sv')
    if ($LASTEXITCODE -ne 0) { throw 'Timing test compilation failed.' }
    & $vvp $image
    if ($LASTEXITCODE -ne 0) { throw 'Request timing regression failed.' }
} finally {
    foreach ($name in @('frontend.v', 'timing.vvp')) {
        $file = Join-Path $temp $name
        if (Test-Path $file) { Remove-Item -LiteralPath $file }
    }
    Remove-Item -LiteralPath $temp
}

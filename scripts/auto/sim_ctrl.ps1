# sim_ctrl.ps1 — tb_ctrl on the Vivado 2020.1 simulator (this machine has no Icarus).
# Run from anywhere; the script locates the project root.
$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$sim  = Join-Path $root "build\sim"
New-Item -ItemType Directory -Force -Path $sim | Out-Null
$log  = Join-Path $sim "ctrl_xsim.log"
if (Test-Path $log) { Remove-Item $log }

if ($env:NETSEC_VIVADO) {
    $vivBin = Split-Path -Parent $env:NETSEC_VIVADO
} elseif ($env:XILINX_VIVADO) {
    $vivBin = Join-Path $env:XILINX_VIVADO "bin"
} else {
    $vivBin = ""
}
$xvlog = if ($vivBin) { Join-Path $vivBin "xvlog.bat" } else { "xvlog.bat" }
$xelab = if ($vivBin) { Join-Path $vivBin "xelab.bat" } else { "xelab.bat" }
$xsim  = if ($vivBin) { Join-Path $vivBin "xsim.bat" } else { "xsim.bat" }
$src = @(
    "rtl\ctrl\netsec_regs_k7.sv",
    "rtl\ctrl\uart_axil_bridge.sv",
    "rtl\ctrl\stat_bank.sv",
    "rtl\ctrl\phy_mgmt.sv",
    "rtl\core\mdio_master.sv",
    "rtl\crypto\aes_sbox_pkg.sv",
    "rtl\crypto\aes128_core.sv",
    "rtl\core\checksum_rfc1071.sv",
    "rtl\crypto\modexp_demo.sv",
    "tb\tb_ctrl.sv"
) | ForEach-Object { Join-Path $root $_ }

Push-Location $sim
try {
    & $xvlog -sv --nolog @src 2>&1 | Tee-Object -FilePath $log
    if ($LASTEXITCODE -ne 0) { throw "xvlog failed ($LASTEXITCODE)" }
    & $xelab tb_ctrl -s tb_ctrl --nolog --timescale 1ns/1ps 2>&1 | Tee-Object -FilePath $log -Append
    if ($LASTEXITCODE -ne 0) { throw "xelab failed ($LASTEXITCODE)" }
    & $xsim tb_ctrl -R --nolog --onerror quit 2>&1 | Tee-Object -FilePath $log -Append
    if ($LASTEXITCODE -ne 0) { throw "xsim failed ($LASTEXITCODE)" }
} finally {
    Pop-Location
}

$pass = @(Select-String -Path $log -Pattern "^PASS:").Count
$fail = @(Select-String -Path $log -Pattern "^FAIL:").Count
Write-Host "SIM pass=$pass fail=$fail"
if ($fail -ne 0 -or $pass -lt 32) { throw "tb_ctrl did not meet PASS>=32 and FAIL=0 (see $log)" }
Write-Host "SIM OK"

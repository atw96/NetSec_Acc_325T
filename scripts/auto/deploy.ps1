# deploy.ps1 — helpers for the MK7325FB deployment.
# Dot-source from the project root:
#   . .\scripts\auto\deploy.ps1
#   Invoke-Viv b1_create scripts\create_project.tcl
#   Save-Out g1

$script:NetsecRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
if ($env:NETSEC_VIVADO) {
    $script:VivadoBat = $env:NETSEC_VIVADO
} elseif ($env:XILINX_VIVADO) {
    $script:VivadoBat = Join-Path $env:XILINX_VIVADO "bin\vivado.bat"
} else {
    $script:VivadoBat = "vivado.bat"
}

function Invoke-Viv {
    param(
        [Parameter(Mandatory = $true)][string]$Step,
        [Parameter(Mandatory = $true)][string]$Tcl
    )
    $logDir = Join-Path $script:NetsecRoot "build\logs"
    New-Item -ItemType Directory -Force -Path $logDir | Out-Null
    $log = Join-Path $logDir "$Step.log"
    if (-not (Test-Path $script:VivadoBat)) { throw "Vivado not found: $script:VivadoBat" }
    $tclPath = $Tcl
    if (-not [System.IO.Path]::IsPathRooted($tclPath)) {
        $tclPath = Join-Path $script:NetsecRoot $Tcl
    }
    Write-Host "VIVADO $Step -> $log"
    Push-Location $script:NetsecRoot
    try {
        & $script:VivadoBat -mode batch -nojournal -log $log -source $tclPath
        $code = $LASTEXITCODE
    } finally {
        Pop-Location
    }
    if ($code -ne 0) { throw "Vivado step $Step exited $code (see $log)" }
    $errs = Select-String -Path $log -Pattern "^ERROR:" | Select-Object -First 20
    if ($errs) {
        $errs | ForEach-Object { Write-Host $_.Line }
        throw "Vivado step $Step logged ERROR (see $log)"
    }
    return $log
}

function Save-Out {
    param([Parameter(Mandatory = $true)][string]$Tag)
    $root = $script:NetsecRoot
    $dst = Join-Path $root "build\out_$Tag"
    New-Item -ItemType Directory -Force -Path $dst | Out-Null
    foreach ($sub in @("out", "reports")) {
        $src = Join-Path $root "build\$sub"
        if (Test-Path $src) {
            Copy-Item -Force -Recurse (Join-Path $src "*") $dst
        }
    }
    Write-Host "Saved build\out and build\reports to build\out_$Tag"
    return $dst
}

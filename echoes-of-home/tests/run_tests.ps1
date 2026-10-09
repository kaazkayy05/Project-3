param([Parameter(Mandatory=$true)][string]$Godot)
$project = Split-Path $PSScriptRoot -Parent
function Invoke-GodotCheck([string[]]$EngineArgs) {
    $result = & $Godot @EngineArgs 2>&1
    $code = $LASTEXITCODE
    $result | ForEach-Object { Write-Host $_ }
    if ($code -ne 0 -or ($result -match 'SCRIPT ERROR:|^ERROR:|FAIL:')) {
        throw "Godot check failed: $EngineArgs"
    }
}
Invoke-GodotCheck @('--headless', '--path', $project, '--editor', '--import', '--quit')
Invoke-GodotCheck @('--headless', '--path', $project, '--script', 'res://tests/test_environment.gd')
Invoke-GodotCheck @('--headless', '--path', $project, '--script', 'res://tests/test_house.gd')
Invoke-GodotCheck @('--headless', '--path', $project, 'res://systems/acoustic_pulse/node.tscn', '--quit-after', '5')
Write-Host 'All checks completed successfully.'

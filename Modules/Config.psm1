# SystemGuardian/Core/Config.psm1
# Shared configuration loading used across every analysis module.
# Import-AppConfig is extracted from Run.ps1's Load-Configuration.
# Get-ConfigValue is new: it replaces the repetitive
# "if ($config.X.Y) { $config.X.Y } else { $default }" blocks that were
# duplicated (with different keys) inside every module's own config
# function, so every configurable threshold still comes from
# config.json with an explicit, visible default if a key is missing.
# Version: 1.0.0

<#
.SYNOPSIS
    Loads and parses config.json, returning $null on any failure.
.DESCRIPTION
    Behavior matches Run.ps1's original Load-Configuration exactly:
    missing file or parse error both produce a warning and a $null
    return, leaving it up to the caller to fall back to defaults.
.PARAMETER ConfigPath
    Full path to config.json.
#>
function Import-AppConfig {
    param([string]$ConfigPath)

    if (-not (Test-Path $ConfigPath)) {
        Write-Warning "Config file not found at $ConfigPath. Using defaults."
        return $null
    }
    try {
        $config = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json
        return $config
    }
    catch {
        Write-Warning "Failed to load config: $($_.Exception.Message). Using defaults."
        return $null
    }
}

<#
.SYNOPSIS
    Safely reads a (possibly nested) value out of a parsed config
    object, falling back to a default if the config, or any segment
    along the path, is missing or null.
.PARAMETER Config
    The parsed config object (from Import-AppConfig), or $null.
.PARAMETER Path
    Dot-separated property path, e.g. "StorageAnalysis.StorageHeavyFileMB".
.PARAMETER Default
    Value returned if Config is $null or the path doesn't resolve.
.EXAMPLE
    Get-ConfigValue -Config $config -Path "StorageAnalysis.StorageHeavyFileMB" -Default 500
#>
function Get-ConfigValue {
    param(
        $Config,
        [string]$Path,
        $Default
    )
    if ($null -eq $Config) { return $Default }

    $current = $Config
    foreach ($segment in ($Path -split '\.')) {
        if ($null -eq $current) { return $Default }
        $current = $current.$segment
    }

    if ($null -eq $current) { return $Default }
    return $current
}

Export-ModuleMember -Function Import-AppConfig, Get-ConfigValue

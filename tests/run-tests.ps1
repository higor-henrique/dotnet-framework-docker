#
# Copyright (c) .NET Foundation and contributors. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.
#

[cmdletbinding()]
param(
    [string]$Version,
    [string]$Architecture,
    [string]$OS,
    [string]$Registry,
    [string]$RepoPrefix,
    [switch]$PullImages,
    [string]$ImageInfoPath,
    [ValidateSet('runtime', 'sdk', 'aspnet', 'wcf', 'pre-build')]
    [string[]]$TestCategories = @("runtime", "sdk", "aspnet", "wcf")
)

function Log {
    param ([string] $Message)

    Write-Output $Message
}

function Exec {
    param ([string] $Cmd)

    Log "Executing: '$Cmd'"
    Invoke-Expression $Cmd
    if ($LASTEXITCODE -ne 0) {
        throw "Failed: '$Cmd'"
    }
}

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Install the .NET Core SDK
$DotnetInstallDir = "$PSScriptRoot/../.dotnet"

if (!(Test-Path "$DotnetInstallDir")) {
    mkdir "$DotnetInstallDir" | Out-Null
}

$IsRunningOnUnix = $PSVersionTable.contains("Platform") -and $PSVersionTable.Platform -eq "Unix"
if ($IsRunningOnUnix) {
    $DotnetInstallScript = "dotnet-install.sh"
}
else {
    $DotnetInstallScript = "dotnet-install.ps1"
}

$activeOS = docker version -f "{{ .Server.Os }}"

if (!(Test-Path $DotnetInstallScript)) {
    $DOTNET_INSTALL_SCRIPT_URL = "https://dot.net/v1/$DotnetInstallScript"
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12;
    Invoke-WebRequest $DOTNET_INSTALL_SCRIPT_URL -OutFile $DotnetInstallDir/$DotnetInstallScript
}

if ($IsRunningOnUnix) {
    & chmod +x $DotnetInstallDir/$DotnetInstallScript
    & $DotnetInstallDir/$DotnetInstallScript --channel "3.1" --version "latest" --install-dir $DotnetInstallDir
}
else {
    & $DotnetInstallDir/$DotnetInstallScript -Channel "3.1" -Version "latest" -InstallDir $DotnetInstallDir
}

if ($LASTEXITCODE -ne 0) { throw "Failed to install the .NET Core SDK" }

# Run Tests
$env:IMAGE_OS = $OS
$env:IMAGE_VERSION = $Version
$env:REGISTRY = $Registry
$env:REPO_PREFIX = $RepoPrefix
$env:IMAGE_INFO_PATH = $ImageInfoPath
$env:SOURCE_REPO_ROOT = (Get-Item "$PSScriptRoot").Parent.FullName

if ($PullImages) {
    $env:PULL_IMAGES = 1
}
else {
    $env:PULL_IMAGES = $null
}

$testFilter = ""
if ($TestCategories) {
    # Construct an expression that filters the test to each of the
    # selected TestCategories (using an OR operator between each category).
    # See https://docs.microsoft.com/en-us/dotnet/core/testing/selective-unit-tests
    $TestCategories | foreach {
        # Skip pre-build tests on Windows because of missing pre-reqs (https://github.com/dotnet/dotnet-docker/issues/2261)
        if ($_ -eq "pre-build" -and $activeOS -eq "windows") {
            Write-Warning "Skipping pre-build tests for Windows containers"
        } else {
            if ($testFilter) {
                $testFilter += "|"
            }

            $testFilter += "Category=$_"
        }
    }

    if (-not $testFilter) {
        exit;
    }

    $testFilter = "--filter `"$testFilter`""
}

Exec "$DotnetInstallDir/dotnet test $testFilter -c Release --logger:trx $PSScriptRoot/Microsoft.DotNet.Framework.Docker.Tests/Microsoft.DotNet.Framework.Docker.Tests.csproj"

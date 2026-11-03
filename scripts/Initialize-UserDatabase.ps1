#Requires -Version 5.1
#Requires -PSEdition Desktop

param(
    [ValidateSet('Sql', 'EntityFramework', 'EntityFrameworkStoredProcedures', 'All')]
    [string]$Implementation,
    [ValidateSet('Debug', 'Release')]
    [string]$Configuration = 'Debug',
    [string]$ConfigPath = (Join-Path $PSScriptRoot '..\HelloWorldWpf48\App.config')
)

$ErrorActionPreference = 'Stop'
[xml]$config = Get-Content -LiteralPath $ConfigPath -Raw
$connection = $config.configuration.connectionStrings.add |
    Where-Object { $_.name -eq 'UserDatabase' }
if (-not $connection -or [string]::IsNullOrWhiteSpace($connection.connectionString)) {
    throw 'The configuration must contain a nonempty UserDatabase connection string.'
}

$choices = @('Sql', 'EntityFramework', 'EntityFrameworkStoredProcedures')
if (-not $Implementation) {
    $setting = $config.configuration.appSettings.add |
        Where-Object { $_.key -eq 'UserServiceImplementation' }
    $Implementation = if ([string]::IsNullOrWhiteSpace($setting.value)) { 'Sql' } else { $setting.value.Trim() }
    if ($Implementation -notin $choices) {
        throw 'Unknown UserServiceImplementation in configuration. Use Sql, EntityFramework or EntityFrameworkStoredProcedures.'
    }
}

$build = Join-Path $PSScriptRoot "..\UserDatabaseService\bin\$Configuration"
foreach ($file in 'EntityFramework.dll', 'EntityFramework.SqlServer.dll', 'UserDatabaseService.dll') {
    $path = Join-Path $build $file
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Build the solution in $Configuration before running database setup; missing $file."
    }
}
foreach ($file in 'EntityFramework.dll', 'EntityFramework.SqlServer.dll', 'UserDatabaseService.dll') {
    Add-Type -Path (Join-Path $build $file)
}

$selected = if ($Implementation -eq 'All') { $choices } else { @($Implementation) }
foreach ($mode in $selected) {
    Write-Host "Preparing user database using $mode..."
    try {
        $service = [UserDatabaseService.UserServiceFactory]::Create($mode, $connection.connectionString)
        $null = $service.CreateOrUpdateDatabaseAsync(
            [Threading.CancellationToken]::None).GetAwaiter().GetResult()
    }
    catch {
        $cause = $_.Exception.GetBaseException()
        $detail = if ($cause -is [System.Data.SqlClient.SqlException]) { " (SQL error $($cause.Number))" } else { '' }
        throw "Database setup failed for $mode$detail. Check the configured connection, SQL Server access, setup permissions and schema compatibility."
    }
    Write-Host "Database setup completed using $mode."
}

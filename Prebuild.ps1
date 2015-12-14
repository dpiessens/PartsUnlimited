# bootstrap DNVM into this session.
&{$Branch='dev';iex ((new-object net.webclient).DownloadString('https://raw.githubusercontent.com/aspnet/Home/dev/dnvminstall.ps1'))}

# load up the global.json so we can find the DNX version
$globalJson = Get-Content -Path $PSScriptRoot\global.json -Raw -ErrorAction Ignore | ConvertFrom-Json -ErrorAction Ignore

if($globalJson)
{
    $dnxVersion = $globalJson.sdk.version
}

if([string]::IsNullOrEmpty($dnxVersion))
{
    Write-Warning "Unable to locate global.json to determine using 'latest'"
    $dnxVersion = "latest"
}

# install DNX
# only installs the default (x86, clr) runtime of the framework.
# If you need additional architectures or runtimes you should add additional calls
# ex: & $env:USERPROFILE\.dnx\bin\dnvm install $dnxVersion -r coreclr
Write-Host "Bootstrapping DNX version: $dnxVersion"
& $env:USERPROFILE\.dnx\bin\dnvm install $dnxVersion -p

# Add custom max depth function here
function Get-MyChildItem
{
  param
  (
    [Parameter(Mandatory = $true)]
    $Path,
    
    $Filter = '*',
    
    [System.Int32]
    $MaxDepth = 3,
    
    [System.Int32]
    $Depth = 0
  )
  
  $Depth++

  Get-ChildItem -Path $Path -Filter $Filter -File 
  
  if ($Depth -le $MaxDepth)
  {
    Get-ChildItem -Path $Path -Directory |
      ForEach-Object { Get-MyChildItem -Path $_.FullName -Filter $Filter -Depth $Depth -MaxDepth $MaxDepth}
  }
  
}

 # run DNU restore on all project.json files in the src folder including 2>1 to redirect stderr to stdout for badly behaved tools
Set-Location $PSScriptRoot
Get-MyChildItem -Path @('src', 'test') -Filter project.json -MaxDepth 2 | ForEach-Object { & dnu restore $_.FullName 2>1 }

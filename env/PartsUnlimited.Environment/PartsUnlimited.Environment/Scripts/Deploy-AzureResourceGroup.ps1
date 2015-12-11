#Requires -Version 3.0

Param(
  [string] [Parameter(Mandatory=$true)] $ResourceGroupLocation,
  [string] $ResourceGroupName = 'PartsUnlimited',
  [switch] $UploadArtifacts,
  [string] $StorageAccountName, 
  [string] $StorageContainerName = $ResourceGroupName.ToLowerInvariant() + '-stageartifacts',
  [string] $TemplateFile = '..\Templates\DemoEnvironmentSetup.json',
  [string] $TemplateParametersFile = '..\Templates\DemoEnvironmentSetup.param.json',
  [string] $ArtifactStagingDirectory = '..\bin\Debug\Artifacts',
  [string] $AzCopyPath = '..\Tools\AzCopy.exe'
)

# Ensure AzCopy.exe is available
. $PSScriptRoot\Install-AzCopy.ps1

Import-Module Azure
#Login-AzureRmAccount

try {
  [Microsoft.Azure.Common.Authentication.AzureSession]::ClientFactory.AddUserAgent("VSAzureTools-$UI$($host.name)".replace(" ","_"), "2.7")
} catch { }

$OptionalParameters = New-Object -TypeName Hashtable
$TemplateFile = [System.IO.Path]::Combine($PSScriptRoot, $TemplateFile)
$TemplateParametersFile = [System.IO.Path]::Combine($PSScriptRoot, $TemplateParametersFile)

Function Get-TemplateParameters {
	Param(
	  [string] [Parameter(Mandatory=$true)] $TemplateParametersFile
	)

	$JsonContent = Get-Content $TemplateParametersFile -Raw | ConvertFrom-Json
	$JsonParameters = $JsonContent | Get-Member -Type NoteProperty | Where-Object {$_.Name -eq "parameters"}

	if ($JsonParameters -eq $null)
	{
		$JsonParameters = $JsonContent
	}
	else
	{
		$JsonParameters = $JsonContent.parameters
	}

	return $JsonParameters
}

if ($UploadArtifacts)
{
	# Convert relative paths to absolute paths if needed
	$AzCopyPath = [System.IO.Path]::Combine($PSScriptRoot, $AzCopyPath)
	$ArtifactStagingDirectory = [System.IO.Path]::Combine($PSScriptRoot, $ArtifactStagingDirectory)

	Set-Variable ArtifactsLocationName '_artifactsLocation' -Option ReadOnly
	Set-Variable ArtifactsLocationSasTokenName '_artifactsLocationSasToken' -Option ReadOnly

	$OptionalParameters.Add($ArtifactsLocationName, $null)
	$OptionalParameters.Add($ArtifactsLocationSasTokenName, $null)

	# Parse the parameter file and update the values of artifacts location and artifacts location SAS token if they are present
	$JsonContent = Get-Content $TemplateParametersFile -Raw | ConvertFrom-Json
	$JsonParameters = $JsonContent | Get-Member -Type NoteProperty | Where-Object {$_.Name -eq "parameters"}

	if ($JsonParameters -eq $null)
	{
		$JsonParameters = $JsonContent
	}
	else
	{
		$JsonParameters = $JsonContent.parameters
	}

	$JsonParameters | Get-Member -Type NoteProperty | ForEach-Object {
		$ParameterValue = $JsonParameters | Select-Object -ExpandProperty $_.Name

		if ($_.Name -eq $ArtifactsLocationName -or $_.Name -eq $ArtifactsLocationSasTokenName)
		{
			$OptionalParameters[$_.Name] = $ParameterValue.value
		}
	}

   
	
	$StorageAccount = Get-AzureRmStorageAccount -Name $StorageAccountName -ResourceGroupName $ResourceGroupName
	$StorageAccountKey = (Get-AzureRmStorageAccountKey -Name $StorageAccountName -ResourceGroupName $ResourceGroupName).Key1
	$StorageAccountContext = $StorageAccount.Context

	# Generate the value for artifacts location if it is not provided in the parameter file
	$ArtifactsLocation = $OptionalParameters[$ArtifactsLocationName]
	if ($ArtifactsLocation -eq $null)
	{
		$ArtifactsLocation = $StorageAccountContext.BlobEndPoint + $StorageContainerName
		Write-Verbose -Verbose "Artifacts Location: $ArtifactsLocation"
		$OptionalParameters[$ArtifactsLocationName] = $ArtifactsLocation
	}

	# Use AzCopy to copy files from the local storage drop path to the storage account container
	& "$AzCopyPath" /Source:""$ArtifactStagingDirectory"" /Dest:$ArtifactsLocation /DestKey:$StorageAccountKey /S /Y /Z:""$env:LocalAppData\Microsoft\Azure\AzCopy\$ResourceGroupName""

	# Generate the value for artifacts location SAS token if it is not provided in the parameter file
	$ArtifactsLocationSasToken = $OptionalParameters[$ArtifactsLocationSasTokenName]
	if ($ArtifactsLocationSasToken -eq $null)
	{
	   # Create a SAS token for the storage container - this gives temporary read-only access to the container (defaults to 1 hour).
	   $ArtifactsLocationSasToken = New-AzureStorageContainerSASToken -Container $StorageContainerName -Context $StorageAccountContext -Permission r
	   $ArtifactsLocationSasToken = ConvertTo-SecureString $ArtifactsLocationSasToken -AsPlainText -Force
	   $OptionalParameters[$ArtifactsLocationSasTokenName] = $ArtifactsLocationSasToken
	   Write-Host "Artifacts SAS Location: $ArtifactsLocationSasToken"
	}
}

# Create or update the resource group using the specified template file and template parameters file
Write-Host "Deployment: $ResourceGroupName, Location: $ResourceGroupLocation, Template: $TemplateFile Parameters: $TemplateParametersFile"
New-AzureRmResourceGroupDeployment -Name $ResourceGroupName `
								   -ResourceGroupName $ResourceGroupName `
								   -Mode Incremental `
								   -TemplateFile $TemplateFile `
								   -TemplateParameterFile $TemplateParametersFile `
								   @OptionalParameters `
								   -Force -Verbose


# Parse the parameter file and update the values, if they are present
$CdnStorageAccountName = $null
$CdnStorageContainerName = $null
$CdnStorageAccountNameForDev = $null
$CdnStorageContainerNameForDev = $null
$CdnStorageAccountNameForStaging = $null
$CdnStorageContainerNameForStaging = $null
$WebsiteName = $null

$JsonParameters = Get-TemplateParameters $TemplateParametersFile

$JsonParameters | Get-Member -Type NoteProperty | ForEach-Object {
	$ParameterValue = $JsonParameters | Select-Object -ExpandProperty $_.Name

	switch ($_.Name)
	{
		"CdnStorageAccountName"             { $CdnStorageAccountName = $ParameterValue.value }
		"CdnStorageContainerName"           { $CdnStorageContainerName = $ParameterValue.value }
		"CdnStorageAccountNameForDev"       { $CdnStorageAccountNameForDev = $ParameterValue.value }
		"CdnStorageContainerNameForDev"     { $CdnStorageContainerNameForDev = $ParameterValue.value }
		"CdnStorageAccountNameForStaging"   { $CdnStorageAccountNameForStaging = $ParameterValue.value }
		"CdnStorageContainerNameForStaging" { $CdnStorageContainerNameForStaging = $ParameterValue.value }
		"WebsiteName"                       { $WebsiteName = $ParameterValue.value}
	}
} 

$WebsiteLocation = (Get-AzureRmWebApp -ResourceGroupName $ResourceGroupName -Name $WebsiteName).Location

#Create Storage container needed for website.
#This will not be needed when Azure Resource Management templates support the creation of storage accounts.

$StorageModule = [System.IO.Path]::Combine($PSScriptRoot, ".\New-CdnStorageContainer.psm1")
Import-Module $StorageModule -Force
$CdnAppSettingName = "CDN:Images"

Function Set-WebAppSetting([string]$SlotName, [string]$SettingName, [string]$SettingValue) {
	$webApp = Get-AzureRMWebAppSlot -ResourceGroupName $ResourceGroupName -Name $WebsiteName -Slot $SlotName
	$appSettingList = $webApp.SiteConfig.AppSettings

	$AppSettings = @{}
	ForEach ($kvp in $appSettingList) {
		$AppSettings[$kvp.Name] = $kvp.Value
	}

	$AppSettings[$SettingName] = $SettingValue
	
	Set-AzureRMWebAppSlot -ResourceGroupName $myResourceGroup -Name $WebsiteName -AppSettings $hash -Slot $SlotName
}


if ($CdnStorageAccountName) {
	
	$cdnUrl = New-CdnStorageContainer -StorageAccountName $CdnStorageAccountName -ContainerName $CdnStorageContainerName -Location $WebsiteLocation -ResourceGroupName $ResourceGroupName
	Set-WebAppSetting -SlotName 'production' -SettingName $CdnAppSettingName -SettingValue $cdnUrl
}

if ($CdnStorageAccountNameForDev) {

	$cdnUrlForDev = New-CdnStorageContainer -StorageAccountName $CdnStorageAccountNameForDev -ContainerName $CdnStorageContainerNameForDev -Location $WebsiteLocation -ResourceGroupName $ResourceGroupName
	Set-WebAppSetting -SlotName 'Dev' -SettingName $CdnAppSettingName -SettingValue $cdnUrlForDev
}

if ($CdnStorageAccountNameForStaging) {

	$cdnUrlForStaging = New-CdnStorageContainer -StorageAccountName $CdnStorageAccountNameForStaging -ContainerName $CdnStorageContainerNameForStaging -Location $WebsiteLocation -ResourceGroupName $ResourceGroupName
	Set-WebAppSetting -SlotName 'Staging' -SettingName $CdnAppSettingName -SettingValue $cdnUrlForStaging
}

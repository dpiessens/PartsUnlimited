#
# New_CdnStorageContainer.psm1
#
Function New-CdnStorageContainer{

Param(
  [Parameter(Mandatory=$true)][string] $StorageAccountName,
  [string] $ContainerName = 'cdn',
  [Parameter(Mandatory=$true)][string] $Location,
  [Parameter(Mandatory=$true)][string] $ResourceGroupName
)

	#Create storage account if needed
	if (!(Test-AzureName -Storage $StorageAccountName)) {
		Write-Verbose "Creating new storage account with name $StorageAccountName"
		$storageAccount = New-AzureRmStorageAccount -StorageAccountName $StorageAccountName -Location $Location -ResourceGroupName $ResourceGroupName -Verbose
		if ($storageAccount)
		{
			Write-Verbose "Created $StorageAccountName storage account in $Location location"
		}
		else
		{
			throw "Failed to create a Microsoft Azure storage account."
		}
	}

	$context = (Get-AzureRmStorageAccount -StorageAccountName $StorageAccountName -ResourceGroupName $ResourceGroupName).Context
	
	#Check to see if container exists.
	if (!(Get-AzureStorageContainer -Context $context | Where-Object {$_.Name -eq $ContainerName})) {
		Write-Verbose "Creating a new storage container named '$ContainerName'"
		$storageContainer = New-AzureStorageContainer -Name $ContainerName -Context $context
		Write-Verbose "Created a new storage container named '$ContainerName' already exists in the account '$StorageAccountName'"
	} else {
		Write-Verbose "A storage container named '$ContainerName' already exists in the account '$StorageAccountName'"
	}

	#Set container to all for Blob Read.  This is needed to execute the scripts
	if ((Get-AzureStorageContainerAcl -Container $ContainerName -Context $context).PublicAccess -eq 'Off') {
		Write-Verbose "Setting Permissions for $ContainerName to 'Blob'"
		Set-AzureStorageContainerAcl -Context $context -Name $ContainerName -Permission Blob
	}

	#Return the url for the cdn storage endpoint
	$url = [string]::Concat($context.BlobEndPoint, $ContainerName)
	Write-Verbose "Blob endpoint for $ContainerName is $url"

	return $url
}

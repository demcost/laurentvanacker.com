﻿Clear-Host
Get-Variable -Scope Script | Remove-Variable -Scope Script -Force -ErrorAction Ignore

#region function definitions 
#Based from https://adamtheautomator.com/powershell-random-password/
function New-RandomPassword
{
    [CmdletBinding(PositionalBinding=$false)]
    param
    (
        [int] $minLength = 12, ## characters
        [int] $maxLength = 15, ## characters
        [int] $nonAlphaChars = 3,
        [switch] $AsSecureString,
        [switch] $ClipBoard
    )

    Add-Type -AssemblyName 'System.Web'
    $length = Get-Random -Minimum $minLength -Maximum $maxLength
    $RandomPassword = [System.Web.Security.Membership]::GeneratePassword($length, $nonAlphaChars)
    Write-Host "The password is : $RandomPassword"
    if ($ClipBoard)
    {
        Write-Verbose "The password has beeen copied into the clipboard ..."
        $RandomPassword | Set-Clipboard
    }
    if ($AsSecureString)
    {
        ConvertTo-SecureString -String $RandomPassword -AsPlainText -Force
    }
    else
    {
        $RandomPassword
    }
}
#endregion

$CurrentScript = $MyInvocation.MyCommand.Path
#Getting the current directory (where this script file resides)
$CurrentDir = Split-Path -Path $CurrentScript -Parent

#region Defining variables 
$RDPPort                        = 3389
$JitPolicyTimeInHours           = 3
$JitPolicyName                  = "Default"
$Location                       = "ukwest"
#To list all Azure locations : (Get-AzLocation).Location | Sort-Object
#$Location                       = "uksouth"
$ResourceGroupName              = "AutomatedLab-rg-$Location"
$VirtualNetworkName             = "AutomatedLab-vnet-$Location"
$VirtualNetworkAddressSpace     = "10.10.0.0/16" # Format 10.10.0.0/16
$SubnetIPRange                  = "10.10.1.0/24" # Format 10.10.1.0/24
$SubnetName                     = "AutomatedLab-Subnet"
$NICNetworkSecurityGroupName    = "AutomatedLab-nic-nsg-$Location"
$subnetNetworkSecurityGroupName = "AutomatedLab-vnet-Subnet-nsg-$Location"
$StorageAccountName             = "automatedlabsa$($Location)" # Name must be unique. Name availability can be check using PowerShell command Get-AzStorageAccountNameAvailability -Name $StorageAccountName 
$StorageAccountSkuName          = "Standard_LRS"
$SubscriptionName               = "Microsoft Azure Internal Consumption"
$MyPublicIp                     = (Invoke-WebRequest -uri "http://ifconfig.me/ip").Content
$DSCFileName                    = "AutomatedLabSetupDSC.ps1"
$DSCFilePath                    = Join-Path -Path $CurrentDir -ChildPath $DSCFileName
$ConfigurationName              = "AutomatedLabSetupDSC"
#endregion

#region Defining credential(s)
$Username = $env:USERNAME
#$ClearTextPassword = 'I@m@JediLikeMyF@therB4Me'
#$ClearTextPassword = New-RandomPassword -ClipBoard -Verbose
#$SecurePassword = ConvertTo-SecureString -String $ClearTextPassword -AsPlainText -Force
$SecurePassword = New-RandomPassword -ClipBoard -AsSecureString -Verbose
$Credential = New-Object System.Management.Automation.PSCredential -ArgumentList ($Username, $SecurePassword)
#endregion

#region Define Variables needed for Virtual Machine
#$VMName 	        = "AL-$('{0:yyMMddHHmm}' -f (Get-Date))"
$VMName 	        = "automatedlab"
$ImagePublisherName	= "MicrosoftWindowsDesktop"
$ImageOffer	        = "Windows-11"
$ImageSku	        = "win11-21h2-ent"
$VMSize 	        = "Standard_D8s_v5"
$PublicIPName       = "$VMName-PIP" 
$NICName            = "$VMName-NIC"
$OSDiskName         = "$VMName-OSDisk"
$DataDiskName       = "$VMName-DataDisk01"
$OSDiskSize         = "127"
$OSDiskType         = "Premium_LRS"
$FQDN               = "$VMName.$Location.cloudapp.azure.com".ToLower()
#endregion

# Login to your Azure subscription.
if (-not((Get-AzContext).Subscription.Name -eq $SubscriptionName))
{
    Connect-AzAccount
    #$Subscription = Get-AzSubscription -SubscriptionName $SubscriptionName -ErrorAction Ignore
    Select-AzSubscription -SubscriptionName $SubscriptionName | Select-Object -Property *
}

$ResourceGroup = Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction Ignore 
if ($ResourceGroup)
{
    #Step 0: Remove previously existing Azure Resource Group with the "AutomatedLab-rg" name
    $ResourceGroup | Remove-AzResourceGroup -Force -Verbose
}

#Step 1: Create Azure Resource Group
# Create Resource Groups and Storage Account for diagnostic
New-AzResourceGroup -Name $ResourceGroupName -Location $Location -Force

#Step 2: Create Azure Storage Account
New-AzStorageAccount -Name $StorageAccountName -ResourceGroupName $ResourceGroupName -Location $Location -SkuName $StorageAccountSkuName

#Step 3: Create Azure Network Security Group
#RDP only for my public IP address
$RDPRule              = New-AzNetworkSecurityRuleConfig -Name RDPRule -Description "Allow RDP" -Access Allow -Protocol Tcp -Direction Inbound -Priority 300 -SourceAddressPrefix $MyPublicIp -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange $RDPPort
#HTTP for everyone
$HTTPRule             = New-AzNetworkSecurityRuleConfig -Name HTTPRule -Description "Allow HTTP" -Access Allow -Protocol Tcp -Direction Inbound -Priority 301 -SourceAddressPrefix Internet -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 80
#$NetworkSecurityGroup = New-AzNetworkSecurityGroup -ResourceGroupName $ResourceGroupName -Location $Location -Name $NICNetworkSecurityGroupName -SecurityRules $HTTPRule, $RDPRule -Force
#Allowing only HTTP for everyone from a NSG POV
$NetworkSecurityGroup = New-AzNetworkSecurityGroup -ResourceGroupName $ResourceGroupName -Location $Location -Name $NICNetworkSecurityGroupName -SecurityRules $HTTPRule -Force

#Steps 4 + 5: Create Azure Virtual network using the virtual network subnet configuration
$vNetwork = New-AzVirtualNetwork -ResourceGroupName $ResourceGroupName -Name $VirtualNetworkName -AddressPrefix $VirtualNetworkAddressSpace -Location $Location

Add-AzVirtualNetworkSubnetConfig -Name $SubnetName -VirtualNetwork $vNetwork -AddressPrefix $SubnetIPRange -NetworkSecurityGroupId $NetworkSecurityGroup.Id
$vNetwork = Set-AzVirtualNetwork -VirtualNetwork $vNetwork
$Subnet   = Get-AzVirtualNetworkSubnetConfig -Name $SubnetName -VirtualNetwork $vNetwork

#Step 6: Create Azure Public Address
$PublicIP = New-AzPublicIpAddress -Name $PublicIPName -ResourceGroupName $ResourceGroupName -Location $Location -AlLocationMethod Static -DomainNameLabel $VMName.ToLower()
#Setting up the DNS Name
#$PublicIP.DnsSettings.Fqdn = $FQDN

#Step 7: Create Network Interface Card 
$NIC      = New-AzNetworkInterface -Name $NICName -ResourceGroupName $ResourceGroupName -Location $Location -SubnetId $Subnet.Id -PublicIpAddressId $PublicIP.Id -NetworkSecurityGroupId $NetworkSecurityGroup.Id

<# Optional : Step 8: Get Virtual Machine publisher, Image Offer, Sku and Image
$ImagePublisherName = Get-AzVMImagePublisher -Location $Location | Where-Object -FilterScript { $_.PublisherName -eq "MicrosoftWindowsDesktop"}
$ImageOffer = Get-AzVMImageOffer -Location $Location -publisher $ImagePublisherName.PublisherName | Where-Object -FilterScript { $_.Offer  -eq "Windows-11"}
$ImageSku = Get-AzVMImageSku -Location  $Location -publisher $ImagePublisherName.PublisherName -offer $ImageOffer.Offer | Where-Object -FilterScript { $_.Skus  -eq "win11-21h2-pro"}
$image = Get-AzVMImage -Location  $Location -publisher $ImagePublisherName.PublisherName -offer $ImageOffer.Offer -sku $ImageSku.Skus | Sort-Object -Property Version -Descending | Select-Object -First 1
#>

# Step 9: Create a virtual machine configuration file (As a Spot Intance)
$VMConfig = New-AzVMConfig -VMName $VMName -VMSize $VMSize -Priority "Spot" -MaxPrice -1
Add-AzVMNetworkInterface -VM $VMConfig -Id $NIC.Id

# Set VM operating system parameters
Set-AzVMOperatingSystem -VM $VMConfig -Windows -ComputerName $VMName -Credential $Credential

# Set boot diagnostic storage account
Set-AzVMBootDiagnostic -Enable -ResourceGroupName $ResourceGroupName -VM $VMConfig -StorageAccountName $StorageAccountName    

# The line below replaces Step #8 : Set virtual machine source image
Set-AzVMSourceImage -VM $VMConfig -PublisherName $ImagePublisherName -Offer $ImageOffer -Skus $ImageSku -Version 'latest'

# Set OsDisk configuration
Set-AzVMOSDisk -VM $VMConfig -Name $OSDiskName -DiskSizeInGB $OSDiskSize -StorageAccountType $OSDiskType -CreateOption fromImage

#region Adding Data Disk
$VMDataDisk01Config = New-AzDiskConfig -SkuName Standard_LRS -Location $Location -CreateOption Empty -DiskSizeGB 512
$VMDataDisk01       = New-AzDisk -DiskName $DataDiskName -Disk $VMDataDisk01Config -ResourceGroupName $ResourceGroupName
$VM                 = Add-AzVMDataDisk -VM $VMConfig -Name $DataDiskName -CreateOption Attach -ManagedDiskId $VMDataDisk01.Id -Lun 0
#endregion

#Step 10: Create Azure Virtual Machine
New-AzVM -ResourceGroupName $ResourceGroupName -Location $Location -VM $VMConfig -DisableBginfoExtension

$VM = Get-AzVM -ResourceGroup $ResourceGroupName -Name $VMName

#region JIT Access Management
#region Enabling JIT Access
$NewJitPolicy = (@{
        id    = $VM.Id
        ports = (@{
                number                     = $RDPPort;
                protocol                   = "*";
                allowedSourceAddressPrefix =  "*";
                maxRequestAccessDuration   = "PT$($JitPolicyTimeInHours)H"
            })   
    })

Write-Host "Get Existing JIT Policy. You can Ignore the error if not found."
$ExistingJITPolicy = (Get-AzJitNetworkAccessPolicy -ResourceGroupName $ResourceGroupName -Location $Location -Name $JitPolicyName -ErrorAction Ignore).VirtualMachines
$UpdatedJITPolicy  = $ExistingJITPolicy.Where{$_.id -ne "$($VM.Id)"} # Exclude existing policy for $VMName
$UpdatedJITPolicy.Add($NewJitPolicy)
	
#! Enable Access to the VM including management Port, and Time Range in Hours
Write-Host "Enabling Just in Time VM Access Policy for ($VMName) on port number $RDPPort for maximum $JitPolicyTimeInHours hours..."
$null = Set-AzJitNetworkAccessPolicy -VirtualMachine $UpdatedJITPolicy -ResourceGroupName $ResourceGroupName -Location $Location -Name $JitPolicyName -Kind "Basic"
#endregion

#region Requesting Temporary Access : 3 hours
$JitPolicy = (@{
        id    = $VM.Id
        ports = (@{
                number                     = $RDPPort;
                endTimeUtc                 = (Get-Date).AddHours(3).ToUniversalTime()
                allowedSourceAddressPrefix = @($MyPublicIP) 
            })
    })
$ActivationVM = @($JitPolicy)
Write-Host "Requesting Temporary Acces via Just in Time for ($VMName) on port number $RDPPort for maximum $JitPolicyTimeInHours hours..."
Start-AzJitNetworkAccessPolicy -ResourceGroupName $($VM.ResourceGroupName) -Location $VM.Location -Name $JitPolicyName -VirtualMachine $ActivationVM
#endregion

#endregion

#region Enabling auto-shutdown at 11:00 PM in the user time zome
$SubscriptionId              = ($VM.Id).Split('/')[2]
$ScheduledShutdownResourceId = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/microsoft.devtestlab/schedules/shutdown-computevm-$VMName"
$Properties                  = @{}
$Properties.Add('status', 'Enabled')
$Properties.Add('taskType', 'ComputeVmShutdownTask')
$Properties.Add('dailyRecurrence', @{'time'= "2300"})
$Properties.Add('timeZoneId', (Get-TimeZone).Id)
$Properties.Add('targetResourceId', $VM.Id)
New-AzResource -Location $location -ResourceId $ScheduledShutdownResourceId -Properties $Properties -Force

#endregion
#Step 11: Start Azure Virtual Machine
Start-AzVM -Name $VMName -ResourceGroupName $ResourceGroupName

#region Setting up the DSC extension
# Publishing DSC Configuration for AutomatedLab via Hyper-V (Nested Virtualization)
Publish-AzVMDscConfiguration $DSCFilePath -ResourceGroupName $ResourceGroupName -StorageAccountName $StorageAccountName -Force -Verbose

Set-AzVMDscExtension -ResourceGroupName $ResourceGroupName -VMName $VMName -ArchiveBlobName "$DSCFileName.zip" -ArchiveStorageAccountName $StorageAccountName -ConfigurationName $ConfigurationName -Version "2.80" -Location $Location -AutoUpdate -Verbose
$VM | Update-AzVM -Verbose
#endregion
<#
#>

Start-Sleep -Seconds 15

#Step 12: Start RDP Session
#mstsc /v $PublicIP.IpAddress
mstsc /v $FQDN
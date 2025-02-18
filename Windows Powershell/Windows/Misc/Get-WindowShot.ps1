<#
This Sample Code is provided for the purpose of illustration only
and is not intended to be used in a production environment.  THIS
SAMPLE CODE AND ANY RELATED INFORMATION ARE PROVIDED "AS IS" WITHOUT
WARRANTY OF ANY KIND, EITHER EXPRESSED OR IMPLIED, INCLUDING BUT NOT
LIMITED TO THE IMPLIED WARRANTIES OF MERCHANTABILITY AND/OR FITNESS
FOR A PARTICULAR PURPOSE.  We grant You a nonexclusive, royalty-free
right to use and modify the Sample Code and to reproduce and distribute
the object code form of the Sample Code, provided that You agree:
(i) to not use Our name, logo, or trademarks to market Your software
product in which the Sample Code is embedded; (ii) to include a valid
copyright notice on Your software product in which the Sample Code is
embedded; and (iii) to indemnify, hold harmless, and defend Us and
Our suppliers from and against any claims or lawsuits, including
attorneys' fees, that arise or result from the use or distribution
of the Sample Code.
#>
#region Function definitions
#requires -Version 2
function Get-SystemMetrics
{
	<#
			.SYNOPSIS
			Retrieves the specified system metric or system configuration setting.

			.DESCRIPTION
			Retrieves the specified system metric or system configuration setting. Note that all dimensions retrieved by GeSystemMetrics are in pixels.

			.PARAMETER nIndex
			The system metric or configuration setting to be retrieved

			.EXAMPLE
			Get-SystemMetrics -nIndex 32 
			Returns the thickness of the sizing border around the perimeter of a window that can be resized, in pixels.

            .LINK
            https://docs.microsoft.com/en-us/windows/desktop/api/winuser/nf-winuser-getsystemmetrics
	#>	
	[CmdletBinding()]
	Param(
		[Parameter(Mandatory=$true)]
		[int]$nIndex
   )
    $signature = '
        [DllImport("user32.dll", CharSet=CharSet.Auto, ExactSpelling=true)] public static extern int GetSystemMetrics(int nIndex);
    '
    $type = Add-Type -MemberDefinition $signature -Name xGetSysMetrics -PassThru
    return $type::GetSystemMetrics($nIndex)
}

function Show-Window
{
	<#
			.SYNOPSIS
			Shows and puts in the foreground the window of the process(es) passed as parameters (or via the pipeline)

			.DESCRIPTION
			Shows and puts in the foreground the window of the process(es) passed as parameters (or via the pipeline)

			.PARAMETER Process
			The process(es) we want to capture the window 

			.EXAMPLE
			Get-Process Powershell | Show-Window
			Shows and puts in the foreground the window of the process(es) passed as parameters (or via the pipeline)

            .LINK
            https://docs.microsoft.com/en-us/windows/desktop/api/winuser/nf-winuser-showwindowasync
            https://docs.microsoft.com/en-us/windows/desktop/api/winuser/nf-winuser-setforegroundwindow
	#>	
	Param(
		[Parameter(Mandatory=$true, ValueFromPipeline=$True, ValueFromPipelineByPropertyName=$True)]
		[System.Diagnostics.Process[]]$Process
   )
    begin
    {
        $signature = '
        [DllImport("user32.dll")] public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);
        [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
        [DllImport("user32.dll")] public static extern int SetForegroundWindow(IntPtr hwnd);
        '
        $type = Add-Type -MemberDefinition $signature -Name xShowWindow -PassThru
    }
    process
    {
        #Going through every process
        foreach ($CurrentProcess in $Process)
        {
            Write-Verbose "Processing $($CurrentProcess.Name) (PID: $($CurrentProcess.ID) - Title:  $($CurrentProcess.MainWindowTitle)) ..."            
            $hwnd = $CurrentProcess.MainWindowHandle
            #$null = $type::ShowWindow($hwnd, 5)
            $null = $type::ShowWindowAsync($hwnd, 5)
            $null = $type::SetForegroundWindow($hwnd) 
        }
    }
    end
    {
    }
}

function Get-WindowRectangle
{
	<#
			.SYNOPSIS
			Return a custom object with the coordinates of the process windows

			.DESCRIPTION
			Return a custom object with the coordinates of the process windows

			.PARAMETER Process
			The process(es) we want to capture the window 

			.PARAMETER NoBorder
			Switch to specify if you want to skip the (invisible) borders

			.EXAMPLE
			Get-Process Powershell | Show-Window
			Shows and puts in the foreground the window of the process(es) passed as parameters (or via the pipeline)

            .LINK
            https://docs.microsoft.com/en-us/windows/desktop/api/winuser/nf-winuser-getwindowrect
            https://docs.microsoft.com/en-us/windows/desktop/api/winuser/nf-winuser-getclientrect
            https://docs.microsoft.com/en-us/windows/desktop/api/winuser/nf-winuser-movewindow
	#>	
	Param(
		[Parameter(Mandatory=$true, ValueFromPipeline=$True, ValueFromPipelineByPropertyName=$True)]
		[System.Diagnostics.Process]$Process,

		[parameter(Mandatory=$false)]
		[Switch]$NoBorder
    )
    Try
    {
        [void][Window]
    }
    Catch
    {
        Add-Type @"
                using System;
                using System.Runtime.InteropServices;
                public class Window {
                [DllImport("user32.dll")]
                [return: MarshalAs(UnmanagedType.Bool)]
                public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
                [DllImport("user32.dll")]
                [return: MarshalAs(UnmanagedType.Bool)]
                public static extern bool GetClientRect(IntPtr hWnd, out RECT lpRect);
                [DllImport("user32.dll")]
                [return: MarshalAs(UnmanagedType.Bool)]
                public extern static bool MoveWindow(IntPtr handle, int x, int y, int width, int height, bool redraw);
                }
                public struct RECT
                {
                    public int Left;        // x position of upper-left corner
                    public int Top;         // y position of upper-left corner
                    public int Right;       // x position of lower-right corner
                    public int Bottom;      // y position of lower-right corner
                }
"@
    }

    #Read https://docs.microsoft.com/en-us/windows/desktop/api/winuser/nf-winuser-getsystemmetrics
    #width of the horizontal border
    New-Variable -Name SM_CXSIZEFRAME -Value 32 -Option Constant
    #height of the vertical border
    New-Variable -Name SM_CYSIZEFRAME -Value 33 -Option Constant
    Write-Verbose "Processing $($Process.Name) (PID: $($Process.ID) - Title:  $($Process.MainWindowTitle)) ..."            
    $rcWindow = New-Object RECT
    $rcClient = New-Object RECT
    $hwnd = $Process.MainWindowHandle
    $WindowRect = [Window]::GetWindowRect($hwnd,[ref]$rcWindow)
    If ($WindowRect) 
    {
        If (($rcWindow.Top -lt 0) -AND ($rcWindow.Left -lt 0))
        {
            Write-Warning "Window is minimized! Coordinates will not be accurate."
        }
        If (($rcWindow.Top -eq 0) -AND ($rcWindow.Left -eq 0) -AND ($rcWindow.Right -eq 0) -AND ($rcWindow.Bottom -eq 0))
        {
            Write-Warning "Window is invisible! Coordinates will not be accurate."
            return $null
        }
        #If you want to skip the horizontla and vertical borders
        if ($NoBorder)
        {
            $HorizontalBorderWidth = Get-SystemMetrics($SM_CXSIZEFRAME)
            $VerticalBorderHeight = Get-SystemMetrics($SM_CYSIZEFRAME)
            $CurrentWindowRectangle = New-Object -TypeName psobject -Property @{"Top"=$rcWindow.Top+$VerticalBorderHeight; "Left"=$rcWindow.Left+$HorizontalBorderWidth; "Width"=$rcWindow.Right-$rcWindow.Left-2*$HorizontalBorderWidth; "Height"=$rcWindow.Bottom-$rcWindow.Top-2*$VerticalBorderHeight}
        }
        else
        {
            $CurrentWindowRectangle = New-Object -TypeName psobject -Property @{"Top"=$rcWindow.Top; "Left"=$rcWindow.Left; "Width"=$rcWindow.Right-$rcWindow.Left; "Height"=$rcWindow.Bottom-$rcWindow.Top}
        }
        #Returning a window
        return $CurrentWindowRectangle
    }
    else
    {
        return $null
    }
}

Function Get-WindowShot
{ 
	<#
			.SYNOPSIS
			Take screenshots from the given process window(s) during a duration and interval when specified 

			.DESCRIPTION
			Take screenshots from the given process window(s) during a duration and interval when specified 

			.PARAMETER FullName
			The destination file when taking only one screenshoot (no duration and interval specified)

			.PARAMETER Directory
			The destination directory when taking mutliple screenshoots (duration and interval specified)

			.PARAMETER Format
			The image format (pick a format in the list : 'bmp','gif','jpg','png','wmf')

			.PARAMETER DurationInSeconds
			The duration in seconds during which we will take a screenshot

			.PARAMETER IntervalInSeconds
			The interval in seconds between two screenshots (when DurationInSeconds is specified)

			.PARAMETER Area
			The are of the screenshot : 'WorkingArea' is for the current screen and 'VirtualScreen' is for all connected screens

			.PARAMETER Beep
			Play a beep everytime a screenshot is taken if specified

			.PARAMETER NoBorder
			Switch to specify if you wnt to skip the (invisible) borders

			.EXAMPLE
			Get-WindowShot
			Take a screenshot of the current screen. The file will be generated in the Pictures folder of the current user and will use the PNG format by default. The filename will use the YYYYMMDDTHHmmSS format

			.EXAMPLE
            Get-WindowShot -FullName 'c:\temp\screenshot.wmf' -Area VirtualScreen
			Take a screenshot of all connected screens. The generated file will be 'c:\temp\screenshot.wmf'

			.EXAMPLE
            Get-WindowShot -Directory 'C:\temp' -Format jpg -DurationInSeconds 30 -IntervalInSeconds 10 -Area WorkingArea -Format JPG -Verbose
			Take multiple screenshots (of the current screen) during a 30 seconds period by waiting 10 second between two shots. The file will be generated in the C:\temp folder and will use the JPG format by default. The filename will use the YYYYMMDDTHHmmSS format

	#>	
    [CmdletBinding(DefaultParameterSetName='Directory', PositionalBinding=$false)]
	Param(
		[Parameter(ParameterSetName='File')]
		[Parameter(Mandatory=$false, ValueFromPipeline=$False, ValueFromPipelineByPropertyName=$False)]
		[ValidateScript({$_  -match  "\.($($(([Drawing.Imaging.ImageCodecInfo]::GetImageEncoders()).Filenameextension -split ";" | ForEach-Object { $_.replace('*.','')}) -join '|'))$"})]
		[string]$FullName,

		[Parameter(ParameterSetName='Directory')]
		[Parameter(Mandatory=$false, ValueFromPipeline=$False, ValueFromPipelineByPropertyName=$False)]
		[string]$Directory,

        <#
		[Parameter(ParameterSetName='Directory')]
		[parameter(Mandatory=$false)]
		[ValidateScript({$_ -in [Drawing.Imaging.ImageCodecInfo]::GetImageEncoders().FormatDescription})]
		[String]$Format='JPEG',
        #>

		[Parameter(ParameterSetName='Directory')]
		[parameter(Mandatory=$false)]
		[ValidateScript({$_ -ge 0})]
		[int]$DurationInSeconds=0,

		[Parameter(ParameterSetName='Directory')]
		[parameter(Mandatory=$false)]
		[ValidateScript({$_ -ge 0})]
		[int]$IntervalInSeconds=0,

		[Parameter(Mandatory=$true, ValueFromPipeline=$False, ValueFromPipelineByPropertyName=$False)]
		[ValidateScript({($_  -in ((Get-Process | Select-Object -Property Name -Unique).Name)) -or ($_  -in ((Get-Process | Select-Object -Property Id -Unique).Id))})]
		[String[]]$ProcessNameOrId,

		[parameter(Mandatory=$false)]
		[ValidateScript({$_ -in 0..100})]
		[int]$QualityLevel=100,


		[parameter(Mandatory=$false)]
		[Switch]$Beep,

		[parameter(Mandatory=$false)]
		[Switch]$NoBorder
	)

	#Dynamic parameter to fill the list of known Formats (Dynamic paramater is just used here for autocompletion :) )
	DynamicParam {
		# Create the dictionary 
		$RuntimeParameterDictionary  = New-Object -TypeName System.Management.Automation.RuntimeDefinedParameterDictionary

		# Create the collection of attributes
		$AttributeCollection = New-Object -TypeName System.Collections.ObjectModel.Collection[System.Attribute]

		# Create and set the parameters' attributes
		$Attributes = New-Object -TypeName System.Management.Automation.ParameterAttribute
		$Attributes.Mandatory = $false
		$Attributes.ParameterSetName = 'Directory'
		
		# Add the attributes to the attributes collection
		$AttributeCollection.Add($Attributes)
		
		# Generate and set the ValidateSet 
		$ValidateSet = [Drawing.Imaging.ImageCodecInfo]::GetImageEncoders().FormatDescription
		$ValidateSetAttribute = New-Object -TypeName System.Management.Automation.ValidateSetAttribute -ArgumentList ($ValidateSet)
		
		# Add the ValidateSet to the attributes collection
		$AttributeCollection.Add($ValidateSetAttribute)
		
		# Create and return the dynamic parameter
		$Format = New-Object -TypeName System.Management.Automation.RuntimeDefinedParameter -ArgumentList ('Format', [string], $AttributeCollection)		
		$RuntimeParameterDictionary.Add('Format', $Format)
		return $RuntimeParameterDictionary 
	}
	
    begin
    {
	    Add-Type -AssemblyName System.Windows.Forms
	    Add-type -AssemblyName System.Drawing
    }

    process
    {
	    #Getting the dynamic paramater 
        $TimeElapsed = 0
        $IsTimeStampedFileName = $false
        if ($Format -is [System.Management.Automation.RuntimeDefinedParameter])
        {
            if ([string]::IsNullOrWhiteSpace($Format.Value))
            {
                $Format = "JPEG"
            }
            else
            {
                $Format = $Format.Value
            }
        }

	    if ($FullName)
	    {
		    $Directory = Split-Path -Path $FullName -Parent
		    $HasExtension = $FullName -match "\.(?<Extension>\w+)$"
		    if ($HasExtension)
		    {
			    $Format = $Matches['Extension']
		    }
		    $null = New-Item -Path $Directory -ItemType Directory -Force
	    }
	    elseif ($Directory)
	    {
		    $null = New-Item -Path $Directory -ItemType Directory -Force
            $IsTimeStampedFileName = $true
	    }
	    else
	    {
		    $Directory = [Environment]::GetFolderPath('MyPictures')
            Write-Verbose "Target directory not specified we use [$Directory]"
            $IsTimeStampedFileName = $true
	    }

	    do 
        {
            if ($ProcessNameOrId -Match '\d+')
            {
                $Process = Get-Process -Id $ProcessNameOrId
            }
            else
            {
                $Process = Get-Process -Name $ProcessNameOrId
            }
            if ($Process.count -gt 1)
            {
                Write-Warning "$($Process.count) processes found for $Process. The screenshots could be inaccurate particularly with browsers"
            }
            foreach ($CurrentProcess in $Process)
            {
                $CurrentProcess | Show-Window
                Start-Sleep -Milliseconds 200
                $CurrentWindowRectangle = $CurrentProcess | Get-WindowRectangle -NoBorder:$NoBorder
             
                Write-Verbose "`$CurrentWindowRectangle : $CurrentWindowRectangle ..."
                # Create bitmap using the top-left and bottom-right bounds
                If ($CurrentWindowRectangle.Width -lt 0 -AND $CurrentWindowRectangle.Height -lt 0)
                {
                    Write-Warning "Window is invisible! Coordinates will not be accurate."
                }
                else
                {
	                $Bitmap = New-Object -TypeName System.Drawing.Bitmap -ArgumentList $CurrentWindowRectangle.Width, $CurrentWindowRectangle.Height

	                # Create Graphics object
	                $Graphic = [System.Drawing.Graphics]::FromImage($Bitmap)

	                # Capture process window
	                $Graphic.CopyFromScreen($CurrentWindowRectangle.Left, $CurrentWindowRectangle.Top, 0, 0, $Bitmap.Size)

                    if ($IsTimeStampedFileName)
                    {
     		            $FullName = Join-Path -Path $Directory -ChildPath $($CurrentProcess.Name + '_' + $CurrentProcess.Id + '_' + (get-date -f yyyyMMddTHHmmss) + ".$Format")
                    }
                    else
                    {
     		            $FullName = Join-Path -Path $Directory -ChildPath $($CurrentProcess.Name + '_' + $CurrentProcess.Id + '_' + ".$Format")
                    }

                    $QualityEncoder = [System.Drawing.Imaging.Encoder]::Quality
                    $EncoderParameters = New-Object System.Drawing.Imaging.EncoderParameters(1)

                    # Set JPEG quality level here: 0 - 100 (inclusive bounds)
                    $EncoderParameters.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter($QualityEncoder, $QualityLevel)

	                # Save to file
                    $ImageEncoder = [Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.FormatDescription -eq $Format }
	                $Bitmap.Save($FullName, $ImageEncoder, $EncoderParameters) 
                    Write-Host -Object "[$(get-date -Format T)] Screenshot saved to $FullName"
                    if ($Beep)
                    {
                        #[console]::beep()
                        [console]::beep(7000,5)
                    }
                }
            }
	    
            if (($DurationInSeconds -gt 0) -and ($IntervalInSeconds -gt 0))
            {
                Write-Verbose "[$(get-date -Format T)] Sleeping $IntervalInSeconds seconds ..."
                Start-Sleep -Seconds $IntervalInSeconds
                $TimeElapsed += $IntervalInSeconds
            }
        } While ($TimeElapsed -lt $DurationInSeconds) 
    }
    end
    {
    }

}
#endregion

Clear-Host
New-Alias -Name New-WindowShot -Value Get-WindowShot -ErrorAction SilentlyContinue

#Get-WindowShot -Verbose
#$Process = "powershell_ise"
#$Process = (Get-Process VirtualBoxVM | Sort-Object -Property CPU -Descending | Select-Object -First 1).Id
$Process = (Get-Process -Name MSEdge | Where-Object -FilterScript {$_.MainWindowTitle -match 'Cloud'}).Id
#$Process = 7348
<#
#Creating 10 Powershell processes for the demos
for($i=0; $i -lt 10; $i++)
{
    Start-Process $Process -ArgumentList "-noexit", "-noprofile", "-command & {'Window #'+$i}"
}
#>
Get-Process -Id $Process | Show-Window
Get-WindowShot -Directory 'C:\temp\Get-WindowShot' -Format JPEG -DurationInSeconds 3600 -IntervalInSeconds 15 -ProcessNameOrId $Process -NoBorder -Verbose -Beep 
#Get-WindowShot -FullName 'c:\temp\screenshot.wmf' -Verbose



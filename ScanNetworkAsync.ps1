##################################################################################################################
###
### Script to scan network and return Status + DNS (if available)
###
##################################################################################################################

<#
    .SYNOPSIS
    Returns an PowerShell Object with basic informations about the Network like IP, Hostname, FQDN and Status

    .DESCRIPTION
    Network Scanner for PowerShell to scan IP-Range async
    
    Returns an PowerShell Object with basic informations about the Network like IP, Hostname, FQDN and Status
    
    The first three quads of the IP-Range must be the same (like 192.168.1.XX - 192.168.1.XX).
    
    .EXAMPLE
    ScanNetworkAsync.ps1 -StartIP 192.168.1.1 -EndIP 192.168.1.200

    .LINK
    https://github.com/BornToBeRoot/PowerShell-Async-IPScanner
#>


##################################################################################################################
### Parameter and default values
##################################################################################################################

[CmdletBinding()]
param(
	[Parameter(
		Position=0,
		Mandatory=$true,
		HelpMessage='Start IP like 192.168.17.1')]
	[String]$StartIP,
	
	[Parameter(
		Position=1,
		Mandatory=$true,
		HelpMessage='End IP like 192.168.17.199')]
	[String]$EndIP,

	[Parameter(
		Position=2,
		Mandatory=$false,
		HelpMessage='Maximum threads at the same time (Default 25)')]
	[Int32]$MaxThreads=25,
	
	[Parameter(
		Position=3,
		Mandatory=$false,
		HelpMessage='Wait time in Milliseconds if all threads are busy (Default 500)')]
	[Int32]$SleepTimer=500
)

##################################################################################################################
### Begin:  User Output (Information about Settings) & Validate IP-Range
##################################################################################################################

begin{
    $StartTime = Get-Date

    Write-Host "`n----------------------------------------------------------------------------------------------------"
    Write-Host "----------------------------------------------------------------------------------------------------`n"
    Write-Host "Start:`tScript (Scan-Network) at $StartTime" -ForegroundColor Green
    Write-Host "`n----------------------------------------------------------------------------------------------------`n"
    Write-Host "Network Scan Settings (Range):`t`t$StartIP - $EndIP"
    Write-Host "Maximum threads at same time:`t`t$MaxThreads (Threads)"
    Write-Host "Wait time if all threads are busy:`t$SleepTimer (Milliseconds)"
    Write-Host "`n----------------------------------------------------------------------------------------------------`n"

    ### Variables for IP-Range Scan
    $TmpStartIP = $StartIP.Split('.')
    $TmpEndIP =  $EndIP.Split('.')

    [String]$StartIP_FirstThree = [String]::Format("{0}.{1}.{2}", $TmpStartIP[0], $TmpStartIP[1], $TmpStartIP[2])
    [String]$EndIP_FirstThree =  [String]::Format("{0}.{1}.{2}", $TmpEndIP[0], $TmpEndIP[1], $TmpEndIP[2])

    $StartRange = $TmpStartIP[3]
    $EndRange = $TmpEndIP[3]

    if($StartIP_FirstThree -notlike $EndIP_FirstThree)
    {
	    Write-Host "The first three quads of the StartIP and EndIP don't match! Abort Script..." -ForegroundColor Red	
	    return
    }

    $FirstThree = $StartIP_FirstThree
}

##################################################################################################################
### Process: Async IP-Scan (with resolveing DNS)
##################################################################################################################

Process{
    Write-Host "Scanning IPs...`n" -ForegroundColor Yellow

    foreach($Quad in $StartRange..$EndRange)
    {
        While ($(Get-Job -state running).count -ge $MaxThreads)
        {
            Start-Sleep -Milliseconds $SleepTimer
        }   
       
        $IPv4Address = "$FirstThree.$Quad"

	    Write-Host "Scanning IP (Async):`t$IPv4Address"

        Start-Job -ArgumentList $IPv4Address -ScriptBlock { 

            $IPv4Address = $args[0]
                
            if(Test-Connection -ComputerName $IPv4Address -Count 2 -Quiet) { $Status = "Up" } else { $Status = "Down" }
		
		    $FQDN = [String]::Empty
		    $Hostname = [String]::Empty
		
		    try	{
			    $FQDN = ([System.Net.Dns]::GetHostEntry($IPv4Address).HostName).ToUpper()                       	
			    $Hostname = $FQDN.Split('.')[0]  						
		    }
		    catch { } # No DNS found
				
		    $Device = New-Object -TypeName PSObject
            Add-Member -InputObject $Device -MemberType NoteProperty -Name IPv4Address -Value $IPv4Address
            Add-Member -InputObject $Device -MemberType NoteProperty -Name Hostname -Value $Hostname
            Add-Member -InputObject $Device -MemberType NoteProperty -Name FQDN -Value $FQDN
		    Add-Member -InputObject $Device -MemberType NoteProperty -Name Status -Value $Status
		
            return $Device      
        } | Out-Null
    }

    Write-Host "`nAwaiting completion of threads..." -ForegroundColor Yellow

    Get-Job | Wait-Job | Out-Null

    Write-Host "`nScanning finished!" -ForegroundColor Yellow


    ### Built Global Array, Wait for Jobs,  Remove Jobs
    $Devices = New-Object System.Collections.ArrayList
   
    Get-Job | Receive-Job | % { $Devices.Add(($_ | Select-Object IPv4Address, Hostname, FQDN, Status))} | Out-Null
   
    Get-Job | Remove-Job | Out-Null
}

##################################################################################################################
### User Output
##################################################################################################################

End {
    $DevicesUp = @($Devices | Where-Object {($_.Status -eq "Up")}).Count
    $DevicesDown = @($Devices | Where-Object {($_.Status -eq "Down") -and (-not([String]::IsNullOrEmpty($_.FQDN)))}).Count
    $DevicesUnkown = @($Devices | Where-Object {($_.Status -eq "Down") -and ([String]::IsNullOrEmpty($_.FQDN))}).Count

    $EndTime = Get-Date
    $ExecutionTime = (New-TimeSpan -Start $StartTime -End $EndTime).Seconds

    Write-Host "`n----------------------------------------------------------------------------------------------------`n"
    Write-Host "Devices Up:`t`t$DevicesUp" 
    Write-Host "Devices Down:`t`t$DevicesDown"
    Write-Host "Devices Unknown:`t$DevicesUnkown" 
    Write-Host "`n----------------------------------------------------------------------------------------------------`n"
    Write-Host "Script duration:`t$ExecutionTime (Seconds)`n" -ForegroundColor Yellow
    Write-Host "End:`tScript (Scan-Network) at $EndTime" -ForegroundColor Green
    Write-Host "`n----------------------------------------------------------------------------------------------------"
    Write-Host "----------------------------------------------------------------------------------------------------`n"

    
    ### Return Network Informations
    return $Devices
}
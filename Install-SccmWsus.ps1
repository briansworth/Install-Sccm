<#
.SYNOPSIS
Install and configure the Wsus role on a local or remote server.

.DESCRIPTION
Install and configure the Wsus role on a local or remote server.

.PARAMETER ComputerName
The name of the computer you are going to install Wsus on.
Default is the current computer.

.PARAMETER ContentPath
The path Wsus will use for storing update information.
This parameter is valid for both the WID and SQL DB options.

.PARAMETER SqlServerName
The SqlServer name that Wsus will connect to for storing updates.

.PARAMETER SqlInstanceName
The SqlServer instance name that Wsus will use for the Database.
If left blank, the default is used 'MSSQLSERVER'.

.EXAMPLE
PS> Install-SccmWsus -ContentPath 'D:\wsus'

Description
-----------
This command will install Wsus using the Windows Internal DB.
The content path for Wsus will 'D:\wsus'

.EXAMPLE
PS> Install-SccmWsus -ComputerName SUP -ContentPath D:\wsus

Description
-----------
This command will install Wsus using the Windows Internal DB.
It will install on the SUP server with the Wsus content path of 'D:\wsus'

.EXAMPLE
PS> Install-SccmWsus -SqlServerName cmsql -ContentPath 'C:\wsus'

Description
-----------
This command will install Wsus on the local computer, and configure it to 
store updated on the Sql server 'cmsql'. 
The local Wsus content will be stored in 'C:\wsus'
#>
[CmdletBinding(DefaultParameterSetName='Wid')]
Param(
  [Parameter(Position=0,ParameterSetName='Wid')]
  [Parameter(Position=0,ParameterSetName='SqlDB')]
  [String]$ComputerName = $ENV:COMPUTERNAME,

  [Parameter(Position=1,ParameterSetName='Wid')]
  [Parameter(Position=1,ParameterSetName='SqlDB')]
  [String]$ContentPath,

  [Parameter(Position=2,Mandatory=$true,ParameterSetName='SqlDB')]
  [String]$SqlServerName,

  [Parameter(Position=3,ParameterSetName='SqlDB')]
  [String]$SqlInstanceName
)
Try{
  $localHostIsWsus = $false
  $localHostIsSql = $false
  $wsusRebootRequired = $false

  Write-Verbose "Verifying DNS resolution of [$ComputerName]"
  $computerDNS = [Net.Dns]::GetHostEntry($ComputerName)
  $localhostDNS = [Net.Dns]::GetHostEntry($ENV:COMPUTERNAME)

  if($PSCmdlet.ParameterSetName -eq 'SqlDB'){
    Write-Verbose "Verifying DNS resolution of SQL Server [$SqlServerName]"
    $sqlServerDNS = [Net.Dns]::GetHostEntry($SqlServerName)
    if($computerDNS.HostName -eq $localhostDNS.HostName){
      $localHostIsSql = $true
    }
  }

  if($computerDNS.HostName -eq $localhostDNS.HostName){
    Write-Verbose "Target computer is localhost [$($computerDNS.HostName)]"
    $localHostIsWsus = $true
  }else{
    Write-Verbose "Testing WinRM connectivity with [$ComputerName]"
    $wsusSession = New-PSSession -ComputerName $ComputerName `
      -ErrorAction Stop
  }

  $features = @(
    'UpdateServices-Services',
    'UpdateServices-WidDB',
    'UpdateServices-DB'
  )

  $featuresParameters = @{
    'Name' = $features;
    'ErrorAction' = 'Stop';
  }

  if(!$localHostIsWsus){
    $featuresParameters.Add('ComputerName', $ComputerName)
  }

  $usFeatures = Get-WindowsFeature @featuresParameters

  $usMainFeature = $usFeatures | Where-Object {$_.Name -eq 'UpdateServices-Services'}

  if($usMainFeature.Installed){
    Write-Verbose "Feature: [$($usMainFeature.Name)] is already installed"
    $widUsFeature = $usFeatures | Where-Object {$_.Name -eq 'UpdateServices-WidDB'}
    $sqlUsFeature = $usFeatures | Where-Object {$_.Name -eq 'UpdateServices-DB'}

    if($widUsFeature.Installed -and !$SqlServerName){
      Write-Verbose "WSUS Windows Internal DB feature already installed"

    }elseif($sqlUsFeature.Installed -and $SqlServerName){
      Write-Verbose "WSUS SQL DB feature already installed"

    }elseif($SqlServerName){
      Write-Verbose "Will install SQL DB for WSUS"
      $featuresParameters.Name = 'UpdateServices-Services', 'UpdateServices-DB'
      Install-WindowsFeature @featuresParameters -IncludeManagementTools

    }else{
      Write-Verbose "Will install Windows Internal DB for WSUS"
      $featuresParameters.Name = 'UpdateServices-Services', 'UpdateServices-WidDB'
      $installResult = Install-WindowsFeature @featuresParameters `
        -IncludeManagementTools

      if($installResult.RestartNeeded -ne 'No'){
        $wsusRebootRequired = $true
      }
    }

  }else{ ### WSUS Features not already installed
    if($SqlServerName){
      $featuresParameters.Name = 'UpdateServices-Services', 'UpdateServices-DB'
      $installResult = Install-WindowsFeature @featuresParameters `
        -IncludeManagementTools
    }else{
      $featuresParameters.Name = 'UpdateServices-Services', 'UpdateServices-WidDB'
      $installResult = Install-WindowsFeature @featuresParameters `
        -IncludeManagementTools
    }

    if($installResult.RestartNeeded -ne 'No'){
      $wsusRebootRequired = $true
    }
  }

  ### Validate the 'WSUS Post Install' state
  $usRegKey = [String]::Format(
    'HKLM:\SOFTWARE\Microsoft\Update Services\{0}',
    'Server\Setup\Installed Role Services'
  )

  if($wsusSession){
    $usState = Invoke-Command -Session $wsusSession `
      -ArgumentList $usRegKey `
      -ScriptBlock { Get-ItemProperty -Path $args[0] } `
      -ErrorAction Stop
  }else{
    $usState = Get-ItemProperty -Path $usRegKey -ErrorAction Stop
  }

  if($usState.'UpdateServices-Services' -eq 2){
    # Post install has completed
    Write-Verbose "WSUS Post install has been run previously"
    break
  }

  ### Create WsusUtil command for post install ###
  $stringScriptBlock = [String]::Format(
    '& "$ENV:PROGRAMFILES\Update Services\Tools\{0}" {1}',
    'WsusUtil.exe',
    'postinstall'
  )

  if($SqlServerName){
    $sqlServerInstanceName = "$($sqlServerDNS.HostName)\$SqlInstanceName"
    $sqlServerInstanceName = $sqlServerInstanceName.TrimEnd('\')

    $stringScriptBlock+=" SQL_INSTANCE_NAME=$sqlServerInstanceName" 
  }
  if($ContentPath){
    $stringScriptBlock+=" CONTENT_DIR=$ContentPath"
  }

  $wsusPostInstallScriptBlock=[ScriptBlock]::Create($stringScriptBlock)
  Write-Verbose "PostInstall command: [$wsusPostInstallScriptBlock]"

  if($localHostIsWsus){
    $wsusPostInstallResult = $wsusPostInstallScriptBlock.Invoke()
  }else{
    $wsusPostInstallResult =Invoke-Command -Session $wsusSession `
      -ScriptBlock $wsusPostInstallScriptBlock `
      -ErrorAction Stop
  }
  if($wsusRebootRequired){
    $rebootMsg = [String]::Format(
      'UpdateServices requires a reboot to complete setup Computer: {0}',
      "[$ComputerName]"
    )
    Write-Warning -Message $rebootMsg
  }

  if($wsusPostInstallResult[-1] -ne 'Post install has successfully completed'){
    $wsusErrorMsg = [String]::Format(
      "Wsus Post Install failed with the following message: {0}. {1}",
      "$($wsusPostInstallResult[-1])",
      "$($wsusPostInstallResult[0]) on server [$ComputerName]"
    )

    $anonLoginFail = [String]::Format(
      "Fatal Error: Login Failed for user {0}",
      "'NT AUTHORITY\ANONYMOUS LOGON'."
    )

    if($wsusPostInstallResult[-1] -eq $anonLoginFail -and !$localHostIsWsus){
      $doubleHopWarning = [String]::Format(
        "This error message is likely a result of {0} {1}. {2} {3}: {4}",  
        "a limitation in Kerberos authentication",
        'when using PowerShell remoting',
        "You should be able to directly login to [$ComputerName]",
        "and run the following command locally to resolve the issue",
        "[$wsusPostInstallScriptBlock]"
      )
    }

    Write-Error $wsusErrorMsg `
      -Category InvalidResult

    if($doubleHopWarning){
      Write-Warning -Message $doubleHopWarning
    }
  }
  # Raw output from the Wsus util post install command
  # Write-Output -InputObject $wsusPostInstallResult

}Catch{
  Write-Error -Exception $_.Exception `
    -Category $_.CategoryInfo.Category
}Finally{
  if($wsusSession){
    Remove-PSSession -Session $wsusSession
  }
}

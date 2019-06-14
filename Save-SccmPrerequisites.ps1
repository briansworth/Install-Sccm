<#
.SYNOPSIS
Save / download required Sccm prerequisites.

.DESCRIPTION
Save / download required Sccm prerequisites. 
This includes the SCCM prerequisites that get downloaded during the installation wizard, 
and the ADK files required for installing the ADK components for SCCM. 
You must run this script in the same directory as your ADKSetup.exe file.

.PARAMETER SccmInstallSource
Path to the Sccm install media. 
Must be a mounted ISO, or a folder in which the ISO contents have been extracted. 

.PARAMETER Path
Path to save the prerequisite files. Must be a directory.

.EXAMPLE
Save-SccmPrerequisites.ps1 -SccmInstallSource D:\ -Path C:\temp\sccmPreReqs

Description
-----------
This will download all files to the 'C:\temp\sccmPreReqs folder. 
The SCCM ISO file has been mounted to the D:\ drive, so we point the -SccmInstallSource parameter to that drive letter. 

.EXAMPLE
Save-SccmPrerequisites.ps1 -SccmInstallSource C:\Temp\SccmExtracted -Verbose

Description
-----------
If you have extracted the SCCM ISO file to your C:\Temp drive you can specify the path to the folder that contains the Installation media. 
This command will use the default location to save the downloaded files.

.NOTES
You will need to run this script from the same directory that has your ADKSetup.exe file (and if necessary the ADKWinPESetup.exe. 
Starting in ADK 1809, the Windows PE component is removed from ADKSetup and has it's own installer.

#>
[CmdletBinding()]
Param(
  [Parameter(Mandatory=$true,Position=0)]
  [String]$SccmInstallSource,

  [Parameter(Position=1)]
  [String]$Path="$ENV:SYSTEMDRIVE\temp\sccm"
)
Try{
  $sccmSetupDlFilePath=Join-Path -Path $SccmInstallSource `
    -ChildPath "SMSSETUP\BIN\X64\setupdl.exe" `
    -ErrorAction Stop
  
  $tempSccmPreReqPath="$Path\prereq"
  $tempAdkPath="$Path\adk"
  $tempAdkWinPEPath="$Path\adkPeAddon"

  if(!(Test-Path -Path $sccmSetupDlFilePath)){
    $setupDlNotFound=[String]::Format(
      "File: {0} not found. Ensure {1} {2}",
      $sccmSetupDlFilePath,
      "that the SCCM Installation Media location specified is correct",
      "[$SccmInstallSource]"
    )
    Write-Error $setupDlNotFound -ErrorAction Stop
  }

  if(!(Test-Path -Path .\adksetup.exe)){
    $adkNotFound=[String]::Format(
      "File: {0} not found. Please {1} '{0}'",
      "adksetup.exe",
      "navigate to the directory containing"
    )
    Write-Error $adkNotFound -ErrorAction Stop
  }

  [version]$adkVersionNoPE='10.1.17763.1'

  $adk=Get-Item -Path .\adksetup.exe -ErrorAction Stop
  [version]$adkVersion=$adk.VersionInfo.FileVersion

  $requirePEAddon=$false
  if($adkVersion -ge $adkVersionNoPE){
    $requirePEAddon=$true

    $adkPeWarn=[String]::Format(
      "The adksetup.exe version you have {0}. {1}. {2}, {3}. {4}",
      "does not contain the WinPE Feature that SCCM requires",
      "You will need to download the AdkWinPE add-on for this AdkVersion",
      "Once you have it downloaded",
      "please copy it to this file location and try again",
      "Ignore this warning if you have already done so."
    )
    Write-Warning $adkPeWarn

    $adkPeFileExist=Test-Path -Path .\adkwinpesetup.exe
    if(!$adkPeFileExist){
      $adkPeFileNotFound=[String]::Format(
        "File: {0} not found. Please {1} '{0}'",
        "adkwinpesetup.exe",
        "navigate to the directory containing"
      )
      Write-Error $adkPeFileNotFound -ErrorAction Stop
    }else{
      if(!(Test-Path -Path $tempAdkWinPEPath)){
        mkdir $tempAdkWinPEPath -ErrorAction Stop | Out-Null
      }
    }
  } # End adk version check


  Function WaitForProcessEnd {
    [CmdletBinding()]
    Param(
      [String]$processName,

      [String]$msg
    )
    $processRunning=$true
    Write-Host $msg -NoNewline
    Do{
      Write-Host '.' -NoNewline
      Start-Sleep -Seconds 30
      $process=Get-Process -Name $processName `
        -ErrorAction SilentlyContinue
      if(!$process){
        $processRunning=$false
      }
    }While($processRunning)
  }

  Write-Verbose "Creating downloads folder structure [$Path]"
  $Path, $tempSccmPreReqPath, $tempAdkPath | Foreach { 
    if(!(Test-Path -Path $_)){
      mkdir $_ -ErrorAction Stop | Out-Null
    }
  }

  Write-Verbose "Downloading SCCM PreReq files [$tempSccmPreReqPath]"
  & $sccmSetupDlFilePath $tempSccmPreReqPath

  Write-Verbose "Downloading ADK Setup files [$tempAdkPath]"
  .\adksetup.exe /layout $tempAdkPath /q

  WaitForProcessEnd -processName adksetup `
    -msg "Downloading ADK... Will take some time"

  if($requirePEAddon){
    Write-Verbose "Downloading ADK PE Addon files [$tempAdkWinPEPath]"
    .\adkwinpesetup.exe /layout $tempAdkWinPEPath /q

    WaitForProcessEnd -processName adkwinpesetup `
      -msg "Downloading ADK WinPE addon... Will take some time"
  }
  WaitForProcessEnd -processName setupdl `
    -msg "Waiting for SCCM PreReq download to finish"

  Write-Host "PreReq Download completed. Check folder [$Path]"
}Catch{
  Write-Error $_
}

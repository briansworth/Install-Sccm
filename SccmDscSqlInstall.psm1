configuration SccmSqlInstallation {
  Param(
    [Parameter(Position=0)]
    [String]$ComputerName=$ENV:COMPUTERNAME,

    [Parameter(Position=1,Mandatory=$true)]
    [String]$SqlSourceFiles,
    
    [Parameter(Position=2)]
    [String]$SqlInstanceName='MSSQLSERVER',
    
    [Parameter(Position=3)]
    [PSCredential]$AgentSvcCredential,

    [Parameter(Position=4)]
    [PSCredential]$SqlSvcCredential,

    [Parameter(Position=5)]
    [String[]]$SysAdminAccounts=(whoami),

    [Parameter(Position=6)]
    [String]$Features='SQLENGINE',

    [Parameter(Position=7)]
    [String]$InstanceDir="$ENV:ProgramFiles\Microsoft SQL Server",

    [Parameter(Position=8)]
    [String]$DataDir,

    [Parameter(Position=9)]
    [String]$SharedDir="$ENV:ProgramFiles\Microsoft SQL Server",

    [Parameter(Position=10)]
    [String]$SharedWOWDir="${ENV:ProgramFiles(x86)}\Microsoft SQL Server",

    [Parameter(Position=11)]
    [ValidateRange(1,65535)]
    [int]$SqlPortNumber=1433
  )
  Import-DscResource -ModuleName SqlServerDsc
  Import-DscResource -ModuleName PSDesiredStateConfiguration

  node $ComputerName {

    WindowsFeature 'NetFramework' {
      Name = 'Net-Framework-45-Core';
      Ensure = 'Present';
    }

    SqlSetup 'SqlInstall' {
      InstanceName = $SqlInstanceName;
      SourcePath = $SqlSourceFiles;
      Action = 'Install';
      Features = $Features;
      InstanceDir = $InstanceDir;
      InstallSQLDataDir = $DataDir;
      InstallSharedDir=$SharedDir;
      InstallSharedWOWDir=$SharedWOWDir;
      SQLSvcStartupType = 'Automatic';
      AgtSvcStartupType = 'Automatic';
      AgtSvcAccount = $AgentSvcCredential;
      SQLSysAdminAccounts = $SysAdminAccounts;
      SQLSvcAccount = $SqlSvcCredential;
      SQLCollation = 'SQL_Latin1_General_CP1_CI_AS';
      DependsOn = '[WindowsFeature]NetFramework';
    }

    SqlServerNetwork 'SqlStaticTcp' {
      InstanceName = $SqlInstanceName;
      ProtocolName = 'TCP';
      IsEnabled = $true;
      TcpPort = "$SqlPortNumber";
      DependsOn = '[SqlSetup]SqlInstall';
    }

    # This part below can be removed # If you aren't using credentials, 
    # OR If you have opted to store credentials in Plain Text
    LocalConfigurationManager {
      CertificateId = $node.Thumbprint
    }
    # Remove to here
  }
}

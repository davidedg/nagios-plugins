#!/usr/bin/env pwsh

## NAGIOS check for Azure SQL Backup Age
## v:20220718.001
## a:Davide Del Grande
#
## MINIMUM PERMISSIONS:
# https://docs.microsoft.com/en-us/sql/relational-databases/system-dynamic-management-views/sys-dm-database-backups-azure-sql-database?view=azuresqldb-current
# https://docs.microsoft.com/en-us/sql/relational-databases/security/authentication-access/server-level-roles?view=sql-server-ver16
# https://docs.microsoft.com/en-us/azure/azure-sql/database/security-server-roles?view=azuresql
#
## on virtual master DB:
# CREATE LOGIN [monitor] WITH PASSWORD = 'enter-your-secret-pwd';
# CREATE USER [monitor] FOR LOGIN [monitor];
# ALTER SERVER ROLE ##MS_ServerStateReader##
# 	ADD MEMBER [monitor];  
# GO
# DBCC FLUSHAUTHCACHE
# GO
#
## check role assignments:
# https://docs.microsoft.com/en-us/sql/relational-databases/system-catalog-views/sys-server-role-members-transact-sql?view=sql-server-ver16#b-azure-sql-database-listing-all-principals-sql-authentication-which-are-members-of-a-server-level-role



[CmdletBinding(DefaultParameterSetName="CredsXML")]
Param (
	[Parameter(Mandatory)]
	[ValidateNotNullOrEmpty()]
    [string]
	$ServerInstance,

	[ValidateNotNullOrEmpty()]
    [string]
	$Database,

	[ValidateScript({$_ -gt 0})]
	[int]
	$ConnectionTimeout = 10,
	
	[ValidateScript({$_ -gt 0})]
	[int]
	$QueryTimeout = 10,

    [Parameter(ParameterSetName="CredsXML")]
		# $Username = "sa"
		# $Password = "...."
		# $secstr = New-Object -TypeName System.Security.SecureString
		# $Password.ToCharArray() | ForEach-Object {$secstr.AppendChar($_)}
		# $cred = new-object -typename System.Management.Automation.PSCredential -argumentlist $Username, $secstr
		# $cred | Export-Clixml '.sql-creds.xml'
    [string]
	$CredentialsXmlFile,
	
    [Parameter(ParameterSetName="CredsPlain")]
    [string]
	$Username,

    [Parameter(ParameterSetName="CredsPlain")]
    [string]
	$Password,

	[ValidateScript({$_ -ge 0})]
	[int]
	$WarnMinutes = 120,
	
	[ValidateScript({$_ -ge 0})]
	[int]
	$CritMinutes = 240,
	
	[switch]
	$InstallMissingPSModules
)



$NAG_OK = 0
$NAG_WARN = 1
$NAG_CRIT = 2
$NAG_UNKNOWN = 3

#Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'


if ($WarnMinutes -gt $CritMinutes) {
	Write-Host "ERROR: WarnMinutes must be greater than CritMinutes"
	Exit $NAG_UNKNOWN
}

try {
	Import-Module SqlServer
}
catch {
	Write-Host $( "ERROR: cannot import 'SQLServer' PS Module. [" + $_.InvocationInfo.ScriptLineNumber + "] [" + $_.Exception.Message + "]" )
	if ($InstallMissingPSModules) {
		Install-Module SqlServer -Scope CurrentUser -Force -SkipPublisherCheck
	}
	Exit $NAG_UNKNOWN
}


# Validate and Prepare Credentials
if ($PSCmdlet.ParameterSetName -eq 'CredsXML') {
	try {
		$cred = Import-CliXml $CredentialsXmlFile
	} catch {
		Write-Host $( "ERROR: cannot load credentials file. [" + $_.InvocationInfo.ScriptLineNumber + "] [" + $_.Exception.Message + "]" )
		Exit $NAG_UNKNOWN
	}
} elseif ($PSCmdlet.ParameterSetName -eq 'CredsPlain') {
	if ( -not $Username) {
		Write-Host "Username cannot be empty"
		Exit $NAG_UNKNOWN
	}
	if ( -not $Password) { $Password = "" }
	$secstr = New-Object -TypeName System.Security.SecureString
	$Password.ToCharArray() | ForEach-Object {$secstr.AppendChar($_)}
	$cred = new-object -typename System.Management.Automation.PSCredential -argumentlist $Username, $secstr
} else {
	Write-Host "ERROR: credentials not specified."
	Exit $NAG_UNKNOWN
}



# Prepare SQL QUERY
if ($Database) {
	$sqlwhere_db = "db.name = '$Database'"
} else {
	$sqlwhere_db = "db.name <> 'master'"
}

$sqlwhere_upper_timerange = $CritMinutes + 2

$Q=@"
SELECT
   TOP 1 db.name,
   backup_finish_date,
   backup_type,
   in_retention
FROM
   sys.dm_database_backups AS ddb 
   INNER JOIN sys.databases AS db ON ddb.physical_database_name = db.physical_database_name 
WHERE
   $sqlwhere_db
   AND in_retention = 1
   AND ( 
   DATEDIFF(minute,backup_finish_date,GETDATE()) between 0 and $sqlwhere_upper_timerange
   )
ORDER BY
   backup_finish_date DESC;
"@


# EXECUTE SQL QUERY
try {
	$SQLRES = Invoke-Sqlcmd -ServerInstance $ServerInstance -Database master -EncryptConnection -QueryTimeout $QueryTimeout -ConnectionTimeout $ConnectionTimeout -Credential $cred -Query $Q
} catch {
	Write-Host $( "ERROR: SQL Query returned an error: [" + $_.InvocationInfo.ScriptLineNumber + "] [" + $_.Exception.Message + "]" )
	Exit $NAG_UNKNOWN
}


# VERIFY THRESHOLDS
$NOW_UTC = [System.TimeZoneInfo]::ConvertTimeBySystemTimeZoneId((Get-Date), 'UTC')

if ($SQLRES.Length -eq 0) {
	Write-Host "CRIT: Backup has not run in selected time range"
	exit $NAG_CRIT
}


$Backup_Age = New-TimeSpan -Start $SQLRES.backup_finish_date -End $NOW_UTC
if ($Backup_Age.TotalMinutes -lt 0) {
	Write-Host "ERROR: Backup is in the future!"
	Exit $NAG_UNKNOWN
}



$disp_minutes = [math]::Round($Backup_Age.TotalMinutes)

$perfdata = "|"
$perfdata += $(" backup_age=" + $disp_minutes + ";" + $WarnMinutes + ";" + $CritMinutes)


if ($Backup_Age.TotalMinutes -ge $CritMinutes) {
	$output = "CRIT: Backup Age: " + $disp_minutes + " minute(s)"
	$exit_code = $NAG_CRIT
} elseif ($Backup_Age.TotalMinutes -ge $WarnMinutes) {
	$output = "WARN: Backup Age: " + $disp_minutes + " minute(s)"
	$exit_code = $NAG_WARN
} elseif ($Backup_Age.TotalMinutes -lt $WarnMinutes) {
	$output = "Backup Age: " + $disp_minutes + " minute(s)"
	$exit_code = $NAG_OK
}


Write-Host $output $perfdata
exit $exit_code

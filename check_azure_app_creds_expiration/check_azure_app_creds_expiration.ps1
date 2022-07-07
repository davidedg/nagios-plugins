#!/usr/bin/env pwsh

## NAGIOS check for Azure App Registration Credentials expiration
## v:20220707.002
## a:Davide Del Grande

[CmdletBinding()]
param (
	[ValidateScript({Test-Path $_})]
	[string]
	$CredentialsXmlFile = $(Join-Path $HOME '.azure-creds.xml'),
		# $clientid = "abd1..."
		# $secretvalue = "...."
		# $secstr = New-Object -TypeName System.Security.SecureString
		# $secretvalue.ToCharArray() | ForEach-Object {$secstr.AppendChar($_)}
		# $cred = new-object -typename System.Management.Automation.PSCredential -argumentlist $clientid, $secstr
		# $cred | Export-Clixml '.azure-creds.xml'

	[Parameter(Mandatory,
	HelpMessage="Enter Azure AD Tenant ID.")]
	[ValidateNotNullOrEmpty()]	
	[string]
	$TenantId,
	
	[ValidateScript({$_ -ge 0})]
	[int]
	$CritDays = 30,
	
	[ValidateScript({$_ -ge 0})]
	[int]
	$WarnDays = 60
)


$NAG_OK = 0
$NAG_WARN = 1
$NAG_CRIT = 2
$NAG_UNKNOWN = 3

#Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'


if ($WarnDays -le $CritDays) {
	Write-Host "ERROR: WarnDays must be greater than CritDays"
	Exit $NAG_UNKNOWN
}

try {
	Import-Module Az.Accounts
	Import-Module Az.Resources
}
catch {
	Write-Host $( "ERROR: cannot import PS Modules. [" + $_.InvocationInfo.ScriptLineNumber + "] [" + $_.Exception.Message + "]" )
	Exit $NAG_UNKNOWN
}

try {
	$creds = Import-CliXml $CredentialsXmlFile
} catch {
	Write-Host $( "ERROR: cannot load credentials file. [" + $_.InvocationInfo.ScriptLineNumber + "] [" + $_.Exception.Message + "]" )
	Exit $NAG_UNKNOWN
}

try {
	$WarningPreference_currvalue = $WarningPreference
	$WarningPreference = 'SilentlyContinue'
	$acct = $(Connect-AzAccount -ServicePrincipal -Scope Process -Credential $creds -Tenant $TenantId)
	$WarningPreference = $WarningPreference_currvalue
} catch {
	Write-Host $( "ERROR: cannot connect to Azure Account. [" + $_.InvocationInfo.ScriptLineNumber + "] [" + $_.Exception.Message + "]" )
	Exit $NAG_UNKNOWN
}

if ($acct.Context.Tenant.Id -notlike $TenantId) {
	Write-Host "ERROR: Tenant ID Mismatch."
	Exit $NAG_UNKNOWN	
}

$TODAY = Get-Date




try {
	$apps = Get-AzADApplication
} catch {
	Write-Host $( "ERROR: cannot retrieve AAD Applications. [" + $_.InvocationInfo.ScriptLineNumber + "] [" + $_.Exception.Message + "]" )
	Exit $NAG_UNKNOWN
}

if ($apps.length -eq 0) {
	Write-Host "No Registered Applications found. | total_credentials=0 expiring_credentials=0"
	Exit $NAG_OK
}

$Expiring_W = @()
$Expiring_C = @()


foreach ($app in $apps) {
	try {

		$app.PasswordCredentials | % {
			$pwdcred = $_
			$days_remaining = (New-TimeSpan -Start $TODAY -End $pwdcred.endDateTime).Days
			if ($days_remaining -gt $WarnDays) {return} ## continue of foreach-object (%) pipeline
			
			$entry = [PSCustomObject] @{
					AppName = $app.DisplayName
					AppObjId = $app.Id
					AppId = $app.AppId
					CredName = $pwdcred.displayName
					CredId = $pwdcred.keyId
					CredEnd = $pwdcred.endDateTime
					DaysRemaining = $days_remaining
				}
			
			if (($days_remaining -le $WarnDays) -and ($days_remaining -gt $CritDays)) {
				$Expiring_W += $entry
			} elseif ($days_remaining -le $CritDays) {
				$Expiring_C += $entry
			} else {
				Write-Host "ERROR: unexpected condition while checking for expiration."
				Exit $NAG_UNKNOWN
			}
		}
	} catch {
		Write-Host $( "ERROR: exception in code. [" + $_.InvocationInfo.ScriptLineNumber + "] [" + $_.Exception.Message + "]" )
		Exit $NAG_UNKNOWN		
	}
}

$perfdata = "|"
$perfdata += $(" total_credentials=" + $($apps.PasswordCredentials.Length))
$perfdata += $(" expiring_credentials=" + $($Expiring_C.Length + $Expiring_W.Length) )


if ($Expiring_C.Length -gt 0) {
	if ($Expiring_C.Length -eq 1) {
		$output = "CRIT: 1 credential is expiring soon." 
	} else {
		$output = $("CRIT: " + $Expiring_C.Length + " credentials are expiring soon." )
	}
	Write-Host $output $perfdata
	Exit $NAG_CRIT
} elseif ($Expiring_W.Length -gt 0) {
	if ($Expiring_W.Length -eq 1) {
		$output = "WARN: 1 credential will expire." 
	} else {
		$output = $("WARN: " + $Expiring_W.Length + " credentials will expire." )
	}
	Write-Host $output $perfdata
	Exit $NAG_WARN
} else {
	Write-Host "No expiring credentials found." $perfdata
	Exit $NAG_OK
}

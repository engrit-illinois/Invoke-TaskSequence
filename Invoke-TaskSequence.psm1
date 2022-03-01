function Invoke-TaskSequence {
	param(
		[Parameter(Mandatory=$true)]
		[string[]]$ComputerNames,
		
		[Parameter(Mandatory=$true)]
		[string]$TsDeploymentId,
		
		[DateTime]$DelayUntilDateTime,
		
		[switch]$DontTriggerImmediately,
		
		[switch]$TestRun,
		
		[switch]$Confirm,
		
		[string]$SiteCode="MP0",
		[string]$Provider="sccmcas.ad.uillinois.edu",
		[string]$CMPSModulePath="$($ENV:SMS_ADMIN_UI_PATH)\..\ConfigurationManager.psd1",
		
		# ":ENGRIT:" will be replaced with "c:\engrit\logs\$($MODULE_NAME)_:TS:.log"
		# ":TS:" will be replaced with start timestamp
		[string]$Log,

		[switch]$NoConsoleOutput,
		[string]$Indent = "    ",
		[string]$LogFileTimestampFormat = "yyyy-MM-dd_HH-mm-ss",
		[string]$LogLineTimestampFormat = "[HH:mm:ss] ",
		[int]$Verbosity = 0
	)
	
	# Logic to determine final filename
	$MODULE_NAME = "Invoke-TaskSequence"
	$ENGRIT_LOG_DIR = "c:\engrit\logs"
	$ENGRIT_LOG_FILENAME = "$($MODULE_NAME)_:TS:"
	$START_TIMESTAMP = Get-Date -Format $LogFileTimestampFormat

	if($Log) {
		$Log = $Log.Replace(":ENGRIT:","$($ENGRIT_LOG_DIR)\$($ENGRIT_LOG_FILENAME).log")
		$Log = $Log.Replace(":TS:",$START_TIMESTAMP)
	}

	# Actual log function
	function log {
		param (
			[Parameter(Position=0)]
			[string]$Msg = "",

			[int]$L = 0, # level of indentation
			[int]$V = 0, # verbosity level

			[ValidateScript({[System.Enum]::GetValues([System.ConsoleColor]) -contains $_})]
			[string]$FC = (get-host).ui.rawui.ForegroundColor, # foreground color
			[ValidateScript({[System.Enum]::GetValues([System.ConsoleColor]) -contains $_})]
			[string]$BC = (get-host).ui.rawui.BackgroundColor, # background color

			[switch]$E, # error
			[switch]$NoTS, # omit timestamp
			[switch]$NoNL, # omit newline after output
			[switch]$NoConsole, # skip outputting to console
			[switch]$NoLog # skip logging to file
		)

		if($E) { $FC = "Red" }

		# Custom indent per message, good for making output much more readable
		for($i = 0; $i -lt $L; $i += 1) {
			$Msg = "$Indent$Msg"
		}

		# Add timestamp to each message
		# $NoTS parameter useful for making things like tables look cleaner
		if(!$NoTS) {
			if($LogLineTimestampFormat) {
				$ts = Get-Date -Format $LogLineTimestampFormat
			}
			$Msg = "$ts$Msg"
		}

		# Each message can be given a custom verbosity ($V), and so can be displayed or ignored depending on $Verbosity
		# Check if this particular message is too verbose for the given $Verbosity level
		if($V -le $Verbosity) {

			# Check if this particular message is supposed to be logged
			if(!$NoLog) {

				# Check if we're allowing logging
				if($Log) {

					# Check that the logfile already exists, and if not, then create it (and the full directory path that should contain it)
					if(-not (Test-Path -PathType "Leaf" -Path $Log)) {
						New-Item -ItemType "File" -Force -Path $Log | Out-Null
						log "Logging to `"$Log`"."
					}

					if($NoNL) {
						$Msg | Out-File $Log -Append -NoNewline
					}
					else {
						$Msg | Out-File $Log -Append
					}
				}
			}

			# Check if this particular message is supposed to be output to console
			if(!$NoConsole) {

				# Check if we're allowing console output
				if(!$NoConsoleOutput) {

					if($NoNL) {
						Write-Host $Msg -NoNewline -ForegroundColor $FC -BackgroundColor $BC
					}
					else {
						Write-Host $Msg -ForegroundColor $FC -BackgroundColor $BC
					}
				}
			}
		}
	}
	
	function Prep-MECM {
		log "Preparing connection to MECM..."
		$success = $true
		
		$initParams = @{}
		
		log "Importing ConfigurationManager PowerShell module..." -L 1
		if((Get-Module ConfigurationManager) -eq $null) {
			# The ConfigurationManager Powershell module switched filepaths at some point around CB 18##
			# So you may need to modify this to match your local environment
			try {
				Import-Module $CMPSModulePath @initParams -Scope Global -ErrorAction "Stop"
			}
			catch {
				log "Failed to import ConfigurationManager PowerShell module!" -E -L 2
				$success = $false
			}
		}
		else {
			log "ConfigurationManager PowerShell module already imported." -L 2
		}
		
		if($success) {
			log "Connecting to MECM site provider drive..." -L 1
			if((Get-PSDrive -Name $SiteCode -PSProvider CMSite -ErrorAction SilentlyContinue) -eq $null) {
				try {
					New-PSDrive -Name $SiteCode -PSProvider CMSite -Root $Provider @initParams -ErrorAction "Stop"
				}
				catch {
					log "Failed to connect to MECM site provider drive!" -E -L 2
					$success = $false
				}
			}
			else {
				log "Already connected to MECM site provider drive." -L 2
			}
		}
		
		if($success) {
			Set-Location "$($SiteCode):\" @initParams
			log "Done prepping connection to MECM." -L 1
		}
		else {
			log "MECM connection prep did not succeed!" -L 1 -E
		}
		
		$success
	}
	
	function Get-DelayInSeconds {
		log "Getting delay in seconds..." -L 1
		$now = Get-Date
		log "It is now: `"$now`"." -L 2
		$delay = $DelayUntilDateTime - $now
		$secondsTotal = $delay.TotalSeconds
		$seconds = [int]$secondsTotal
		log "Rounded number of seconds is: `"$seconds`"." -L 2
		
		$seconds
	}
	
	function Do-Delay {
		$validDelay = $true
		
		if($DelayUntilDateTime) {
			log "-DelayUntilDateTime was specified."
			log "Specified time is: `"$DelayUntilDateTime`"." -L 1
			
			$delaySeconds = Get-DelayInSeconds
			
			if($delaySeconds -le 1) {
				log "The value specified for -DelayUntilDateTime was calculated to be `"$(0 - $delaySeconds)`" seconds in the past! Enter a valid future DateTime for -DelayUntilDateTime, or omit it to run immediately." -L 1
				$validDelay = $false
			}
			else {
				log "Delaying `"$delaySeconds`" seconds until `"$DelayUntilDateTime`"..." -L 1
				Start-Sleep -Seconds $delaySeconds
				log "Delay complete." -L 2
			}
		}
		else {
			log "-DelayUntilDateTime was not specified."
		}
		
		if(-not $validDelay) {
			log "Invalid delay!" -E -L 1
		}
		
		$validDelay
	}
	
	function Get-ScriptBlock {
		$scriptBlock = {
			param(
				$dep,
				[bool]$DontTriggerImmediately=$false,
				[bool]$TestRun=$false,
				[string]$LogLineTimestampFormat,
				[string]$Indent
			)
			
			function log {
				param (
					[Parameter(Position=0)]
					[string]$Msg = "",

					[int]$L = 0, # level of indentation
					[switch]$NoTS # omit timestamp
				)

				# Custom indent per message, good for making output much more readable
				$L2 = $L + 2
				for($i = 0; $i -lt $L2; $i += 1) {
					$Msg = "$Indent$Msg"
				}

				# Add timestamp to each message
				# $NoTS parameter useful for making things like tables look cleaner
				if(!$NoTS) {
					if($LogLineTimestampFormat) {
						$ts = Get-Date -Format $LogLineTimestampFormat
					}
					$Msg = "$ts$Msg"
				}
				
				Write-Information $Msg
			}
			
			function Get-TsAd {
				log "Retrieving local TS advertisements from WMI..."
				$tsAds = Get-CimInstance -Namespace "root\ccm\policy\machine\actualconfig" -Class "CCM_TaskSequence"
				
				if(-not $tsAds) {
					log "Failed to retrieve local TS advertisements from WMI!" -L 1
				}
				else {
					log "Getting local advertisement for deployment `"$($dep.DeploymentID)`" of TS `"$($dep.PackageID)`"..." -L 1
					$tsAd = $tsAds | Where-Object { ($_.PKG_PackageID -eq $dep.PackageID) -and ($_.ADV_AdvertisementID -eq $dep.DeploymentID) }
					
					if(-not $tsAd) {
						log "Failed to get local advertisement!" -L 2
					}
					else {
						log "ADV_RepeatRunBehavior is currently set to `"$($tsAd.ADV_RepeatRunBehavior)`"." -L 2
						log "ADV_MandatoryAssignments is currently set to `"$($tsAd.ADV_MandatoryAssignments)`"." -L 2
					}
				}
				
				$tsAd
			}
			
			function Set-TsAd($tsAd) {
				log "Modifying local advertisement..."
				$tsAd = Set-RerunAlways $tsAd
				$tsAd = Set-Mandatory $tsAd
				$tsAd
			}
			
			function Set-RerunAlways($tsAd) {
				# Set the RepeatRunBehavior property of this local advertisement to trick the client into thinking it should always rerun, regardless of previous success/failure
				if($tsAd.ADV_RepeatRunBehavior -notlike "RerunAlways") {
					log "Changing ADV_RepeatRunBehavior to `"RerunAlways`"." -L 1
					
					if($TestRun) {
						log "-TestRun was specified. Skipping modification of ADV_RepeatRunBehavior." -L 1
					}
					else {
						$tsAd.ADV_RepeatRunBehavior = "RerunAlways"
						$tsAd = Set-CimInstance -CimInstance $tsAd -PassThru
						if($tsAd.ADV_RepeatRunBehavior -notlike "RerunAlways") {
							log "Failed to change ADV_RepeatRunBehavior!" -L 2
						}
						else {
							log "Successfully changed ADV_RepeatRunBehavior." -L 2
						}
					}
				}
				else {
					log "No need to change ADV_RepeatRunBehavior." -L 1
				}
				
				$tsAd
			}
			
			function Set-Mandatory($tsAd) {
				# Set the MandatoryAssignments property of this local advertisement to trick the client into thinking it's a Required deployment, regardless of whether it actually is
				if($tsAd.ADV_MandatoryAssignments -ne $true) {
					log "Changing ADV_MandatoryAssignments to `"$true`"." -L 1
					
					if($TestRun) {
						log "-TestRun was specified. Skipping modification of ADV_MandatoryAssignments." -L 1
					}
					else {
						$tsAd.ADV_MandatoryAssignments = $true
						$tsAd = Set-CimInstance -CimInstance $tsAd -PassThru
						if(-not $tsAd.ADV_MandatoryAssignments) {
							log "Failed to change ADV_MandatoryAssignments!" -L 2
						}
						else {
							log "Successfully changed ADV_MandatoryAssignments." -L 2
						}
					}
				}
				else {
					log "No need to change ADV_MandatoryAssignments." -L 1
				}
				
				$tsAd
			}
			
			function Get-ScheduleId {
				# Get the schedule for the newly modified advertisement
				log "Retrieving scheduler history from WMI..." -L 1
				$schedulerHistory = Get-CimInstance -Namespace "root\ccm\scheduler" -Class "CCM_Scheduler_History"
				
				if(-not $schedulerHistory) {
					log "Failed to retrieve scheduler history from WMI!" -L 2
				}
				else {
					
					log "Getting schedule for local TS advertisement..." -L 2
					# ScheduleIDs look like "<DeploymentID>-<PackageID>-<ScheduleID>"
					$scheduleId = $schedulerHistory | Where-Object { ($_.ScheduleID -like "*$($dep.PackageID)*") -and ($_.ScheduleID -like "*$($dep.DeploymentID)*") } | Select-Object -ExpandProperty ScheduleID
					
					if(-not $scheduleId) {
						log "Failed to get schedule for local TS advertisement!" -L 3
					}
				}
				
				$scheduleId
			}
			
			function Trigger-TS($scheduleId) {
				# Get the schedule for the newly modified advertisement and trigger it to run
				log "Triggering TS..."
				
				if($TestRun) {
					log "-TestRun was specified. Skipping triggering TS." -L 1
				}
				else {
					if($DontTriggerImmediately) {
						log "-DontTriggerImmediately was specified. TS should be triggered on deployment schedule during next deployment evaluation." -L 1
					}
					else {
						log "Triggering schedule for newly-modified local advertisement..." -L 1
						Invoke-WmiMethod -Namespace "root\ccm" -Class "SMS_Client" -Name "TriggerSchedule" -ArgumentList $scheduleID
					}
				}
			}
			
			function Do-Stuff {
				$tsAd = Get-TsAd
				if($tsAd) {
					$tsAd = Set-TsAd $tsAd
					$scheduleId = Get-ScheduleId
					if($scheduleId) {
						Trigger-TS $scheduleId
					}
				}
			}
			
			Do-Stuff
			
			log "EOS"
		}
		
		$scriptBlock
	}
	
	function Do-Session($comp, $dep) {
		log "Starting PSSession to `"$comp`"..."
		$session = New-PSSession -ComputerName $comp
		
		log "Sending commands to session..." -L 1
		log "------------------------------" -L 1
		log " " -NoTS
		#$scriptBlock = Get-TestScriptBlock
		$scriptBlock = Get-ScriptBlock
		
		if($Log) {
			Invoke-Command -Session $session -ScriptBlock $scriptBlock -ArgumentList $dep,$DontTriggerImmediately,$TestRun,$LogLineTimestampFormat,$Indent 6>&1 | Tee-Object -FilePath $Log -Append
		}
		else {
			Invoke-Command -Session $session -ScriptBlock $scriptBlock -ArgumentList $dep,$DontTriggerImmediately,$TestRun,$LogLineTimestampFormat,$Indent 6>&1
		}
		log " " -NoTS
		log "------------------------------" -L 1
		log "Done sending commands to session." -L 1
		
		log "Ending session..." -L 1
		Remove-PSSession $session
		log "Session ended." -L 1
	}
	
	function Log-Inputs {
		log "Inputs:"
		$names = $ComputerNames -join "`",`""
		log "-ComputerNames: `"$names`"." -L 1
		log "-TsDeploymentId: `"$TsDeploymentId`"." -L 1
		log "-DelayUntilDateTime: `"$DelayUntilDateTime`"." -L 1
		log "-DontTriggerImmediately: `"$DontTriggerImmediately`"." -L 1
		log "-TestRun: `"$TestRun`"." -L 1
	}
	
	function Get-IntentString($intent) {
		$string = "unknown"
		# https://docs.microsoft.com/en-us/mem/configmgr/develop/reference/apps/sms_appdeploymentassetdetails-server-wmi-class
		switch($intent) {
			"1" { $string = "Required" }
			"2" { $string = "Available" }
			"3" { $string = "Simulate" }
			default { $string = "unrecognized" }
		}
		$string
	}
	
	function Get-ConfigTypeString($configType) {
		$string = "unknown"
		# https://docs.microsoft.com/en-us/mem/configmgr/develop/reference/compliance/sms_ciassignmentbaseclass-server-wmi-class
		# https://stackoverflow.com/questions/14748402/uninstalling-applications-using-sccm-sdk
		switch($configType) {
			"1" { $string = "REQUIRED (a.k.a. `"Install`")" }
			"2" { $string = "NOT_ALLOWED (a.k.a. `"Uninstall`")" }
			default { $string = "unrecognized" }
		}
		$string
	}
	
	function Get-FeatureTypeString($featureType) {
		$string = "unknown"
		# https://docs.microsoft.com/en-us/mem/configmgr/develop/reference/apps/sms_deploymentsummary-server-wmi-class
		switch($featureType) {
			"1" { $string = "Application" }
			"2" { $string = "Program" }
			"3" { $string = "MobileProgram" }
			"4" { $string = "Script" }
			"5" { $string = "SoftwareUpdate" }
			"6" { $string = "Baseline" }
			"7" { $string = "TaskSequence" }
			"8" { $string = "ContentDistribution" }
			"9" { $string = "DistributionPointGroup" }
			"10" { $string = "DistributionPointHealth" }
			"11" { $string = "ConfigurationPolicy" }
			"28" { $string = "AbstractConfigurationItem" }
			default { $string = "unrecognized" }
		}
		$string
	}
	
	function Get-ObjectTypeString($objectType) {
		$string = "unknown"
		# https://docs.microsoft.com/en-us/mem/configmgr/develop/reference/apps/sms_deploymentsummary-server-wmi-class
		switch($objectType) {
			"200" { $string = "SMS_CIAssignment" }
			"201" { $string = "SMS_Advertisement" }
			default { $string = "unrecognized" }
		}
		$string
	}
	
	function Get-Dep {
		log "Retrieving data for deployment `"$TsDeploymentId`"..."
		
		$dep = Get-CMDeployment -DeploymentId $TsDeploymentId
		if($dep) {
			log "Found deployment:" -L 1
			log "ApplicationName: `"$($dep.ApplicationName)`" (`"$($dep.PackageID)`")." -L 2
			log "CollectionName: `"$($dep.CollectionName)`" (`"$($dep.CollectionID)`")." -L 2
			$intent = Get-IntentString $dep.DeploymentIntent
			log "DeploymentIntent (a.k.a. `"Purpose`"): `"$($dep.DeploymentIntent)`" (`"$intent`")." -L 2
			$configType = Get-ConfigTypeString $dep.DesiredConfigType
			log "DesiredConfigType (a.k.a. `"Action`"): `"$($dep.DesiredConfigType)`" (`"$configType`")." -L 2
			$featureType = Get-FeatureTypeString $dep.FeatureType
			log "FeatureType: `"$($dep.FeatureType)`" (`"$featureType`")." -L 2
			$objectType = Get-ObjectTypeString $dep.ObjectTypeID
			log "ObjectTypeID: `"$($dep.ObjectTypeID)`" (`"$objectType`")." -L 2
		}
		
		$dep
	}
	
	function Test-Dep($dep) {
		$test = $false
		
		if($dep) {
			if($dep.FeatureType -eq "7") {
				$test = $true
			}
			else {
				log "Deployment is not a Task Sequence!" -E
			}
		}
		else {
			log "Failed to retrieve deployment from MECM!" -E
		}
		
		$test
	}
	
	function Test-Confirm($dep) {
		$manualConfirm = $false
		
		if(-not $Confirm) {
			$num = @($ComputerNames).count
			log "Review the above information. Are you sure you want to invoke this deployment on $num computers? Enter y or n: " -FC "yellow" -NoNL
			$input = Read-Host
			
			if(
				($input -eq "y") -or
				($input -eq "Y")
			) {
				$manualConfirm = $true
				log "User confirmed." -FC "green" -L 1
			}
			else {
				log "User aborted!" -E -L 1
			}
		}
		else {
			log "-Confirm was specified. Skipping manual confirmation."
			$manualConfirm = $true
		}
		
		$manualConfirm
	}
	
	function Do-Stuff {
		Log-Inputs
		
		$myPWD = $pwd.path
		if(Prep-MECM) {
			$dep = Get-Dep
			Set-Location $myPWD
			
			if(Test-Dep $dep) {
				if(Test-Confirm $dep) {
					if(Do-Delay) {
						$ComputerNames | ForEach-Object {
							Do-Session $_ $dep
						}
					}
				}
			}
		}
	}
	
	Do-Stuff
	
	log "EOF"
}

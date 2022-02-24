function Invoke-TaskSequence {
	param(
		[Parameter(Mandatory=$true)]
		[string]$ComputerName,
		
		[Parameter(Mandatory=$true)]
		[string]$TsPackageId,
		
		[Parameter(Mandatory=$true)]
		[string]$TsDeploymentId,
		
		[DateTime]$DelayUntilDateTime,
		
		[switch]$TriggerImmediately,
		
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

	function Get-DelayInSeconds {
		log "Getting delay in seconds..." -L 1
		$now = Get-Date
		$delay = $DelayUntilDateTime - $now
		$secondsTotal = $delay.TotalSeconds
		$seconds = [int]$secondsTotal
		log "Rounded number of seconds is: `"$seconds`"." -L 2
		
		$seconds
	}
	
	function Do-Delay {
		if($DelayUntilDateTime) {
			log "-DelayUntilDateTime was specified."
			log "It is now: `"$now`"." -L 1
			log "Specified time is: `"$DelayUntilDateTime`"." -L 1
			
			$delaySeconds = Get-DelayInSeconds
			
			if($delaySeconds -le 1) {
				log "The value specified for -DelayUntilDateTime is in the past. Delay will be skipped." -L 1
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
	}
	
	function Get-ScriptBlock {
		$scriptBlock = {
			param(
				[string]$TsPackageId,
				[string]$TsDeploymentId,
				[bool]$TriggerImmediately=$false
			)
			
			function Get-TsAd {
				Write-Output "Retrieving local TS advertisements from WMI..."
				$tsAds = Get-CimInstance -Namespace "root\ccm\policy\machine\actualconfig" -Class "CCM_TaskSequence"
				
				if(-not $tsAds) {
					Write-Output "    Failed to retrieve local TS advertisements from WMI!"
				}
				else {
					Write-Output "Getting local advertisement for deployment `"$($TsDeploymentId)`" of TS `"$($TsPackageId)`"..."
					$tsAd = $tsAds | Where-Object { ($_.PKG_PackageID -eq $TsPackageId) -and ($_.ADV_AdvertisementID -eq $TsDeploymentId) }
					
					if(-not $tsAd) {
						Write-Output "    Failed to get local advertisement!"
					}
				}
				
				$tsAd
			}
			
			function Set-TsAd($tsAd) {
				Write-Output "Modifying local advertisement..."
				$tsAd = Set-RerunAlways $tsAd
				$tsAd = Set-Mandatory $tsAd
				$tsAd
			}
			
			function Set-RerunAlways($tsAd) {
				# Set the RepeatRunBehavior property of this local advertisement to trick the client into thinking it should always rerun, regardless of previous success/failure
				Write-Output "    ADV_RepeatRunBehavior is currently set to `"$($tsAd.ADV_RepeatRunBehavior)`"."
				if($tsAd.ADV_RepeatRunBehavior -notlike "RerunAlways") {
					Write-Output "        Changing ADV_RepeatRunBehavior to `"RerunAlways`"."
					$tsAd.ADV_RepeatRunBehavior = "RerunAlways"
					$tsAd = Set-CimInstance -CimInstance $tsAd -PassThru
					Write-Output "        ADV_RepeatRunBehavior is now set to `"$($tsAd.ADV_RepeatRunBehavior)`"."
				}
				else {
					Write-Output "        No need to change ADV_RepeatRunBehavior."
				}
				
				$tsAd
			}
			
			function Set-Mandatory($tsAd) {
				# Set the MandatoryAssignments property of this local advertisement to trick the client into thinking it's a Required deployment, regardless of whether it actually is
				Write-Output "    ADV_MandatoryAssignments is currently set to `"$($tsAd.ADV_MandatoryAssignments)`"."
				if($tsAd.ADV_MandatoryAssignments -ne $true) {
					Write-Output "        Changing ADV_MandatoryAssignments to `"$true`"."
					$tsAd.ADV_MandatoryAssignments = $true
					$tsAd = Set-CimInstance -CimInstance $tsAd -PassThru
					Write-Output "        ADV_MandatoryAssignments is now set to `"$($tsAd.ADV_MandatoryAssignments)`"."
				}
				else {
					Write-Output "        No need to change ADV_MandatoryAssignments."
				}
				
				$tsAd
			}
			
			function Get-ScheduleId {
				# Get the schedule for the newly modified advertisement
				Write-Output "    Retrieving scheduler history from WMI..."
				$schedulerHistory = Get-CimInstance -Namespace "root\ccm\scheduler" -Class "CCM_Scheduler_History"
				
				if(-not $schedulerHistory) {
					Write-Output "        Failed to retrieve scheduler history from WMI!"
				}
				else {
					
					Write-Output "    Getting schedule for local TS advertisement..."
					# ScheduleIDs look like "<DeploymentID>-<PackageID>-<ScheduleID>"
					$scheduleId = $schedulerHistory | Where-Object { ($_.ScheduleID -like "*$($TsPackageId)*") -and ($_.ScheduleID -like "*$($TsDeploymentId)*") } | Select-Object -ExpandProperty ScheduleID
					
					if(-not $scheduleId) {
						Write-Output "        Failed to get schedule for local TS advertisement!"
					}
				}
				
				$scheduleId
			}
			
			function Trigger-TS($scheduleId) {
				# Get the schedule for the newly modified advertisement and trigger it to run
				Write-Output "Triggering TS..."
				
				if(-not $TriggerImmediately) {
					Write-Output "-TriggerImmediately was NOT specified. TS should be triggered on next deployment evaluation."
				}
				else {
					Write-Output "-TriggerImmediately was specified. Triggering schedule for newly-modified local advertisement..."
					Invoke-WmiMethod -Namespace "root\ccm" -Class "SMS_Client" -Name "TriggerSchedule" -ArgumentList $scheduleID
				}
			}
			
			function Do-Stuff {
				Write-Output "test2"
				$tsAd = Get-TsAd
				if($tsAd) {
					if($TriggerImmediately) {
						$scheduleId = Get-ScheduleId
						if($scheduleId) {
							Trigger-TS $scheduleId
						}
					}
					else {
						$tsAd = Set-TsAd $tsAd
					}
				}
				Write-Output "test3"
			}
			
			Write-Output "test1"
			Do-Stuff
			Write-Output "test4"
		}
		
		$scriptBlock
	}
	
	function Get-TestScriptBlock {
		$scriptBlock = {
			getmac
		}
		
		$scriptBlock
	}
	
	function Do-Session {
		log "Starting PSSession to `"$ComputerName`"..."
		$session = New-PSSession -ComputerName $ComputerName
		
		log "Sending commands to session..." -L 1
		#$scriptBlock = Get-TestScriptBlock
		$scriptBlock = Get-ScriptBlock
		$output = Invoke-Command -Session $session -ScriptBlock $scriptBlock -ArgumentList $TsPackageId,$TsDeploymentId,$TriggerImmediately
		log "Done sending commands to session." -L 1
		
		log "Ending session..." -L 1
		Remove-PSSession $session
		log "Session ended." -L 1
		
		log "Session output:" -L 1
		log "--------------------" -L 1
		log "" -NoTS
		log ($output | Out-String) -NoTS
		log "" -NoTS
		log "--------------------" -L 1
	}
	
	function Do-Stuff {
		Do-Delay
		Do-Session
	}
	
	Do-Stuff
	
	log "EOF"
}
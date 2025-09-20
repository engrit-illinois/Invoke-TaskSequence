# Summary
Triggers an MECM Task Sequence (TS) on one or more remote machines by communicating directly with the machines' MECM client, optionally after a configurable delay.  

# Behavior
This is accomplished on each machine by:  
1. Entering a remote powershell session to the target machine.
2. Modifying the target deployment's local assignment (a.k.a. advertisement) data stored in WMI to trick it into thinking the target TS deployment is _Required_, and that it has never been run before.
3. Triggering the "schedule" for the newly-modified assignment, which causes the TS to start.

# Caveats and gotchas
Because this relies on the mechanism described above, this only works for TSe deployed to "Configuration Manager Clients". So it doesn't work for TSes which are only deployed to "media and PXE". Also, this is primarily intended for running TSes deployed as _Available_, on demand. It may work for TSes deployed as _Required_, but this is not fully tested.  

Similarly, it will also only work if the target endpoints are in their maintenance window period (unless no maintenance windows are configured, in which case it should work immediately). In theory, executing the module against an endpoint while outside of the endpoint's maintenance window should cause the TS to wait and start immediately once the endpoint enters its maintenance window. However as this can be a risky proposition, that's why the delay parameters are provided. It should be kept in mind that if the TS does not immediately start (due to the endpoint being being in its maintenance window), the module will still affect the changes noted above, and the client will remain "tricked" into thinking the TS is _Required_ and scheduled.  

As such if you're not aware that a maintenance window is not active it can seem as though the module fails to work, and you may be surprised to see the endpoint begin the task sequence later, once the maintenance window starts. Alternatively, it's possible (though unconfirmed) that an update to client policy could partially or wholly revert the WMI changes, meaning the endpoint may _not_ start the TS upon entering a maintenance window as expected. Because of all of this potential confusion, it's recommended to only use the module to initiate a TS while a machine's maintenance window is already in effect (or use the scheduling parameters accordingly).  

# Usage
1. Download `Invoke-TaskSequence.psm1` to the appropriate subdirectory of your PowerShell [modules directory](https://github.com/engrit-illinois/how-to-install-a-custom-powershell-module).
2. Run it using the examples and documentation provided below.

# Examples

### Run on one machine
`Invoke-TaskSequence -ComputerNames "comp-name-01" -TsDeploymentId "MP02137A" -Log ":ENGRIT:"`

### Wait for a given delay, and then run on one machine
`Invoke-TaskSequence -ComputerNames "comp-name-01" -TsDeploymentId "MP02137A" -DelayUntilDateTime "2050-01-01 23:00:00" -Log ":ENGRIT:"`

### Run on multiple specific machines
`Invoke-TaskSequence -ComputerNames "comp-name-01","comp-name-37" -TsDeploymentId "MP02137A" -Log ":ENGRIT:"`

### Run on multiple sequentially-named lab machines
The below example will run on computers `comp-name-0` through `comp-name-9`.  
```powershell
$comps = @(0..9) | ForEach-Object {
	"comp-name-$($_)"
}
Invoke-TaskSequence -ComputerNames $comps -TsDeploymentId "MP02137A" -Log ":ENGRIT:"
```

The below example will run on computers `comp-name-01` through `comp-name-10`.  
```powershell
$comps = @(1..10) | ForEach-Object {
	$num = ([string]$_).PadLeft(2,"0")
	"comp-name-$($num)"
}
Invoke-TaskSequence -ComputerNames $comps -TsDeploymentId "MP02137A" -Log ":ENGRIT:"
```

### Find the TS deployment (a.k.a. "advertisement") ID of the deployment(s) for a given TS
```powershell
$tsName = "UIUC-ENGR-Instructional Win11 2025a v2.3g"
$ts = Get-CMTaskSequence -Fast -Name $tsName
$ts | Select Name,PackageId | Out-Host
$tsPackageId = $ts.PackageId
$tsDeployment = Get-CMTaskSequenceDeployment -Fast -TaskSequenceId $tsPackageId
$tsDeployment | Select AdvertisementName,PackageId,AdvertisementId | Out-Host
```

# Parameters

### -ComputerNames \<string[]\>
Required string array.  
An array of strings representing one or more names of computers to target.  

### -TsDeploymentId \<string\>
Required string.  
The DeploymentID of the desired deployment of the desired TS.  
Get this from the MECM console.  
This is necessary in case there are multiple deployments of the same TS.  

### -DelayUntilDateTime \<DateTime\>
Optional DateTime.  
A string in a valid DateTime format, representing when to perform the operations on the remote machine(s).  
The script will wait until this time before doing anything.  
The given time must be in the future, or the script will give a warning and exit without performing any operations.  
It's recommended to use an unambiguous format such as `"2022-01-01 13:00:00"`.  

### -DontTriggerImmediately
Optional switch.  
When specified, skips triggering the assignment's schedule.  
Theoretically, this should mean the deployment will get run the next time the client evaluates its deployments.  
This may only be the case for _Required_ deployments, and possibly only when they have a schedule configured. I've not seen it work for _Available_ deployments.  
Not recommended. Rely on this at your own risk.  
I will do more testing with _Required_ deployments in the future.  

### -TestRun
Optional switch.  
When specified, the script operates as normal, except it skips performing any operations which actually have an effect on the remote machine(s).  
This includes the modification of the deployment's local assignment data, and the triggering of the assignment's schedule.  
Useful to get a report of whether the given TS/Deployment exists in the remote machine's local assignment data, and how it is currently configured.  

### -Confirm
Optional switch.  
When omitted, the script will pause to ask for confirmation, after displaying information about the given deployment.  
When specified, this manual confirmation is skipped.  

### -SiteCode
Optional string, representing the Site Code ID for your SCCM site.  
Default value is `MP0`, because that's the author's site.  
You can change the default value near the top of the script.  

### -Provider
Optional string, representing the hostname of your provider.  
Use whatever you use in the console GUI application.  
Default value is `sccmcas.ad.uillinois.edu`, because that's the author's provider.  
You can change the default value near the top of the script.  

### -CMPSModulePath
Optional string, representing the local path where the ConfigurationManager Powershell module exists.  
Default value is `$($ENV:SMS_ADMIN_UI_PATH)\..\ConfigurationManager.psd1`, because there's where it is for us.  
You may need to change this, depending on your SCCM (Console) version. The path has changed across various versions of SCCM, but the environment variable used by default should account for those changes in most cases.  
You can change the default value near the top of the script.  

### -Log \<string\>
Optional string.  
The full path of a file to log to.  
If omitted, no log will be created.  
If `:TS:` is given as part of the string, it will be replaced by a timestamp of when the script was started, with a format specified by `-LogFileTimestampFormat`.  
Specify `:ENGRIT:` to use a default path (i.e. `c:\engrit\logs\Invoke-TaskSequence_<timestamp>.log`).  

### -NoConsoleOutput
Optional switch.  
If specified, progress output is not logged to the console.  

### -Indent \<string\>
Optional string.  
The string used as an indent, when indenting log entries.  
Default is four space characters.  

### -LogFileTimestampFormat \<string\>
Optional string.  
The format of the timestamp used in filenames which include `:TS:`.  
Default is `yyyy-MM-dd_HH-mm-ss`.  

### -LogLineTimestampFormat \<string\>
Optional string.  
The format of the timestamp which prepends each log line.  
Default is `[HH:mm:ss]⎵`.  

### -Verbosity \<int\>
Optional integer.  
The level of verbosity to include in output logged to the console and logfile.  
Currently not significantly implemented.  
Default is `0`.  

# Notes
- Useful source information: https://msendpointmgr.com/2019/02/14/how-to-rerun-a-task-sequence-in-configmgr-using-powershell/
- By mseng3. See my other projects here: https://github.com/mmseng/code-compendium.

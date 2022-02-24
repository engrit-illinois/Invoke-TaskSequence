# THIS SCRIPT IS A WORK IN PROGRESS

# Summary
Triggers an MECM Task Sequence (TS) deployed by communicating directly with a machine's MECM client.

# Usage
WIP

# Examples

### Run on one machine
`Invoke-TaskSequence -ComputerNames "comp-name-01" -TsPackageId "MP002DF7" -TsDeploymentId "MP02137A"`

### Wait for a given delay, and then run on one machine
`Invoke-TaskSequence -ComputerNames "comp-name-01" -TsPackageId "MP002DF7" -TsDeploymentId "MP02137A" -DelayUntilDateTime "2050-01-01 23:00:00"`

### Run on multiple specific machines
`Invoke-TaskSequence -ComputerNames "comp-name-01","comp-name-37" -TsPackageId "MP002DF7" -TsDeploymentId "MP02137A"`

### Run on multiple sequentially-named lab machines
The below example will run on computers `comp-name-01` through `comp-name-10`.  
```powershell
$comps = @(1..10) | ForEach-Object {
	$num = ([string]$int).PadLeft(2,"0")
	"comp-name-$($num)"
}
Invoke-TaskSequence -ComputerNames $comps -TsPackageId "MP002DF7" -TsDeploymentId "MP02137A"
```

# Behavior
This is accomplished by the following steps:
1. Enters a remote powershell session to the target machine.
2. Modifies the deployment's local assignment (a.k.a. advertisement) data stored in WMI to trick it into thinking the target TS deployment is _Required_, and that it has never been run before.
3. Triggers the "schedule" for the newly-modified assignment, which causes the TS to start.

# Parameters

### -ComputerNames \<string[]\>
Required string array.  
WIP  

### -TsPackageId \<string\>
Required string.  
The PackageID of the desired TS.  
Get this from the MECM console.  

### -TsDeploymentId \<string\>
Required string.  
The DeploymentID of the desired deployment of the desired TS.  
Get this from the MECM console.  
This is necessary in case there are multiple deployments of the same TS.  

### -DelayUntilDateTime \<DateTime\>
Optional DateTime.  
WIP  

### -DontTriggerImmediately
Optional switch.  
WIP  

### -TestRun
Optional switch.  
WIP  

### -Log \<string\>
Optional string.  
The full path of a file to log to.  
If omitted, no log will be created.  
If `:TS:` is given as part of the string, it will be replaced by a timestamp of when the script was started, with a format specified by `-LogFileTimestampFormat`.  
Specify `:ENGRIT:` to use a default path (i.e. `c:\engrit\logs\Invoke-AvailableTaskSequence_<timestamp>.log`).  

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
- By mseng3. See my other projects here: https://github.com/mmseng/code-compendium.
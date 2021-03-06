function Test-Command {
    <#
    .Synopsis
        Test-Command checks commands for consistency.
    .Description
        Test-Command checks commands for consistency.
        
        Test-Command run a series of static analysis rules on your script, and helps you see if there's anything to improve.
        
        It will not run any script, just look at the information about the script, like it's help, command metadata, or the script content itself.                
    .Example
        Get-Module ScriptCop | Test-Command
    .Example
        Get-Command -Type Cmdlet | Test-Command
    .Example
        Get-Command Get-Command | Test-Command
    .Link
        about_ScriptCop_rules
    #>
    [CmdletBinding(DefaultParameterSetName='Command')]
    param(
    # The command or module to test.  If the object is not a module info or command
    # info, it will not work.
    [Parameter(ValueFromPipeline=$true,Mandatory=$true,Position=0,ParameterSetName='Command')]
    [ValidateScript({
        if ($_ -is [Management.Automation.CommandInfo]) { return $true }
        if ($_ -is [Management.Automation.PSModuleInfo]) { return $true }
        if ($_ -is [IO.FileInfo]) { return $true }
        if ($_ -is [string]) { return $true }
        throw "Input must either be a command, a module, a file, or a name"
    })]
    $Command,
    
    # A script block containing functions, for instance: function foo {}.  
    # Script Blocks that do not contain functions will be ignored.
    [Parameter(Mandatory=$true,ParameterSetName='ScriptBlock',Position=0)]
    [ScriptBlock]
    $ScriptBlock,
    
    # The scriptcop 'patrol' (list of rules) to run   
    #|MaxLength 255
    #|Options Get-ScriptCopPatrol | Select-Object -ExpandProperty Name
    [string]$Patrol,            
    
    # The name of the rule to run
    #|Options Get-ScriptCopRule | Select-Object -ExpandProperty Name
    [String[]]$Rule,
    
    # Rules to avoid running.
    #|Options Get-ScriptCopRule | Select-Object -ExpandProperty Name
    [String[]]$ExcludedRule    
    )
    
    begin {        
        Set-StrictMode -Off       
        
        $CommandMetaData = @()  
        $ModuleMetaData = @()
        
        function WriteScriptCopError{
            param([switch]$IsModuleError)        
            
            if ($ScriptCopError) {
                foreach ($e in $ScriptCopError) {
                    if (-not $e) { continue }                    
                    $result = New-Object PSObject -Property @{
                        Rule = if ($IsModuleError) { $Module } else { $testCmd } 
                        Problem = $e
                        ItemWithProblem = if ($IsModuleError) { $ModuleInfo} else { $CommandInfo } 
                    }
                    $result.psObject.TypeNames.Add("ScriptCopError")
                    $result
                }
            }        
        }
        
        $progressId = Get-Random
    }
    
    process {
        
    
        Write-Progress "Collecting Commands" "$command " -Id $progressId
        if ($psCmdlet.ParameterSetName -eq 'Command') {
            if ($command -is [string]) {
                $cmds = @(Get-Command $command -ErrorAction Silentlycontinue)
            } elseif ($command -is [Management.Automation.PSModuleInfo]) {
                $cmds = @($command.ExportedFunctions.Values) + $command.ExportedCmdlets.Values
                $ModuleMetaData += $command
            } elseif ($command -is [Management.Automation.CommandInfo]) {
                $cmds = @($command)
            } elseif ($command -is [IO.FileInfo]) {
                $cmds = @(Get-Command $command.FullName)
            } 
        } elseif ($psBoundParameters.Scriptblock) {
            $functionOnly = Get-FunctionFromScript -ScriptBlock $psBoundParameters.ScriptBlock            
            $cmds = @()
            foreach ($f in $functionOnly) {
                . ([ScriptBlock]::Create($f))
                $matched = $f -match "function ((\w+-\w+)|(\w+))"
                if ($matched -and $matches[1]) {
                    $cmds+=Get-Command $matches[1]
                }                        
            }
        }       
        
        if ($cmds) {
            Write-Progress "Collecting Command Details" " " -Id $progressId
            $c = 0 
            foreach ($cmd in $cmds) {
                $c++
                $perc = $c * 100 / $cmds.Count                
                Write-Progress "Collecting Command Details" "$cmd" -PercentComplete $perc -Id $progressId
                $help = $cmd | Get-Help  
                $CommandMetaData += @{
                    Command = $cmd
                    Function = $(if ($cmd -is [Management.Automation.FunctionInfo]) { $cmd })
                    Application = $(if ($cmd -is [Management.Automation.ApplicationInfo]) { $cmd })
                    ExternalScript = $(if ($cmd -is [Management.Automation.ExternalScriptInfo]) { $cmd })
                    Cmdlet = $(if ($cmd -is [Management.Automation.CmdletInfo]) { $cmd })
                    Help = $(if ($help -and $help -isnot [string]) { $help })
                    Tokens = $(
                        if ($cmd -is [Management.Automation.FunctionInfo]) {
                            [Management.Automation.PSParser]::Tokenize($cmd.scriptblock,[ref]$null)
                        } elseif ($cmd -is [Management.Automation.ExternalScriptInfo]) {
                            [Management.Automation.PSParser]::Tokenize($cmd.scriptcontents,[ref]$null)
                        }
                    )
                    Text = $(
                        if ($cmd -is [Management.Automation.FunctionInfo]) {
                            "function $($cmd.Name) {
                                $($cmd.definition)
                            }"
                        } elseif ($cmd -is [Management.Automation.ExternalScriptInfo]) {
                            $cmd.scriptcontents
                        }
                    )
                }
            }
            Write-Progress "Collecting Command Details" " " -ID $progressId 
        }                                                                  
    }
    
    end {
        Write-Progress 'Filtering Rules' ' ' -Id $progressId              
        
        $currentRules = @{} + $script:ScriptCopRules
        
        $RuleNameMatch = { 
            $Rule -contains $_.Name -or
            $Rule -contains $_.Name.Replace(".ps1","")
        }
        
        if ($Rule) {
            $currentRules.TestCommandInfo = @($currentRules.TestCommandInfo | Where-Object $RuleNameMatch)
            $currentRules.TestCmdletInfo = @($currentRules.TestCmdletInfo | Where-Object $RuleNameMatch)
            $currentRules.TestScriptInfo = @($currentRules.TestScriptInfo | Where-Object $RuleNameMatch)
            $currentRules.TestFunctionInfo = @($currentRules.TestFunctionInfo | Where-Object $RuleNameMatch)
            $currentRules.TestApplicationInfo=  @($currentRules.TestApplicationInfo | Where-Object $RuleNameMatch)
            $currentRules.TestModuleInfo = @($currentRules.TestModuleInfo | Where-Object $RuleNameMatch)
            $currentRules.TestScriptToken = @($currentRules.TestScriptToken | Where-Object $RuleNameMatch)
            $currentRules.TestHelpContent = @($currentRules.TestHelpContent | Where-Object $RuleNameMatch)
        }
        
        $ExcludedRuleNotMatch = { 
            $ExcludedRule -notcontains $_.Name -and
            $ExcludedRule -notcontains $_.Name.Replace(".ps1","")
        }
        
        if ($ExcludedRule) {
            $currentRules.TestCommandInfo = @($currentRules.TestCommandInfo | Where-Object $ExcludedRuleNotMatch)
            $currentRules.TestCmdletInfo = @($currentRules.TestCmdletInfo | Where-Object $ExcludedRuleNotMatch)
            $currentRules.TestScriptInfo = @($currentRules.TestScriptInfo | Where-Object $ExcludedRuleNotMatch)
            $currentRules.TestFunctionInfo = @($currentRules.TestFunctionInfo | Where-Object $ExcludedRuleNotMatch)
            $currentRules.TestApplicationInfo=  @($currentRules.TestApplicationInfo | Where-Object $ExcludedRuleNotMatch)
            $currentRules.TestModuleInfo = @($currentRules.TestModuleInfo | Where-Object $ExcludedRuleNotMatch)
            $currentRules.TestScriptToken = @($currentRules.TestScriptToken | Where-Object $ExcludedRuleNotMatch)
            $currentRules.TestHelpContent = @($currentRules.TestHelpContent | Where-Object $ExcludedRuleNotMatch)
        }
        
        if ($patrol) {
            $commandRules = Get-ScriptCopPatrol -Name $patrol | 
                Select-Object -ExpandProperty CommandRule -ErrorAction SilentlyContinue
            $moduleRules = Get-ScriptCopPatrol -Name $patrol | 
                Select-Object -ExpandProperty ModuleRule -ErrorAction SilentlyContinue
            
            $patrolCommandMatch = $RuleNameMatch = { 
                $commandRules -contains $_.Name -or
                $commandRules -contains $_.Name.Replace(".ps1","")
            }
            
            $patrolModuleMatch = $RuleNameMatch = { 
                $moduleRules -contains $_.Name -or
                $moduleRules -contains $_.Name.Replace(".ps1","")
            }
            
            $currentRules.TestCommandInfo = @($currentRules.TestCommandInfo | Where-Object $patrolCommandMatch)
            $currentRules.TestCmdletInfo = @($currentRules.TestCmdletInfo | Where-Object $patrolCommandMatch)
            $currentRules.TestScriptInfo = @($currentRules.TestScriptInfo | Where-Object $patrolCommandMatch)
            $currentRules.TestFunctionInfo = @($currentRules.TestFunctionInfo | Where-Object $patrolCommandMatch)
            $currentRules.TestApplicationInfo=  @($currentRules.TestApplicationInfo | Where-Object $patrolCommandMatch)
            $currentRules.TestModuleInfo = @($currentRules.TestModuleInfo | Where-Object $patrolModuleMatch)
            $currentRules.TestScriptToken = @($currentRules.TestScriptToken | Where-Object $patrolCommandMatch)
            $currentRules.TestHelpContent = @($currentRules.TestHelpContent | Where-Object $patrolCommandMatch)
        }
                
        Write-Progress "Running ScriptCop" "Validating Modules" -Id $ProgressId       
        if ($currentRules.TestModuleInfo) {
            $c = 0
            $ruleCount = @($currentRules.TestModuleInfo).Count
            foreach ($module in $currentRules.TestModuleInfo){                        
                $c++
                $perc  = $c * 100 / $ruleCount
                Write-Progress "Running ScriptCop" "Validating Modules - $($module.Name)" -PercentComplete $perc -Id $ProgressId
                if ($scriptCopError) {$scriptCopError = $null }
                $ModuleMetaData | 
                    ForEach-Object {
                        $moduleInfo = $_
                        $null = $_ | 
                            & $Module -ErrorAction SilentlyContinue -ErrorVariable ScriptCopError
                        
                        WriteScriptCopError -IsModuleError 
                        
                    }
                    
                    
            }        
        }                                                        
        
        #region Validating Commands        
        
        Write-Progress "Running ScriptCop" "Validating Command Metadata" -Id $ProgressId               
        if ($currentRules.TestCommandInfo) {
            $c = 0
            $ruleCount = @($currentRules.TestCommandInfo).Count
            foreach ($testCmd in $currentRules.TestCommandInfo){                        
                $c++
                $perc  = $c * 100 / $RuleCount
                Write-Progress "Running ScriptCop" "Validating Command Metadata - $($testCmd.Name)" -Id $ProgressId -PercentComplete $perc
                if ($scriptCopError) {$scriptCopError = $null }
                $CommandMetaData | 
                    Where-Object { $_.Command } |
                    ForEach-Object { 
                        $commandInfo = $_.Command 
                        $null = $commandInfo | 
                            & $testCmd -ErrorAction SilentlyContinue -ErrorVariable ScriptCopError
                        
                        WriteScriptCopError                        
                    }
                    
                                    
            }        
        }
            
        #endregion Validating Commands        

        #region Validating Cmdlets        
        Write-Progress "Running ScriptCop" "Validating Cmdlet Metadata" -Id $ProgressId 
                
        if ($currentRules.TestCmdletInfo) {
            $c = 0
            $ruleCount = @($currentRules.TestCmdletInfo).Count
            foreach ($testCmd in $currentRules.TestCmdletInfo){                        
                $c++
                $perc  = $c * 100 / $ruleCount
                Write-Progress "Running ScriptCop" "Validating Cmdlet Metadata - $($testCmd.Name)" -Id $ProgressId -PercentComplete $perc
                if ($scriptCopError) {$scriptCopError = $null }
                $CmdletMetaData | 
                    Where-Object { 
                        $_.Cmdlet
                    } |
                    ForEach-Object { 
                        $commandInfo = $_.Cmdlet 
                        $null = $commandInfo | 
                            & $testCmd -ErrorAction SilentlyContinue -ErrorVariable ScriptCopError
                        
                        WriteScriptCopError                        
                    }                    
            }        
        }
            
        #endregion Validating Cmdlets        

        
        #region Validating Functions
        Write-Progress "Running ScriptCop" "Validating Functions" -Id $ProgressId  
                
        if ($currentRules.TestFunctionInfo) {
            $c = 0
            $ruleCount = @($currentRules.TestFunctionInfo).Count
            foreach ($testCmd in $currentRules.TestFunctionInfo){                        
                $c++
                $perc  = $c * 100 / $ruleCount
                Write-Progress "Running ScriptCop" "Validating Function Metadata - $($testCmd.Name)" -Id $ProgressId -PercentComplete $perc
                if ($scriptCopError) {$scriptCopError = $null }
                $CommandMetaData | 
                    Where-Object { 
                        $_.Function
                    } |
                    ForEach-Object { 
                        $commandInfo = $_.Function 
                        $null = $commandInfo | 
                            & $testCmd -ErrorAction SilentlyContinue -ErrorVariable ScriptCopError
                        
                        WriteScriptCopError                        
                    }  
            }        
        }
            
        #endregion Validating Functions
        
        #region Validating Applications
        Write-Progress "Running ScriptCop" "Validating Applications Metadata" -Id $ProgressId
                
        if ($currentRules.TestApplicationInfo) {
            $c = 0
            $ruleCount = @($currentRules.TestApplicationInfo).Count
            foreach ($testCmd in $currentRules.TestApplicationInfo){                        
                $c++
                $perc  = $c * 100 / $ruleCount
                Write-Progress "Running ScriptCop" "Validating Applications Metadata - $($testCmd.Name)" -Id $ProgressId -PercentComplete $perc
                if ($scriptCopError) {$scriptCopError = $null }
                $CommandMetaData | 
                    Where-Object { 
                        $_.Application
                    } |
                    ForEach-Object { 
                        $commandInfo = $_.Application 
                        $null = $commandInfo | 
                            & $testCmd -ErrorAction SilentlyContinue -ErrorVariable ScriptCopError
                        
                        WriteScriptCopError                        
                    }  
                    
                    
                
            }        
        }
                    
        #endregion Validating Applications
                    
        #region Validating Scripts
        Write-Progress "Running ScriptCop" "Validating Script Metadata" -Id $ProgressId
                
        if ($currentRules.TestScriptInfo) {
            $c = 0
            $ruleCount = @($currentRules.TestScriptInfo).Count
            foreach ($testCmd in $currentRules.TestScriptInfo){                        
                $c++
                $perc  = $c * 100 / $ruleCount
                Write-Progress "Running ScriptCop" "Validating Script Metadata - $($testCmd.Name)" -Id $ProgressId -PercentComplete $perc
                if ($scriptCopError) {$scriptCopError = $null }
                $CommandMetaData | 
                    Where-Object {  $_.Script } |
                    ForEach-Object { 
                        $commandInfo = $_.Script 
                        $null = $commandInfo | 
                            & $testCmd -ErrorAction SilentlyContinue -ErrorVariable ScriptCopError
                        
                        WriteScriptCopError                        
                    }                                    
            }        
        }
                   
        #endregion Validating Scripts    
        
        #region Validating Help
        Write-Progress "Running ScriptCop" "Validating Help" -Id $ProgressId
                
        if ($currentRules.TestHelpContent) {
            $c = 0
            $ruleCount = @($currentRules.TestHelpContent).Count
            foreach ($testCmd in $currentRules.TestHelpContent){                        
                $c++
                $perc  = $c * 100 / $ruleCount
                Write-Progress "Running ScriptCop" "Validating Help - $($testCmd.Name)" -Id $ProgressId -PercentComplete $perc
                if ($scriptCopError) {$scriptCopError = $null }
                $CommandMetaData | 
                    ForEach-Object {                    
                        $commandInfo = $_.Command
                        $null = & $testCmd -HelpCommand $_.Command -HelpContent $_.Help -ErrorAction SilentlyContinue -ErrorVariable ScriptCopError
                        WriteScriptCopError
                    }
                                        
            }        
        }
            
        #endregion Validating Help   
        
        #region Validating Tokens
        Write-Progress "Running ScriptCop" "Validating Tokens" -Id $ProgressId
                
        if ($currentRules.TestScriptToken) {
            $c = 0
            $ruleCount = @($currentRules.TestScriptToken).Count
            foreach ($testCmd in $currentRules.TestScriptToken){                        
                $c++
                $perc  = $c * 100 / $ruleCount                
                Write-Progress "Running ScriptCop" "Validating Tokens - $($testCmd.Name)" -Id $ProgressId -PercentComplete $perc
                if ($scriptCopError) {$scriptCopError = $null }
                $CommandMetaData | 
                    ForEach-Object {   
                        $commandInfo = $_.Command     
                        if ($_.Tokens -and $_.Text) {            
                            $null = & $testCmd -ScriptTokenCommand $_.Command -ScriptToken $_.Tokens -ScriptText "$($_.Text)" -ErrorAction SilentlyContinue -ErrorVariable ScriptCopError
                            WriteScriptCopError                        
                        }

                    }
                                        
            }        
        }
                    
        #endregion Validating Tokens   

    }
    
    
}
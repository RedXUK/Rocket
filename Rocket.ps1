<#
.SYNOPSIS
Rocket - Windows Enhancement Utility - 

.DESCRIPTION
Rocket is a PowerShell GUI application designed to optimize and customize Windows 10 and 11 systems. 
It features tools for:
- Software installation
- Bloatware removal
- Privacy and security enhancements
- Windows update settings
- Power settings adjustments
- Registry tweaks
- General PC optimizations

.AUTHOR
Red

#>

# ====================================================================================================
# Table of Contents
# ====================================================================================================
# 1. Namespaces & Assemblies
# 2. Type Definitions
#    - Enums
#    - Classes
# 3. Global Variables & Configuration
#    - Base Registry Keys
#    - Registry Configuration
#    - Other Configuration Settings
# 4. Function Definitions
#    - Helper Functions
#    - Registry Functions
#    - GUI Helper Functions
# 5. GUI Definition
#    - XAML Definition
#    - Window Creation
# 6. Control Management
#    - Find Controls
#    - Initialize Controls
# 7. Event Handlers
#    - Window Events
#    - Button & Slider Events
#    - Checkbox Events
# 8. Main Execution
## TIP: Search for #region to Navigate Sections

#region 1. Namespaces & Assemblies
# ====================================================================================================
# Namespaces & Assemblies
# This section defines the required namespaces and loads necessary assemblies for the application
# ====================================================================================================

using namespace Microsoft.Win32
using namespace System.Windows
using namespace System.Windows.Controls
using namespace System.Windows.Media

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms

# Update the SystemParametersInfo declaration to include all required parameters (for Wallaper Functions)
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public class Wallpaper {
    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern int SystemParametersInfo(
        uint uAction,
        uint uParam,
        string lpvParam,
        uint fuWinIni
    );

    public const uint SPI_SETDESKWALLPAPER = 0x0014;
    public const uint SPIF_UPDATEINIFILE = 0x01;
    public const uint SPIF_SENDCHANGE = 0x02;
}
"@

# Hide the console window as events are logged and shown in the GUI status text
Add-Type -Name Window -Namespace Console -MemberDefinition '
[DllImport("Kernel32.dll")]
public static extern IntPtr GetConsoleWindow();
[DllImport("user32.dll")]
public static extern bool ShowWindow(IntPtr hWnd, Int32 nCmdShow);
'
$consolePtr = [Console.Window]::GetConsoleWindow()
[Console.Window]::ShowWindow($consolePtr, 0) | Out-Null

# Check if running as administrator
If (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]"Administrator")) {
    Try {
        Start-Process PowerShell.exe -ArgumentList ("-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"{0}`"" -f $PSCommandPath) -Verb RunAs
        Exit
    }
    Catch {
        [System.Windows.MessageBox]::Show("Failed to run as Administrator. Please rerun with elevated privileges.", "Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
        Exit
    }
}

#region 2. Type Definitions
# ====================================================================================================
# Type Definitions
# Definition of custom types, enums, and classes used throughout the application
# ====================================================================================================

# [Enums]
enum RegistryAction {
    Apply
    Test
    Rollback
}

enum TaskAction {
    Apply
    Rollback
}

enum BaseKey {
    System
    LocationConsent
    SensorOverrides
    Telemetry
    Feedback
    Advertising
    CapabilityConsent
    InternationalUserProfile
    EdgeUI
    InputPersonalization
    TrainedDataStore
    PersonalizationSettings
    SiufRules
    ContentDeliveryManager
    AccountNotifications
    CloudContent
    SharedAccess
    DeviceMetadata
    RemoteAssistance
    Maintenance
    ErrorReporting
    PushToInstall
    WindowsSearch
    PolicyManagerWiFi
    AppPrivacy
    InkingTypingPersonalization
    ThemesPersonalize
    Maps
    LocationService
    WindowsInk
    SystemPolicy
    BitLocker
    EnhancedStorage
    GameConfigStore
    GameBar
    DirectXUserGpuPreferences
    GameDVR
    NvidiaFTS
    MultimediaSystemProfile
    MultimediaSystemProfileTasksGames
    GraphicsDrivers
    PriorityControl
    StorageSensePolicies
    WindowsUpdateMain
    WindowsUpdate
    DeliveryOptimization
    WindowsStorePolicies
    AppxPolicies
    Taskband
    TaskbarChat
    TaskbarFeeds
    PolicyManagerNews
    TaskbarDsh
    LMPolicyExplorer
    ExplorerPolicies
    CUExplorerAdvanced
    CUExplorer
    CUPolicyExplorer
    CUSearch
    PolicyManagerStart
    PolicyManagerProvidersStart
    FileSystem
    WorkplaceJoin
    MyComputerNamespace
    MyComputerNamespaceWOW64
    DesktopNamespace
    Explorer
    CabinetState
    ControlPanelMouse
    VisualEffects
    ControlPanelDesktop
    TabletTip
    ClassesCLSID
    ImmersiveShell
    BootAnimation
    EditionOverrides
    MultimediaAudio
    SpeechOneCoreSettings
    Accessibility
    EaseOfAccess
    InputSettings
    Lighting
    SearchSettings
    Notifications
    Services
}

class RegistrySetting {
    [string] $Category 
    [RegistryHive] $Hive
    [string] $SubKey
    [string] $Name
    [object] $RecommendedValue
    [RegistryValueKind] $ValueType
    [object] $DefaultValue
    [string] $Description
    hidden [RegistryView] $_RegistryView = [RegistryView]::Registry64

    # Constructor
    RegistrySetting(
        [RegistryHive] $Hive,
        [string] $SubKey,
        [string] $Name,
        [object] $RecommendedValue,
        [RegistryValueKind] $ValueType,
        [object] $DefaultValue,
        [string] $Description
    ) {
        $this.Hive = $Hive
        $this.SubKey = $SubKey.Trim('\') -replace '/', '\'
        $this.Name = $Name
        $this.RecommendedValue = $RecommendedValue
        $this.ValueType = $ValueType
        $this.DefaultValue = $DefaultValue
        $this.Description = $Description
        
        $this._RegistryView = if ($this.Hive -eq [RegistryHive]::LocalMachine) {
            [RegistryView]::Registry64
        }
        else {
            [RegistryView]::Default
        }
    }

    [void] Execute([RegistryAction] $Action) {
        $baseKey = $null
        $registrySubKey = $null 
    
        try {
            Write-Log "Processing: $($this.Name) [Action: $Action]"
            $baseKey = [RegistryKey]::OpenBaseKey($this.Hive, $this._RegistryView)
            
            switch ($Action) {
                ([RegistryAction]::Apply) {
                    if ($this.ValueType -eq [RegistryValueKind]::None) {
                        # Handle key deletion
                        $fullPath = [IO.Path]::Combine($this.SubKey, $this.Name)
                        try {
                            $baseKey.DeleteSubKeyTree($fullPath, $false)
                            Write-Log "Deleted key: $fullPath"
                        }
                        catch [System.ArgumentException] {
                            # Key doesn't exist, which is fine
                            Write-Log "Key already removed: $fullPath"
                        }
                    }
                    else {
                        # Handle value operations
                        $registrySubKey = $baseKey.OpenSubKey($this.SubKey, $true)
                        if (-not $registrySubKey) {
                            $registrySubKey = $baseKey.CreateSubKey($this.SubKey, $true)
                        }
                        $registrySubKey.SetValue($this.Name, $this.RecommendedValue, $this.ValueType)
                        Write-Log "Set value: $($this.Name)=$($this.RecommendedValue)"
                        $registrySubKey.Flush()
                    }
                }
                ([RegistryAction]::Test) {
                    if ($this.ValueType -eq [RegistryValueKind]::None) {
                        $fullPath = [IO.Path]::Combine($this.SubKey, $this.Name)
                        $exists = $null -ne $baseKey.OpenSubKey($fullPath)
                        Write-Log "Tested key existence: $fullPath = $exists (Expected: False)"
                    }
                    else {
                        $registrySubKey = $baseKey.OpenSubKey($this.SubKey)
                        if ($registrySubKey) {
                            $currentValue = $registrySubKey.GetValue($this.Name, $null)
                            Write-Log "Tested: $($this.Name) = $currentValue (Expected: $($this.RecommendedValue))"
                        }
                        else {
                            Write-Log "Tested: SubKey does not exist: $($this.SubKey)"
                        }
                    }
                }
                ([RegistryAction]::Rollback) {
                    if ($this.ValueType -eq [RegistryValueKind]::None) {
                        # For key deletion, rollback means recreating the key if DefaultValue is not null
                        if ($null -ne $this.DefaultValue) {
                            $fullPath = [IO.Path]::Combine($this.SubKey, $this.Name)
                            $baseKey.CreateSubKey($fullPath, $true)
                            Write-Log "Restored key: $fullPath"
                        }
                    }
                    else {
                        $registrySubKey = $baseKey.OpenSubKey($this.SubKey, $true)
                        if ($registrySubKey) {
                            if ($null -ne $this.DefaultValue) {
                                $registrySubKey.SetValue($this.Name, $this.DefaultValue, $this.ValueType)
                                Write-Log "Restored default: $($this.Name)=$($this.DefaultValue)"
                            }
                            else {
                                $registrySubKey.DeleteValue($this.Name, $false)
                                Write-Log "Deleted value: $($this.Name)"
                            }
                            $registrySubKey.Flush()
                        }
                    }
                }
            }
        }
        catch {
            Write-Log "Error ($Action): $($this.Name) - $($_.Exception.Message)"
            throw
        }
        finally {
            if ($registrySubKey) { $registrySubKey.Close() }
            if ($baseKey) { $baseKey.Close() }
        }
    }
}

class ValuePair {
    [object] $Value
    [RegistryValueKind] $Type
    
    ValuePair([object]$val, [RegistryValueKind]$type) {
        $this.Value = $val
        $this.Type = $type
    }
}

class RegistryHelper {
    static [object] GetCurrentValue([RegistrySetting]$Setting) {
        $baseKey = $null
        $subKey = $null
        try {
            $baseKey = [RegistryKey]::OpenBaseKey($Setting.Hive, $Setting._RegistryView)
            $subKey = $baseKey.OpenSubKey($Setting.SubKey)
            
            if ($null -ne $subKey) {
                return $subKey.GetValue($Setting.Name, $null)
            }
            return $null
        }
        catch {
            Write-Log "Error reading $($Setting.Name): $_"
            return $null
        }
        finally {
            if ($subKey) { $subKey.Close() }
            if ($baseKey) { $baseKey.Close() }
        }
    }

    static [void] ApplyValue([RegistrySetting]$Setting, [object]$Value) {
        $baseKey = $null
        $subKey = $null
        try {
            if ($null -eq $Value) {
                # Delete the value
                $baseKey = [RegistryKey]::OpenBaseKey($Setting.Hive, $Setting._RegistryView)
                $subKey = $baseKey.OpenSubKey($Setting.SubKey, $true)
                if ($null -ne $subKey) {
                    $subKey.DeleteValue($Setting.Name)
                    Write-Log "Deleted $($Setting.Name)"
                }
            }
            else {
                # Create temporary setting and apply
                $tempSetting = [RegistrySetting]::new(
                    $Setting.Hive,
                    $Setting.SubKey,
                    $Setting.Name,
                    $Value,
                    $Setting.ValueType,
                    $Setting.DefaultValue,
                    $Setting.Description
                )
                $tempSetting.Execute([RegistryAction]::Apply)
            }
        }
        catch {
            throw "Registry operation failed: $_"
        }
        finally {
            if ($subKey) { $subKey.Close() }
            if ($baseKey) { $baseKey.Close() }
        }
    }
}

#region 3. Global Variables & Configuration
# ====================================================================================================
# Global Variables & Configuration
# Global script variables, configuration settings, and constants
# ====================================================================================================

# === Logging Configuration ===
$SCRIPT:LogPath = "$env:TEMP\Rocket-Log_$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
$SCRIPT:LogEnabled = $true
$SCRIPT:Version = "25.02.06"

# ====================================================================================================
# Registry Base Keys
# Defines base registry paths used throughout the configuration
# Each BaseKey includes:
#   Hive   - Registry hive (e.g., HKLM, HKCU)
#   SubKey - Base registry path/subkey
# These act as reusable base paths that can be combined with SubKeySuffix values in RegConfig
# ====================================================================================================
$SCRIPT:BaseKeys = @{
    [BaseKey]::System                            = [pscustomobject]@{
        Hive   = [RegistryHive]::LocalMachine
        SubKey = "SOFTWARE\Policies\Microsoft\Windows\System"
    }
    [BaseKey]::LocationConsent                   = [pscustomobject]@{
        Hive   = [RegistryHive]::LocalMachine
        SubKey = "SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore"
    }
    [BaseKey]::SensorOverrides                   = [pscustomobject]@{
        Hive   = [RegistryHive]::LocalMachine
        SubKey = "SOFTWARE\Microsoft\Windows NT\CurrentVersion\Sensor\Overrides"
    }
    [BaseKey]::Telemetry                         = [pscustomobject]@{
        Hive   = [RegistryHive]::LocalMachine
        SubKey = "SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection"
    }
    [BaseKey]::Feedback                          = [pscustomobject]@{
        Hive   = [RegistryHive]::LocalMachine
        SubKey = "SOFTWARE\Policies\Microsoft\Windows\DataCollection"
    }
    [BaseKey]::Advertising                       = [pscustomobject]@{
        Hive   = [RegistryHive]::LocalMachine
        SubKey = "SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo"
    }
    [BaseKey]::CapabilityConsent                 = [pscustomobject]@{
        Hive   = [RegistryHive]::LocalMachine
        SubKey = "Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore"
    }
    [BaseKey]::InternationalUserProfile          = [pscustomobject]@{
        Hive   = [RegistryHive]::CurrentUser
        SubKey = "Control Panel\International\User Profile"
    }
    [BaseKey]::EdgeUI                            = [pscustomobject]@{
        Hive   = [RegistryHive]::CurrentUser
        SubKey = "Software\Policies\Microsoft\Windows\EdgeUI"
    }
    [BaseKey]::InputPersonalization              = [pscustomobject]@{
        Hive   = [RegistryHive]::CurrentUser
        SubKey = "Software\Microsoft\InputPersonalization"
    }
    [BaseKey]::TrainedDataStore                  = [pscustomobject]@{
        Hive   = [RegistryHive]::CurrentUser
        SubKey = "Software\Microsoft\InputPersonalization\TrainedDataStore"
    }
    [BaseKey]::PersonalizationSettings           = [pscustomobject]@{
        Hive   = [RegistryHive]::CurrentUser
        SubKey = "Software\Microsoft\Personalization\Settings"
    }
    [BaseKey]::SiufRules                         = [pscustomobject]@{
        Hive   = [RegistryHive]::CurrentUser
        SubKey = "SOFTWARE\Microsoft\Siuf\Rules"
    }
    [BaseKey]::ContentDeliveryManager            = [pscustomobject]@{
        Hive   = [RegistryHive]::CurrentUser
        SubKey = "Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
    }
    [BaseKey]::AccountNotifications              = [pscustomobject]@{
        Hive   = [RegistryHive]::CurrentUser
        SubKey = "Software\Microsoft\Windows\CurrentVersion\SystemSettings\AccountNotifications"
    }
    [BaseKey]::CloudContent                      = [pscustomobject]@{
        Hive   = [RegistryHive]::CurrentUser
        SubKey = "Software\Policies\Microsoft\Windows\CloudContent"
    }
    [BaseKey]::SharedAccess                      = [pscustomobject]@{
        Hive   = [RegistryHive]::LocalMachine
        SubKey = "SYSTEM\ControlSet001\Control\Network\SharedAccessConnection"
    }
    [BaseKey]::DeviceMetadata                    = [pscustomobject]@{
        Hive   = [RegistryHive]::LocalMachine
        SubKey = "SOFTWARE\Microsoft\Windows\CurrentVersion\Device Metadata"
    }
    [BaseKey]::RemoteAssistance                  = [pscustomobject]@{
        Hive   = [RegistryHive]::LocalMachine
        SubKey = "SYSTEM\CurrentControlSet\Control\Remote Assistance"
    }
    [BaseKey]::Maintenance                       = [pscustomobject]@{
        Hive   = [RegistryHive]::LocalMachine
        SubKey = "SOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\Maintenance"
    }
    [BaseKey]::ErrorReporting                    = [pscustomobject]@{
        Hive   = [RegistryHive]::LocalMachine
        SubKey = "SOFTWARE\Policies\Microsoft\Windows\Windows Error Reporting"
    }
    [BaseKey]::PushToInstall                     = [pscustomobject]@{
        Hive   = [RegistryHive]::LocalMachine
        SubKey = "SOFTWARE\Policies\Microsoft\PushToInstall"
    }
    [BaseKey]::WindowsSearch                     = [pscustomobject]@{
        Hive   = [RegistryHive]::LocalMachine
        SubKey = "Software\Policies\Microsoft\Windows\Windows Search"
    }
    [BaseKey]::PolicyManagerWiFi                 = [pscustomobject]@{
        Hive   = [RegistryHive]::LocalMachine
        SubKey = "Software\Microsoft\PolicyManager\default\WiFi"
    }
    [BaseKey]::AppPrivacy                        = [pscustomobject]@{
        Hive   = [RegistryHive]::LocalMachine
        SubKey = "SOFTWARE\Policies\Microsoft\Windows\AppPrivacy"
    }
    [BaseKey]::InkingTypingPersonalization       = [pscustomobject]@{
        Hive   = [RegistryHive]::CurrentUser
        SubKey = "Software\Microsoft\Windows\CurrentVersion\CPSS\Store\InkingAndTypingPersonalization"
    }
    [BaseKey]::ThemesPersonalize                 = [pscustomobject]@{
        Hive   = [RegistryHive]::CurrentUser
        SubKey = "Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"
    }
    [BaseKey]::Maps                              = [pscustomobject]@{
        Hive   = [RegistryHive]::LocalMachine
        SubKey = "SYSTEM\Maps"
    }
    [BaseKey]::LocationService                   = [pscustomobject]@{
        Hive   = [RegistryHive]::LocalMachine
        SubKey = "SYSTEM\CurrentControlSet\Services\lfsvc\Service\Configuration"
    }
    [BaseKey]::WindowsInk                        = [pscustomobject]@{
        Hive   = [RegistryHive]::LocalMachine
        SubKey = "SOFTWARE\Policies\Microsoft\WindowsInkWorkspace"
    }
    [BaseKey]::SystemPolicy                      = [pscustomobject]@{
        Hive   = [RegistryHive]::LocalMachine
        SubKey = "SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
    }
    [BaseKey]::BitLocker                         = [pscustomobject]@{
        Hive   = [RegistryHive]::LocalMachine
        SubKey = "SYSTEM\CurrentControlSet\Control\BitLocker"
    } 
    [BaseKey]::EnhancedStorage                   = [pscustomobject]@{
        Hive   = [RegistryHive]::LocalMachine
        SubKey = "SOFTWARE\Policies\Microsoft\Windows\EnhancedStorageDevices"
    }
    [BaseKey]::GameConfigStore                   = [pscustomobject]@{
        Hive   = [RegistryHive]::CurrentUser
        SubKey = "System\GameConfigStore"
    }
    [BaseKey]::GameBar                           = [pscustomobject]@{
        Hive   = [RegistryHive]::CurrentUser
        SubKey = "Software\Microsoft\GameBar"
    }
    [BaseKey]::DirectXUserGpuPreferences         = [pscustomobject]@{
        Hive   = [RegistryHive]::CurrentUser
        SubKey = "Software\Microsoft\DirectX\UserGpuPreferences"
    }
    [BaseKey]::GameDVR                           = [pscustomobject]@{
        Hive   = [RegistryHive]::LocalMachine
        SubKey = "SOFTWARE\Policies\Microsoft\Windows\GameDVR"
    }
    [BaseKey]::NvidiaFTS                         = [pscustomobject]@{
        Hive   = [RegistryHive]::LocalMachine
        SubKey = "SYSTEM\CurrentControlSet\Services\nvlddmkm\FTS"
    }
    [BaseKey]::MultimediaSystemProfile           = [pscustomobject]@{
        Hive   = [RegistryHive]::LocalMachine
        SubKey = "SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"
    }
    [BaseKey]::MultimediaSystemProfileTasksGames = [pscustomobject]@{
        Hive   = [RegistryHive]::LocalMachine
        SubKey = "SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games"
    }
    [BaseKey]::GraphicsDrivers                   = [pscustomobject]@{
        Hive   = [RegistryHive]::LocalMachine
        SubKey = "SYSTEM\CurrentControlSet\Control\GraphicsDrivers"
    }
    [BaseKey]::PriorityControl                   = [pscustomobject]@{
        Hive   = [RegistryHive]::LocalMachine
        SubKey = "SYSTEM\CurrentControlSet\Control\PriorityControl"
    }
    [BaseKey]::StorageSensePolicies              = [pscustomobject]@{
        Hive   = [RegistryHive]::LocalMachine
        SubKey = "SOFTWARE\Policies\Microsoft\Windows\StorageSense"
    }
    [BaseKey]::WindowsUpdateMain                 = [pscustomobject]@{
        Hive   = [RegistryHive]::LocalMachine
        SubKey = "SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
    }
    [BaseKey]::WindowsUpdate                     = [pscustomobject]@{
        Hive   = [RegistryHive]::LocalMachine
        SubKey = "SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"
    }
    [BaseKey]::DeliveryOptimization              = [pscustomobject]@{
        Hive   = [RegistryHive]::LocalMachine
        SubKey = "SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization"
    }
    [BaseKey]::WindowsStorePolicies              = [pscustomobject]@{
        Hive   = [RegistryHive]::LocalMachine
        SubKey = "SOFTWARE\Policies\Microsoft\WindowsStore"
    }
    [BaseKey]::AppxPolicies                      = [pscustomobject]@{
        Hive   = [RegistryHive]::LocalMachine
        SubKey = "SOFTWARE\Policies\Microsoft\Windows\Appx"
    }
    [BaseKey]::Taskband                          = [pscustomobject]@{
        Hive   = [RegistryHive]::CurrentUser
        SubKey = "Software\Microsoft\Windows\CurrentVersion\Explorer\Taskband"
    }
    [BaseKey]::TaskbarChat                       = [pscustomobject]@{
        Hive   = [RegistryHive]::LocalMachine
        SubKey = "SOFTWARE\Microsoft\Windows\Windows Chat"
    }
    [BaseKey]::TaskbarFeeds                      = [pscustomobject]@{
        Hive   = [RegistryHive]::LocalMachine
        SubKey = "SOFTWARE\Policies\Microsoft\Windows\Windows Feeds"
    }
    [BaseKey]::PolicyManagerNews                 = [pscustomobject]@{
        Hive   = [RegistryHive]::LocalMachine
        SubKey = "SOFTWARE\Microsoft\PolicyManager\default\NewsAndInterests"
    }
    [BaseKey]::TaskbarDsh                        = [pscustomobject]@{
        Hive   = [RegistryHive]::LocalMachine
        SubKey = "SOFTWARE\Policies\Microsoft\Dsh"
    }
    [BaseKey]::LMPolicyExplorer                  = [pscustomobject]@{
        Hive   = [RegistryHive]::LocalMachine
        SubKey = "SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer"
    }
    [BaseKey]::ExplorerPolicies                  = [pscustomobject]@{
        Hive   = [RegistryHive]::CurrentUser
        SubKey = "SOFTWARE\Policies\Microsoft\Windows\Explorer"
    }
    [BaseKey]::CUExplorerAdvanced                = [pscustomobject]@{
        Hive   = [RegistryHive]::CurrentUser
        SubKey = "Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
    }
    [BaseKey]::CUExplorer                        = [pscustomobject]@{
        Hive   = [RegistryHive]::CurrentUser
        SubKey = "Software\Microsoft\Windows\CurrentVersion\Explorer"
    }
    [BaseKey]::CUPolicyExplorer                  = [pscustomobject]@{
        Hive   = [RegistryHive]::CurrentUser
        SubKey = "Software\Microsoft\Windows\CurrentVersion\Policies\Explorer"
    }
    [BaseKey]::CUSearch                          = [pscustomobject]@{
        Hive   = [RegistryHive]::CurrentUser
        SubKey = "Software\Microsoft\Windows\CurrentVersion\Search"
    }
    [BaseKey]::PolicyManagerStart                = [pscustomobject]@{
        Hive   = [RegistryHive]::LocalMachine
        SubKey = "SOFTWARE\Microsoft\PolicyManager\current\device\Start"
    }
    [BaseKey]::PolicyManagerProvidersStart       = [pscustomobject]@{
        Hive   = [RegistryHive]::LocalMachine
        SubKey = "SOFTWARE\Microsoft\PolicyManager\providers\B5292708-1619-419B-9923-E5D9F3925E71\default\Device\Start"
    }
    [BaseKey]::FileSystem                        = [pscustomobject]@{
        Hive   = [RegistryHive]::LocalMachine
        SubKey = "SYSTEM\CurrentControlSet\Control\FileSystem"
    }
    [BaseKey]::WorkplaceJoin                     = [pscustomobject]@{
        Hive   = [RegistryHive]::LocalMachine
        SubKey = "SOFTWARE\Policies\Microsoft\Windows\WorkplaceJoin"
    }
    [BaseKey]::MyComputerNamespace               = [pscustomobject]@{
        Hive   = [RegistryHive]::LocalMachine
        SubKey = "SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\MyComputer\NameSpace"
    }
    [BaseKey]::MyComputerNamespaceWOW64          = [pscustomobject]@{
        Hive   = [RegistryHive]::LocalMachine
        SubKey = "SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Explorer\MyComputer\NameSpace"
    }
    [BaseKey]::DesktopNamespace                  = [pscustomobject]@{
        Hive   = [RegistryHive]::LocalMachine
        SubKey = "SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace"
    }
    [BaseKey]::Explorer                          = [pscustomobject]@{
        Hive   = [RegistryHive]::CurrentUser
        SubKey = "Software\Microsoft\Windows\CurrentVersion\Explorer"
    }
    [BaseKey]::CabinetState                      = [pscustomobject]@{
        Hive   = [RegistryHive]::CurrentUser
        SubKey = "Software\Microsoft\Windows\CurrentVersion\Explorer\CabinetState"
    }
    [BaseKey]::ControlPanelMouse                 = [pscustomobject]@{
        Hive   = [RegistryHive]::CurrentUser
        SubKey = "Control Panel\Mouse"
    }
    [BaseKey]::VisualEffects                     = [pscustomobject]@{
        Hive   = [RegistryHive]::CurrentUser
        SubKey = "Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects"
    }
    [BaseKey]::ControlPanelDesktop               = [pscustomobject]@{
        Hive   = [RegistryHive]::CurrentUser
        SubKey = "Control Panel\Desktop"
    }
    [BaseKey]::TabletTip                         = [pscustomobject]@{
        Hive   = [RegistryHive]::CurrentUser
        SubKey = "Software\Microsoft\TabletTip\1.7"
    }
    [BaseKey]::ClassesCLSID                      = [pscustomobject]@{
        Hive   = [RegistryHive]::CurrentUser
        SubKey = "Software\Classes\CLSID"
    }
    [BaseKey]::ImmersiveShell                    = [pscustomobject]@{
        Hive   = [RegistryHive]::LocalMachine
        SubKey = "SOFTWARE\Microsoft\Windows\CurrentVersion\ImmersiveShell"
    }
    [BaseKey]::BootAnimation                     = [pscustomobject]@{
        Hive   = [RegistryHive]::LocalMachine
        SubKey = "Software\Microsoft\Windows\CurrentVersion\Authentication\LogonUI\BootAnimation"
    }
    [BaseKey]::EditionOverrides                  = [pscustomobject]@{
        Hive   = [RegistryHive]::LocalMachine
        SubKey = "Software\Microsoft\Windows\CurrentVersion\EditionOverrides"
    }
    [BaseKey]::MultimediaAudio                   = [pscustomobject]@{
        Hive   = [RegistryHive]::CurrentUser
        SubKey = "Software\Microsoft\Multimedia\Audio"
    }
    [BaseKey]::SpeechOneCoreSettings             = [pscustomobject]@{
        Hive   = [RegistryHive]::CurrentUser
        SubKey = "Software\Microsoft\Speech_OneCore\Settings\VoiceActivation\UserPreferenceForAllApps"
    }
    [BaseKey]::Accessibility                     = [pscustomobject]@{
        Hive   = [RegistryHive]::CurrentUser
        SubKey = "Control Panel\Accessibility"
    }
    [BaseKey]::EaseOfAccess                      = [pscustomobject]@{
        Hive   = [RegistryHive]::CurrentUser
        SubKey = "Software\Microsoft\Ease of Access"
    }
    [BaseKey]::InputSettings                     = [pscustomobject]@{
        Hive   = [RegistryHive]::CurrentUser
        SubKey = "Software\Microsoft\input\Settings"
    }
    [BaseKey]::Lighting                          = [pscustomobject]@{
        Hive   = [RegistryHive]::CurrentUser
        SubKey = "Software\Microsoft\Lighting"
    }
    [BaseKey]::SearchSettings                    = [pscustomobject]@{
        Hive   = [RegistryHive]::CurrentUser
        SubKey = "Software\Microsoft\Windows\CurrentVersion\SearchSettings"
    }
    [BaseKey]::Notifications                     = [pscustomobject]@{
        Hive   = [RegistryHive]::CurrentUser
        SubKey = "Software\Microsoft\Windows\CurrentVersion"
    }
    [BaseKey]::Services                          = [pscustomobject]@{
        Hive   = [RegistryHive]::LocalMachine
        SubKey = "SYSTEM\ControlSet001\Services"
    }
}

# ====================================================================================================
# Registry Configuration Settings
# Defines registry settings for various system configurations organized by category (Privacy, Security, etc.)
# Each setting includes:
#   BaseKey      - Registry hive and subkey path
#   SubKeySuffix - Additional path to append to BaseKey path (if applicable)
#   Name         - Registry value name
#   Recommended  - Recommended value and data type using ValuePair class
#   DefaultValue - Original/default value (null if not applicable) 
#   Description  - Description of what the setting controls
# ====================================================================================================
$SCRIPT:RegConfig = @{
    Privacy         = @(
        # Region: Activity History
        [pscustomobject]@{
            BaseKey      = [BaseKey]::System
            Name         = "EnableActivityFeed"
            Recommended  = [ValuePair]::new(0, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Disables activity history tracking"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::System
            Name         = "PublishUserActivities"
            Recommended  = [ValuePair]::new(0, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Prevents publishing user activities to Microsoft"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::System
            Name         = "UploadUserActivities"
            Recommended  = [ValuePair]::new(0, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Blocks uploading user activity history to the cloud"
        },

        # Region: Location Tracking
        [pscustomobject]@{
            BaseKey      = [BaseKey]::LocationConsent
            SubKeySuffix = "location"
            Name         = "Value"
            Recommended  = [ValuePair]::new("Deny", [RegistryValueKind]::String)
            DefaultValue = $null
            Description  = "Denies location tracking consent for all apps"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::SensorOverrides
            SubKeySuffix = "{BFA794E4-F964-4FDB-90F6-51056BFE4B44}"
            Name         = "SensorPermissionState"
            Recommended  = [ValuePair]::new(0, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Disables location sensor override permissions"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Maps
            Name         = "AutoUpdateEnabled"
            Recommended  = [ValuePair]::new(0, [RegistryValueKind]::DWord)
            DefaultValue = 1
            Description  = "Disables automatic map updates for offline maps"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::LocationService
            Name         = "Status"
            Recommended  = [ValuePair]::new(0, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Disables location service (lfsvc)"
        },

        # Region: Telemetry
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Telemetry
            Name         = "AllowTelemetry"
            Recommended  = [ValuePair]::new(0, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Sets telemetry level to disabled (Security)"
        },

        # Region: Feedback Notifications
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Feedback
            Name         = "AllowTelemetry"
            Recommended  = [ValuePair]::new(0, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Disables feedback and diagnostic data collection"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Feedback
            Name         = "DoNotShowFeedbackNotifications"
            Recommended  = [ValuePair]::new(1, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Hides feedback notifications from Microsoft"
        },

        # Region: Windows Ink Workspace
        [pscustomobject]@{
            BaseKey      = [BaseKey]::WindowsInk
            Name         = "AllowWindowsInkWorkspace"
            Recommended  = [ValuePair]::new(0, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Disables Windows Ink Workspace functionality"
        },

        # Region: Advertising ID
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Advertising
            Name         = "DisabledByGroupPolicy"
            Recommended  = [ValuePair]::new(1, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Disables advertising ID through group policy"
        },

        # Region: Account Info
        [pscustomobject]@{
            BaseKey      = [BaseKey]::CapabilityConsent
            SubKeySuffix = "userAccountInformation"
            Name         = "Value"
            Recommended  = [ValuePair]::new("Deny", [RegistryValueKind]::String)
            DefaultValue = "Allow"
            Description  = "Blocks apps from accessing account information"
        },

        # Region: Language List Tracking
        [pscustomobject]@{
            BaseKey      = [BaseKey]::InternationalUserProfile
            Name         = "HttpAcceptLanguageOptOut"
            Recommended  = [ValuePair]::new(1, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Prevents websites from accessing language list"
        },

        # Region: App Launch Tracking
        [pscustomobject]@{
            BaseKey      = [BaseKey]::EdgeUI
            Name         = "DisableMFUTracking"
            Recommended  = [ValuePair]::new(1, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Disables tracking of frequently used apps"
        },

        # Region: Speech Recognition
        [pscustomobject]@{
            BaseKey      = [BaseKey]::InputPersonalization
            Name         = "AllowInputPersonalization"
            Recommended  = [ValuePair]::new(0, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Disables online speech recognition services"
        },

        # Region: Inking & Typing Data Collection
        [pscustomobject]@{
            BaseKey      = [BaseKey]::InkingTypingPersonalization
            Name         = "Value"
            Recommended  = [ValuePair]::new(0, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Disables personal inking and typing dictionary"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::InputPersonalization
            Name         = "RestrictImplicitInkCollection"
            Recommended  = [ValuePair]::new(1, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Restricts implicit ink data collection"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::InputPersonalization
            Name         = "RestrictImplicitTextCollection"
            Recommended  = [ValuePair]::new(1, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Restricts implicit text input collection"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::TrainedDataStore
            Name         = "HarvestContacts"
            Recommended  = [ValuePair]::new(0, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Prevents harvesting contacts for typing data"
        },

        # Region: Feedback Frequency
        [pscustomobject]@{
            BaseKey      = [BaseKey]::PersonalizationSettings
            Name         = "AcceptedPrivacyPolicy"
            Recommended  = [ValuePair]::new(0, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Resets privacy policy acceptance state"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::SiufRules
            Name         = "NumberOfSIUFInPeriod"
            Recommended  = [ValuePair]::new(0, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Disables periodic feedback prompts"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::SiufRules
            Name         = "PeriodInNanoSeconds"
            Recommended  = [ValuePair]::new(0, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Removes feedback collection interval setting"
        },

        # Region: Suggested Content
        [pscustomobject]@{
            BaseKey      = [BaseKey]::ContentDeliveryManager
            Name         = "SubscribedContent-338393Enabled"
            Recommended  = [ValuePair]::new(0, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Disables suggested content in Settings"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::ContentDeliveryManager
            Name         = "SubscribedContent-353694Enabled"
            Recommended  = [ValuePair]::new(0, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Blocks third-party content suggestions"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::ContentDeliveryManager
            Name         = "SubscribedContent-353696Enabled"
            Recommended  = [ValuePair]::new(0, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Disables promotional content in Settings"
        },

        # Region: Account Notifications
        [pscustomobject]@{
            BaseKey      = [BaseKey]::AccountNotifications
            Name         = "EnableAccountNotifications"
            Recommended  = [ValuePair]::new(0, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Disables account-related notifications"
        },

        # Region: Tailored Experiences
        [pscustomobject]@{
            BaseKey      = [BaseKey]::CloudContent
            Name         = "DisableTailoredExperiencesWithDiagnosticData"
            Recommended  = [ValuePair]::new(1, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Blocks personalized experiences using diagnostic data"
        },
        # Cloud Content
        [pscustomobject]@{
            BaseKey      = [BaseKey]::CloudContent
            Name         = "DisableWindowsConsumerFeatures"
            Recommended  = [ValuePair]::new(0, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Disable Windows Consumer Features"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::CloudContent
            Name         = "DisableConsumerAccountStateContent"
            Recommended  = [ValuePair]::new(1, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Disable Consumer Account State Content"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::CloudContent
            Name         = "DisableCloudOptimizedContent"
            Recommended  = [ValuePair]::new(1, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Disable Cloud Optimized Content"
        },
        # Network Privacy
        [pscustomobject]@{
            BaseKey      = [BaseKey]::SharedAccess
            Name         = "EnableControl"
            Recommended  = [ValuePair]::new(0, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Disable allow other network users to control or disable the shared internet connection"
        },
    
        # Device Privacy
        [pscustomobject]@{
            BaseKey      = [BaseKey]::DeviceMetadata
            Name         = "PreventDeviceMetadataFromNetwork"
            Recommended  = [ValuePair]::new(1, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Disable device installation settings"
        },
    
        # Remote Access
        [pscustomobject]@{
            BaseKey      = [BaseKey]::RemoteAssistance
            Name         = "fAllowToGetHelp"
            Recommended  = [ValuePair]::new(0, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Disable remote assistance"
        },
    
        # System Maintenance
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Maintenance
            Name         = "MaintenanceDisabled"
            Recommended  = [ValuePair]::new(1, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Disable automatic maintenance"
        },
    
        # Error Reporting
        [pscustomobject]@{
            BaseKey      = [BaseKey]::ErrorReporting
            Name         = "Disabled"
            Recommended  = [ValuePair]::new(1, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Disable error reporting"
        },
    
        # Push To Install
        [pscustomobject]@{
            BaseKey      = [BaseKey]::PushToInstall
            Name         = "DisablePushToInstall"
            Recommended  = [ValuePair]::new(1, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Disables the Push To Install feature"
        },
    
        # Cortana
        [pscustomobject]@{
            BaseKey      = [BaseKey]::WindowsSearch
            Name         = "AllowCortana"
            Recommended  = [ValuePair]::new(0, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Disables Cortana"
        },
    
        # WiFi Sense
        [pscustomobject]@{
            BaseKey      = [BaseKey]::PolicyManagerWiFi
            Name         = "AllowWiFiHotSpotReporting"
            Recommended  = [ValuePair]::new(0, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Disable WiFi HotSpot Reporting"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::PolicyManagerWiFi
            Name         = "AllowAutoConnectToWiFiSenseHotspots"
            Recommended  = [ValuePair]::new(0, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Disable WiFi Sense Hotspots"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::BitLocker
            Name         = "PreventDeviceEncryption"
            Recommended  = [ValuePair]::new(1, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Automatic Bitlocker Drive Encryption"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::EnhancedStorage
            Name         = "TCGSecurityActivationDisabled"
            Recommended  = [ValuePair]::new(1, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Disables TCG security device activation"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::SystemPolicy
            Name         = "DisableAutomaticRestartSignOn"
            Recommended  = [ValuePair]::new(1, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Disables automatic restart sign-on and restore of applications"
        },
        # Background Apps
        [pscustomobject]@{
            BaseKey      = [BaseKey]::AppPrivacy
            Name         = "LetAppsRunInBackground"
            Recommended  = [ValuePair]::new(2, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Disable background apps"
        },
        # Content Delivery Manager Settings
        [pscustomobject]@{
            BaseKey      = [BaseKey]::ContentDeliveryManager
            Name         = "ContentDeliveryAllowed"
            Recommended  = [ValuePair]::new(0, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Disable content delivery"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::ContentDeliveryManager
            Name         = "FeatureManagementEnabled"
            Recommended  = [ValuePair]::new(0, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Disable feature management"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::ContentDeliveryManager
            Name         = "OemPreInstalledAppsEnabled"
            Recommended  = [ValuePair]::new(0, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Disable OEM pre-installed apps"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::ContentDeliveryManager
            Name         = "PreInstalledAppsEnabled"
            Recommended  = [ValuePair]::new(0, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Disable pre-installed apps"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::ContentDeliveryManager
            Name         = "PreInstalledAppsEverEnabled"
            Recommended  = [ValuePair]::new(0, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Disable pre-installed apps from ever being enabled"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::ContentDeliveryManager
            Name         = "RotatingLockScreenEnabled"
            Recommended  = [ValuePair]::new(0, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Disable rotating lock screen"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::ContentDeliveryManager
            Name         = "RotatingLockScreenOverlayEnabled"
            Recommended  = [ValuePair]::new(0, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Disable rotating lock screen overlay"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::ContentDeliveryManager
            Name         = "SilentInstalledAppsEnabled"
            Recommended  = [ValuePair]::new(0, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Disable silent installation of apps"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::ContentDeliveryManager
            Name         = "SlideshowEnabled"
            Recommended  = [ValuePair]::new(0, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Disable slideshow"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::ContentDeliveryManager
            Name         = "SoftLandingEnabled"
            Recommended  = [ValuePair]::new(0, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Disable soft landing"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::ContentDeliveryManager
            Name         = "SubscribedContent-310093Enabled"
            Recommended  = [ValuePair]::new(0, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Disable subscribed content 310093"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::ContentDeliveryManager
            Name         = "SubscribedContent-314563Enabled"
            Recommended  = [ValuePair]::new(0, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Disable subscribed content 314563"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::ContentDeliveryManager
            Name         = "SubscribedContent-338388Enabled"
            Recommended  = [ValuePair]::new(0, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Disable subscribed content 338388"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::ContentDeliveryManager
            Name         = "SubscribedContent-338389Enabled"
            Recommended  = [ValuePair]::new(0, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Disable subscribed content 338389"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::ContentDeliveryManager
            Name         = "SubscribedContent-353698Enabled"
            Recommended  = [ValuePair]::new(0, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Disable subscribed content 353698"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::ContentDeliveryManager
            Name         = "SubscribedContentEnabled"
            Recommended  = [ValuePair]::new(0, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Disable all subscribed content"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::ContentDeliveryManager
            Name         = "SystemPaneSuggestionsEnabled"
            Recommended  = [ValuePair]::new(0, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Disable system pane suggestions"
        }
    )
    Gaming          = @(
        # Disable game bar
        [pscustomobject]@{
            BaseKey      = [BaseKey]::GameConfigStore
            Name         = "GameDVR_Enabled"
            Recommended  = [ValuePair]::new(0, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Disables Game Bar and Game DVR"
        },
        # Disable enable open Xbox game bar using game controller
        [pscustomobject]@{
            BaseKey      = [BaseKey]::GameBar
            Name         = "UseNexusForGameBarEnabled"
            Recommended  = [ValuePair]::new(0, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Disables opening Xbox Game Bar using a game controller"
        },
        # Enable game mode
        [pscustomobject]@{
            BaseKey      = [BaseKey]::GameBar
            Name         = "AutoGameModeEnabled"
            Recommended  = [ValuePair]::new(1, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Enables Game Mode for better gaming performance"
        },
        # Disable variable refresh rate & enable optimizations for windowed games
        [pscustomobject]@{
            BaseKey      = [BaseKey]::DirectXUserGpuPreferences
            Name         = "DirectXUserGlobalSettings"
            Recommended  = [ValuePair]::new("SwapEffectUpgradeEnable=1;VRROptimizeEnable=0;", [RegistryValueKind]::String)
            DefaultValue = $null
            Description  = "Disables variable refresh rate and enables optimizations for windowed games"
        },
        # Disable Xbox GameDVR
        [pscustomobject]@{
            BaseKey      = [BaseKey]::GameDVR
            Name         = "AllowGameDVR"
            Recommended  = [ValuePair]::new(0, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Disables Xbox GameDVR to improve gaming performance"
        },
        # Enable Old Nvidia Sharpening
        [pscustomobject]@{
            BaseKey      = [BaseKey]::NvidiaFTS
            Name         = "EnableGR535"
            Recommended  = [ValuePair]::new(0, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Enables old Nvidia sharpening for better image quality"
        },
        # Gives Multimedia Applications like Games and Video Editing a Higher Priority
        [pscustomobject]@{
            BaseKey      = [BaseKey]::MultimediaSystemProfile
            Name         = "SystemResponsiveness"
            Recommended  = [ValuePair]::new(0, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Improves system responsiveness for multimedia applications like games and video editing"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::MultimediaSystemProfile
            Name         = "NetworkThrottlingIndex"
            Recommended  = [ValuePair]::new(10, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Adjusts network throttling index for better gaming performance"
        },
        # Gives GPU and CPU a Higher Priority for Gaming and Gives Games a higher priority in the system's scheduling
        [pscustomobject]@{
            BaseKey      = [BaseKey]::MultimediaSystemProfileTasksGames
            Name         = "GPU Priority"
            Recommended  = [ValuePair]::new(8, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Increases GPU priority for gaming"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::MultimediaSystemProfileTasksGames
            Name         = "Priority"
            Recommended  = [ValuePair]::new(6, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Increases CPU priority for gaming"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::MultimediaSystemProfileTasksGames
            Name         = "Scheduling Category"
            Recommended  = [ValuePair]::new("High", [RegistryValueKind]::String)
            DefaultValue = $null
            Description  = "Sets scheduling category to High for games"
        },
        # Turn on hardware accelerated GPU scheduling
        [pscustomobject]@{
            BaseKey      = [BaseKey]::GraphicsDrivers
            Name         = "HwSchMode"
            Recommended  = [ValuePair]::new(2, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Enables hardware-accelerated GPU scheduling"
        },
        # Adjust for best performance of programs
        [pscustomobject]@{
            BaseKey      = [BaseKey]::PriorityControl
            Name         = "Win32PrioritySeparation"
            Recommended  = [ValuePair]::new(38, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Adjusts Win32 priority separation for best performance of programs"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::StorageSensePolicies
            Name         = "AllowStorageSenseGlobal"
            Recommended  = [ValuePair]::new(0, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Disables Storage Sense"
        }
    )
    Updates         = @(
        # Automatic Updates (AU)
        [pscustomobject]@{
            BaseKey      = [BaseKey]::WindowsUpdate
            Name         = "NoAutoUpdate"
            Recommended  = [ValuePair]::new(1, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Disable automatic updates"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::WindowsUpdate
            Name         = "AUOptions"
            Recommended  = [ValuePair]::new(2, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Configure automatic update behavior"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::WindowsUpdate
            Name         = "AutoInstallMinorUpdates"
            Recommended  = [ValuePair]::new(0, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Disable automatic installation of minor updates"
        },

        # Windows Update Policies
        [pscustomobject]@{
            BaseKey      = [BaseKey]::WindowsUpdateMain
            Name         = "TargetReleaseVersion"
            Recommended  = [ValuePair]::new(1, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Enable target version configuration"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::WindowsUpdateMain
            Name         = "TargetReleaseVersionInfo"
            Recommended  = [ValuePair]::new("22H2", [RegistryValueKind]::String)
            DefaultValue = $null
            Description  = "Specify target feature update version"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::WindowsUpdateMain
            Name         = "ProductVersion"
            Recommended  = [ValuePair]::new("Windows 10", [RegistryValueKind]::String)
            DefaultValue = $null
            Description  = "Lock OS version to Windows 10 (Manual Upgrade to 11 still Allowed)"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::WindowsUpdateMain
            Name         = "DeferFeatureUpdates"
            Recommended  = [ValuePair]::new(1, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Defer feature updates"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::WindowsUpdateMain
            Name         = "DeferFeatureUpdatesPeriodInDays"
            Recommended  = [ValuePair]::new(365, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Feature update deferral period (days)"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::WindowsUpdateMain
            Name         = "DeferQualityUpdates"
            Recommended  = [ValuePair]::new(1, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Defer quality updates"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::WindowsUpdateMain
            Name         = "DeferQualityUpdatesPeriodInDays"
            Recommended  = [ValuePair]::new(7, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Quality update deferral period (days)"
        },

        # Delivery Optimization
        [pscustomobject]@{
            BaseKey      = [BaseKey]::DeliveryOptimization
            Name         = "DODownloadMode"
            Recommended  = [ValuePair]::new(0, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Disable peer-to-peer update distribution"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::WindowsStorePolicies
            Name         = "AutoDownload"
            Recommended  = [ValuePair]::new(2, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Disables automatic updates for Microsoft Store apps"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::AppxPolicies
            Name         = "AllowAutomaticAppArchiving"
            Recommended  = [ValuePair]::new(0, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Disables automatic archiving of unused apps"
        }
    )
    Personalization = @(
        [pscustomobject]@{
            BaseKey      = [BaseKey]::ThemesPersonalize
            Name         = "AppsUseLightTheme"
            Recommended  = [ValuePair]::new(0, [RegistryValueKind]::DWord)
            DefaultValue = 1 
            Description  = "Application theme (0=Dark)"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::ThemesPersonalize
            Name         = "SystemUsesLightTheme"
            Recommended  = [ValuePair]::new(0, [RegistryValueKind]::DWord)
            DefaultValue = 1  
            Description  = "System theme (0=Dark)"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::ThemesPersonalize
            Name         = "EnableTransparency"
            Recommended  = [ValuePair]::new(1, [RegistryValueKind]::DWord)
            DefaultValue = 1 
            Description  = "Transparency effects"
        }
    )
    Taskbar         = @(
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Taskband
            Name         = "Favorites"
            Recommended  = [ValuePair]::new([byte[]](
                    0x00, 0xaa, 0x01, 0x00, 0x00, 0x3a, 0x00, 0x1f, 0x80, 0xc8, 0x27, 0x34, 0x1f, 0x10, 0x5c, 0x10,
                    0x42, 0xaa, 0x03, 0x2e, 0xe4, 0x52, 0x87, 0xd6, 0x68, 0x26, 0x00, 0x01, 0x00, 0x26, 0x00, 0xef,
                    0xbe, 0x10, 0x00, 0x00, 0x00, 0xf4, 0x7e, 0x76, 0xfa, 0xde, 0x9d, 0xda, 0x01, 0x40, 0x61, 0x5d,
                    0x09, 0xdf, 0x9d, 0xda, 0x01, 0x19, 0xb8, 0x5f, 0x09, 0xdf, 0x9d, 0xda, 0x01, 0x14, 0x00, 0x56,
                    0x00, 0x31, 0x00, 0x00, 0x00, 0x00, 0x00, 0xa4, 0x58, 0xa9, 0x26, 0x10, 0x00, 0x54, 0x61, 0x73,
                    0x6b, 0x42, 0x61, 0x72, 0x00, 0x40, 0x00, 0x09, 0x00, 0x04, 0x00, 0xef, 0xbe, 0xa4, 0x58, 0xa9,
                    0x26, 0xa4, 0x58, 0xa9, 0x26, 0x2e, 0x00, 0x00, 0x00, 0xde, 0x9c, 0x01, 0x00, 0x00, 0x00, 0x02,
                    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x0c,
                    0xf4, 0x85, 0x00, 0x54, 0x00, 0x61, 0x00, 0x73, 0x00, 0x6b, 0x00, 0x42, 0x00, 0x61, 0x00, 0x72,
                    0x00, 0x00, 0x00, 0x16, 0x00, 0x18, 0x01, 0x32, 0x00, 0x8a, 0x04, 0x00, 0x00, 0xa4, 0x58, 0xb6,
                    0x26, 0x20, 0x00, 0x46, 0x49, 0x4c, 0x45, 0x45, 0x58, 0x7e, 0x31, 0x2e, 0x4c, 0x4e, 0x4b, 0x00,
                    0x00, 0x54, 0x00, 0x09, 0x00, 0x04, 0x00, 0xef, 0xbe, 0xa4, 0x58, 0xb6, 0x26, 0xa4, 0x58, 0xb6,
                    0x26, 0x2e, 0x00, 0x00, 0x00, 0xb7, 0xa8, 0x01, 0x00, 0x00, 0x00, 0x04, 0x00, 0x00, 0x00, 0x00,
                    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xc0, 0x5a, 0x1e, 0x01, 0x46,
                    0x00, 0x69, 0x00, 0x6c, 0x00, 0x65, 0x00, 0x20, 0x00, 0x45, 0x00, 0x78, 0x00, 0x70, 0x00, 0x6c,
                    0x00, 0x6f, 0x00, 0x72, 0x00, 0x65, 0x00, 0x72, 0x00, 0x2e, 0x00, 0x6c, 0x00, 0x6e, 0x00, 0x6b,
                    0x00, 0x00, 0x00, 0x1c, 0x00, 0x22, 0x00, 0x00, 0x00, 0x1e, 0x00, 0xef, 0xbe, 0x02, 0x00, 0x55,
                    0x00, 0x73, 0x00, 0x65, 0x00, 0x72, 0x00, 0x50, 0x00, 0x69, 0x00, 0x6e, 0x00, 0x6e, 0x00, 0x65,
                    0x00, 0x64, 0x00, 0x00, 0x00, 0x1c, 0x00, 0x12, 0x00, 0x00, 0x00, 0x2b, 0x00, 0xef, 0xbe, 0x19,
                    0xb8, 0x5f, 0x09, 0xdf, 0x9d, 0xda, 0x01, 0x1c, 0x00, 0x74, 0x00, 0x00, 0x00, 0x1d, 0x00, 0xef,
                    0xbe, 0x02, 0x00, 0x7b, 0x00, 0x46, 0x00, 0x33, 0x00, 0x38, 0x00, 0x42, 0x00, 0x46, 0x00, 0x34,
                    0x00, 0x30, 0x00, 0x34, 0x00, 0x2d, 0x00, 0x31, 0x00, 0x44, 0x00, 0x34, 0x00, 0x33, 0x00, 0x2d,
                    0x00, 0x34, 0x00, 0x32, 0x00, 0x46, 0x00, 0x32, 0x00, 0x2d, 0x00, 0x39, 0x00, 0x33, 0x00, 0x30,
                    0x00, 0x35, 0x00, 0x2d, 0x00, 0x36, 0x00, 0x37, 0x00, 0x44, 0x00, 0x45, 0x00, 0x30, 0x00, 0x42,
                    0x00, 0x32, 0x00, 0x38, 0x00, 0x46, 0x00, 0x43, 0x00, 0x32, 0x00, 0x33, 0x00, 0x7d, 0x00, 0x5c,
                    0x00, 0x65, 0x00, 0x78, 0x00, 0x70, 0x00, 0x6c, 0x00, 0x6f, 0x00, 0x72, 0x00, 0x65, 0x00, 0x72,
                    0x00, 0x2e, 0x00, 0x65, 0x00, 0x78, 0x00, 0x65, 0x00, 0x00, 0x00, 0x1c, 0x00, 0x00, 0x00, 0xff
                ), [RegistryValueKind]::Binary)
            DefaultValue = $null
            Description  = "File Explorer pinning and taskbar layout"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::TaskbarChat
            Name         = "ChatIcon"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Windows Chat icon visibility"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::TaskbarFeeds
            Name         = "EnableFeeds"
            Recommended  = [ValuePair]::new(0, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Disable news and interests feed"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::PolicyManagerNews
            Name         = "value"
            Recommended  = [ValuePair]::new(0, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Block news and interests"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::TaskbarDsh
            Name         = "AllowNewsAndInterests"
            Recommended  = [ValuePair]::new(0, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Disable news and interests"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::LMPolicyExplorer
            Name         = "HideSCAMeetNow"
            Recommended  = [ValuePair]::new(1, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Hide Meet Now button"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::CUExplorerAdvanced
            Name         = "TaskbarMn"
            Recommended  = [ValuePair]::new(0, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Taskbar menu configuration"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::CUExplorerAdvanced
            Name         = "ShowTaskViewButton"
            Recommended  = [ValuePair]::new(0, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Hide Task View button"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::CUExplorer
            Name         = "EnableAutoTray"
            Recommended  = [ValuePair]::new(0, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "System tray icon behavior"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::CUPolicyExplorer
            Name         = "NoStartMenuMFUprogramsList"
            Recommended  = [ValuePair]::new(0, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Clear frequently used programs list"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::CUPolicyExplorer
            Name         = "HideSCAMeetNow"
            Recommended  = [ValuePair]::new(1, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Hide Meet Now button (user)"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::CUSearch
            Name         = "SearchboxTaskbarMode"
            Recommended  = [ValuePair]::new(0, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Search box appearance"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::CUExplorerAdvanced
            Name         = "ShowCopilotButton"
            Recommended  = [ValuePair]::new(0, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Hide Copilot button"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::CUExplorerAdvanced
            Name         = "TaskbarSn"
            Recommended  = [ValuePair]::new(0, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Taskbar system notifications"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::CUExplorerAdvanced
            Name         = "TaskbarAl"
            Recommended  = [ValuePair]::new(0, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Left-align taskbar icons"
        }
    )
    Explorer        = @(
        [pscustomobject]@{
            BaseKey      = [BaseKey]::FileSystem
            Name         = "LongPathsEnabled"
            Recommended  = [ValuePair]::new(1, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Enables long file paths (up to 32,767 characters)"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::CloudContent
            Name         = "DisableSpotlightCollectionOnDesktop"
            Recommended  = [ValuePair]::new(1, [RegistryValueKind]::DWord)
            DefaultValue = [ValuePair]::new(0, [RegistryValueKind]::DWord)
            Description  = "Disables Windows Spotlight wallpaper feature"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::WorkplaceJoin
            Name         = "BlockAADWorkplaceJoin"
            Recommended  = [ValuePair]::new(1, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Blocks 'Allow my organization to manage my device' pop-up"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::MyComputerNamespace
            Name         = "{0DB7E03F-FC29-4DC6-9020-FF41B59E513A}"
            Recommended  = [ValuePair]::new($null, [RegistryValueKind]::None)
            DefaultValue = $null
            Description  = "Removes 3D Objects from This PC"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::MyComputerNamespaceWOW64
            Name         = "{0DB7E03F-FC29-4DC6-9020-FF41B59E513A}"
            Recommended  = [ValuePair]::new($null, [RegistryValueKind]::None)
            DefaultValue = $null
            Description  = "Removes 3D Objects from This PC (WOW64)"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::DesktopNamespace
            Name         = "{f874310e-b6b7-47dc-bc84-b9e6b38f5903}"
            Recommended  = [ValuePair]::new($null, [RegistryValueKind]::None)
            DefaultValue = $null
            Description  = "Removes Home Folder from Navigation Pane"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::CUExplorerAdvanced
            Name         = "LaunchTo"
            Recommended  = [ValuePair]::new(1, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Opens File Explorer to 'This PC'"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::CUExplorerAdvanced
            Name         = "HideFileExt"
            Recommended  = [ValuePair]::new(0, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Shows file name extensions"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::CUExplorerAdvanced
            Name         = "FolderContentsInfoTip"
            Recommended  = [ValuePair]::new(0, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Disables file size information in folder tips"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::CUExplorerAdvanced
            Name         = "ShowInfoTip"
            Recommended  = [ValuePair]::new(0, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Disables pop-up descriptions for folder and desktop items"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::CUExplorerAdvanced
            Name         = "ShowPreviewHandlers"
            Recommended  = [ValuePair]::new(0, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Disables preview handlers in preview pane"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::CUExplorerAdvanced
            Name         = "ShowStatusBar"
            Recommended  = [ValuePair]::new(0, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Disables status bar in File Explorer"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::CUExplorerAdvanced
            Name         = "ShowSyncProviderNotifications"
            Recommended  = [ValuePair]::new(0, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Disables sync provider notifications"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::CUExplorerAdvanced
            Name         = "SharingWizardOn"
            Recommended  = [ValuePair]::new(0, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Disables sharing wizard"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::CUExplorerAdvanced
            Name         = "TaskbarAnimations"
            Recommended  = [ValuePair]::new(0, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Disables taskbar animations"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::CUExplorerAdvanced
            Name         = "IconsOnly"
            Recommended  = [ValuePair]::new(0, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Shows thumbnails instead of icons"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::CUExplorerAdvanced
            Name         = "ListviewAlphaSelect"
            Recommended  = [ValuePair]::new(0, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Disables translucent selection rectangle"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::CUExplorerAdvanced
            Name         = "ListviewShadow"
            Recommended  = [ValuePair]::new(0, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Disables drop shadows for icon labels"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::CUExplorerAdvanced
            Name         = "Start_AccountNotifications"
            Recommended  = [ValuePair]::new(0, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Disables account-related notifications"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::CUExplorerAdvanced
            Name         = "Start_TrackDocs"
            Recommended  = [ValuePair]::new(0, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Disables recently opened items in Start and File Explorer"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::CUExplorerAdvanced
            Name         = "Start_IrisRecommendations"
            Recommended  = [ValuePair]::new(0, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Disables recommendations for tips and shortcuts"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::CUExplorerAdvanced
            Name         = "SnapAssist"
            Recommended  = [ValuePair]::new(0, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Disables Snap Assist"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::CUExplorerAdvanced
            Name         = "DITest"
            Recommended  = [ValuePair]::new(0, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Disables DITest"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::CUExplorerAdvanced
            Name         = "EnableSnapBar"
            Recommended  = [ValuePair]::new(0, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Disables Snap Bar"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::CUExplorerAdvanced
            Name         = "EnableTaskGroups"
            Recommended  = [ValuePair]::new(0, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Disables Task Groups"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::CUExplorerAdvanced
            Name         = "EnableSnapAssistFlyout"
            Recommended  = [ValuePair]::new(0, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Disables Snap Assist Flyout"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::CUExplorerAdvanced
            Name         = "SnapFill"
            Recommended  = [ValuePair]::new(0, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Disables Snap Fill"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::CUExplorerAdvanced
            Name         = "JointResize"
            Recommended  = [ValuePair]::new(0, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Disables Joint Resize"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::CUExplorerAdvanced
            Name         = "MultiTaskingAltTabFilter"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Sets Alt+Tab to show open windows only"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Explorer
            Name         = "ShowFrequent"
            Recommended  = [ValuePair]::new(0, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Hides frequent folders in Quick Access"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Explorer
            Name         = "ShowCloudFilesInQuickAccess"
            Recommended  = [ValuePair]::new(0, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Disables files from Office.com in Quick Access"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::CabinetState
            Name         = "FullPath"
            Recommended  = [ValuePair]::new(1, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Enables full path in the title bar"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::ControlPanelMouse
            Name         = "MouseSpeed"
            Recommended  = [ValuePair]::new("0", [RegistryValueKind]::String)
            DefaultValue = $null
            Description  = "Disables enhance pointer precision (mouse fix)"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::ControlPanelMouse
            Name         = "MouseThreshold1"
            Recommended  = [ValuePair]::new("0", [RegistryValueKind]::String)
            DefaultValue = $null
            Description  = "Disables mouse threshold 1"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::ControlPanelMouse
            Name         = "MouseThreshold2"
            Recommended  = [ValuePair]::new("0", [RegistryValueKind]::String)
            DefaultValue = $null
            Description  = "Disables mouse threshold 2"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::ControlPanelMouse
            Name         = "MouseSensitivity"
            Recommended  = [ValuePair]::new("10", [RegistryValueKind]::String)
            DefaultValue = $null
            Description  = "Sets mouse sensitivity to 10"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::ControlPanelMouse
            Name         = "SmoothMouseXCurve"
            Recommended  = [ValuePair]::new(
                [byte[]]@(0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xC0, 0xCC, 0x0C, 0x00, 0x00, 0x00, 0x00, 0x00, 0x80, 0x99, 0x19, 0x00, 0x00, 0x00, 0x00, 0x00, 0x40, 0x66, 0x26, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x33, 0x33, 0x00, 0x00, 0x00, 0x00, 0x00),
                [RegistryValueKind]::Binary
            )
            DefaultValue = $null
            Description  = "Sets SmoothMouseXCurve"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::ControlPanelMouse
            Name         = "SmoothMouseYCurve"
            Recommended  = [ValuePair]::new(
                [byte[]]@(0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x38, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x70, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xA8, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xE0, 0x00, 0x00, 0x00, 0x00, 0x00),
                [RegistryValueKind]::Binary
            )
            DefaultValue = $null
            Description  = "Sets SmoothMouseYCurve"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::VisualEffects
            Name         = "VisualFXSetting"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Sets appearance options to custom"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::ControlPanelDesktop
            Name         = "UserPreferencesMask"
            Recommended  = [ValuePair]::new(
                [byte[]]@(0x90, 0x12, 0x03, 0x80, 0x10, 0x00, 0x00, 0x00),
                [RegistryValueKind]::Binary
            )
            DefaultValue = $null
            Description  = "Disables animations and visual effects"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::ControlPanelDesktop
            Name         = "FontSmoothing"
            Recommended  = [ValuePair]::new("2", [RegistryValueKind]::String)
            DefaultValue = $null
            Description  = "Enables smooth edges of screen fonts"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::ControlPanelDesktop
            Name         = "LogPixels"
            Recommended  = [ValuePair]::new(96, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Sets DPI scaling to 100%"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::ControlPanelDesktop
            Name         = "Win8DpiScaling"
            Recommended  = [ValuePair]::new(1, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Enables Win8 DPI scaling"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::ControlPanelDesktop
            Name         = "EnablePerProcessSystemDPI"
            Recommended  = [ValuePair]::new(0, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Disables per-process system DPI"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::ControlPanelDesktop
            Name         = "MenuShowDelay"
            Recommended  = [ValuePair]::new("0", [RegistryValueKind]::String)
            DefaultValue = $null
            Description  = "Disables menu show delay"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::TabletTip
            Name         = "EnableAutoShiftEngage"
            Recommended  = [ValuePair]::new(0, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Disables auto-capitalization"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::TabletTip
            Name         = "EnableKeyAudioFeedback"
            Recommended  = [ValuePair]::new(0, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Disables key sounds"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::TabletTip
            Name         = "EnableDoubleTapSpace"
            Recommended  = [ValuePair]::new(0, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Disables double-tap spacebar period"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::TabletTip
            Name         = "IsKeyBackgroundEnabled"
            Recommended  = [ValuePair]::new(0, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Disables key background"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::DesktopNamespace
            Name         = "{e88865ea-0e1c-4e20-9aa6-edcd0212c87c}"
            Recommended  = [ValuePair]::new($null, [RegistryValueKind]::None)
            DefaultValue = $null
            Description  = "Removes gallery from navigation pane"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::ClassesCLSID
            SubKeySuffix = "{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32"
            Recommended  = [ValuePair]::new("", [RegistryValueKind]::String)
            DefaultValue = $null
            Description  = "Restores the classic context menu"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::ImmersiveShell
            Name         = "TabletMode"
            Recommended  = [ValuePair]::new(0, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Disables Tablet Mode"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::ImmersiveShell
            Name         = "SignInMode"
            Recommended  = [ValuePair]::new(1, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Ensures the system always goes to desktop mode on sign-in"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::InputSettings
            Name         = "IsVoiceTypingKeyEnabled"
            Recommended  = [ValuePair]::new(0, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Disables voice typing microphone button"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::InputSettings
            Name         = "InsightsEnabled"
            Recommended  = [ValuePair]::new(0, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Disables typing insights"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Explorer
            SubKeySuffix = "SmartActionPlatform\SmartClipboard"
            Name         = "Disabled"
            Recommended  = [ValuePair]::new(1, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Disables suggested actions"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Explorer
            SubKeySuffix = "Windows"
            Name         = "LegacyDefaultPrinterMode"
            Recommended  = [ValuePair]::new(1, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Disables Windows managing default printer"
        }
    )
    Notifications   = @(
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Notifications
            SubKeySuffix = "PushNotifications"
            Name         = "ToastEnabled"
            Recommended  = [ValuePair]::new(0, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Disables toast notifications"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Notifications
            SubKeySuffix = "PushNotifications"
            Name         = "LockScreenToastEnabled"
            Recommended  = [ValuePair]::new(0, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Disables notifications on lock screen"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Notifications
            SubKeySuffix = "Notifications\Settings"
            Name         = "NOC_GLOBAL_SETTING_ALLOW_NOTIFICATION_SOUND"
            Recommended  = [ValuePair]::new(0, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Disables notification sounds"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Notifications
            SubKeySuffix = "Notifications\Settings"
            Name         = "NOC_GLOBAL_SETTING_ALLOW_TOASTS_ABOVE_LOCK"
            Recommended  = [ValuePair]::new(0, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Disables notifications above lock screen"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Notifications
            SubKeySuffix = "Notifications\Settings"
            Name         = "NOC_GLOBAL_SETTING_ALLOW_CRITICAL_TOASTS_ABOVE_LOCK"
            Recommended  = [ValuePair]::new(0, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Disables critical notifications above lock screen"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Notifications
            SubKeySuffix = "Notifications\Settings\Windows.SystemToast.SecurityAndMaintenance"
            Name         = "Enabled"
            Recommended  = [ValuePair]::new(0, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Disables security and maintenance notifications"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Notifications
            SubKeySuffix = "Notifications\Settings\windows.immersivecontrolpanel_cw5n1h2txyewy!microsoft.windows.immersivecontrolpanel"
            Name         = "Enabled"
            Recommended  = [ValuePair]::new(0, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Disables immersive control panel notifications"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Notifications
            SubKeySuffix = "Notifications\Settings\Windows.SystemToast.CapabilityAccess"
            Name         = "Enabled"
            Recommended  = [ValuePair]::new(0, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Disables capability access notifications"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Notifications
            SubKeySuffix = "Notifications\Settings\Windows.SystemToast.StartupApp"
            Name         = "Enabled"
            Recommended  = [ValuePair]::new(0, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Disables startup app notifications"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Notifications
            SubKeySuffix = "UserProfileEngagement"
            Name         = "ScoobeSystemSettingEnabled"
            Recommended  = [ValuePair]::new(0, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Disables system setting engagement notifications"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::ControlPanelDesktop
            SubKeySuffix = "TimeDate"
            Name         = "DstNotification"
            Recommended  = [ValuePair]::new(0, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Disables clock change notifications"
        }
    )
    Sound           = @(
        [pscustomobject]@{
            BaseKey      = [BaseKey]::BootAnimation
            Name         = "DisableStartupSound"
            Recommended  = [ValuePair]::new(1, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Disables the startup sound during boot"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::EditionOverrides
            Name         = "UserSetting_DisableStartupSound"
            Recommended  = [ValuePair]::new(1, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Disables the startup sound for the user"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::MultimediaAudio
            Name         = "UserDuckingPreference"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Configures sound communications to do nothing (no ducking)"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::SpeechOneCoreSettings
            Name         = "AgentActivationEnabled"
            Recommended  = [ValuePair]::new(0, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Disables voice activation for all apps"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::SpeechOneCoreSettings
            Name         = "AgentActivationLastUsed"
            Recommended  = [ValuePair]::new(0, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Disables the last used voice activation setting"
        }
    )
    Accessibility   = @(
        [pscustomobject]@{
            BaseKey      = [BaseKey]::EaseOfAccess
            Name         = "selfvoice"
            Recommended  = [ValuePair]::new(0, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Disables self voice feature"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::EaseOfAccess
            Name         = "selfscan"
            Recommended  = [ValuePair]::new(0, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Disables self scan feature"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Accessibility
            Name         = "Sound on Activation"
            Recommended  = [ValuePair]::new("0", [RegistryValueKind]::String)
            DefaultValue = $null
            Description  = "Disables activation sounds"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Accessibility
            Name         = "Warning Sounds"
            Recommended  = [ValuePair]::new("0", [RegistryValueKind]::String)
            DefaultValue = $null
            Description  = "Disables warning sounds"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Accessibility
            SubKeySuffix = "HighContrast"
            Name         = "Flags"
            Recommended  = [ValuePair]::new("4194", [RegistryValueKind]::String)
            DefaultValue = $null
            Description  = "Configures high contrast settings"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Accessibility
            SubKeySuffix = "Keyboard Response"
            Name         = "Flags"
            Recommended  = [ValuePair]::new("2", [RegistryValueKind]::String)
            DefaultValue = $null
            Description  = "Configures keyboard response settings"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Accessibility
            SubKeySuffix = "Keyboard Response"
            Name         = "AutoRepeatRate"
            Recommended  = [ValuePair]::new("0", [RegistryValueKind]::String)
            DefaultValue = $null
            Description  = "Sets auto-repeat rate"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Accessibility
            SubKeySuffix = "Keyboard Response"
            Name         = "AutoRepeatDelay"
            Recommended  = [ValuePair]::new("0", [RegistryValueKind]::String)
            DefaultValue = $null
            Description  = "Sets auto-repeat delay"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Accessibility
            SubKeySuffix = "MouseKeys"
            Name         = "Flags"
            Recommended  = [ValuePair]::new("130", [RegistryValueKind]::String)
            DefaultValue = $null
            Description  = "Configures mouse keys settings"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Accessibility
            SubKeySuffix = "MouseKeys"
            Name         = "MaximumSpeed"
            Recommended  = [ValuePair]::new("39", [RegistryValueKind]::String)
            DefaultValue = $null
            Description  = "Sets maximum mouse keys speed"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Accessibility
            SubKeySuffix = "MouseKeys"
            Name         = "TimeToMaximumSpeed"
            Recommended  = [ValuePair]::new("3000", [RegistryValueKind]::String)
            DefaultValue = $null
            Description  = "Sets time to reach maximum speed"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Accessibility
            SubKeySuffix = "StickyKeys"
            Name         = "Flags"
            Recommended  = [ValuePair]::new("2", [RegistryValueKind]::String)
            DefaultValue = $null
            Description  = "Configures sticky keys settings"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Accessibility
            SubKeySuffix = "ToggleKeys"
            Name         = "Flags"
            Recommended  = [ValuePair]::new("34", [RegistryValueKind]::String)
            DefaultValue = $null
            Description  = "Configures toggle keys settings"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Accessibility
            SubKeySuffix = "SoundSentry"
            Name         = "Flags"
            Recommended  = [ValuePair]::new("0", [RegistryValueKind]::String)
            DefaultValue = $null
            Description  = "Configures sound sentry settings"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Accessibility
            SubKeySuffix = "SoundSentry"
            Name         = "FSTextEffect"
            Recommended  = [ValuePair]::new("0", [RegistryValueKind]::String)
            DefaultValue = $null
            Description  = "Disables fullscreen text effect"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Accessibility
            SubKeySuffix = "SoundSentry"
            Name         = "TextEffect"
            Recommended  = [ValuePair]::new("0", [RegistryValueKind]::String)
            DefaultValue = $null
            Description  = "Disables text effect"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Accessibility
            SubKeySuffix = "SoundSentry"
            Name         = "WindowsEffect"
            Recommended  = [ValuePair]::new("0", [RegistryValueKind]::String)
            DefaultValue = $null
            Description  = "Disables windows effect"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Accessibility
            SubKeySuffix = "SlateLaunch"
            Name         = "ATapp"
            Recommended  = [ValuePair]::new("", [RegistryValueKind]::String)
            DefaultValue = $null
            Description  = "Configures slate launch app"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Accessibility
            SubKeySuffix = "SlateLaunch"
            Name         = "LaunchAT"
            Recommended  = [ValuePair]::new(0, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Disables automatic launch of accessibility tools"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Explorer
            SubKeySuffix = "ScreenMagnifier"
            Name         = "FollowCaret"
            Recommended  = [ValuePair]::new(0, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Disables magnifier following caret"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Explorer
            SubKeySuffix = "ScreenMagnifier"
            Name         = "FollowNarrator"
            Recommended  = [ValuePair]::new(0, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Disables magnifier following narrator"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Explorer
            SubKeySuffix = "ScreenMagnifier"
            Name         = "FollowMouse"
            Recommended  = [ValuePair]::new(0, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Disables magnifier following mouse"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Explorer
            SubKeySuffix = "ScreenMagnifier"
            Name         = "FollowFocus"
            Recommended  = [ValuePair]::new(0, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Disables magnifier following focus"
        }
    )
    Search          = @(
        [pscustomobject]@{
            BaseKey      = [BaseKey]::SearchSettings
            Name         = "IsDynamicSearchBoxEnabled"
            Recommended  = [ValuePair]::new(0, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Disables search highlights"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::SearchSettings
            Name         = "IsDeviceSearchHistoryEnabled"
            Recommended  = [ValuePair]::new(0, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Disables search history"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::SearchSettings
            Name         = "SafeSearchMode"
            Recommended  = [ValuePair]::new(0, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Disables safe search"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::SearchSettings
            Name         = "IsAADCloudSearchEnabled"
            Recommended  = [ValuePair]::new(0, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Disables cloud content search for work/school account"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::SearchSettings
            Name         = "IsMSACloudSearchEnabled"
            Recommended  = [ValuePair]::new(0, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Disables cloud content search for Microsoft account"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::ExplorerPolicies
            Name         = "DisableSearchBoxSuggestions"
            Recommended  = [ValuePair]::new(1, [RegistryValueKind]::DWord)
            DefaultValue = $null
            Description  = "Disables web search in the Start menu"
        }
    )
    Services        = @(
        # Disabled Services
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "AJRouter"
            Name         = "Start"
            Recommended  = [ValuePair]::new(4, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "AllJoyn Router Service"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "AppVClient"
            Name         = "Start"
            Recommended  = [ValuePair]::new(4, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Application Virtualization Client"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "AssignedAccessManagerSvc"
            Name         = "Start"
            Recommended  = [ValuePair]::new(4, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Assigned Access Manager Service"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "DiagTrack"
            Name         = "Start"
            Recommended  = [ValuePair]::new(4, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Connected User Experiences and Telemetry"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "DialogBlockingService"
            Name         = "Start"
            Recommended  = [ValuePair]::new(4, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Dialog Blocking Service"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "NetTcpPortSharing"
            Name         = "Start"
            Recommended  = [ValuePair]::new(4, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Net.Tcp Port Sharing Service"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "RemoteAccess"
            Name         = "Start"
            Recommended  = [ValuePair]::new(4, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Remote Access Connection Manager"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "RemoteRegistry"
            Name         = "Start"
            Recommended  = [ValuePair]::new(4, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Remote Registry Service"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "UevAgentService"
            Name         = "Start"
            Recommended  = [ValuePair]::new(4, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "User Experience Virtualization Service"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "shpamsvc"
            Name         = "Start"
            Recommended  = [ValuePair]::new(4, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Shared Protection Access Manager"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "ssh-agent"
            Name         = "Start"
            Recommended  = [ValuePair]::new(4, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "OpenSSH Authentication Agent"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "tzautoupdate"
            Name         = "Start"
            Recommended  = [ValuePair]::new(4, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Auto Time Zone Updater"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "uhssvc"
            Name         = "Start"
            Recommended  = [ValuePair]::new(4, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Microsoft Update Health Service"
        },

        # Manual Services
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "ALG"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Application Layer Gateway Service"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "AppIDSvc"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Application Identity"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "AppMgmt"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Application Management"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "AppReadiness"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "App Readiness"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "AppXSvc"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "AppX Deployment Service"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "Appinfo"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Application Information"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "AxInstSV"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "ActiveX Installer"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "BDESVC"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "BitLocker Drive Encryption Service"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "BITS"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Background Intelligent Transfer Service"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "BTAGService"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Bluetooth Audio Gateway Service"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "Browser"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Computer Browser"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "CDPSvc"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Connected Devices Platform Service"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "COMSysApp"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "COM+ System Application"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "CertPropSvc"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Certificate Propagation"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "ClipSVC"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Client License Service"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "CscService"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Offline Files"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "DcpSvc"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Data Collection and Publishing Service"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "DevQueryBroker"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "DevQuery Background Discovery Broker"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "DeviceAssociationService"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Device Association Service"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "DeviceInstall"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Device Install Service"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "DisplayEnhancementService"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Display Enhancement Service"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "DmEnrollmentSvc"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Device Management Enrollment Service"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "DoSvc"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Delivery Optimization"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "DsSvc"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Data Sharing Service"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "DsmSvc"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Device Setup Manager"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "EFS"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Encrypting File System"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "EapHost"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Extensible Authentication Protocol"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "EntAppSvc"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Enterprise App Management Service"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "FDResPub"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Function Discovery Resource Publication"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "Fax"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Fax Service"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "FrameServer"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Windows Camera Frame Server"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "FrameServerMonitor"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Windows Camera Frame Server Monitor"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "GraphicsPerfSvc"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Graphics Performance Monitor Service"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "HvHost"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "HV Host Service"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "IKEEXT"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "IKE and AuthIP IPsec Keying Modules"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "InstallService"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Microsoft Store Install Service"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "InventorySvc"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Inventory and Compatibility Assessment Service"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "IpxlatCfgSvc"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "IP Translation Configuration Service"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "KtmRm"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "KtmRm for Distributed Transaction Coordinator"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "LicenseManager"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Windows License Manager Service"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "LxpSvc"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Language Experience Service"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "MSDTC"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Distributed Transaction Coordinator"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "MSiSCSI"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Microsoft iSCSI Initiator Service"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "MapsBroker"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Downloaded Maps Manager"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "McpManagementService"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Microsoft Connectivity Platform Management Service"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "MicrosoftEdgeElevationService"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Microsoft Edge Elevation Service"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "MixedRealityOpenXRSvc"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Mixed Reality OpenXR Service"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "MsKeyboardFilter"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Microsoft Keyboard Filter"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "NaturalAuthentication"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Natural Authentication"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "NcaSvc"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Network Connectivity Assistant"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "NcbService"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Network Connection Broker"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "NcdAutoSetup"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Network Connected Devices Auto-Setup"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "Netman"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Network Connections"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "NgcCtnrSvc"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Microsoft Passport Container"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "NgcSvc"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Microsoft Passport"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "NlaSvc"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Network Location Awareness"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "PNRPAutoReg"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "PNRP Machine Name Publication Service"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "PNRPsvc"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Peer Name Resolution Protocol"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "PcaSvc"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Program Compatibility Assistant Service"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "PeerDistSvc"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "BranchCache"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "PerfHost"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Performance Counter DLL Host"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "PhoneSvc"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Phone Service"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "PlugPlay"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Plug and Play"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "PolicyAgent"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "IPsec Policy Agent"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "PrintNotify"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Printer Extensions and Notifications"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "PushToInstall"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Windows PushToInstall Service"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "QWAVE"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Quality Windows Audio Video Experience"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "RasAuto"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Remote Access Auto Connection Manager"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "RasMan"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Remote Access Connection Manager"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "RetailDemo"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Retail Demo Service"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "RmSvc"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Radio Management Service"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "RpcLocator"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Remote Procedure Call (RPC) Locator"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "SCPolicySvc"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Smart Card Removal Policy"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "SCardSvr"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Smart Card"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "SDRSVC"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Windows Backup"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "SEMgrSvc"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Payments and NFC/SE Manager"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "SensorDataService"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Sensor Data Service"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "SensorService"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Sensor Service"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "SensrSvc"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Sensor Monitoring Service"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "SessionEnv"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Remote Desktop Configuration"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "SharedAccess"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Internet Connection Sharing"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "SharedRealitySvc"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Spatial Data Service"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "SmsRouter"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Microsoft Windows SMS Router Service"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "SstpSvc"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Secure Socket Tunneling Protocol Service"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "StateRepository"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "State Repository Service"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "StiSvc"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Windows Image Acquisition"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "StorSvc"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Storage Service"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "TabletInputService"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Touch Keyboard and Handwriting Panel Service"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "TapiSrv"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Telephony"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "TextInputManagementService"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Text Input Management Service"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "TieringEngineService"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Storage Tiers Management"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "TimeBrokerSvc"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Time Broker"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "TokenBroker"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Web Account Manager"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "TroubleshootingSvc"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Recommended Troubleshooting Service"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "TrustedInstaller"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Windows Modules Installer"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "UI0Detect"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Interactive Services Detection"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "UmRdpService"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Remote Desktop Services UserMode Port Redirector"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "UsoSvc"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Update Orchestrator Service"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "VSS"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Volume Shadow Copy"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "VacSvc"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Volumetric Audio Compositor Service"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "W32Time"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Windows Time"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "WEPHOSTSVC"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Windows Event Collection Service"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "WFDSConMgrSvc"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Wi-Fi Direct Services Connection Manager Service"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "WMPNetworkSvc"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Windows Media Player Network Sharing Service"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "WManSvc"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Windows Management Service"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "WPDBusEnum"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Portable Device Enumerator Service"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "WSearch"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Windows Search"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "WaaSMedicSvc"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Windows Update Medic Service"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "WalletService"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "WalletService"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "WarpJITSvc"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "WarpJITSvc"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "WbioSrvc"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Windows Biometric Service"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "WdiServiceHost"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Diagnostic Service Host"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "WdiSystemHost"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Diagnostic System Host"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "WebClient"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "WebClient"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "Wecsvc"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Windows Event Collector"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "WerSvc"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Windows Error Reporting Service"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "WiaRpc"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Still Image Acquisition Events"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "WinHttpAutoProxySvc"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "WinHTTP Web Proxy Auto-Discovery Service"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "WinRM"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Windows Remote Management"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "WpcMonSvc"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Parental Controls"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "WpnService"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Windows Push Notifications System Service"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "bthserv"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Bluetooth Support Service"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "defragsvc"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Optimize drives"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "dot3svc"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Wired AutoConfig"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "edgeupdate"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Microsoft Edge Update Service"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "edgeupdatem"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Microsoft Edge Update Service (edgeupdatem)"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "fdPHost"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Function Discovery Provider Host"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "fhsvc"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "File History Service"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "hidserv"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Human Interface Device Service"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "icssvc"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Windows Mobile Hotspot Service"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "lfsvc"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Geolocation Service"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "lltdsvc"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Link-Layer Topology Discovery Mapper"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "msiserver"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Windows Installer"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "netprofm"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Network List Service"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "p2pimsvc"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Peer Networking Identity Manager"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "p2psvc"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Peer Networking Grouping"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "perceptionsimulation"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Windows Perception Simulation Service"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "pla"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Performance Logs & Alerts"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "seclogon"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Secondary Logon"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "smphost"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Microsoft Storage Spaces SMP"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "spectrum"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Windows Perception Service"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "sppsvc"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Software Protection"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "svsvc"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Spot Verifier"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "swprv"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Microsoft Software Shadow Copy Provider"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "upnphost"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "UPnP Device Host"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "vds"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Virtual Disk"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "wbengine"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Block Level Backup Engine Service"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "wcncsvc"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Windows Connect Now - Config Registrar"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "wercplsupport"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Problem Reports Control Panel Support"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "wisvc"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Windows Insider Service"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "wlidsvc"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Microsoft Account Sign-in Assistant"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "wlpasvc"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Local Profile Assistant Service"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "wmiApSrv"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "WMI Performance Adapter"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "workfolderssvc"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Work Folders"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "wuauserv"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Windows Update"
        },
        [pscustomobject]@{
            BaseKey      = [BaseKey]::Services
            SubKeySuffix = "wudfsvc"
            Name         = "Start"
            Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
            DefaultValue = 2
            Description  = "Windows Driver Foundation - User-mode Driver Framework"
        }
    )
}

#region 4. Function Definitions
# ====================================================================================================
# Function Definitions
# Core functionality and helper functions used throughout the application
# ====================================================================================================

# =================================
# Logging Functions
# =================================
function Start-Log {
    param([string]$Path = $SCRIPT:LogPath)
    @"
==== Rocket Log - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ====
Version: $SCRIPT:Version
User: $env:USERNAME
Computer: $env:COMPUTERNAME
Elevated Admin: $(([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
PowerShell Version: $($PSVersionTable.PSVersion)
=============================================
"@ | Out-File $Path
}

function Write-Log {
    param(
        [Parameter(Mandatory)]
        [string]$Message,
        [ValidateSet('INFO', 'SUCCESS', 'WARNING', 'ERROR')]
        [string]$Severity = 'INFO'
    )
    if (-not $SCRIPT:LogEnabled) { return }

    try {
        $timestamp = Get-Date -Format 'HH:mm:ss'
        $Message -split "`n" | ForEach-Object {
            "[$timestamp] [$Severity] $_" | Out-File $SCRIPT:LogPath -Append -ErrorAction Stop
        }
    }
    catch {
        Write-Host "Logging failure: $($_.Exception.Message)"
    }
}

function Stop-Log {
    if ($SCRIPT:LogEnabled) {
        try {
            Write-Log -Message "Script completed successfully" -Severity 'SUCCESS'
            Write-Log -Message "==== Log End - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ====" -Severity 'INFO'
        }
        catch {
            Write-Host "Failed to write final log entries: $($_.Exception.Message)"
        }
    }
}

# ==================================
# Registry Settings Helper Functions
# ==================================

function Backup-Registry {
    [CmdletBinding()]
    param()
    
    try {
        # Define backup directory in Program Files
        $backupDir = Join-Path $env:ProgramFiles "Rocket\Backups\REG"
        
        # Create backup directory if it doesn't exist
        if (-not (Test-Path $backupDir)) {
            New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
        }

        # Check if this is first run by looking for FirstRun backup
        $isFirstRun = -not (Get-ChildItem -Path $backupDir -Filter "RocketBackup_FirstRun.reg" -ErrorAction SilentlyContinue)
        
        # Set backup filename based on whether it's first run
        if ($isFirstRun) {
            $backupFile = Join-Path -Path $backupDir -ChildPath "RocketBackup_FirstRun.reg"
        }
        else {
            $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
            $backupFile = Join-Path -Path $backupDir -ChildPath "RocketBackup_$timestamp.reg"
        }
        
        # Initialize StringBuilder for better performance with large strings
        $regContent = New-Object System.Text.StringBuilder
        $regContent.AppendLine("Windows Registry Editor Version 5.00") | Out-Null
        
        # Process each category in RegConfig
        foreach ($category in $SCRIPT:RegConfig.Keys) {
            foreach ($setting in $SCRIPT:RegConfig[$category]) {
                try {
                    $baseKey = $SCRIPT:BaseKeys[$setting.BaseKey]
                    if ($null -eq $baseKey) { continue }
                    
                    $fullPath = $baseKey.SubKey
                    if ($setting.SubKeySuffix) {
                        $fullPath = Join-Path -Path $fullPath -ChildPath $setting.SubKeySuffix
                    }
                    
                    $hive = switch ($baseKey.Hive) {
                        ([Microsoft.Win32.RegistryHive]::LocalMachine) {
                            $regContent.AppendLine("`n[HKEY_LOCAL_MACHINE\$fullPath]") | Out-Null
                            [Microsoft.Win32.Registry]::LocalMachine
                        }
                        ([Microsoft.Win32.RegistryHive]::CurrentUser) {
                            $regContent.AppendLine("`n[HKEY_CURRENT_USER\$fullPath]") | Out-Null
                            [Microsoft.Win32.Registry]::CurrentUser
                        }
                    }
                    
                    $key = $hive.OpenSubKey($fullPath)
                    if ($key) {
                        if ($key.GetValue($setting.Name, $null) -ne $null) {
                            $value = $key.GetValue($setting.Name)
                            $kind = $key.GetValueKind($setting.Name)
                            
                            $formattedValue = switch ($kind) {
                                "String" { "`"$value`"" }
                                "DWord" { "dword:$('{0:X8}' -f $value)" }
                                "QWord" { "qword:$('{0:X16}' -f $value)" }
                                "Binary" { 
                                    if ($value) {
                                        "hex:" + (($value | ForEach-Object { "{0:X2}" -f $_ }) -join ',')
                                    }
                                    else { "" }
                                }
                                "MultiString" { 
                                    "hex(7):" + (($value | ForEach-Object { 
                                                [System.Text.Encoding]::Unicode.GetBytes("$_`0") | ForEach-Object { 
                                                    "{0:X2}" -f $_ 
                                                }
                                            }) -join ',')
                                }
                                "ExpandString" { 
                                    "hex(2):" + (([System.Text.Encoding]::Unicode.GetBytes("$value`0") | ForEach-Object { 
                                                "{0:X2}" -f $_ 
                                            }) -join ',')
                                }
                                default { "`"$value`"" }
                            }
                            
                            if (![string]::IsNullOrEmpty($setting.Name)) {
                                $regContent.AppendLine("`"$($setting.Name)`"=$formattedValue") | Out-Null
                            }
                            else {
                                $regContent.AppendLine("@=$formattedValue") | Out-Null
                            }
                        }
                        $key.Close()
                    }
                }
                catch {
                    continue
                }
            }
        }
        
        # Write the entire content at once
        [System.IO.File]::WriteAllText($backupFile, $regContent.ToString(), [System.Text.Encoding]::Unicode)
        
        # Verify backup was created
        if (-not (Test-Path -Path $backupFile)) {
            return $false
        }

        # Cleanup old backups if this isn't the first run
        if (-not $isFirstRun) {
            # Get all backup files except FirstRun
            $backups = Get-ChildItem -Path $backupDir -Filter "RocketBackup_*.reg" | 
            Where-Object { $_.Name -ne "RocketBackup_FirstRun.reg" } |
            Sort-Object CreationTime -Descending

            # Keep only the 2 most recent backups
            if ($backups.Count -gt 2) {
                $backups | Select-Object -Skip 2 | Remove-Item -Force
            }
        }

        return $backupFile
    }
    catch {
        return $false
    }
}

function ConvertTo-RegistrySettings {
    [OutputType([hashtable])]
    param()
    
    # Map RegistryValueKind to .NET types with null handling
    $typeMap = @{
        [RegistryValueKind]::DWord        = [int]
        [RegistryValueKind]::QWord        = [long]
        [RegistryValueKind]::String       = [string]
        [RegistryValueKind]::Binary       = [byte[]]
        [RegistryValueKind]::MultiString  = [string[]]
        [RegistryValueKind]::ExpandString = [string]
    }

    $result = @{}    
    foreach ($category in $SCRIPT:RegConfig.Keys) {
        $categorySettings = foreach ($config in $SCRIPT:RegConfig[$category]) {
            # Resolve base key properties
            $base = $SCRIPT:BaseKeys[$config.BaseKey]
            
            # Enhanced null handling
            $recommendedValue = $config.Recommended.Value
            $expectedType = $typeMap[$config.Recommended.Type]

            # Validate null values based on registry type
            if ($null -eq $recommendedValue) {
                if ($config.Recommended.Type -in @([RegistryValueKind]::DWord, [RegistryValueKind]::QWord)) {
                    throw "Null not allowed for DWord/QWord in $($config.Name). Use 0 instead."
                }
            }
            else {
                if ($recommendedValue -isnot $expectedType) {
                    throw "Type mismatch for $($config.Name). Expected $($expectedType.Name), got $($recommendedValue.GetType().Name)"
                }
            }
            
            # Build subkey path
            $subKey = $base.SubKey
            if ($config.SubKeySuffix) {
                $subKey = [IO.Path]::Combine($subKey, $config.SubKeySuffix)
            }
            
            # Create RegistrySetting instance
            [RegistrySetting]::new(
                $base.Hive,
                $subKey,
                $config.Name,
                $recommendedValue,
                $config.Recommended.Type,
                $config.DefaultValue,
                $config.Description
            )
        }
        
        # Add category property
        $categorySettings | ForEach-Object { $_.Category = $category }
        $result[$category] = $categorySettings
    }
    
    return $result
}

# Initialize RegSettings using conversion
$SCRIPT:RegSettings = ConvertTo-RegistrySettings

# Invoke Registry Settings helper function
function Invoke-Settings {
    param(
        [ValidateSet('Privacy', 'Gaming', 'Updates', 'Taskbar', 'Explorer', 'Accessibility', 'Search', 'Notifications', 'Sound', 'Services', 'All')]
        [string[]] $Categories, 
        [RegistryAction] $Action = [RegistryAction]::Apply,
        [switch] $SuppressMessage
    )

    # Get the settings collection
    $allSettings = @()
    foreach ($category in $Categories) {
        $settings = if ($category -eq 'All') {
            $SCRIPT:RegSettings.GetEnumerator() | ForEach-Object { $_.Value }
        }
        else {
            $SCRIPT:RegSettings[$category]
        }
        $allSettings += $settings
    }

    # Process settings (handle both single and nested arrays)
    $allSettings | ForEach-Object {
        foreach ($setting in $_) {
            try {
                $setting.Execute($Action)
                Write-Log "[$($setting.Category)] Processed $($setting.Name)" -Severity 'SUCCESS'
            }
            catch {
                Write-Log "[$($setting.Category)] Failed $($setting.Name) - $($_.Exception.Message)" -Severity 'ERROR'
            }
        }
    }

    # Return success status instead of showing message
    return $true
}

# ==================================
# Windows Security Helper Function
# ==================================
# Source: https://raw.githubusercontent.com/AveYo/LeanAndMean/refs/heads/main/RunAsTI.ps1
function RunAsTI($cmd, $arg) {
    $id = 'RunAsTI'; $key = "Registry::HKU\$(((whoami /user)-split' ')[-1])\Volatile Environment"; $code = @'
    $I=[int32]; $M=$I.module.gettype("System.Runtime.Interop`Services.Mar`shal"); $P=$I.module.gettype("System.Int`Ptr"); $S=[string]
    $D=@(); $T=@(); $DM=[AppDomain]::CurrentDomain."DefineDynami`cAssembly"(1,1)."DefineDynami`cModule"(1); $Z=[uintptr]::size
    0..5|% {$D += $DM."Defin`eType"("AveYo_$_",1179913,[ValueType])}; $D += [uintptr]; 4..6|% {$D += $D[$_]."MakeByR`efType"()}
    $F='kernel','advapi','advapi', ($S,$S,$I,$I,$I,$I,$I,$S,$D[7],$D[8]), ([uintptr],$S,$I,$I,$D[9]),([uintptr],$S,$I,$I,[byte[]],$I)
    0..2|% {$9=$D[0]."DefinePInvok`eMethod"(('CreateProcess','RegOpenKeyEx','RegSetValueEx')[$_],$F[$_]+'32',8214,1,$S,$F[$_+3],1,4)}
    $DF=($P,$I,$P),($I,$I,$I,$I,$P,$D[1]),($I,$S,$S,$S,$I,$I,$I,$I,$I,$I,$I,$I,[int16],[int16],$P,$P,$P,$P),($D[3],$P),($P,$P,$I,$I)
    1..5|% {$k=$_; $n=1; $DF[$_-1]|% {$9=$D[$k]."Defin`eField"('f' + $n++, $_, 6)}}; 0..5|% {$T += $D[$_]."Creat`eType"()}
    0..5|% {nv "A$_" ([Activator]::CreateInstance($T[$_])) -fo}; function F ($1,$2) {$T[0]."G`etMethod"($1).invoke(0,$2)}
    $TI=(whoami /groups)-like'*1-16-16384*'; $As=0; if(!$cmd) {$cmd='control';$arg='admintools'}; if ($cmd-eq'This PC'){$cmd='file:'}
    if (!$TI) {'TrustedInstaller','lsass','winlogon'|% {if (!$As) {$9=sc.exe start $_; $As=@(get-process -name $_ -ea 0|% {$_})[0]}}
    function M ($1,$2,$3) {$M."G`etMethod"($1,[type[]]$2).invoke(0,$3)}; $H=@(); $Z,(4*$Z+16)|% {$H += M "AllocHG`lobal" $I $_}
    M "WriteInt`Ptr" ($P,$P) ($H[0],$As.Handle); $A1.f1=131072; $A1.f2=$Z; $A1.f3=$H[0]; $A2.f1=1; $A2.f2=1; $A2.f3=1; $A2.f4=1
    $A2.f6=$A1; $A3.f1=10*$Z+32; $A4.f1=$A3; $A4.f2=$H[1]; M "StructureTo`Ptr" ($D[2],$P,[boolean]) (($A2 -as $D[2]),$A4.f2,$false)
    $Run=@($null, "powershell -win 1 -nop -c iex `$env:R; # $id", 0, 0, 0, 0x0E080600, 0, $null, ($A4 -as $T[4]), ($A5 -as $T[5]))
    F 'CreateProcess' $Run; return}; $env:R=''; rp $key $id -force; $priv=[diagnostics.process]."GetM`ember"('SetPrivilege',42)[0]
    'SeSecurityPrivilege','SeTakeOwnershipPrivilege','SeBackupPrivilege','SeRestorePrivilege' |% {$priv.Invoke($null, @("$_",2))}
    $HKU=[uintptr][uint32]2147483651; $NT='S-1-5-18'; $reg=($HKU,$NT,8,2,($HKU -as $D[9])); F 'RegOpenKeyEx' $reg; $LNK=$reg[4]
    function L ($1,$2,$3) {sp 'HKLM:\Software\Classes\AppID\{CDCBCFCA-3CDC-436f-A4E2-0E02075250C2}' 'RunAs' $3 -force -ea 0
    $b=[Text.Encoding]::Unicode.GetBytes("\Registry\User\$1"); F 'RegSetValueEx' @($2,'SymbolicLinkValue',0,6,[byte[]]$b,$b.Length)}
    function Q {[int](gwmi win32_process -filter 'name="explorer.exe"'|?{$_.getownersid().sid-eq$NT}|select -last 1).ProcessId}
    $11bug=($((gwmi Win32_OperatingSystem).BuildNumber)-eq'22000')-AND(($cmd-eq'file:')-OR(test-path -lit $cmd -PathType Container))
    if ($11bug) {'System.Windows.Forms','Microsoft.VisualBasic' |% {[Reflection.Assembly]::LoadWithPartialName("'$_")}}
    if ($11bug) {$path='^(l)'+$($cmd -replace '([\+\^\%\~\(\)\[\]])','{$1}')+'{ENTER}'; $cmd='control.exe'; $arg='admintools'}
    L ($key-split'\\')[1] $LNK ''; $R=[diagnostics.process]::start($cmd,$arg); if ($R) {$R.PriorityClass='High'; $R.WaitForExit()}
    if ($11bug) {$w=0; do {if($w-gt40){break}; sleep -mi 250;$w++} until (Q); [Microsoft.VisualBasic.Interaction]::AppActivate($(Q))}
    if ($11bug) {[Windows.Forms.SendKeys]::SendWait($path)}; do {sleep 7} while(Q); L '.Default' $LNK 'Interactive User'
'@; $V = ''; 'cmd', 'arg', 'id', 'key' | ForEach-Object { $V += "`n`$$_='$($(Get-Variable $_ -val)-replace"'","''")';" }; Set-ItemProperty $key $id $($V, $code) -type 7 -force -ea 0
    Start-Process powershell -args "-win 1 -nop -c `n$V `$env:R=(gi `$key -ea 0).getvalue(`$id)-join''; iex `$env:R" -verb runas -Wait
}

# =================================
# Customize Screen Helpers
# =================================

# Helper function to get current theme
function Get-CurrentTheme {
    try {
        $themeSettings = $SCRIPT:RegSettings.Personalization | 
        Where-Object { $_.Name -in @('AppsUseLightTheme', 'SystemUsesLightTheme') }
        
        $darkSettings = $themeSettings | Where-Object {
            [int][RegistryHelper]::GetCurrentValue($_) -eq 0
        }
        
        return $darkSettings.Count -ge 1
    }
    catch {
        Write-Log "Theme detection failed: $_"
        return $false
    }
}

# Function to verify and set wallpaper
function Set-Wallpaper {
    param (
        [string]$wallpaperPath
    )
    
    try {
        # First verify the path exists
        if (-not (Test-Path $wallpaperPath)) {
            Write-Log "Wallpaper path not found: $wallpaperPath" -Severity Error
            throw "Wallpaper file not found at: $wallpaperPath"
        }

        # Get absolute path
        $wallpaperPath = (Get-Item $wallpaperPath).FullName

        # Update the registry
        $result = reg.exe add "HKEY_CURRENT_USER\Control Panel\Desktop" /v Wallpaper /t REG_SZ /d "$wallpaperPath" /f
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to update registry with wallpaper path"
        }

        # Set the wallpaper using SystemParametersInfo
        $result = [Wallpaper]::SystemParametersInfo(
            [Wallpaper]::SPI_SETDESKWALLPAPER,
            0,
            $wallpaperPath,
            [Wallpaper]::SPIF_UPDATEINIFILE -bor [Wallpaper]::SPIF_SENDCHANGE
        )

        if ($result -eq 0) {
            throw "SystemParametersInfo call failed"
        }

        Write-Log "Wallpaper set successfully to: $wallpaperPath"
        return $true
    }
    catch {
        Write-Log "Failed to set wallpaper: $_" -Severity Error
        throw
    }
}

# ==================================
# Rocket GUI Helper Functions
# ==================================
# Helper function to force UI update
function Update-WPFControls {
    # Process UI events
    [System.Windows.Forms.Application]::DoEvents()
    # Process dispatcher queue
    $script:Window.Dispatcher.Invoke([Action] {}, [System.Windows.Threading.DispatcherPriority]::Background)
}
# Helper function to show messageboxes
function Show-MessageBox {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Message,

        [Parameter(Position = 1)]
        [string]$Title = "Message",

        [Parameter(Position = 2)]
        [string]$Buttons = "OK",

        [Parameter(Position = 3)]
        [string]$Icon = "Information"
    )

    # Helper function to convert string to Enum with validation
    function Convert-StringToEnum {
        param (
            [Parameter(Mandatory = $true)]
            [string]$Value,

            [Parameter(Mandatory = $true)]
            [type]$EnumType,

            [Parameter(Mandatory = $false)]
            [string]$Default
        )

        try {
            return [Enum]::Parse($EnumType, $Value, $true)
        }
        catch {
            Write-Warning "Invalid value '$Value' for enum '$EnumType'. Defaulting to '$Default'."
            return [Enum]::Parse($EnumType, $Default)
        }
    }

    # Convert Buttons and Icon strings to their respective enums
    $buttonsEnum = Convert-StringToEnum -Value $Buttons -EnumType ([System.Windows.MessageBoxButton]) -Default "OK"
    $iconEnum = Convert-StringToEnum -Value $Icon -EnumType ([System.Windows.MessageBoxImage]) -Default "Information"

    # Display the message box
    [System.Windows.MessageBox]::Show($Message, $Title, $buttonsEnum, $iconEnum)
}

# Helper function to update screen status text and write to log
function Write-Status {
    param (
        [string]$Message,
        [string]$TargetScreen
    )

    # Log the message
    Write-Log $Message

    # Only update status if we're on the target screen
    if ($TargetScreen -eq $script:CurrentScreen) {
        # Map the active screen to its status text variable
        $statusTextControl = switch ($TargetScreen) {
            "SoftAppsScreen" { $script:softAppsStatusText }
            "OptimizeScreen" { $script:optimizeStatusText }
            "CustomizeScreen" { $script:customizeStatusText }
            "AboutScreen" { $script:aboutStatusText }
            default { $null }
        }

        if ($null -ne $statusTextControl) {
            # Need to use Dispatcher for thread-safe UI updates
            $statusTextControl.Dispatcher.Invoke([Action] {
                    $statusTextControl.Text = $Message
                    # Process UI events
                    [System.Windows.Forms.Application]::DoEvents()
                    # Process dispatcher queue
                    $script:Window.Dispatcher.Invoke([Action] {}, [System.Windows.Threading.DispatcherPriority]::Background)
                }, "Normal")
        }
    }

    Update-WPFControls
}

# Function to highlight selected nav button
function Set-NavigationButtonSelected {
    param (
        [Parameter(Mandatory)]
        [System.Windows.Controls.Button]$SelectedButton
    )

    # Get the navigation panel
    $NavigationPanel = $window.FindName("NavigationPanel")
    
    # Verify navigation panel exists
    if (-not $NavigationPanel) {
        Write-Error "NavigationPanel not found or not initialized."
        return
    }

    # Reset all navigation buttons to default state
    foreach ($child in $NavigationPanel.Children) {
        if ($child -is [System.Windows.Controls.Button]) {
            $child.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#202020")
            $child.Foreground = [System.Windows.Media.Brushes]::White
        }
    }

    # Set selected button state
    $SelectedButton.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#303030")
    $SelectedButton.Foreground = [System.Windows.Media.Brushes]::White
}

# Function to switch screens
function Switch-Screen {
    param (
        [Parameter(Mandatory)]
        [System.Windows.Controls.Button]$SelectedButton,

        [Parameter(Mandatory)]
        [ValidateSet('SoftAppsScreen', 'OptimizeScreen', 'CustomizeScreen', 'AboutScreen')]
        [string]$TargetScreenName
    )

    try {
        # Set button highlight
        Set-NavigationButtonSelected -SelectedButton $SelectedButton

        # Hide all screens
        foreach ($screen in $script:screens.Values) {
            $screen.Visibility = 'Collapsed'
        }

        # Show target screen
        if ($script:screens.ContainsKey($TargetScreenName)) {
            $script:screens[$TargetScreenName].Visibility = 'Visible'
            # Update current screen tracker
            $script:CurrentScreen = $TargetScreenName
        }
        else {
            throw "Screen '$TargetScreenName' not found"
        }

        Write-Log "Switched to screen: $TargetScreenName"
    }
    catch {
        Write-Log "Error switching screens: $_" -Severity 'ERROR'
        Show-MessageBox -Message "Failed to switch screens: $($_.Exception.Message)" -Title "Navigation Error" -Icon Error
    }
}

# Function to initialize screens
function Initialize-Screens {
    # Initialize screen dictionary
    $script:screens = @{
        'SoftAppsScreen'  = $window.FindName("SoftAppsScreen")
        'OptimizeScreen'  = $window.FindName("OptimizeScreen")
        'CustomizeScreen' = $window.FindName("CustomizeScreen")
        'AboutScreen'     = $window.FindName("AboutScreen")
    }

    # Initialize status text controls
    $script:softAppsStatusText = $window.FindName("SoftAppsStatusText")
    $script:optimizeStatusText = $window.FindName("OptimizeStatusText")
    $script:customizeStatusText = $window.FindName("CustomizeStatusText")
    $script:aboutStatusText = $window.FindName("AboutStatusText")

    # Set initial screen
    $script:CurrentScreen = 'SoftAppsScreen'

    # Set initial visibility states
    foreach ($screenName in $script:screens.Keys) {
        $script:screens[$screenName].Visibility = if ($screenName -eq 'SoftAppsScreen') { 'Visible' } else { 'Collapsed' }
    }

    # Set initial navigation button state
    Set-NavigationButtonSelected -SelectedButton $SoftwareAppsNavButton
}

# ==================================
# General Helper Functions
# ==================================

# Check for internet connection
function Test-InternetConnection {
    Try {
        $connection = Test-Connection -ComputerName www.microsoft.com -Count 1 -ErrorAction Stop
        if ($connection) {
            return $true
        }
    }
    Catch {
        return $false
    }
}

# Determine Windows Version (Windows 10 or Windows 11)
function Get-WindowsVersion {
    return (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion").CurrentBuild
}

# Update Windows Graphical User Interface helper function
function Update-WinGUI {
    Write-Status "Refreshing Windows GUI and Shell..."

    # Refresh Windows GUI
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public class WindowsGUI {
    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern IntPtr SendMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);

    public const int HWND_BROADCAST = 0xffff;
    public const int WM_SETTINGCHANGE = 0x1A;

    public static void Refresh() {
        SendMessage((IntPtr)HWND_BROADCAST, WM_SETTINGCHANGE, IntPtr.Zero, IntPtr.Zero);
    }
}
"@

    [WindowsGUI]::Refresh()
    Write-Status "Windows GUI refreshed successfully!"

    # Restart Windows Shell without opening an Explorer window
    Write-Status "Restarting Windows Shell..."

    Get-Process explorer -ErrorAction SilentlyContinue | ForEach-Object {
        Write-Status "Stopping explorer process (PID: $($_.Id))..."
        Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
    }

    Write-Status "Restarting shell process..."
    Start-Process -FilePath "explorer.exe" -ArgumentList "/NOUACCHECK" -WindowStyle Hidden

    Start-Sleep -Seconds 2

    if (Get-Process explorer -ErrorAction SilentlyContinue) {
        Write-Status "Windows Shell restarted successfully!"
    }
    else {
        Write-Status "Failed to restart Windows Shell. Please check for issues."
    }
}

# =================================
# Software & Apps Screen Functions
# =================================
# =================================
# Install Software Functions
# =================================

# Helper function to check if WinGet is installed
function Test-WinGetInstalled {
    Try {
        winget --version | Out-Null
        return $true
    }
    Catch {
        return $false
    }
}

# Helper function to install required dependencies from GitHub
function Install-WinGet {
    try {
        Write-Status "Checking WinGet dependencies..." -TargetScreen SoftAppsScreen
        Update-WPFControls

        # Create temp directory if it doesn't exist
        $tempDir = "$env:TEMP\WinGetInstall"
        if (-not (Test-Path $tempDir)) {
            New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
        }

        # Define dependency package information
        $dependencies = @(
            @{
                Name        = "Microsoft UI XAML"
                Url         = "https://github.com/microsoft/microsoft-ui-xaml/releases/download/v2.8.6/Microsoft.UI.Xaml.2.8.x64.appx"
                Path        = "$tempDir\Microsoft.UI.Xaml.2.8.appx"
                PackageName = "Microsoft.UI.Xaml.2.8"
            },
            @{
                Name        = "VCLibs Desktop Runtime"
                Url         = "https://aka.ms/Microsoft.VCLibs.x64.14.00.Desktop.appx"
                Path        = "$tempDir\Microsoft.VCLibs.140.00.UWPDesktop.x64.appx"
                PackageName = "Microsoft.VCLibs.140.00.UWPDesktop"
            }
        )

        # Check and install dependencies if needed
        foreach ($dependency in $dependencies) {
            # Check if dependency is already installed
            if (!(Get-AppxPackage -Name $dependency.PackageName)) {
                try {
                    Write-Status "Downloading $($dependency.Name)..." -TargetScreen SoftAppsScreen
                    Update-WPFControls

                    # Download dependency
                    $webClient = New-Object System.Net.WebClient
                    $webClient.DownloadFile($dependency.Url, $dependency.Path)

                    # Verify download
                    if (-not (Test-Path $dependency.Path) -or (Get-Item $dependency.Path).Length -eq 0) {
                        Write-Status "Failed to download $($dependency.Name). File is missing or empty." -TargetScreen SoftAppsScreen
                        Update-WPFControls
                        Show-MessageBox -Message "Failed to download $($dependency.Name). Please try again." -Title "Download Error" -Icon Error
                        return $false
                    }

                    Write-Status "Installing $($dependency.Name)..." -TargetScreen SoftAppsScreen
                    Update-WPFControls

                    # Install dependency by executing the .appx file
                    $process = Start-Process -FilePath $dependency.Path -ArgumentList "install", "--quiet" -Wait -PassThru
                    if ($process.ExitCode -ne 0) {
                        throw "Failed to install $($dependency.Name) with exit code: $($process.ExitCode)"
                    }
                }
                catch {
                    Write-Status "Failed to install $($dependency.Name): $($_.Exception.Message)" -TargetScreen SoftAppsScreen
                    Update-WPFControls
                    Show-MessageBox -Message "Failed to install $($dependency.Name). Please try again." -Title "Installation Error" -Icon Error
                    return $false
                }
            }
        }

        # Download and install WinGet
        Write-Status "Downloading WinGet installer..." -TargetScreen SoftAppsScreen
        Update-WPFControls

        $wingetDownloadUrl = "https://github.com/microsoft/winget-cli/releases/latest/download/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle"
        $wingetInstallerPath = "$tempDir\WinGetInstaller.msixbundle"

        try {
            $webClient = New-Object System.Net.WebClient
            $webClient.DownloadFile($wingetDownloadUrl, $wingetInstallerPath)

            if (-not (Test-Path $wingetInstallerPath) -or (Get-Item $wingetInstallerPath).Length -eq 0) {
                Write-Status "Failed to download WinGet installer. File is missing or empty." -TargetScreen SoftAppsScreen
                Update-WPFControls
                Show-MessageBox -Message "Failed to download WinGet installer. Please try again." -Title "Download Error" -Icon Error
                return $false
            }

            Write-Status "Installing WinGet... Please wait." -TargetScreen SoftAppsScreen
            Update-WPFControls

            # Install WinGet by executing the .msixbundle file
            $process = Start-Process -FilePath $wingetInstallerPath -ArgumentList "install", "--quiet" -Wait -PassThru
            
            if ($process.ExitCode -eq 0) {
                Write-Status "WinGet installed successfully!" -TargetScreen SoftAppsScreen
                Update-WPFControls
                Show-MessageBox -Message "WinGet has been successfully installed!" -Title "Installation Complete" -Icon Information
                return $true
            }
            else {
                throw "WinGet installation failed with exit code: $($process.ExitCode)"
            }
        }
        catch {
            Write-Status "Failed to install WinGet: $($_.Exception.Message)" -TargetScreen SoftAppsScreen
            Update-WPFControls
            Show-MessageBox -Message "Failed to install WinGet. Please try again." -Title "Installation Error" -Icon Error
            return $false
        }
    }
    catch {
        Write-Status "An error occurred during installation: $($_.Exception.Message)" -TargetScreen SoftAppsScreen
        Update-WPFControls
        Show-MessageBox -Message "An error occurred during installation. Please try again." -Title "Installation Error" -Icon Error
        return $false
    }
    finally {
        # Clean up downloaded files
        if (Test-Path $tempDir) {
            Remove-Item -Path $tempDir -Force -Recurse
        }
    }
}

# Main function to check if WinGet is installed, install if necessary, and check for updates
function Test-WinGetStatus {
    # Check if WinGet is installed, if not, install it
    if (-not (Test-WinGetInstalled)) {
        Install-WinGet
    }

    # Once installed, check for updates
    
    Write-Status "Checking for WinGet updates..." -TargetScreen SoftAppsScreen
    Try {
        $updateCheck = winget upgrade --id Microsoft.WinGet -e --accept-package-agreements --accept-source-agreements 2>&1
        if ($updateCheck -match "No installed package found" -or $updateCheck -match "No applicable upgrade found") {
            
            Write-Status "WinGet is already up-to-date." -TargetScreen SoftAppsScreen
        }
        elseif ($updateCheck -match "An applicable upgrade is available") {
            # Perform the upgrade if available
            
            Write-Status "An update is available for WinGet. Upgrading now..." -TargetScreen SoftAppsScreen
            Try {
                winget upgrade --id Microsoft.WinGet -e --accept-package-agreements --accept-source-agreements | Out-Null
                if ($LASTEXITCODE -eq 0) {
                    
                    Write-Status "WinGet updated successfully." -TargetScreen SoftAppsScreen
                }
                else {
                    
                    Write-Status "Failed to update WinGet. Proceeding with app installation..." -TargetScreen SoftAppsScreen
                }
            }
            Catch {
                
                Write-Status "An error occurred while upgrading WinGet. Proceeding with app installation..." -TargetScreen SoftAppsScreen
            }
        }
        else {
            
            Write-Status "Could not determine WinGet update status. Proceeding with app installation..." -TargetScreen SoftAppsScreen
        }
    }
    Catch {
        
        Write-Status "An error occurred while checking for WinGet updates. Proceeding with app installation..." -TargetScreen SoftAppsScreen
    }
}

# Define app installation configurations
$AppInstallConfigs = @{
    'InstallStore'       = @{
        CustomInstall = $true
        Function      = 'Install-Store'
        FriendlyName  = 'Microsoft Store'
    }
    'InstallUniGetUI'    = @{
        AppName      = 'MartiCliment.UniGetUI'
        FriendlyName = 'UniGetUI'
    }
    'InstallThorium'     = @{
        AppName      = 'Alex313031.Thorium'
        FriendlyName = 'Thorium Browser'
    }
    'InstallFirefox'     = @{
        AppName      = 'Mozilla.Firefox'
        FriendlyName = 'Mozilla Firefox'
    }
    'InstallChrome'      = @{
        AppName      = 'Google.Chrome'
        FriendlyName = 'Google Chrome'
    }
    'InstallBrave'       = @{
        AppName      = 'Brave.Brave'
        FriendlyName = 'Brave Browser'
    }
    'InstallEdge'        = @{
        CustomInstall = $true
        Function      = 'Install-MicrosoftEdge'
        FriendlyName  = 'Microsoft Edge'
    }
    'InstallEdgeWebView' = @{
        CustomInstall = $true
        Function      = 'Install-EdgeWebView'
        FriendlyName  = 'Microsoft Edge WebView2'
    }
    'InstallOneDrive'    = @{
        CustomInstall = $true
        Function      = 'Install-OneDrive'
        FriendlyName  = 'OneDrive'
    }
    'InstallXbox'        = @{
        CustomInstall = $true
        Function      = 'Install-Xbox'
        FriendlyName  = 'Xbox'
    }
}

# Generic installation handler function
function Initialize-InstallationHandlers {
    foreach ($button in $AppInstallConfigs.Keys) {
        $config = $AppInstallConfigs[$button]
        $buttonVar = Get-Variable -Name $button
        
        $scriptBlock = {
            [System.Windows.Input.Mouse]::OverrideCursor = [System.Windows.Input.Cursors]::Wait
            try {
                $config = $AppInstallConfigs[$this.Name]
                
                Write-Status "Preparing to install $($config.FriendlyName). Please wait..."
                Update-WPFControls
                
                if ($config.CustomInstall) {
                    Write-Status "Installing $($config.FriendlyName). This might take a while..."
                    Update-WPFControls
                    $scriptBlock = [ScriptBlock]::Create($config.Function)
                    & $scriptBlock
                }
                else {
                    Write-Status "Starting installation of $($config.FriendlyName). This process might take several minutes..."
                    Update-WPFControls
                    
                    Install-AppWithWinGet -AppName $config.AppName -FriendlyName $config.FriendlyName
                }
                Update-WPFControls
            }
            catch {
                Write-Log "Error installing $($config.FriendlyName): $($_.Exception.Message)" -Severity 'ERROR'
                Write-Status "Error installing $($config.FriendlyName). Please try again or check the logs."
                Update-WPFControls
                Show-MessageBox -Message "Failed to install $($config.FriendlyName)`n`n$($_.Exception.Message)" -Title "Installation Error" -Icon Error
            }
            finally {
                [System.Windows.Input.Mouse]::OverrideCursor = $null
            }
        }
        
        # Set the button name property for reference in the script block
        $buttonVar.Value.Name = $button
        $buttonVar.Value.Add_Click($scriptBlock)
    }
}


# Function to install Microsoft Store and Remove Rocket Removal script and scheduled task
function Install-Store {
    try {
        # First, update BloatRemoval.ps1 to remove Store entry
        $bloatRemovalPath = "$env:ProgramFiles\Rocket\Scripts\BloatRemoval.ps1"

        if (Test-Path $bloatRemovalPath) {
            Write-Status "Updating bloatware configuration..." -TargetScreen "SoftAppsScreen"
            Update-WPFControls

            # Read content
            $content = Get-Content -Path $bloatRemovalPath
            
            # Create backup
            $backupPath = "$bloatRemovalPath.backup"
            Copy-Item -Path $bloatRemovalPath -Destination $backupPath -Force

            # Filter out Store-related lines and any malformed lines
            $modifiedContent = $content | Where-Object {
                $line = $_.Trim()
                return $line -and 
                $line -notmatch '^}.*Remove-AppxPackage' -and
                $line -notmatch 'Microsoft\.WindowsStore'
            }

            # Write changes back to file
            $modifiedContent | Set-Content -Path $bloatRemovalPath -Force
            Write-Log "Successfully updated BloatRemoval script to preserve Microsoft Store" -Severity 'INFO'

            # Remove backup file
            if (Test-Path $backupPath) {
                Remove-Item -Path $backupPath -Force
                Write-Log "Removed backup file: $backupPath" -Severity 'INFO'
            }

            # Restart Task Scheduler service to refresh tasks
            Restart-Service -Name Schedule -Force
            Write-Log "Restarted Task Scheduler service to refresh tasks" -Severity 'INFO'
        }

        # Make sure the store is removed first or else installation might fail
        Get-AppxPackage -AllUsers *Microsoft.WindowsStore* | Remove-AppxPackage -ErrorAction SilentlyContinue

        # Check for internet connection
        if (-not (Test-InternetConnection)) {
            Write-Status "No internet connection available." -TargetScreen "SoftAppsScreen"
            Write-Log "Microsoft Store installation failed: No internet connection available."
            Show-MessageBox -Message "Please connect to the internet and try again." -Title "No Internet Connection" -Icon Warning -Buttons OK
            return
        }

        Write-Status "Installing Microsoft Store..." -TargetScreen "SoftAppsScreen"
        
        # Method 1: Try registering existing package
        Write-Status "Attempting Method 1: Package Registration..." -TargetScreen "SoftAppsScreen"
        try {
            Get-AppxPackage -AllUsers Microsoft.WindowsStore* | ForEach-Object {
                Add-AppxPackage -DisableDevelopmentMode -Register "$($_.InstallLocation)\AppXManifest.xml" -ErrorAction Stop
            }
            
            # Check if successful
            $storePackage = Get-AppxPackage -Name "Microsoft.WindowsStore" | Where-Object { $_.Status -eq "Ok" }
            if ($null -ne $storePackage) {
                Write-Status "Microsoft Store installed successfully via Method 1!" -TargetScreen "SoftAppsScreen"
                Write-Log "Microsoft Store installed successfully via package registration. Version: $($storePackage.Version)"
                Show-MessageBox -Message "Microsoft Store has been successfully installed!`nVersion: $($storePackage.Version)" -Title "Installation Success" -Icon Information
                return
            }
        }
        catch {
            Write-Log "Method 1 failed: $($_.Exception.Message)" -Severity 'WARNING'
        }

        # Method 2: WSReset
        Write-Status "Attempting Method 2: WSReset..." -TargetScreen "SoftAppsScreen"
        try {
            wsreset -i
            Write-Status "Microsoft Store installation initiated. Please wait..." -TargetScreen "SoftAppsScreen"
            
            # Wait and check for Store installation
            for ($i = 0; $i -lt 10; $i++) {
                Start-Sleep -Seconds 5
                $storePackage = Get-AppxPackage -Name "Microsoft.WindowsStore" | Where-Object { $_.Status -eq "Ok" }
                if ($null -ne $storePackage) {
                    Write-Status "Microsoft Store installed successfully via Method 2!" -TargetScreen "SoftAppsScreen"
                    Write-Log "Microsoft Store installed successfully via WSReset. Version: $($storePackage.Version)"
                    Show-MessageBox -Message "Microsoft Store has been successfully installed!`nVersion: $($storePackage.Version)" -Title "Installation Success" -Icon Information
                    return
                }
                Write-Status "Checking installation status... Attempt $($i + 1) of 10" -TargetScreen "SoftAppsScreen"
            }
        }
        catch {
            Write-Log "Method 2 failed: $($_.Exception.Message)" -Severity 'WARNING'
        }

        # Method 3: Xbox App Installation
        $message = "The previous methods to install the Microsoft Store were unsuccessful.`n`n" +
        "Would you like to try installing the Xbox app? The Xbox app can help restore the Microsoft Store as a dependency.`n`n" +
        "Would you like to proceed with installing Xbox?"
        
        $result = Show-MessageBox -Message $message -Title "Try Alternative Method?" -Icon Question -Buttons YesNo

        if ($result -eq 'Yes') {
            Write-Status "Attempting Method 3: Installing Xbox..." -TargetScreen "SoftAppsScreen"
            Install-Xbox
        }
        else {
            Write-Status "Microsoft Store installation cancelled by user." -TargetScreen "SoftAppsScreen"
            Write-Log "User declined Xbox installation method for Microsoft Store"
        }
    }
    catch {
        Write-Log "Error during Microsoft Store installation: $($_.Exception.Message)" -Severity 'ERROR'
        Write-Status "An error occurred while installing Microsoft Store." -TargetScreen "SoftAppsScreen"
        Show-MessageBox -Message "An error occurred while installing Microsoft Store.`n`n$($_.Exception.Message)" -Title "Installation Error" -Icon Error
    }
}

# Function to install an app using WinGet
function Install-AppWithWinGet {
    param (
        [string]$AppName,
        [string]$FriendlyName
    )

    # Check for internet connection
    if (-not (Test-InternetConnection)) {
        Write-Status -Message "Cannot install $FriendlyName - No internet connection detected. Please connect to the internet and try again." -TargetScreen "SoftAppsScreen"
        Update-WPFControls
        return
    }

    # Update WinGet to ensure it's the latest version
    Write-Status -Message "Checking WinGet status before installing $FriendlyName..." -TargetScreen "SoftAppsScreen"
    Update-WPFControls
    Test-WinGetStatus

    Write-Status -Message "Starting installation of $FriendlyName..." -TargetScreen "SoftAppsScreen"
    Update-WPFControls
    
    # Capture the friendly name in a script-scoped variable to ensure availability in the timer
    $script:currentFriendlyName = $FriendlyName
    
    # Create the background job
    $job = Start-Job -ScriptBlock {
        param($AppName, $FriendlyName)
        
        # Attempt to install or upgrade the app using WinGet
        $installOutput = winget install --id $AppName -e --silent --accept-package-agreements --accept-source-agreements 2>&1
        
        # Return the output for processing
        return @{
            Output       = $installOutput
            AppName      = $AppName
            FriendlyName = $FriendlyName
        }
    } -ArgumentList $AppName, $FriendlyName

    # Create script-level variables to store state
    $script:waitCounter = 0
    $script:installationComplete = $false
    $script:wingetWasRunning = $false

    # Start watching the job
    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromSeconds(1)
    
    $timer.Add_Tick({
            # If installation is already marked as complete, do nothing
            if ($script:installationComplete) {
                return
            }

            # Try to get the winget process
            $wingetProcess = Get-Process winget -ErrorAction SilentlyContinue

            # If winget is currently running
            if ($wingetProcess) {
                $script:wingetWasRunning = $true
                # Update status with a waiting animation
                $dots = "." * ($script:waitCounter % 4)
                Write-Status -Message "Installing $($script:currentFriendlyName). Please wait$dots" -TargetScreen "SoftAppsScreen"
                $script:waitCounter++
                Update-WPFControls
            }
            # If winget was running before but now it's not, assume installation completed successfully
            elseif ($script:wingetWasRunning) {
                $script:installationComplete = $true
                $timer.Stop()
            
                Write-Status -Message "The $($script:currentFriendlyName) app has been successfully installed!" -TargetScreen "SoftAppsScreen"
                Show-MessageBox -Message "The $($script:currentFriendlyName) app has been successfully installed!" -Title "$($script:currentFriendlyName) Installation Complete" -Icon Information
            
                Remove-Job -Job $job
                Update-WPFControls
                [System.Windows.Input.Mouse]::OverrideCursor = $null
            }
            # If winget hasn't started yet
            else {
                # Update status with a waiting animation
                $dots = "." * ($script:waitCounter % 4)
                Write-Status -Message "Preparing to install $($script:currentFriendlyName) Please wait$dots" -TargetScreen "SoftAppsScreen"
                $script:waitCounter++
                Update-WPFControls
            }

            # Check for job failure (this would be an actual PowerShell job failure, not a winget failure)
            if ($job.State -eq 'Failed') {
                $script:installationComplete = $true
                $timer.Stop()
                Write-Status -Message "An unexpected error occurred while installing $($script:currentFriendlyName)." -TargetScreen "SoftAppsScreen"
                Show-MessageBox -Message "An unexpected error occurred while installing $($script:currentFriendlyName)." -Title "Installation Error" -Icon Error
                Remove-Job -Job $job
                Update-WPFControls
                [System.Windows.Input.Mouse]::OverrideCursor = $null
            }
        })
    
    $timer.Start()
}

# Function to install Microsoft Edge and Remove Rocket Removal script and scheduled task
function Install-MicrosoftEdge {
    try {
        Write-Status "Downloading Microsoft Edge... Please wait." -TargetScreen "SoftAppsScreen"
        Update-WPFControls

        # Download URL for Edge
        $url = "https://go.microsoft.com/fwlink/?linkid=2109047&Channel=Stable&language=en&brand=M100"
        
        # Create temp directory if it doesn't exist
        $tempDir = "$env:TEMP\EdgeInstall"
        if (-not (Test-Path $tempDir)) {
            New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
        }

        # Set installer path
        $installerPath = "$tempDir\MicrosoftEdgeSetup.exe"

        # Download Edge installer
        try {
            $webClient = New-Object System.Net.WebClient
            $webClient.DownloadFile($url, $installerPath)
        }
        catch {
            Write-Log "Failed to download Edge installer: $($_.Exception.Message)" -Severity 'ERROR'
            Write-Status "Failed to download Microsoft Edge. Please try again." -TargetScreen "SoftAppsScreen"
            Update-WPFControls
            return $false
        }

        # Verify the download
        if (-not (Test-Path $installerPath)) {
            Write-Log "Edge installer not found after download" -Severity 'ERROR'
            Write-Status "Failed to download Microsoft Edge. Please try again." -TargetScreen "SoftAppsScreen"
            Update-WPFControls
            return $false
        }

        Write-Status "Installing Microsoft Edge... Please wait." -TargetScreen "SoftAppsScreen"
        Update-WPFControls

        # Install Edge
        $process = Start-Process -FilePath $installerPath -ArgumentList "/install" -Wait -PassThru

        # Clean up the installer
        if (Test-Path $installerPath) {
            Remove-Item -Path $installerPath -Force
        }

        if (Test-Path $tempDir) {
            Remove-Item -Path $tempDir -Force -Recurse
        }

        # Delete Rocket Edge tasks and scripts
        $task = Get-ScheduledTask -TaskName "EdgeRemoval" -ErrorAction SilentlyContinue
        if ($task) {
            Unregister-ScheduledTask -TaskName "EdgeRemoval" -Confirm:$false
            Write-Log "EdgeRemoval scheduled task has been deleted before Edge installation" -Severity 'INFO'
        }
         
        $scriptPath = "$env:ProgramFiles\Rocket\Scripts\EdgeRemoval.ps1"
        if (Test-Path $scriptPath) {
            Remove-Item -Path $scriptPath -Force -ErrorAction SilentlyContinue
            Write-Log "EdgeRemoval script has been deleted" -Severity 'INFO'
        }

        # Also install EdgeWebview2
        Install-EdgeWebView

        # Check if installation was successful
        if ($process.ExitCode -eq 0) {
            Write-Status "Microsoft Edge has been successfully installed!" -TargetScreen "SoftAppsScreen"
            Write-Log "Microsoft Edge installed successfully" -Severity 'INFO'
            Update-WPFControls
            Show-MessageBox -Message "Microsoft Edge has been successfully installed!" -Title "Installation Complete" -Icon Information
            return $true
        }
        else {
            Write-Status "Failed to install Microsoft Edge. Exit code: $($process.ExitCode)" -TargetScreen "SoftAppsScreen"
            Write-Log "Edge installation failed with exit code: $($process.ExitCode)" -Severity 'ERROR'
            Update-WPFControls
            Show-MessageBox -Message "Failed to install Microsoft Edge. Please try again." -Title "Installation Error" -Icon Error
            return $false
        }
    }
    catch {
        Write-Log "Error during Edge installation: $($_.Exception.Message)" -Severity 'ERROR'
        Write-Status "An error occurred while installing Microsoft Edge." -TargetScreen "SoftAppsScreen"
        Update-WPFControls
        Show-MessageBox -Message "An error occurred while installing Microsoft Edge.`n`n$($_.Exception.Message)" -Title "Installation Error" -Icon Error
        return $false
    }
}

# Function to install Edge Webview Only
function Install-EdgeWebView {
    try {
        Write-Status "Downloading Microsoft Edge WebView2... Please wait." -TargetScreen "SoftAppsScreen"
        Update-WPFControls
 
        # Download URL for Edge WebView2
        $url = "https://msedge.sf.dl.delivery.mp.microsoft.com/filestreamingservice/files/304fddef-b073-4e0a-b1ff-c2ea02584017/MicrosoftEdgeWebview2Setup.exe"
        
        # Create temp directory if it doesn't exist
        $tempDir = "$env:TEMP\WebViewInstall"
        if (-not (Test-Path $tempDir)) {
            New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
        }
 
        # Set installer path
        $installerPath = "$tempDir\MicrosoftEdgeWebview2Setup.exe"
 
        # Download WebView2 installer
        try {
            $webClient = New-Object System.Net.WebClient
            $webClient.DownloadFile($url, $installerPath)
        }
        catch {
            Write-Log "Failed to download Edge WebView2 installer: $($_.Exception.Message)" -Severity 'ERROR'
            Write-Status "Failed to download Microsoft Edge WebView2. Please try again." -TargetScreen "SoftAppsScreen"
            Update-WPFControls
            return $false
        }
 
        # Verify the download
        if (-not (Test-Path $installerPath)) {
            Write-Log "Edge WebView2 installer not found after download" -Severity 'ERROR'
            Write-Status "Failed to download Microsoft Edge WebView2. Please try again." -TargetScreen "SoftAppsScreen"
            Update-WPFControls
            return $false
        }
 
        Write-Status "Installing Microsoft Edge WebView2... Please wait." -TargetScreen "SoftAppsScreen"
        Update-WPFControls
 
        # Install WebView2 silently
        $process = Start-Process -FilePath $installerPath -ArgumentList "/install" -Wait -PassThru
 
        # Clean up the installer
        if (Test-Path $installerPath) {
            Remove-Item -Path $installerPath -Force
        }
 
        if (Test-Path $tempDir) {
            Remove-Item -Path $tempDir -Force -Recurse
        }
 
        # Check if installation was successful
        if ($process.ExitCode -eq 0) {
            Write-Status "Microsoft Edge WebView2 has been successfully installed!" -TargetScreen "SoftAppsScreen"
            Write-Log "Microsoft Edge WebView2 installed successfully" -Severity 'INFO'
            Update-WPFControls
            Show-MessageBox -Message "Microsoft Edge WebView2 has been successfully installed!" -Title "Installation Complete" -Icon Information
            return $true
        }
        else {
            Write-Status "Failed to install Microsoft Edge WebView2. Exit code: $($process.ExitCode)" -TargetScreen "SoftAppsScreen"
            Write-Log "Edge WebView2 installation failed with exit code: $($process.ExitCode)" -Severity 'ERROR'
            Update-WPFControls
            Show-MessageBox -Message "Failed to install Microsoft Edge WebView2. Please try again." -Title "Installation Error" -Icon Error
            return $false
        }
    }
    catch {
        Write-Log "Error during Edge WebView2 installation: $($_.Exception.Message)" -Severity 'ERROR'
        Write-Status "An error occurred while installing Microsoft Edge WebView2." -TargetScreen "SoftAppsScreen"
        Update-WPFControls
        Show-MessageBox -Message "An error occurred while installing Microsoft Edge WebView2.`n`n$($_.Exception.Message)" -Title "Installation Error" -Icon Error
        return $false
    }
}

# Function to install OneDrive and Remove Rocket Removal script and scheduled task
function Install-OneDrive {
    try {
        Write-Status "Downloading OneDrive... Please wait." -TargetScreen "SoftAppsScreen"
        Update-WPFControls

        # Download URL for OneDrive
        $url = "https://go.microsoft.com/fwlink/p/?LinkID=2182910&clcid=0x409&culture=en-us&country=us"
        
        # Create temp directory if it doesn't exist
        $tempDir = "$env:TEMP\OneDriveInstall"
        if (-not (Test-Path $tempDir)) {
            New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
        }

        # Set installer path
        $installerPath = "$tempDir\OneDriveSetup.exe"

        # Download OneDrive installer
        try {
            $webClient = New-Object System.Net.WebClient
            $webClient.DownloadFile($url, $installerPath)
        }
        catch {
            Write-Log "Failed to download OneDrive installer: $($_.Exception.Message)" -Severity 'ERROR'
            Write-Status "Failed to download OneDrive. Please try again." -TargetScreen "SoftAppsScreen"
            Update-WPFControls
            return $false
        }

        # Verify the download
        if (-not (Test-Path $installerPath)) {
            Write-Log "OneDrive installer not found after download" -Severity 'ERROR'
            Write-Status "Failed to download OneDrive. Please try again." -TargetScreen "SoftAppsScreen"
            Update-WPFControls
            return $false
        }

        Write-Status "Installing OneDrive... Please wait." -TargetScreen "SoftAppsScreen"
        Update-WPFControls

        # Add required registry entries
        reg.exe add "HKLM\SOFTWARE\Policies\Microsoft\OneDrive" /v KFMBlockOptIn /t REG_DWORD /d 0 /f *> $null
        reg.exe add "HKLM\SOFTWARE\Policies\Microsoft\Windows\OneDrive" /v DisableFileSyncNGSC /t REG_DWORD /d 0 /f *> $null
        reg.exe add "HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\Privacy" /v SettingSyncEnabled /t REG_DWORD /d 1 /f *> $null

        # Install OneDrive
        $process = Start-Process -FilePath $installerPath -ArgumentList "/allusers" -Wait -PassThru

        # Clean up the installer
        if (Test-Path $installerPath) {
            Remove-Item -Path $installerPath -Force
        }

        if (Test-Path $tempDir) {
            Remove-Item -Path $tempDir -Force -Recurse
        }

        # Delete Rocket OneDrive tasks and scripts
        $task = Get-ScheduledTask -TaskName "OneDriveRemoval" -ErrorAction SilentlyContinue
        if ($task) {
            Unregister-ScheduledTask -TaskName "OneDriveRemoval" -Confirm:$false
            Write-Log "OneDriveRemoval scheduled task has been deleted before OneDrive installation" -Severity 'INFO'
        }
         
        $scriptPath = "$env:ProgramFiles\Rocket\Scripts\OneDriveRemoval.ps1"
        if (Test-Path $scriptPath) {
            Remove-Item -Path $scriptPath -Force -ErrorAction SilentlyContinue
            Write-Log "OneDriveRemoval script has been deleted" -Severity 'INFO'
        }

        # Check if installation was successful
        if ($process.ExitCode -eq 0) {
            Write-Status "OneDrive has been successfully installed!" -TargetScreen "SoftAppsScreen"
            Write-Log "OneDrive installed successfully" -Severity 'INFO'
            Update-WPFControls
            Show-MessageBox -Message "OneDrive has been successfully installed!" -Title "Installation Complete" -Icon Information
            return $true
        }
        else {
            Write-Status "Failed to install OneDrive. Exit code: $($process.ExitCode)" -TargetScreen "SoftAppsScreen"
            Write-Log "OneDrive installation failed with exit code: $($process.ExitCode)" -Severity 'ERROR'
            Update-WPFControls
            Show-MessageBox -Message "Failed to install OneDrive. Please try again." -Title "Installation Error" -Icon Error
            return $false
        }
    }
    catch {
        Write-Log "Error during OneDrive installation: $($_.Exception.Message)" -Severity 'ERROR'
        Write-Status "An error occurred while installing OneDrive." -TargetScreen "SoftAppsScreen"
        Update-WPFControls
        Show-MessageBox -Message "An error occurred while installing OneDrive.`n`n$($_.Exception.Message)" -Title "Installation Error" -Icon Error
        return $false
    }
}

# Function to install Xbox and Remove Rocket Removal script and scheduled task
function Install-Xbox {
    try {
        $bloatRemovalPath = "$env:ProgramFiles\Rocket\Scripts\BloatRemoval.ps1"

        if (Test-Path $bloatRemovalPath) {
            Write-Status "Updating bloatware configuration..." -TargetScreen "SoftAppsScreen"
            Update-WPFControls

            # Read content
            $content = Get-Content -Path $bloatRemovalPath
            
            # Create backup
            $backupPath = "$bloatRemovalPath.backup"
            Copy-Item -Path $bloatRemovalPath -Destination $backupPath -Force

            # Filter out Xbox-related lines and any malformed lines
            $modifiedContent = $content | Where-Object {
                $line = $_.Trim()
                # Skip empty lines, malformed lines, and Xbox-related lines
                return $line -and 
                $line -notmatch '^}.*Remove-AppxPackage' -and
                $line -notmatch 'Microsoft\.Xbox' -and 
                $line -notmatch 'Microsoft\.GamingApp'
            }

            # Write changes back to file
            $modifiedContent | Set-Content -Path $bloatRemovalPath -Force
            Write-Log "Successfully updated BloatRemoval script to preserve Xbox packages" -Severity 'INFO'

            # Remove backup file
            if (Test-Path $backupPath) {
                Remove-Item -Path $backupPath -Force
                Write-Log "Removed backup file: $backupPath" -Severity 'INFO'
            }

            # Restart Task Scheduler service to refresh tasks
            Restart-Service -Name Schedule -Force
            Write-Log "Restarted Task Scheduler service to refresh tasks" -Severity 'INFO'
        }

        # Continue with your existing Xbox installation code...
        Write-Status "Downloading Xbox installer... Please wait." -TargetScreen "SoftAppsScreen"
        Update-WPFControls

        # Create temp directory if it doesn't exist
        $tempDir = "$env:TEMP\XboxInstall"
        if (-not (Test-Path $tempDir)) {
            New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
        }

        # Set installer path
        $installerPath = "$tempDir\XboxInstaller.exe"

        # Download Xbox installer
        try {
            $webClient = New-Object System.Net.WebClient
            $webClient.DownloadFile("https://aka.ms/xboxinstaller", $installerPath)
            
            # Verify the download
            if (-not (Test-Path $installerPath)) {
                throw "Xbox installer not found after download"
            }

            Write-Status "Installing Xbox app... Please wait." -TargetScreen "SoftAppsScreen"
            Update-WPFControls

            # Install Xbox silently
            $process = Start-Process -FilePath $installerPath -ArgumentList "/silent" -Wait -PassThru

            # Clean up the installer
            if (Test-Path $installerPath) {
                Remove-Item -Path $installerPath -Force
            }

            if (Test-Path $tempDir) {
                Remove-Item -Path $tempDir -Force -Recurse
            }

            # Check if installation was successful
            if ($process.ExitCode -eq 0) {
                Write-Status "Xbox app has been successfully installed!" -TargetScreen "SoftAppsScreen"
                Write-Log "Xbox app installed successfully" -Severity 'INFO'
                Update-WPFControls
                Show-MessageBox -Message "Xbox app has been successfully installed!`n`nIMPORTANT: After launching Xbox for the first time, go to Settings > App and install any required dependencies to ensure all features work correctly." -Title "Installation Complete" -Icon Information
                return $true
            }
            else {
                throw "Installation failed with exit code: $($process.ExitCode)"
            }
        }
        catch {
            Write-Log "Direct installation failed for Xbox, attempting WinGet: $($_.Exception.Message)" -Severity 'WARNING'
            
            # Second attempt: Try to install via WinGet
            Write-Status "Attempting to install Xbox app via WinGet..." -TargetScreen "SoftAppsScreen"
            Update-WPFControls

            try {
                Install-AppWithWinGet -AppName "Microsoft.GamingApp" -FriendlyName "Xbox"
                return $true
            }
            catch {
                Write-Log "WinGet installation also failed for Xbox: $($_.Exception.Message)" -Severity 'ERROR'
                Write-Status "Failed to install Xbox app. Please try again." -TargetScreen "SoftAppsScreen"
                Update-WPFControls
                Show-MessageBox -Message "Failed to install Xbox app. Please try again." -Title "Installation Error" -Icon Error
                return $false
            }
        }
    }
    catch {
        Write-Log "Error during Xbox installation: $($_.Exception.Message)" -Severity 'ERROR'
        Write-Status "An error occurred while installing Xbox app." -TargetScreen "SoftAppsScreen"
        Update-WPFControls
        Show-MessageBox -Message "An error occurred while installing Xbox app.`n`n$($_.Exception.Message)" -Title "Installation Error" -Icon Error
        return $false
    }
}

# =================================
# Remove Windows Apps Functions
# =================================

# Define Bloatware Windows Apps
$Bloatappx = @{
    # 3D/Mixed Reality Apps
    "Microsoft.Microsoft3DViewer"            = @{
        FriendlyName = "3D Viewer"
        PackageName  = "Microsoft.Microsoft3DViewer"
    }
    "Microsoft.MixedReality.Portal"          = @{
        FriendlyName = "Mixed Reality Portal"
        PackageName  = "Microsoft.MixedReality.Portal"
    }

    # Bing/Search Apps
    "Microsoft.BingSearch"                   = @{
        FriendlyName = "Bing Search"
        PackageName  = "Microsoft.BingSearch"
    }
    "Microsoft.BingNews"                     = @{
        FriendlyName = "News"
        PackageName  = "Microsoft.BingNews"
    }
    "Microsoft.BingWeather"                  = @{
        FriendlyName = "Weather"
        PackageName  = "Microsoft.BingWeather"
    }

    # Camera/Media Apps
    "Microsoft.WindowsCamera"                = @{
        FriendlyName = "Camera"
        PackageName  = "Microsoft.WindowsCamera"
    }
    "Clipchamp.Clipchamp"                    = @{
        FriendlyName = "Clipchamp"
        PackageName  = "Clipchamp.Clipchamp"
    }

    # System Utility Apps
    "Microsoft.WindowsAlarms"                = @{
        FriendlyName = "Alarms & Clock"
        PackageName  = "Microsoft.WindowsAlarms"
    }
    "Microsoft.549981C3F5F10"                = @{
        FriendlyName = "Cortana"
        PackageName  = "Microsoft.549981C3F5F10"
    }
    "Microsoft.GetHelp"                      = @{
        FriendlyName = "Get Help"
        PackageName  = "Microsoft.GetHelp"
    }

    # System Tools
    "Microsoft.Windows.DevHome"              = @{
        FriendlyName     = "Dev Home"
        PackageName      = "Microsoft.Windows.DevHome"
        RegistrySettings = @(
            [pscustomobject]@{
                BaseKey      = [BaseKey]::WindowsUpdateMain
                SubKeySuffix = "UScheduler_Oobe\DevHomeUpdate"
                Name         = $null
                Recommended  = [ValuePair]::new($null, [RegistryValueKind]::None)
                DefaultValue = $null
                Description  = "Prevent Dev Home Installation"
            }
        )
    }

    # Family & Communication
    "MicrosoftCorporationII.MicrosoftFamily" = @{
        FriendlyName = "Microsoft Family"
        PackageName  = "MicrosoftCorporationII.MicrosoftFamily"
    }
    "microsoft.windowscommunicationsapps"    = @{
        FriendlyName = "Mail and Calendar"
        PackageName  = "microsoft.windowscommunicationsapps"
    }

    # Feedback & Telemetry
    "Microsoft.WindowsFeedbackHub"           = @{
        FriendlyName = "Feedback Hub"
        PackageName  = "Microsoft.WindowsFeedbackHub"
    }

    # Maps & Location
    "Microsoft.WindowsMaps"                  = @{
        FriendlyName = "Maps"
        PackageName  = "Microsoft.WindowsMaps"
    }

    # Office Apps
    "Microsoft.MicrosoftOfficeHub"           = @{
        FriendlyName = "Office Hub"
        PackageName  = "Microsoft.MicrosoftOfficeHub"
    }
    "Microsoft.Office.OneNote"               = @{
        FriendlyName = "OneNote"
        PackageName  = "Microsoft.Office.OneNote"
    }

    # Paint Apps
    "Microsoft.MSPaint"                      = @{
        FriendlyName = "Paint 3D"
        PackageName  = "Microsoft.MSPaint"
    }

    # People & Social
    "Microsoft.People"                       = @{
        FriendlyName = "People"
        PackageName  = "Microsoft.People"
    }

    # Power Automate
    "Microsoft.PowerAutomateDesktop"         = @{
        FriendlyName = "Power Automate"
        PackageName  = "Microsoft.PowerAutomateDesktop"
    }

    # Quick Assist
    "MicrosoftCorporationII.QuickAssist"     = @{
        FriendlyName = "Quick Assist"
        PackageName  = "MicrosoftCorporationII.QuickAssist"
    }

    # Games & Entertainment
    "Microsoft.MicrosoftSolitaireCollection" = @{
        FriendlyName = "Solitaire Collection"
        PackageName  = "Microsoft.MicrosoftSolitaireCollection"
    }

    # Productivity Apps
    "Microsoft.MicrosoftStickyNotes"         = @{
        FriendlyName = "Sticky Notes"
        PackageName  = "Microsoft.MicrosoftStickyNotes"
    }

    # Getting Started
    "Microsoft.Getstarted"                   = @{
        FriendlyName = "Get Started"
        PackageName  = "Microsoft.Getstarted"
    }

    # To Do
    "Microsoft.Todos"                        = @{
        FriendlyName = "To Do"
        PackageName  = "Microsoft.Todos"
    }

    # Sound Recorder
    "Microsoft.WindowsSoundRecorder"         = @{
        FriendlyName = "Sound Recorder"
        PackageName  = "Microsoft.WindowsSoundRecorder"
    }

    # Phone Link
    "Microsoft.YourPhone"                    = @{
        FriendlyName = "Phone Link"
        PackageName  = "Microsoft.YourPhone"
    }

    # Copilot Related
    "Microsoft.Windows.Ai.Copilot.Provider"  = @{
        FriendlyName     = "Copilot Provider"
        PackageName      = "Microsoft.Windows.Ai.Copilot.Provider"
        RegistrySettings = @(
            [pscustomobject]@{
                BaseKey      = [BaseKey]::CloudContent
                Name         = "TurnOffWindowsCopilot"
                Recommended  = [ValuePair]::new(1, [RegistryValueKind]::DWord)
                DefaultValue = $null
                Description  = "Disable Windows Copilot system-wide"
            }
        )
    }
    "Microsoft.Copilot"                      = @{
        FriendlyName     = "Copilot"
        PackageName      = "Microsoft.Copilot"
        RegistrySettings = @(
            [pscustomobject]@{
                BaseKey      = [BaseKey]::CUExplorerAdvanced
                Name         = "ShowCopilotButton"
                Recommended  = [ValuePair]::new(0, [RegistryValueKind]::DWord)
                DefaultValue = $null
                Description  = "Hide Copilot button from taskbar"
            }
        )
    }
    "Microsoft.Copilot_8wekyb3d8bbwe"        = @{
        FriendlyName = "Copilot (Store)"
        PackageName  = "Microsoft.Copilot_8wekyb3d8bbwe"
    }

    # Meeting Apps
    "Microsoft.WindowsMeetNow"               = @{
        FriendlyName     = "Meet Now"
        PackageName      = "Microsoft.WindowsMeetNow"
        RegistrySettings = @(
            [pscustomobject]@{
                BaseKey      = [BaseKey]::LMPolicyExplorer
                Name         = "HideSCAMeetNow"
                Recommended  = [ValuePair]::new(1, [RegistryValueKind]::DWord)
                DefaultValue = $null
                Description  = "Hide Meet Now button"
            }
        )
    }

    # Communication Apps
    "Microsoft.SkypeApp"                     = @{
        FriendlyName = "Skype"
        PackageName  = "Microsoft.SkypeApp"
    }
}

# Define potentially useful Windows Apps
$UsefulAppx = @{
    # Xbox Related Apps
    "Microsoft.Xbox.TCUI"               = @{
        FriendlyName = "Xbox"
        PackageName  = "Microsoft.Xbox.TCUI"
    }
    "Microsoft.XboxApp"                 = @{
        FriendlyName = "Xbox"
        PackageName  = "Microsoft.XboxApp"
    }
    "Microsoft.XboxGameOverlay"         = @{
        FriendlyName = "Xbox"
        PackageName  = "Microsoft.XboxGameOverlay"
    }
    "Microsoft.XboxGamingOverlay"       = @{
        FriendlyName = "Xbox"
        PackageName  = "Microsoft.XboxGamingOverlay"
    }
    "Microsoft.XboxIdentityProvider"    = @{
        FriendlyName = "Xbox"
        PackageName  = "Microsoft.XboxIdentityProvider"
    }
    "Microsoft.XboxSpeechToTextOverlay" = @{
        FriendlyName = "Xbox"
        PackageName  = "Microsoft.XboxSpeechToTextOverlay"
    }
    "Microsoft.GamingApp"               = @{
        FriendlyName = "Xbox"
        PackageName  = "Microsoft.GamingApp"
    }

    # Outlook
    "Microsoft.OutlookForWindows"       = @{
        FriendlyName     = "New Outlook"
        PackageName      = "Microsoft.OutlookForWindows"
        RegistrySettings = @(
            [pscustomobject]@{
                BaseKey      = [BaseKey]::WindowsUpdateMain
                SubKeySuffix = "UScheduler_Oobe\OutlookUpdate"
                Name         = $null
                Recommended  = [ValuePair]::new($null, [RegistryValueKind]::None)
                DefaultValue = $null
                Description  = "Prevent New Outlook Installation"
            },
            [pscustomobject]@{
                BaseKey      = [BaseKey]::CUExplorerAdvanced
                Name         = "HideNewOutlookToggle"
                Recommended  = [ValuePair]::new(0, [RegistryValueKind]::DWord)
                DefaultValue = $null
                Description  = "Hide New Outlook Toggle"
            }
        )
    }

    # Store
    "Microsoft.WindowsStore"            = @{
        FriendlyName = "Microsoft Store"
        PackageName  = "Microsoft.WindowsStore"
    }

    # Basic Windows Apps
    "Microsoft.Paint"                   = @{
        FriendlyName = "Paint"
        PackageName  = "Microsoft.Paint"
    }
    "Microsoft.WindowsCalculator"       = @{
        FriendlyName = "Calculator"
        PackageName  = "Microsoft.WindowsCalculator"
    }
    "Microsoft.Windows.Photos"          = @{
        FriendlyName = "Photos"
        PackageName  = "Microsoft.Windows.Photos"
    }

    # Media Apps
    "Microsoft.ZuneMusic"               = @{
        FriendlyName = "Groove Music"
        PackageName  = "Microsoft.ZuneMusic"
    }
    "Microsoft.ZuneVideo"               = @{
        FriendlyName = "Movies & TV"
        PackageName  = "Microsoft.ZuneVideo"
    }

    # Screenshot Tool
    "Microsoft.ScreenSketch"            = @{
        FriendlyName = "Snip & Sketch"
        PackageName  = "Microsoft.ScreenSketch"
    }

    # Teams
    "MSTeams"                           = @{
        FriendlyName     = "Microsoft Teams"
        PackageName      = "MSTeams"
        RegistrySettings = @(
            [pscustomobject]@{
                BaseKey      = [BaseKey]::TaskbarChat
                Name         = "ChatIcon"
                Recommended  = [ValuePair]::new(3, [RegistryValueKind]::DWord)
                DefaultValue = $null
                Description  = "Hide Chat/Teams icon from taskbar"
            }
        )
    }
}

# Define Legacy Windows Capabilities
$LegacyCapabilities = @{
    "Browser.InternetExplorer"         = @{
        FriendlyName = "Internet Explorer"
        Name         = "Browser.InternetExplorer"
    }
    "MathRecognizer"                   = @{
        FriendlyName = "Math Recognizer"
        Name         = "MathRecognizer"
    }
    "OpenSSH.Client"                   = @{
        FriendlyName = "OpenSSH Client"
        Name         = "OpenSSH.Client"
    }
    "Microsoft.Windows.PowerShell.ISE" = @{
        FriendlyName = "PowerShell ISE"
        Name         = "Microsoft.Windows.PowerShell.ISE"
    }
    "App.Support.QuickAssist"          = @{
        FriendlyName = "Quick Assist"
        Name         = "App.Support.QuickAssist"
    }
    "App.StepsRecorder"                = @{
        FriendlyName = "Steps Recorder"
        Name         = "App.StepsRecorder"
    }
    "Media.WindowsMediaPlayer"         = @{
        FriendlyName = "Windows Media Player"
        Name         = "Media.WindowsMediaPlayer"
    }
    "Microsoft.Windows.WordPad"        = @{
        FriendlyName = "WordPad"
        Name         = "Microsoft.Windows.WordPad"
    }
    "Microsoft.Windows.MSPaint"        = @{
        FriendlyName = "Paint"
        Name         = "Microsoft.Windows.MSPaint"
    }
}


# Define the Edge removal logic as a script block
$EdgeRemovalScript = {
    # EdgeRemoval.ps1
    # Standalone script to remove Microsoft Edge
    # Source: Rocket ()"

    # stop edge running
    $stop = "MicrosoftEdgeUpdate", "OneDrive", "WidgetService", "Widgets", "msedge", "msedgewebview2"
    $stop | ForEach-Object { Stop-Process -Name $_ -Force -ErrorAction SilentlyContinue }
    # uninstall copilot
    Get-AppxPackage -allusers *Microsoft.Windows.Ai.Copilot.Provider* | Remove-AppxPackage
    # disable edge updates regedit
    reg add "HKLM\SOFTWARE\Microsoft\EdgeUpdate" /v "DoNotUpdateToEdgeWithChromium" /t REG_DWORD /d "1" /f | Out-Null
    # allow edge uninstall regedit
    reg add "HKLM\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdateDev" /v "AllowUninstall" /t REG_SZ /f | Out-Null
    # new folder to uninstall edge
    New-Item -Path "$env:SystemRoot\SystemApps\Microsoft.MicrosoftEdge_8wekyb3d8bbwe" -ItemType Directory -ErrorAction SilentlyContinue | Out-Null
    # new file to uninstall edge
    New-Item -Path "$env:SystemRoot\SystemApps\Microsoft.MicrosoftEdge_8wekyb3d8bbwe" -ItemType File -Name "MicrosoftEdge.exe" -ErrorAction SilentlyContinue | Out-Null
    # find edge uninstall string
    $regview = [Microsoft.Win32.RegistryView]::Registry32
    $microsoft = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, $regview).
    OpenSubKey("SOFTWARE\Microsoft", $true)
    $uninstallregkey = $microsoft.OpenSubKey("Windows\CurrentVersion\Uninstall\Microsoft Edge")
    try {
        $uninstallstring = $uninstallregkey.GetValue("UninstallString") + " --force-uninstall"
    }
    catch {
    }
    # uninstall edge
    Start-Process cmd.exe "/c $uninstallstring" -WindowStyle Hidden -Wait
    # remove folder file
    Remove-Item -Recurse -Force "$env:SystemRoot\SystemApps\Microsoft.MicrosoftEdge_8wekyb3d8bbwe" -ErrorAction SilentlyContinue | Out-Null
    # find edgeupdate.exe
    $edgeupdate = @(); "LocalApplicationData", "ProgramFilesX86", "ProgramFiles" | ForEach-Object {
        $folder = [Environment]::GetFolderPath($_)
        $edgeupdate += Get-ChildItem "$folder\Microsoft\EdgeUpdate\*.*.*.*\MicrosoftEdgeUpdate.exe" -rec -ea 0
    }
    # find edgeupdate & allow uninstall regedit
    $global:REG = "HKCU:\SOFTWARE", "HKLM:\SOFTWARE", "HKCU:\SOFTWARE\Policies", "HKLM:\SOFTWARE\Policies", "HKCU:\SOFTWARE\WOW6432Node", "HKLM:\SOFTWARE\WOW6432Node", "HKCU:\SOFTWARE\WOW6432Node\Policies", "HKLM:\SOFTWARE\WOW6432Node\Policies"
    foreach ($location in $REG) { Remove-Item "$location\Microsoft\EdgeUpdate" -recurse -force -ErrorAction SilentlyContinue }
    # uninstall edgeupdate
    foreach ($path in $edgeupdate) {
        if (Test-Path $path) { Start-Process -Wait $path -Args "/unregsvc" | Out-Null }
        do { Start-Sleep 3 } while ((Get-Process -Name "setup", "MicrosoftEdge*" -ErrorAction SilentlyContinue).Path -like "*\Microsoft\Edge*")
        if (Test-Path $path) { Start-Process -Wait $path -Args "/uninstall" | Out-Null }
        do { Start-Sleep 3 } while ((Get-Process -Name "setup", "MicrosoftEdge*" -ErrorAction SilentlyContinue).Path -like "*\Microsoft\Edge*")
    }
    # remove edgewebview regedit
    cmd /c "reg delete `"HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft EdgeWebView`" /f >nul 2>&1"
    cmd /c "reg delete `"HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft EdgeWebView`" /f >nul 2>&1"
    # remove folders edge edgecore edgeupdate edgewebview temp
    Remove-Item -Recurse -Force "$env:SystemDrive\Program Files (x86)\Microsoft" -ErrorAction SilentlyContinue | Out-Null
    # remove edge shortcuts
    Remove-Item -Recurse -Force "$env:SystemDrive\Windows\System32\config\systemprofile\AppData\Roaming\Microsoft\Internet Explorer\Quick Launch\Microsoft Edge.lnk" -ErrorAction SilentlyContinue | Out-Null
    Remove-Item -Recurse -Force "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Microsoft Edge.lnk" -ErrorAction SilentlyContinue | Out-Null

    $fileSystemProfiles = Get-ChildItem -Path "C:\Users" -Directory | Where-Object { 
        $_.Name -notin @('Public', 'Default', 'Default User', 'All Users') -and 
        (Test-Path -Path "$($_.FullName)\NTUSER.DAT")
    }
    
    # Loop through each user profile and clean up Edge shortcuts
    foreach ($profile in $fileSystemProfiles) {
        $userProfilePath = $profile.FullName
        
        # Define user-specific paths to clean
        $edgeShortcutPaths = @(
            "$userProfilePath\AppData\Roaming\Microsoft\Internet Explorer\Quick Launch\Microsoft Edge.lnk",
            "$userProfilePath\Desktop\Microsoft Edge.lnk",
            "$userProfilePath\AppData\Roaming\Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar\Microsoft Edge.lnk",
            "$userProfilePath\AppData\Roaming\Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar\Tombstones\Microsoft Edge.lnk",
            "$userProfilePath\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Microsoft Edge.lnk"
        )
    
        # Remove Edge shortcuts for each user
        foreach ($path in $edgeShortcutPaths) {
            if (Test-Path -Path $path -PathType Leaf) {
                Remove-Item -Path $path -Force -ErrorAction SilentlyContinue
            }
        }
    }
    
    # Clean up common locations
    $commonShortcutPaths = @(
        "$env:PUBLIC\Desktop\Microsoft Edge.lnk",
        "$env:ALLUSERSPROFILE\Microsoft\Windows\Start Menu\Programs\Microsoft Edge.lnk",
        "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Microsoft Edge.lnk"
    )
    
    foreach ($path in $commonShortcutPaths) {
        if (Test-Path -Path $path -PathType Leaf) {
            Remove-Item -Path $path -Force -ErrorAction SilentlyContinue
        }
    }

    # Removes Edge in Task Manager Startup Apps for All Users
    # Get all user profiles on the system
    $userProfiles = Get-CimInstance -ClassName Win32_UserProfile | 
    Where-Object { -not $_.Special -and $_.SID -notmatch 'S-1-5-18|S-1-5-19|S-1-5-20' }

    foreach ($profile in $userProfiles) {
        $sid = $profile.SID
        $hiveLoaded = $false

        if (-not (Test-Path "Registry::HKEY_USERS\$sid")) {
            $userRegPath = Join-Path $profile.LocalPath "NTUSER.DAT"
            if (Test-Path $userRegPath) {
                reg load "HKU\$sid" $userRegPath | Out-Null
                $hiveLoaded = $true
                Start-Sleep -Seconds 2
            }
        }

        $runKeyPath = "Registry::HKEY_USERS\$sid\Software\Microsoft\Windows\CurrentVersion\Run"

        if (Test-Path $runKeyPath) {
            $properties = Get-ItemProperty -Path $runKeyPath
            $edgeEntries = $properties.PSObject.Properties | 
            Where-Object { $_.Name -like 'MicrosoftEdgeAutoLaunch*' }
    
            foreach ($entry in $edgeEntries) {
                Remove-ItemProperty -Path $runKeyPath -Name $entry.Name -Force
            }
        }

        if ($hiveLoaded) {
            [gc]::Collect()
            Start-Sleep -Seconds 2
            reg unload "HKU\$sid" | Out-Null
        }
    }

}

# Function to remove Microsoft Edge and create removal script and scheduled task
function Remove-Edge {
    # Confirm with the user before proceeding
    $result = Show-MessageBox -Message "You're about to remove Microsoft Edge from your system. This may cause system instability.`nAre you sure you want to continue?" -Title "Warning" -Buttons "YesNo" -Icon "Warning"

    if ($result -eq [System.Windows.Forms.DialogResult]::Yes) {
        # Execute the Edge removal logic
        Write-Status -Message "Starting Edge Removal. Please wait..." -TargetScreen "SoftAppsScreen"
        try {
            & $EdgeRemovalScript

            # Save the standalone script
            $scriptPath = "$env:ProgramFiles\Rocket\Scripts\EdgeRemoval.ps1"
            if (-not (Test-Path -Path (Split-Path -Parent $scriptPath))) {
                New-Item -ItemType Directory -Path (Split-Path -Parent $scriptPath) -Force
            }
            Set-Content -Path $scriptPath -Value $EdgeRemovalScript -Force
            Write-Status -Message "Standalone script saved at $scriptPath" -TargetScreen "SoftAppsScreen"

            # Creates Scheduled Task to remove Edge if it's installed again (via Windows Update for example)
            Register-ScheduledTask -TaskName "Rocket\EdgeRemoval" `
                -Action (New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-File `"$scriptPath`"") `
                -Trigger (New-ScheduledTaskTrigger -AtStartup) `
                -User "SYSTEM" `
                -RunLevel Highest `
                -Settings (New-ScheduledTaskSettingsSet -DontStopIfGoingOnBatteries -AllowStartIfOnBatteries) `
                -Force
            Write-Status -Message "Scheduled task created to run EdgeRemoval.ps1 at startup." -TargetScreen "SoftAppsScreen"

            # Show success message box
            Show-MessageBox -Message "Microsoft Edge has been successfully removed from your system.`n`nA startup task was created to prevent it from reinstalling.`nIf you experience issues, you can delete the 'EdgeRemoval' task in Task Scheduler." -Title "Success" -Buttons "OK" -Icon "Information"
        }
        catch {
            # Handle errors and display a failure message
            Write-Status -Message "An error occurred during Edge removal: $($_.Exception.Message)" -TargetScreen "SoftAppsScreen"
            Show-MessageBox -Message "An error occurred while removing Microsoft Edge. Please check the logs or try again." -Title "Error" -Buttons "OK" -Icon "Error"
        }
    }
    else {
        Write-Status -Message "Edge removal operation canceled by the user." -TargetScreen "SoftAppsScreen"
    }
}

$OneDriveRemovalScript = {
    try {
        # Stop OneDrive processes
        $processesToStop = @("OneDrive", "FileCoAuth", "FileSyncHelper")
        foreach ($processName in $processesToStop) { 
            Get-Process -Name $processName -ErrorAction SilentlyContinue | 
            Stop-Process -Force -ErrorAction SilentlyContinue
        }
        Start-Sleep -Seconds 1
    }
    catch {
        # Continue if process stopping fails
    }
    
    # Check and execute uninstall strings from registry
    $registryPaths = @(
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\OneDriveSetup.exe",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\OneDriveSetup.exe"
    )

    foreach ($regPath in $registryPaths) {
        try {
            if (Test-Path $regPath) {
                $uninstallString = (Get-ItemProperty -Path $regPath -ErrorAction Stop).UninstallString
                if ($uninstallString) {
                    if ($uninstallString -match '^"([^"]+)"(.*)$') {
                        $exePath = $matches[1]
                        $args = $matches[2].Trim()
                        Start-Process -FilePath $exePath -ArgumentList $args -NoNewWindow -Wait -ErrorAction SilentlyContinue
                    }
                    else {
                        Start-Process -FilePath $uninstallString -NoNewWindow -Wait -ErrorAction SilentlyContinue
                    }
                }
            }
        }
        catch {
            # Continue if registry operation fails
            continue
        }
    }

    try {
        # Remove OneDrive AppX package
        Get-AppxPackage -Name "*OneDrive*" -ErrorAction SilentlyContinue | 
        Remove-AppxPackage -ErrorAction SilentlyContinue
    }
    catch {
        # Continue if AppX removal fails
    }
    
    # Uninstall OneDrive using setup files
    $oneDrivePaths = @(
        "$env:SystemRoot\SysWOW64\OneDriveSetup.exe",
        "$env:SystemRoot\System32\OneDriveSetup.exe",
        "$env:LOCALAPPDATA\Microsoft\OneDrive\OneDrive.exe"
    )
    
    foreach ($path in $oneDrivePaths) {
        try {
            if (Test-Path $path) {
                Start-Process -FilePath $path -ArgumentList "/uninstall" -NoNewWindow -Wait -ErrorAction SilentlyContinue
            }
        }
        catch {
            # Continue if uninstall fails
            continue
        }
    }
    
    try {
        # Remove OneDrive scheduled tasks
        Get-ScheduledTask -ErrorAction SilentlyContinue | 
        Where-Object { $_.TaskName -match 'OneDrive' -and $_.TaskName -ne 'OneDriveRemoval' } | 
        ForEach-Object { 
            Unregister-ScheduledTask -TaskName $_.TaskName -Confirm:$false -ErrorAction SilentlyContinue 
        }
    }
    catch {
        # Continue if task removal fails
    }
    
    try {
        # Configure registry settings
        $regPath = "HKLM:\SOFTWARE\Policies\Microsoft\OneDrive"
        if (-not (Test-Path $regPath)) {
            New-Item -Path $regPath -Force -ErrorAction SilentlyContinue | Out-Null
        }
        Set-ItemProperty -Path $regPath -Name "KFMBlockOptIn" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
        
        # Remove OneDrive from startup
        Remove-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Name "OneDriveSetup" -ErrorAction SilentlyContinue
        
        # Remove OneDrive from Navigation Pane
        Remove-Item -Path "Registry::HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace\{018D5C66-4533-4307-9B53-224DE2ED1FE6}" -Recurse -Force -ErrorAction SilentlyContinue
    }
    catch {
        # Continue if registry operations fail
    }
    
    # Function to handle robust folder removal
    function Remove-OneDriveFolder {
        param ([string]$folderPath)
        
        if (-not (Test-Path $folderPath)) {
            return
        }
        
        try {
            # Stop OneDrive processes if they're running
            Get-Process -Name "OneDrive" -ErrorAction SilentlyContinue | 
            Stop-Process -Force -ErrorAction SilentlyContinue
            
            # Take ownership and grant permissions
            $null = Start-Process "takeown.exe" -ArgumentList "/F `"$folderPath`" /R /A /D Y" -Wait -NoNewWindow -PassThru -ErrorAction SilentlyContinue
            $null = Start-Process "icacls.exe" -ArgumentList "`"$folderPath`" /grant administrators:F /T" -Wait -NoNewWindow -PassThru -ErrorAction SilentlyContinue
            
            # Try direct removal
            Remove-Item -Path $folderPath -Force -Recurse -ErrorAction SilentlyContinue
        }
        catch {
            try {
                # If direct removal fails, create and execute a cleanup batch file
                $batchPath = "$env:TEMP\RemoveOneDrive_$(Get-Random).bat"
                $batchContent = @"
@echo off
timeout /t 2 /nobreak > nul
takeown /F "$folderPath" /R /A /D Y
icacls "$folderPath" /grant administrators:F /T
rd /s /q "$folderPath"
del /F /Q "%~f0"
"@
                Set-Content -Path $batchPath -Value $batchContent -Force -ErrorAction SilentlyContinue
                Start-Process "cmd.exe" -ArgumentList "/c $batchPath" -WindowStyle Hidden -ErrorAction SilentlyContinue
            }
            catch {
                # Continue if batch file cleanup fails
            }
        }
    }

    # Files to remove (single items)
    $filesToRemove = @(
        "$env:ALLUSERSPROFILE\Users\Default\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\OneDrive.lnk",
        "$env:ALLUSERSPROFILE\Users\Default\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\OneDrive.exe",
        "$env:PUBLIC\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\OneDrive.lnk",
        "$env:PUBLIC\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\OneDrive.exe",
        "$env:SystemRoot\System32\OneDriveSetup.exe",
        "$env:SystemRoot\SysWOW64\OneDriveSetup.exe",
        "$env:LOCALAPPDATA\Microsoft\OneDrive\OneDrive.exe",
        "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\OneDrive.lnk"
    )

    # Remove single files
    foreach ($file in $filesToRemove) {
        try {
            if (Test-Path $file) {
                Remove-Item $file -Force -ErrorAction SilentlyContinue
            }
        }
        catch {
            # Continue if file removal fails
            continue
        }
    }

    # Folders that need special handling
    $foldersToRemove = @(
        "$env:ProgramFiles\Microsoft\OneDrive",
        "$env:ProgramFiles\Microsoft OneDrive",
        "$env:LOCALAPPDATA\Microsoft\OneDrive"
    )

    # Remove folders with robust method
    foreach ($folder in $foldersToRemove) {
        try {
            Remove-OneDriveFolder -folderPath $folder
        }
        catch {
            # Continue if folder removal fails
            continue
        }
    }
}

# Function to Remove-Onedrive
function Remove-OneDrive {
    # Confirm with the user before proceeding
    $result = Show-MessageBox -Message "You're about to remove OneDrive from your system.`n`nThis will:
- Uninstall OneDrive completely
- Remove OneDrive integration from Windows
- Disable OneDrive features system-wide`n`nAre you sure you want to continue?" -Title "Warning" -Buttons "YesNo" -Icon "Warning"

    if ($result -eq [System.Windows.Forms.DialogResult]::Yes) {
        # Set wait cursor
        $Window.Cursor = [System.Windows.Input.Cursors]::Wait
        
        try {
            Write-Status -Message "Removing OneDrive. Please wait..." -TargetScreen SoftAppsScreen
            Update-WPFControls
            
            # Execute the OneDrive removal logic
            & $OneDriveRemovalScript

            # Save the standalone script
            $scriptPath = "$env:ProgramFiles\Rocket\Scripts\OneDriveRemoval.ps1"
            if (-not (Test-Path -Path (Split-Path -Parent $scriptPath))) {
                New-Item -ItemType Directory -Path (Split-Path -Parent $scriptPath) -Force
            }
            Set-Content -Path $scriptPath -Value $OneDriveRemovalScript -Force
            
            Write-Status -Message "Standalone script saved at $scriptPath" -TargetScreen SoftAppsScreen
            Update-WPFControls

            # Create scheduled task to remove OneDrive if it's installed again
            $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-File `"$scriptPath`""
            $trigger = New-ScheduledTaskTrigger -AtStartup
            $settings = New-ScheduledTaskSettingsSet -DontStopIfGoingOnBatteries -AllowStartIfOnBatteries
            
            Register-ScheduledTask -TaskName "Rocket\OneDriveRemoval" `
                -Action $action `
                -Trigger $trigger `
                -User "SYSTEM" `
                -RunLevel Highest `
                -Settings $settings `
                -Force
            
            Write-Status -Message "Scheduled task created to run OneDriveRemoval.ps1 at startup." -TargetScreen SoftAppsScreen
            Update-WPFControls

            # Prompt user about cleaning up their OneDrive data
            $cleanupMessage = "Would you like to remove local OneDrive folders and data?`n`n" +
            "NOTE: This will delete all local OneDrive data from your computer. Your files will still be available through OneDrive.com if you've previously synced them.`n`n" +
            "This step is optional and should only be performed if you:`n" +
            "- Are sure your files are synced to OneDrive.com`n" +
            "- No longer need local copies of your OneDrive files`n" +
            "- Understand how to access your files from OneDrive.com`n`n" +
            "This action cannot be undone."

            $cleanupResult = Show-MessageBox -Message $cleanupMessage -Title "OneDrive Data Cleanup" -Buttons YesNo -Icon Warning

            if ($cleanupResult -eq [System.Windows.Forms.DialogResult]::Yes) {
                Write-Status -Message "Cleaning up OneDrive folders..." -TargetScreen SoftAppsScreen
                Update-WPFControls
                
                $oneDriveFolders = @(
                    "$env:USERPROFILE\OneDrive",
                    "$env:LOCALAPPDATA\Microsoft\OneDrive",
                    "$env:PROGRAMDATA\Microsoft OneDrive"
                )
                foreach ($folder in $oneDriveFolders) {
                    if (Test-Path $folder) {
                        Remove-Item -Path $folder -Recurse -Force -ErrorAction SilentlyContinue
                    }
                }
            }

            Show-MessageBox -Message "OneDrive has been successfully removed from your system.`n`nA startup task was created to prevent it from reinstalling.`nIf you experience issues, you can delete the 'OneDriveRemoval' task in Task Scheduler." -Title "Success" -Buttons OK -Icon Information
            Write-Status -Message "OneDrive removal completed successfully!" -TargetScreen SoftAppsScreen
            Update-WPFControls
        }
        catch {
            Write-Status -Message "Error removing OneDrive: $($_.Exception.Message)" -TargetScreen SoftAppsScreen
            Update-WPFControls
            Show-MessageBox -Message "An error occurred while removing OneDrive: $($_.Exception.Message)" -Title "Error" -Buttons OK -Icon Error
        }
        finally {
            # Reset cursor back to normal
            $Window.Cursor = $null
        }
    }
    else {
        Write-Status -Message "OneDrive removal cancelled by user." -TargetScreen SoftAppsScreen
        Update-WPFControls
    }
}

# Function to remove the selected apps (Including Edge and OneDrive), create removal script and scheduled task
function Remove-SelectedBloatware {
    function Process-Child {
        param (
            $child,
            [System.Collections.ArrayList]$bloatScriptContent,
            [ref]$hasNormalApps,
            [ref]$hasEdge,
            [ref]$hasOneDrive
        )
    
        if ($child -is [System.Windows.Controls.CheckBox] -and $child.IsChecked -eq $true) {
            if ($child.Content -eq "Select All") {
                Write-Status "Skipping 'Select All' checkbox."
                return
            }
    
            Write-Status "Processing checkbox: $($child.Content)"
    
            # Handle special cases first
            switch ($child.Tag) {
                "Edge" {
                    $hasEdge.Value = $true
                    Remove-Edge
                    return
                }
                "OneDrive" {
                    $hasOneDrive.Value = $true
                    Remove-OneDrive
                    return
                }
                "Recall" {
                    $hasNormalApps.Value = $true
                    Write-Status "Adding Recall disable command to script..."
                    # Add Recall disable command to script
                    $bloatScriptContent.Add("# Disable Recall Feature") | Out-Null
                    $bloatScriptContent.Add('$result = Dism /Online /Disable-Feature /Featurename:Recall /NoRestart 2>&1') | Out-Null
                    $bloatScriptContent.Add('if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne 3010) { throw "Failed to disable Recall feature. Exit code: $LASTEXITCODE" }') | Out-Null
                    
                    # Execute Recall disable immediately
                    try {
                        $result = Dism /Online /Disable-Feature /Featurename:Recall /NoRestart 2>&1
                        if ($LASTEXITCODE -eq 0 -or $LASTEXITCODE -eq 3010) {
                            Write-Status "Recall feature disabled successfully."
                        }
                        else {
                            Write-Status "Failed to disable Recall feature. Error: $($result -join '\n')"
                        }
                    }
                    catch {
                        Write-Status "Error disabling Recall: $($_.Exception.Message)"
                    }
                    return
                }
            }
    
            # Handle regular app removal and capabilities based on tag type
            $hasNormalApps.Value = $true
            if ($child.Content -eq "Useless Bloatware") {
                # Handle appx package removal
                foreach ($appName in $child.Tag) {
                    Process-AppRemoval -AppName $appName -BloatScriptContent $bloatScriptContent
                    Process-RegistrySettings -AppName $appName -BloatScriptContent $bloatScriptContent
                }
            
                # Handle capabilities removal - execute only, don't add to script
                Write-Status "Processing Legacy Windows Features..."
                try {
                    Get-WindowsCapability -Online | 
                    Where-Object { $LegacyCapabilities.Keys -contains ($_.Name -split '~')[0] } |
                    ForEach-Object {
                        $friendlyName = $LegacyCapabilities[($_.Name -split '~')[0]].FriendlyName
                        Write-Status "Removing Legacy Feature: $friendlyName"
                        Remove-WindowsCapability -Online -Name $_.Name -ErrorAction SilentlyContinue | Out-Null
                    }
                }
                catch {
                    Write-Status "Error removing Legacy Features: $($_.Exception.Message)"
                }
            }
            elseif ($child.Tag -is [Array]) {
                foreach ($appName in $child.Tag) {
                    Process-AppRemoval -AppName $appName -BloatScriptContent $bloatScriptContent
                    Process-RegistrySettings -AppName $appName -BloatScriptContent $bloatScriptContent
                }
            }
            else {
                $appName = $child.Tag.Trim()
                Process-AppRemoval -AppName $appName -BloatScriptContent $bloatScriptContent
                Process-RegistrySettings -AppName $appName -BloatScriptContent $bloatScriptContent
            }
        }
    
        if ($child -is [System.Windows.Controls.Panel]) {
            foreach ($nestedChild in $child.Children) {
                Process-Child -child $nestedChild -bloatScriptContent $bloatScriptContent -hasNormalApps $hasNormalApps -hasEdge $hasEdge -hasOneDrive $hasOneDrive
            }
        }
    }
    
    function Process-AppRemoval {
        param (
            [string]$AppName,
            [System.Collections.ArrayList]$bloatScriptContent
        )
    
        Write-Status "Removing app: $AppName" -TargetScreen SoftAppsScreen
        
        # Add to the standalone script (without Write-Status commands)
        $bloatScriptContent.Add("Get-AppxPackage -AllUsers | Where-Object { `$_.Name -eq '$AppName' } | ForEach-Object { Remove-AppxPackage -Package `$_.PackageFullName -AllUsers -ErrorAction SilentlyContinue }") | Out-Null
        
        # Get all packages matching the app name
        $packages = Get-AppxPackage -AllUsers | Where-Object { $_.Name -eq $AppName }
        
        if (-not $packages) {
            Write-Status "No packages found for $AppName" -TargetScreen SoftAppsScreen
            return
        }
    
        # Log all found packages before removal
        foreach ($pkg in $packages) {
            Write-Status "Found package: $($pkg.PackageFullName) (Architecture: $($pkg.Architecture), Version: $($pkg.Version))" -TargetScreen SoftAppsScreen
        }
        
        foreach ($package in $packages) {
            Write-Status "Removing package: $($package.PackageFullName)" -TargetScreen SoftAppsScreen
            try {
                # First try to remove provisioned package if it exists
                $provPackage = Get-AppxProvisionedPackage -Online | 
                Where-Object { $_.DisplayName -eq $AppName }
                if ($provPackage) {
                    Write-Status "Removing provisioned package first: $($provPackage.PackageName)" -TargetScreen SoftAppsScreen
                    Remove-AppxProvisionedPackage -Online -PackageName $provPackage.PackageName -ErrorAction SilentlyContinue | Out-Null
                }
    
                # Create a separate PowerShell process for package removal
                $script = {
                    param($packageFullName)
                    try {
                        Remove-AppxPackage -Package $packageFullName -AllUsers -ErrorAction Stop
                        return @{
                            Success = $true
                            Message = "Successfully removed package"
                        }
                    }
                    catch {
                        return @{
                            Success = $false
                            Message = $_.Exception.Message
                        }
                    }
                }
                
                $job = Start-Job -ScriptBlock $script -ArgumentList $package.PackageFullName
                $completed = Wait-Job -Job $job -Timeout 30
                
                if ($completed) {
                    $result = Receive-Job -Job $job
                    if ($result.Success) {
                        Write-Status "Successfully removed $($package.PackageFullName)" -TargetScreen SoftAppsScreen
                    }
                    else {
                        Write-Status "Error removing $($package.PackageFullName): $($result.Message)" -TargetScreen SoftAppsScreen
                    }
                }
                else {
                    Write-Status "Package removal timed out: $($package.PackageFullName)" -TargetScreen SoftAppsScreen
                }
                Remove-Job -Job $job -Force
            }
            catch {
                Write-Status "Error processing package $($package.PackageFullName): $($_.Exception.Message)" -TargetScreen SoftAppsScreen
            }
        }
    }
    
    function Process-RegistrySettings {
        param (
            [string]$AppName,
            [System.Collections.ArrayList]$bloatScriptContent
        )
    
        # Look up app configuration in both arrays
        $appConfig = $null
        if ($Bloatappx.ContainsKey($AppName)) {
            $appConfig = $Bloatappx[$AppName]
        }
        elseif ($UsefulAppx.ContainsKey($AppName)) {
            $appConfig = $UsefulAppx[$AppName]
        }
    
        if ($appConfig -and $appConfig.RegistrySettings) {
            Write-Status "Processing registry settings for $($appConfig.FriendlyName)"
    
            foreach ($regSetting in $appConfig.RegistrySettings) {
                $baseKeyInfo = $SCRIPT:BaseKeys[$regSetting.BaseKey]
                $subKey = $baseKeyInfo.SubKey
                
                if ($regSetting.SubKeySuffix) {
                    $subKey = Join-Path $subKey $regSetting.SubKeySuffix
                }
    
                try {
                    # For registry keys that need to be deleted
                    if ($null -eq $regSetting.Name) {
                        if (Test-Path $subKey) {
                            Remove-Item -Path $subKey -Force -ErrorAction Stop
                            Write-Status "Removed registry key: $subKey"
                            $bloatScriptContent.Add("if (Test-Path '$subKey') { Remove-Item -Path '$subKey' -Force -ErrorAction SilentlyContinue }") | Out-Null
                        }
                    }
                    else {
                        # For registry values that need to be set
                        if (-not (Test-Path $subKey)) {
                            New-Item -Path $subKey -Force | Out-Null
                        }
            
                        $setting = [RegistrySetting]::new(
                            $baseKeyInfo.Hive,
                            $subKey,
                            $regSetting.Name,
                            $regSetting.Recommended.Value,
                            $regSetting.Recommended.Type,
                            $regSetting.DefaultValue,
                            $regSetting.Description
                        )
                        $setting.Execute([RegistryAction]::Apply)
                        Write-Status "Applied registry setting: $($regSetting.Description)"
            
                        # Changed how we generate the registry commands
                        $bloatScriptContent.Add("if (-not (Test-Path '$subKey')) { New-Item -Path '$subKey' -Force | Out-Null }") | Out-Null
                        $value = if ($regSetting.Recommended.Type -eq 'DWord') { "[int]$($regSetting.Recommended.Value)" } else { "'$($regSetting.Recommended.Value)'" }
                        $bloatScriptContent.Add("`$null = New-ItemProperty -Path '$subKey' -Name '$($regSetting.Name)' -Value $value -PropertyType $($regSetting.Recommended.Type) -Force -ErrorAction SilentlyContinue") | Out-Null
                    }
                }
                catch {
                    Write-Status "Failed to apply registry setting: $($regSetting.Description) - $_"
                }
            }
        }
    }

    # Initialize flags to track what types of items are selected
    $hasNormalApps = [ref]$false
    $hasEdge = [ref]$false
    $hasOneDrive = [ref]$false

    # First, handle Edge and OneDrive separately
    foreach ($child in $uniformGrid.Children) {
        if ($child -is [System.Windows.Controls.CheckBox] -and $child.IsChecked -eq $true) {
            if ($child.Content -eq "Select All") { continue }
            
            # Process Edge and OneDrive immediately
            switch ($child.Tag) {
                "Edge" { 
                    Remove-Edge
                }
                "OneDrive" { 
                    Remove-OneDrive
                }
                default { 
                    $hasNormalApps.Value = $true 
                }
            }
        }
    }

    # Then handle normal apps with warning
    if ($hasNormalApps.Value) {
        $result = Show-MessageBox -Message "You're about to remove apps from your system that could cause instability.`nMissing apps will have to be reinstalled individually.`nAre you sure you want to continue?" -Title "Warning" -Buttons "YesNo" -Icon "Warning"

        if ($result -eq [System.Windows.Forms.DialogResult]::Yes) {
            # Initialize content for the standalone script using ArrayList
            $bloatScriptContent = [System.Collections.ArrayList]@(
                "# BloatRemoval.ps1",
                "# Standalone script to remove selected bloatware",
                "# Source: Rocket ()",
                ""
            )

            # Process only non-Edge/OneDrive items
            foreach ($child in $uniformGrid.Children) {
                if ($child -is [System.Windows.Controls.CheckBox] -and $child.IsChecked -eq $true) {
                    if ($child.Content -eq "Select All" -or $child.Tag -eq "Edge" -or $child.Tag -eq "OneDrive") { 
                        continue 
                    }
                    Process-Child -child $child -bloatScriptContent $bloatScriptContent -hasNormalApps $hasNormalApps -hasEdge $hasEdge -hasOneDrive $hasOneDrive
                }
                elseif ($child -is [System.Windows.Controls.Panel]) {
                    foreach ($nestedChild in $child.Children) {
                        if ($nestedChild.Tag -ne "Edge" -and $nestedChild.Tag -ne "OneDrive") {
                            Process-Child -child $nestedChild -bloatScriptContent $bloatScriptContent -hasNormalApps $hasNormalApps -hasEdge $hasEdge -hasOneDrive $hasOneDrive
                        }
                    }
                }
            }

            # Save and register the script
            $scriptPath = "$env:ProgramFiles\Rocket\Scripts\BloatRemoval.ps1"
            if (-not (Test-Path -Path (Split-Path -Parent $scriptPath))) {
                New-Item -ItemType Directory -Path (Split-Path -Parent $scriptPath) -Force
            }
            $bloatScriptContent | Set-Content -Path $scriptPath -Force
            Write-Status "Standalone script saved at $scriptPath" -TargetScreen SoftAppsScreen

            # Register the scheduled task
            Register-ScheduledTask -TaskName "Rocket\BloatRemoval" -Action (New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-File `"$scriptPath`"") -Trigger (New-ScheduledTaskTrigger -AtStartup) -User "SYSTEM" -RunLevel Highest -Settings (New-ScheduledTaskSettingsSet -DontStopIfGoingOnBatteries -AllowStartIfOnBatteries) -Force
            Write-Status "Scheduled task created to run BloatRemoval.ps1 at startup." -TargetScreen SoftAppsScreen

            Write-Status "Selected apps removed." -TargetScreen SoftAppsScreen
            Show-MessageBox -Message "Selected apps removed.`n`nA startup task was created to prevent apps from reinstalling. If you experience issues with automatic app removal in the future, you can delete the 'BloatRemoval' task in Task Scheduler." -Title "Success" -Buttons "OK" -Icon "Information"
        }
        else {
            Write-Status "Operation canceled by the user." -TargetScreen SoftAppsScreen
        }
    }
}

# =================================
# Optimize Screen Functions
# =================================
# Windows Security Settings
# =================================

# Function to Handle UAC Settings
function Update-UACNotificationLevel {
    param(
        [Parameter()]
        [ValidateSet('Get', 'Set')]
        [string]$Mode = 'Get',

        [Parameter()]
        [ValidateRange(0, 2)]
        [int]$Level
    )

    $regPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
    $regName = "ConsentPromptBehaviorAdmin"

    # Define value mappings (combine both maps into a single structure)
    $uacMap = @{
        Registry = @{
            0 = 0  # Never notify (Low)
            1 = 5  # Notify me only (Moderate)
            2 = 2  # Always notify (High)
        }
        Slider   = @{
            0 = 0  # Never notify (Low)
            5 = 1  # Notify me only (Moderate)
            2 = 2  # Always notify (High)
        }
        Names    = @{
            0 = "Low"
            1 = "Moderate" 
            2 = "High"
        }
    }

    try {
        switch ($Mode) {
            'Get' {
                # Get current registry value
                if (Test-Path $regPath) {
                    $rawValue = Get-ItemProperty -Path $regPath -Name $regName -ErrorAction Stop |
                    Select-Object -ExpandProperty $regName
                }
                else {
                    Write-Log "UAC registry path not found"
                    return 0
                }

                # Convert and map value
                $rawNumber = try { 
                    [int]$rawValue 
                }
                catch {
                    Write-Log "UAC value conversion failed for '$rawValue'. Error: $_"
                    return 0
                }

                if (-not $uacMap.Slider.ContainsKey($rawNumber)) {
                    Write-Log "Unmapped UAC value detected: $rawNumber"
                    return 0
                }

                return $uacMap.Slider[$rawNumber]
            }

            'Set' {
                if (-not $uacMap.Registry.ContainsKey($Level)) {
                    throw "Invalid UAC level: $Level"
                }

                # Create registry path if it doesn't exist
                if (-not (Test-Path $regPath)) {
                    New-Item -Path $regPath -Force | Out-Null
                }

                # Set the registry value
                Set-ItemProperty -Path $regPath -Name $regName -Value $uacMap.Registry[$Level] -Type DWord
                Write-Status "UAC successfully set to $($uacMap.Names[$Level])" -TargetScreen OptimizeScreen
            }
        }
    }
    catch {
        $errorMsg = if ($Mode -eq 'Get') { "UAC notification level check failed: $_" } else { "UAC update failed: $($_.Exception.Message)" }
        Write-Log $errorMsg
        if ($Mode -eq 'Set') {
            Write-Status $errorMsg -TargetScreen OptimizeScreen
            throw
        }
        return 0
    }
}


# Function to Enable Windows Security Suite
# Source Script: https://raw.githubusercontent.com/FR33THYFR33THY/Ultimate-Windows-Optimization-Guide/refs/heads/main/8%20Advanced/7%20Security.ps1
function Enable-WindowsSecuritySuite {
    $enableWarning = @"
You are about to enable the Windows Security Suite and set Windows Security Defaults.

Do you want to continue?
"@

    $confirm = Show-MessageBox -Message $enableWarning -Title "Enable Windows Security" -Buttons "YesNo" -Icon "Question"
    if ($confirm -eq "No") { return }
    Write-Status "Enabling Windows Security Suite. Please Wait . . ." -TargetScreen OptimizeScreen
    # create reg file
    $MultilineComment = @"
Windows Registry Editor Version 5.00

; ENABLE WINDOWS SECURITY SETTINGS
; real time protection
[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows Defender\Real-Time Protection]
"DisableRealtimeMonitoring"=dword:00000000

; dev drive protection
[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows Defender\Real-Time Protection]
"DisableAsyncScanOnOpen"=dword:00000000

; cloud delivered protection
[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows Defender\Spynet]
"SpyNetReporting"=dword:00000002

; automatic sample submission
[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows Defender\Spynet]
"SubmitSamplesConsent"=dword:00000001

; tamper protection
[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows Defender\Features]
"TamperProtection"=dword:00000005

; controlled folder access 
[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows Defender\Windows Defender Exploit Guard\Controlled Folder Access]
"EnableControlledFolderAccess"=dword:00000001

; firewall notifications
[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows Defender Security Center\Notifications]
"DisableEnhancedNotifications"=dword:00000000

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows Defender Security Center\Virus and threat protection]
"NoActionNotificationDisabled"=dword:00000000
"SummaryNotificationDisabled"=dword:00000000
"FilesBlockedNotificationDisabled"=dword:00000000

[HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows Defender Security Center\Account protection]
"DisableNotifications"=dword:00000000
"DisableDynamiclockNotifications"=dword:00000000
"DisableWindowsHelloNotifications"=dword:00000000

[HKEY_LOCAL_MACHINE\System\ControlSet001\Services\SharedAccess\Epoch]
"Epoch"=dword:000004cc

[HKEY_LOCAL_MACHINE\System\ControlSet001\Services\SharedAccess\Parameters\FirewallPolicy\DomainProfile]
"DisableNotifications"=dword:00000000

[HKEY_LOCAL_MACHINE\System\ControlSet001\Services\SharedAccess\Parameters\FirewallPolicy\PublicProfile]
"DisableNotifications"=dword:00000000

[HKEY_LOCAL_MACHINE\System\ControlSet001\Services\SharedAccess\Parameters\FirewallPolicy\StandardProfile]
"DisableNotifications"=dword:00000000

; smart app control (can't turn back on)
; [HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows Defender]
; "VerifiedAndReputableTrustModeEnabled"=dword:00000001
; "SmartLockerMode"=dword:00000001
; "PUAProtection"=dword:00000002

; [HKEY_LOCAL_MACHINE\System\ControlSet001\Control\AppID\Configuration\SMARTLOCKER]
; "START_PENDING"=dword:00000004
; "ENABLED"=hex(b):04,00,00,00,00,00,00,00

; [HKEY_LOCAL_MACHINE\System\ControlSet001\Control\CI\Policy]
; "VerifiedAndReputablePolicyState"=dword:00000001

; check apps and files
[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer]
"SmartScreenEnabled"="Warn"

; smartscreen for microsoft edge
[HKEY_CURRENT_USER\SOFTWARE\Microsoft\Edge\SmartScreenEnabled]
@=dword:00000001

[HKEY_CURRENT_USER\SOFTWARE\Microsoft\Edge\SmartScreenPuaEnabled]
@=dword:00000001

; phishing protection
[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\WTDS\Components]
"CaptureThreatWindow"=dword:00000001
"NotifyMalicious"=dword:00000001
"NotifyPasswordReuse"=dword:00000001
"NotifyUnsafeApp"=dword:00000001
"ServiceEnabled"=dword:00000001

; potentially unwanted app blocking
[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows Defender]
"PUAProtection"=dword:00000001

; smartscreen for microsoft store apps
[HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\AppHost]
"EnableWebContentEvaluation"=dword:00000001

; exploit protection
[HKEY_LOCAL_MACHINE\System\ControlSet001\Control\Session Manager\kernel]
"MitigationOptions"=hex(3):11,11,11,00,00,01,00,00,00,00,00,00,00,00,00,00,\
00,00,00,00,00,00,00,00

; core isolation 
; Red integrity 
[HKEY_LOCAL_MACHINE\System\ControlSet001\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity]
"ChangedInBootCycle"=-
"Enabled"=dword:00000001
"WasEnabledBy"=dword:00000002

; kernel-mode hardware-enforced stack protection
[HKEY_LOCAL_MACHINE\System\ControlSet001\Control\DeviceGuard\Scenarios\KernelShadowStacks]
"ChangedInBootCycle"=-
"Enabled"=dword:00000001
"WasEnabledBy"=dword:00000002

; microsoft vulnerable driver blocklist
[HKEY_LOCAL_MACHINE\System\ControlSet001\Control\CI\Config]
"VulnerableDriverBlocklistEnable"=dword:00000001

; ENABLE DEFENDER SERVICES
; microsoft defender antivirus network inspection service
[HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Services\WdNisSvc]
"Start"=dword:00000003

; microsoft defender antivirus service
[HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Services\WinDefend]
"Start"=dword:00000002

; microsoft defender core service
[HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Services\MDCoreSvc]
"Start"=dword:00000002

; security center
[HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Services\wscsvc]
"Start"=dword:00000002

; web threat defense service
[HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Services\webthreatdefsvc]
"Start"=dword:00000003

; web threat defense user service_XXXXX
[HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Services\webthreatdefusersvc]
"Start"=dword:00000002

; windows defender advanced threat protection service
[HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Services\Sense]
"Start"=dword:00000003

; windows security service
[HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Services\SecurityHealthService]
"Start"=dword:00000002

; ENABLE DEFENDER DRIVERS
; microsoft defender antivirus boot driver
[HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Services\WdBoot]
"Start"=dword:00000000

; microsoft defender antivirus mini-filter driver
[HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Services\WdFilter]
"Start"=dword:00000000

; microsoft defender antivirus network inspection system driver
[HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Services\WdNisDrv]
"Start"=dword:00000003

; ENABLE OTHER
; windows defender firewall
[HKEY_LOCAL_MACHINE\System\ControlSet001\Services\SharedAccess\Parameters\FirewallPolicy\PublicProfile]
"EnableFirewall"=dword:00000001

[HKEY_LOCAL_MACHINE\System\ControlSet001\Services\SharedAccess\Parameters\FirewallPolicy\StandardProfile]
"EnableFirewall"=dword:00000001

; spectre and meltdown
[HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Control\Session Manager\Red Management]
"FeatureSettingsOverrideMask"=-
"FeatureSettingsOverride"=-

; defender context menu handlers
[HKEY_LOCAL_MACHINE\SOFTWARE\Classes\*\shellex\ContextMenuHandlers\EPP]
@="{09A47860-11B0-4DA5-AFA5-26D86198A780}"

[HKEY_LOCAL_MACHINE\SOFTWARE\Classes\Drive\shellex\ContextMenuHandlers\EPP]
@="{09A47860-11B0-4DA5-AFA5-26D86198A780}"

[HKEY_LOCAL_MACHINE\SOFTWARE\Classes\Directory\shellex\ContextMenuHandlers\EPP]
@="{09A47860-11B0-4DA5-AFA5-26D86198A780}"

; enable open file - security warning prompt
; launching applications and unsafe files (not secure) - prompt (recommended)
[HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Internet Settings\Zones\1]
"2707"=-

[HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Internet Settings\Zones\2]
"270B"=-
"2709"=-
"2708"=-
"2704"=-
"2703"=-
"2702"=-
"2701"=-
"2700"=-
"2600"=-
"2402"=-
"2401"=-
"2400"=-
"2302"=-
"2301"=-
"2300"=-
"2201"=-
"2200"=-
"2108"=-
"2107"=-
"2106"=-
"2105"=-
"2104"=-
"2103"=-
"2102"=-
"2101"=-
"2100"=-
"2007"=-
"2005"=-
"2004"=-
"2001"=-
"2000"=-
"1C00"=-
"1A10"=-
"1A06"=-
"1A05"=-
"2500"=-
"270C"=-
"1A02"=-
"1A00"=-
"1812"=-
"1809"=-
"1804"=-
"1803"=-
"1802"=-
"160B"=-
"160A"=-
"1609"=-
"1608"=-
"1607"=-
"1606"=-
"1605"=-
"1604"=-
"1601"=-
"140D"=-
"140C"=-
"140A"=-
"1409"=-
"1408"=-
"1407"=-
"1406"=-
"1405"=-
"1402"=-
"120C"=-
"120B"=-
"120A"=-
"1209"=-
"1208"=-
"1207"=-
"1206"=-
"1201"=-
"1004"=-
"1001"=-
"1A03"=-
"270D"=-
"2707"=-
"1A04"=-

[HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Internet Settings\Zones\3]
"2000"=-
"2707"=-
"2500"=-
"1A00"=-
"1402"=-
"1409"=-
"2105"=-
"2103"=-
"1407"=-
"2101"=-
"1606"=-
"2301"=-
"1809"=-
"1601"=-
"270B"=-
"1607"=-
"1804"=-
"1806"=-
"160A"=-
"2100"=-
"1802"=-
"1A04"=-
"1609"=-
"2104"=-
"2300"=-
"120C"=-
"2102"=-
"1206"=-
"1608"=-
"2708"=-
"2709"=-
"1406"=-
"2600"=-
"1604"=-
"1803"=-
"1405"=-
"270C"=-
"120B"=-
"1201"=-
"1004"=-
"1001"=-
"120A"=-
"2201"=-
"1209"=-
"1208"=-
"2702"=-
"2001"=-
"2004"=-
"2007"=-
"2401"=-
"2400"=-
"2402"=-
"CurrentLevel"=dword:11500

[HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Internet Settings\Zones\4]
"270C"=-
"1A05"=-
"1A04"=-
"1A03"=-
"1A02"=-
"1A00"=-
"1812"=-
"180B"=-
"1809"=-
"1804"=-
"1803"=-
"1802"=-
"160B"=-
"160A"=-
"1609"=-
"1608"=-
"1607"=-
"1606"=-
"1605"=-
"1604"=-
"1601"=-
"140D"=-
"140C"=-
"140A"=-
"1409"=-
"1408"=-
"1407"=-
"1406"=-
"1405"=-
"1402"=-
"120C"=-
"120B"=-
"120A"=-
"1209"=-
"1208"=-
"1207"=-
"1206"=-
"1201"=-
"1004"=-
"1001"=-
"1A10"=-
"1C00"=-
"2000"=-
"2001"=-
"2004"=-
"2005"=-
"2007"=-
"2100"=-
"2101"=-
"2102"=-
"2103"=-
"2104"=-
"2105"=-
"2106"=-
"2107"=-
"2200"=-
"2201"=-
"2300"=-
"2301"=-
"2302"=-
"2400"=-
"2401"=-
"2402"=-
"2600"=-
"2700"=-
"2701"=-
"2702"=-
"2703"=-
"2704"=-
"2708"=-
"2709"=-
"270B"=-
"1A06"=-
"270D"=-
"2707"=-
"2500"=-
"@
    Set-Content -Path "$env:TEMP\SecurityOn.reg" -Value $MultilineComment -Force
    
    # enable scheduled tasks
    schtasks /Change /TN "Microsoft\Windows\ExploitGuard\ExploitGuard MDM policy Refresh" /Enable | Out-Null
    schtasks /Change /TN "Microsoft\Windows\Windows Defender\Windows Defender Cache Maintenance" /Enable | Out-Null
    schtasks /Change /TN "Microsoft\Windows\Windows Defender\Windows Defender Cleanup" /Enable | Out-Null
    schtasks /Change /TN "Microsoft\Windows\Windows Defender\Windows Defender Scheduled Scan" /Enable | Out-Null
    schtasks /Change /TN "Microsoft\Windows\Windows Defender\Windows Defender Verification" /Enable | Out-Null

    # import reg file
    Regedit.exe /S "$env:TEMP\SecurityOn.reg"
    Timeout /T 5 | Out-Null
    # import reg file RunAsTI
    $SecurityOn = @'
Regedit.exe /S "$env:TEMP\SecurityOn.reg"
'@
    RunAsTI powershell "-nologo -windowstyle hidden -command $SecurityOn"
    Timeout /T 5 | Out-Null
    # move smartscreen
    $SmartScreen = @'
cmd.exe /c move /y "C:\Windows\smartscreen.exe" "C:\Windows\System32\smartscreen.exe"
'@
    RunAsTI powershell "-nologo -windowstyle hidden -command $SmartScreen"
    Timeout /T 5 | Out-Null
    # Enable windows-defender-default-definitions & applicationguard
    $Defender = @"
    Dism /Online /NoRestart /Enable-Feature /FeatureName:Windows-Defender-Default-Definitions | Out-Null
    Dism /Online /NoRestart /Enable-Feature /FeatureName:Windows-Defender-ApplicationGuard | Out-Null
"@
    # Execute the commands using RunAsTI
    RunAsTI powershell "-nologo -windowstyle hidden -command { $Defender }"
    # Enable data execution prevention
    cmd /c "bcdedit /deletevalue nx >nul 2>&1"
    # Delete Reg file
    Remove-Item -Path "$env:TEMP\SecurityOn.reg" -Force -ErrorAction SilentlyContinue
    Write-Status "Windows Security Suite Enabled." -TargetScreen OptimizeScreen
    # Show a single message box with "Yes" and "No" options
    $response = Show-MessageBox -Message "Windows Security Suite Enabled.`nA restart is required to apply changes.`nRestart Now?" -Title "Restart Required" -Buttons "YesNo" -Icon "Warning"

    # Check the user's response
    if ($response -eq [System.Windows.Forms.DialogResult]::Yes) {
        # Restart the system immediately
        shutdown -r -t 00
    }
    # If "No" is selected, the message box will close
}

# Function to Disable Windows Security Suite entirely
function Disable-WindowsSecuritySuite {
    # Initial warning
    $initialWarning = @"
This will disable critical Windows security components including:
- Real-time protection
- Cloud-delivered protection
- Firewall
- SmartScreen
- Anti-malware services
- Exploit protections

THIS WILL LEAVE YOUR SYSTEM VULNERABLE TO ATTACKS!

Do you want to continue?
"@

    $confirm = Show-MessageBox -Message $initialWarning -Title "Security Warning" -Buttons "YesNo" -Icon "Warning"
    if ($confirm -eq "No") { return }

    # Additional warning
    $additionalWarning = @"
Are you SURE you know what you're doing?
"@

    $finalConfirm = Show-MessageBox -Message $additionalWarning -Title "Final Confirmation" -Buttons "YesNo" -Icon "Warning"
    if ($finalConfirm -eq "No") { return }

    Write-Status "Disabling Windows Security Suite. Please Wait . . ." -TargetScreen OptimizeScreen
    # disable exploit protection, leaving control flow guard cfg on for vanguard anticheat
    cmd /c "reg add `"HKLM\SYSTEM\ControlSet001\Control\Session Manager\kernel`" /v `"MitigationOptions`" /t REG_BINARY /d `"222222000001000000000000000000000000000000000000`" /f >nul 2>&1"
    Timeout /T 2 | Out-Null
    # define reg file
    $MultilineComment = @"
Windows Registry Editor Version 5.00

; DISABLE WINDOWS SECURITY SETTINGS
; real time protection
[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows Defender\Real-Time Protection]
"DisableRealtimeMonitoring"=dword:00000001

; dev drive protection
[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows Defender\Real-Time Protection]
"DisableAsyncScanOnOpen"=dword:00000001

; cloud delivered protection
[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows Defender\Spynet]
"SpyNetReporting"=dword:00000000

; automatic sample submission
[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows Defender\Spynet]
"SubmitSamplesConsent"=dword:00000000

; tamper protection
[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows Defender\Features]
"TamperProtection"=dword:00000004

; controlled folder access 
[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows Defender\Windows Defender Exploit Guard\Controlled Folder Access]
"EnableControlledFolderAccess"=dword:00000000

; firewall notifications
[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows Defender Security Center\Notifications]
"DisableEnhancedNotifications"=dword:00000001

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows Defender Security Center\Virus and threat protection]
"NoActionNotificationDisabled"=dword:00000001
"SummaryNotificationDisabled"=dword:00000001
"FilesBlockedNotificationDisabled"=dword:00000001

[HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows Defender Security Center\Account protection]
"DisableNotifications"=dword:00000001
"DisableDynamiclockNotifications"=dword:00000001
"DisableWindowsHelloNotifications"=dword:00000001

[HKEY_LOCAL_MACHINE\System\ControlSet001\Services\SharedAccess\Epoch]
"Epoch"=dword:000004cf

[HKEY_LOCAL_MACHINE\System\ControlSet001\Services\SharedAccess\Parameters\FirewallPolicy\DomainProfile]
"DisableNotifications"=dword:00000001

[HKEY_LOCAL_MACHINE\System\ControlSet001\Services\SharedAccess\Parameters\FirewallPolicy\PublicProfile]
"DisableNotifications"=dword:00000001

[HKEY_LOCAL_MACHINE\System\ControlSet001\Services\SharedAccess\Parameters\FirewallPolicy\StandardProfile]
"DisableNotifications"=dword:00000001

; smart app control
[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows Defender]
"VerifiedAndReputableTrustModeEnabled"=dword:00000000
"SmartLockerMode"=dword:00000000
"PUAProtection"=dword:00000000

[HKEY_LOCAL_MACHINE\System\ControlSet001\Control\AppID\Configuration\SMARTLOCKER]
"START_PENDING"=dword:00000000
"ENABLED"=hex(b):00,00,00,00,00,00,00,00

[HKEY_LOCAL_MACHINE\System\ControlSet001\Control\CI\Policy]
"VerifiedAndReputablePolicyState"=dword:00000000

; check apps and files
[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer]
"SmartScreenEnabled"="Off"

; smartscreen for microsoft edge
[HKEY_CURRENT_USER\SOFTWARE\Microsoft\Edge\SmartScreenEnabled]
@=dword:00000000

[HKEY_CURRENT_USER\SOFTWARE\Microsoft\Edge\SmartScreenPuaEnabled]
@=dword:00000000

; phishing protection
[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\WTDS\Components]
"CaptureThreatWindow"=dword:00000000
"NotifyMalicious"=dword:00000000
"NotifyPasswordReuse"=dword:00000000
"NotifyUnsafeApp"=dword:00000000
"ServiceEnabled"=dword:00000000

; potentially unwanted app blocking
[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows Defender]
"PUAProtection"=dword:00000000

; smartscreen for microsoft store apps
[HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\AppHost]
"EnableWebContentEvaluation"=dword:00000000

; exploit protection, leaving control flow guard cfg on for vanguard anticheat
[HKEY_LOCAL_MACHINE\System\ControlSet001\Control\Session Manager\kernel]
"MitigationOptions"=hex:22,22,22,00,00,01,00,00,00,00,00,00,00,00,00,00,\
00,00,00,00,00,00,00,00

; core isolation 
; Red integrity 
[HKEY_LOCAL_MACHINE\System\ControlSet001\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity]
"ChangedInBootCycle"=-
"Enabled"=dword:00000000
"WasEnabledBy"=-

; kernel-mode hardware-enforced stack protection
[HKEY_LOCAL_MACHINE\System\ControlSet001\Control\DeviceGuard\Scenarios\KernelShadowStacks]
"ChangedInBootCycle"=-
"Enabled"=dword:00000000
"WasEnabledBy"=-

; microsoft vulnerable driver blocklist
[HKEY_LOCAL_MACHINE\System\ControlSet001\Control\CI\Config]
"VulnerableDriverBlocklistEnable"=dword:00000000

; DISABLE DEFENDER SERVICES
; microsoft defender antivirus network inspection service
[HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Services\WdNisSvc]
"Start"=dword:00000004

; microsoft defender antivirus service
[HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Services\WinDefend]
"Start"=dword:00000004

; microsoft defender core service
[HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Services\MDCoreSvc]
"Start"=dword:00000004

; security center
[HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Services\wscsvc]
"Start"=dword:00000004

; web threat defense service
[HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Services\webthreatdefsvc]
"Start"=dword:00000004

; web threat defense user service_XXXXX
[HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Services\webthreatdefusersvc]
"Start"=dword:00000004

; windows defender advanced threat protection service
[HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Services\Sense]
"Start"=dword:00000004

; windows security service
[HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Services\SecurityHealthService]
"Start"=dword:00000004

; DISABLE DEFENDER DRIVERS
; microsoft defender antivirus boot driver
[HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Services\WdBoot]
"Start"=dword:00000004

; microsoft defender antivirus mini-filter driver
[HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Services\WdFilter]
"Start"=dword:00000004

; microsoft defender antivirus network inspection system driver
[HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Services\WdNisDrv]
"Start"=dword:00000004

; DISABLE OTHER
; windows defender firewall
[HKEY_LOCAL_MACHINE\System\ControlSet001\Services\SharedAccess\Parameters\FirewallPolicy\PublicProfile]
"EnableFirewall"=dword:00000000

[HKEY_LOCAL_MACHINE\System\ControlSet001\Services\SharedAccess\Parameters\FirewallPolicy\StandardProfile]
"EnableFirewall"=dword:00000000

; spectre and meltdown
[HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Control\Session Manager\Red Management]
"FeatureSettingsOverrideMask"=dword:00000003
"FeatureSettingsOverride"=dword:00000003

; defender context menu handlers
[-HKEY_LOCAL_MACHINE\SOFTWARE\Classes\*\shellex\ContextMenuHandlers\EPP]


[-HKEY_LOCAL_MACHINE\SOFTWARE\Classes\Drive\shellex\ContextMenuHandlers\EPP]


[-HKEY_LOCAL_MACHINE\SOFTWARE\Classes\Directory\shellex\ContextMenuHandlers\EPP]

; disable open file - security warning prompt
; launching applications and unsafe files (not secure) - enable (not secure)
[HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Internet Settings\Zones\1]
"2707"=dword:00000000

[HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Internet Settings\Zones\2]
"270B"=dword:00000000
"2709"=dword:00000003
"2708"=dword:00000003
"2704"=dword:00000000
"2703"=dword:00000000
"2702"=dword:00000000
"2701"=dword:00000000
"2700"=dword:00000003
"2600"=dword:00000000
"2402"=dword:00000000
"2401"=dword:00000000
"2400"=dword:00000000
"2302"=dword:00000003
"2301"=dword:00000000
"2300"=dword:00000001
"2201"=dword:00000003
"2200"=dword:00000003
"2108"=dword:00000003
"2107"=dword:00000000
"2106"=dword:00000000
"2105"=dword:00000000
"2104"=dword:00000000
"2103"=dword:00000000
"2102"=dword:00000003
"2101"=dword:00000000
"2100"=dword:00000000
"2007"=dword:00010000
"2005"=dword:00000000
"2004"=dword:00000000
"2001"=dword:00000000
"2000"=dword:00000000
"1C00"=dword:00010000
"1A10"=dword:00000001
"1A06"=dword:00000000
"1A05"=dword:00000001
"2500"=dword:00000003
"270C"=dword:00000003
"1A02"=dword:00000000
"1A00"=dword:00020000
"1812"=dword:00000000
"1809"=dword:00000000
"1804"=dword:00000001
"1803"=dword:00000000
"1802"=dword:00000000
"160B"=dword:00000000
"160A"=dword:00000000
"1609"=dword:00000001
"1608"=dword:00000000
"1607"=dword:00000003
"1606"=dword:00000000
"1605"=dword:00000000
"1604"=dword:00000000
"1601"=dword:00000000
"140D"=dword:00000000
"140C"=dword:00000000
"140A"=dword:00000000
"1409"=dword:00000000
"1408"=dword:00000000
"1407"=dword:00000001
"1406"=dword:00000003
"1405"=dword:00000000
"1402"=dword:00000000
"120C"=dword:00000000
"120B"=dword:00000000
"120A"=dword:00000003
"1209"=dword:00000003
"1208"=dword:00000000
"1207"=dword:00000000
"1206"=dword:00000003
"1201"=dword:00000003
"1004"=dword:00000003
"1001"=dword:00000001
"1A03"=dword:00000000
"270D"=dword:00000000
"2707"=dword:00000000
"1A04"=dword:00000003

[HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Internet Settings\Zones\3]
"2000"=dword:00000000
"2707"=dword:00000000
"2500"=dword:00000000
"1A00"=dword:00020000
"1402"=dword:00000000
"1409"=dword:00000000
"2105"=dword:00000003
"2103"=dword:00000003
"1407"=dword:00000001
"2101"=dword:00000000
"1606"=dword:00000000
"2301"=dword:00000000
"1809"=dword:00000000
"1601"=dword:00000000
"270B"=dword:00000003
"1607"=dword:00000003
"1804"=dword:00000001
"1806"=dword:00000000
"160A"=dword:00000003
"2100"=dword:00000000
"1802"=dword:00000000
"1A04"=dword:00000003
"1609"=dword:00000001
"2104"=dword:00000003
"2300"=dword:00000001
"120C"=dword:00000003
"2102"=dword:00000003
"1206"=dword:00000003
"1608"=dword:00000000
"2708"=dword:00000003
"2709"=dword:00000003
"1406"=dword:00000003
"2600"=dword:00000000
"1604"=dword:00000000
"1803"=dword:00000000
"1405"=dword:00000000
"270C"=dword:00000000
"120B"=dword:00000003
"1201"=dword:00000003
"1004"=dword:00000003
"1001"=dword:00000001
"120A"=dword:00000003
"2201"=dword:00000003
"1209"=dword:00000003
"1208"=dword:00000003
"2702"=dword:00000000
"2001"=dword:00000003
"2004"=dword:00000003
"2007"=dword:00010000
"2401"=dword:00000000
"2400"=dword:00000003
"2402"=dword:00000003
"CurrentLevel"=dword:00000000

[HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Internet Settings\Zones\4]
"270C"=dword:00000000
"1A05"=dword:00000003
"1A04"=dword:00000003
"1A03"=dword:00000003
"1A02"=dword:00000003
"1A00"=dword:00010000
"1812"=dword:00000001
"180B"=dword:00000001
"1809"=dword:00000000
"1804"=dword:00000003
"1803"=dword:00000003
"1802"=dword:00000001
"160B"=dword:00000000
"160A"=dword:00000003
"1609"=dword:00000001
"1608"=dword:00000003
"1607"=dword:00000003
"1606"=dword:00000003
"1605"=dword:00000000
"1604"=dword:00000003
"1601"=dword:00000001
"140D"=dword:00000000
"140C"=dword:00000003
"140A"=dword:00000000
"1409"=dword:00000000
"1408"=dword:00000003
"1407"=dword:00000003
"1406"=dword:00000003
"1405"=dword:00000003
"1402"=dword:00000003
"120C"=dword:00000003
"120B"=dword:00000003
"120A"=dword:00000003
"1209"=dword:00000003
"1208"=dword:00000003
"1207"=dword:00000003
"1206"=dword:00000003
"1201"=dword:00000003
"1004"=dword:00000003
"1001"=dword:00000003
"1A10"=dword:00000003
"1C00"=dword:00000000
"2000"=dword:00000003
"2001"=dword:00000003
"2004"=dword:00000003
"2005"=dword:00000003
"2007"=dword:00000003
"2100"=dword:00000003
"2101"=dword:00000003
"2102"=dword:00000003
"2103"=dword:00000003
"2104"=dword:00000003
"2105"=dword:00000003
"2106"=dword:00000003
"2107"=dword:00000003
"2200"=dword:00000003
"2201"=dword:00000003
"2300"=dword:00000003
"2301"=dword:00000000
"2302"=dword:00000003
"2400"=dword:00000003
"2401"=dword:00000003
"2402"=dword:00000003
"2600"=dword:00000003
"2700"=dword:00000000
"2701"=dword:00000003
"2702"=dword:00000000
"2703"=dword:00000003
"2704"=dword:00000003
"2708"=dword:00000003
"2709"=dword:00000003
"270B"=dword:00000003
"1A06"=dword:00000003
"270D"=dword:00000003
"2707"=dword:00000000
"2500"=dword:00000000
"@
    Set-Content -Path "$env:TEMP\SecurityOff.reg" -Value $MultilineComment -Force
    # disable scheduled tasks
    schtasks /Change /TN "Microsoft\Windows\ExploitGuard\ExploitGuard MDM policy Refresh" /Disable | Out-Null
    schtasks /Change /TN "Microsoft\Windows\Windows Defender\Windows Defender Cache Maintenance" /Disable | Out-Null
    schtasks /Change /TN "Microsoft\Windows\Windows Defender\Windows Defender Cleanup" /Disable | Out-Null
    schtasks /Change /TN "Microsoft\Windows\Windows Defender\Windows Defender Scheduled Scan" /Disable | Out-Null
    schtasks /Change /TN "Microsoft\Windows\Windows Defender\Windows Defender Verification" /Disable | Out-Null
    # import reg file
    Regedit.exe /S "$env:TEMP\SecurityOff.reg"
    Timeout /T 5 | Out-Null
    # import reg file RunAsTI
    $SecurityOff = @'
Regedit.exe /S "$env:TEMP\SecurityOff.reg"
'@
    RunAsTI powershell "-nologo -windowstyle hidden -command $SecurityOff"
    Timeout /T 5 | Out-Null
    # stop smartscreen running
    Stop-Process -Force -Name smartscreen -ErrorAction SilentlyContinue | Out-Null
    # move smartscreen
    $SmartScreen = @'
cmd.exe /c move /y "C:\Windows\System32\smartscreen.exe" "C:\Windows\smartscreen.exe"
'@
    RunAsTI powershell "-nologo -windowstyle hidden -command $SmartScreen"
    Timeout /T 5 | Out-Null
    # Disable windows-defender-default-definitions & applicationguard
    $Defender = @"
    Dism /Online /NoRestart /Disable-Feature /FeatureName:Windows-Defender-Default-Definitions | Out-Null
    Dism /Online /NoRestart /Disable-Feature /FeatureName:Windows-Defender-ApplicationGuard | Out-Null
"@
    # Execute the commands using RunAsTI
    RunAsTI powershell "-nologo -windowstyle hidden -command { $Defender }"
    # disable data execution prevention
    cmd /c "bcdedit /set nx AlwaysOff >nul 2>&1"
    # Delete Reg file
    Remove-Item -Path "$env:TEMP\SecurityOff.reg" -Force -ErrorAction SilentlyContinue
    # Show a single message box with "Yes" and "No" options
    Write-Status "Windows Security Suite Disabled." -TargetScreen OptimizeScreen
    $response = Show-MessageBox -Message "Windows Security Suite Disabled.`nA restart is required to apply changes.`nRestart Now?" -Title "Restart Required" -Buttons "YesNo" -Icon "Warning"

    # Check the user's response
    if ($response -eq [System.Windows.Forms.DialogResult]::Yes) {
        # Restart the system immediately
        shutdown -r -t 00
    }
    # If "No" is selected, the message box will close
}

# =================================
# Other Optimizations
# =================================
# Function to set Recommended Power Settings
# Source Script: https://raw.githubusercontent.com/FR33THYFR33THY/Ultimate-Windows-Optimization-Guide/refs/heads/main/6%20Windows/9%20Power%20Plan.ps1
function Set-RecommendedPowerSettings {
    Write-Log "Importing ultimate power plan" -Severity 'INFO'
    cmd /c "powercfg /duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 99999999-9999-9999-9999-999999999999 >nul 2>&1"

    Write-Log "Setting ultimate power plan as active" -Severity 'INFO'
    cmd /c "powercfg /SETACTIVE 99999999-9999-9999-9999-999999999999 >nul 2>&1"

    Write-Log "Retrieving list of power plans" -Severity 'INFO'
    $output = powercfg /L
    $powerPlans = @()
    foreach ($line in $output) {
        Write-Log "Extracting power plan GUID" -Severity 'INFO'
        if ($line -match ':') {
            $parse = $line -split ':'
            $index = $parse[1].Trim().indexof('(')
            $guid = $parse[1].Trim().Substring(0, $index)
            $powerPlans += $guid
        }
    }

    Write-Log "Removing existing power plans" -Severity 'INFO'
    foreach ($plan in $powerPlans) {
        if ($plan -ne "99999999-9999-9999-9999-999999999999") {
            Write-Log "Deleting power plan: $plan" -Severity 'INFO'
            powercfg /delete $plan 2>&1 | Out-Null
        }
    }
    Write-Log "Disabling hibernate" -Severity 'INFO'
    powercfg /hibernate off
    cmd /c "reg add `"HKLM\SYSTEM\CurrentControlSet\Control\Power`" /v `"HibernateEnabled`" /t REG_DWORD /d `"0`" /f >nul 2>&1"
    cmd /c "reg add `"HKLM\SYSTEM\CurrentControlSet\Control\Power`" /v `"HibernateEnabledDefault`" /t REG_DWORD /d `"0`" /f >nul 2>&1"

    Write-Log "Optimizing battery video quality settings" -Severity 'INFO'
    cmd /c "reg add `"HKCU\Software\Microsoft\Windows\CurrentVersion\VideoSettings`" /v VideoQualityOnBattery /t REG_DWORD /d 1 /f >nul 2>&1"

    Write-Log "Disabling lock option in power menu" -Severity 'INFO' 
    cmd /c "reg add `"HKLM\Software\Microsoft\Windows\CurrentVersion\Explorer\FlyoutMenuSettings`" /v `"ShowLockOption`" /t REG_DWORD /d `"0`" /f >nul 2>&1"

    Write-Log "Disabling fast boot" -Severity 'INFO'
    cmd /c "reg add `"HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Power`" /v `"HiberbootEnabled`" /t REG_DWORD /d `"0`" /f >nul 2>&1"

    Write-Log "Unparking CPU cores" -Severity 'INFO'
    cmd /c "reg add `"HKLM\SYSTEM\ControlSet001\Control\Power\PowerSettings\54533251-82be-4824-96c1-47b60b740d00\0cc5b647-c1df-4637-891a-dec35c318583`" /v `"ValueMax`" /t REG_DWORD /d `"0`" /f >nul 2>&1"

    Write-Log "Disabling power throttling" -Severity 'INFO'
    cmd /c "reg add `"HKLM\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling`" /v `"PowerThrottlingOff`" /t REG_DWORD /d `"1`" /f >nul 2>&1"

    Write-Log "Unhiding hub selective suspend timeout setting" -Severity 'INFO'
    cmd /c "reg add `"HKLM\System\ControlSet001\Control\Power\PowerSettings\2a737441-1930-4402-8d77-b2bebba308a3\0853a681-27c8-4100-a2fd-82013e970683`" /v `"Attributes`" /t REG_DWORD /d `"2`" /f >nul 2>&1"

    Write-Log "Unhiding USB 3 link power management setting" -Severity 'INFO'
    cmd /c "reg add `"HKLM\System\ControlSet001\Control\Power\PowerSettings\2a737441-1930-4402-8d77-b2bebba308a3\d4e98f31-5ffe-4ce1-be31-1b38b384c009`" /v `"Attributes`" /t REG_DWORD /d `"2`" /f >nul 2>&1"
    Write-Log "Setting up desktop and laptop power management configurations" -Severity 'INFO'

    Write-Log "Setting hard disk to never turn off automatically" -Severity 'INFO'
    powercfg /setacvalueindex 99999999-9999-9999-9999-999999999999 0012ee47-9041-4b5d-9b77-535fba8b1442 6738e2c4-e8a5-4a42-b16a-e040e769756e 0x00000000 *> $null
    powercfg /setdcvalueindex 99999999-9999-9999-9999-999999999999 0012ee47-9041-4b5d-9b77-535fba8b1442 6738e2c4-e8a5-4a42-b16a-e040e769756e 0x00000000 *> $null

    Write-Log "Pausing desktop background slideshow to conserve resources" -Severity 'INFO'
    powercfg /setacvalueindex 99999999-9999-9999-9999-999999999999 0d7dbae2-4294-402a-ba8e-26777e8488cd 309dce9b-bef4-4119-9921-a851fb12f0f4 001 *> $null
    powercfg /setdcvalueindex 99999999-9999-9999-9999-999999999999 0d7dbae2-4294-402a-ba8e-26777e8488cd 309dce9b-bef4-4119-9921-a851fb12f0f4 001 *> $null

    Write-Log "Setting wireless adapter to maximum performance mode" -Severity 'INFO'
    powercfg /setacvalueindex 99999999-9999-9999-9999-999999999999 19cbb8fa-5279-450e-9fac-8a3d5fedd0c1 12bbebe6-58d6-4636-95bb-3217ef867c1a 000 *> $null
    powercfg /setdcvalueindex 99999999-9999-9999-9999-999999999999 19cbb8fa-5279-450e-9fac-8a3d5fedd0c1 12bbebe6-58d6-4636-95bb-3217ef867c1a 000 *> $null

    Write-Log "Adjusting sleep settings for performance" -Severity 'INFO'

    Write-Log "Disabling automatic sleep mode" -Severity 'INFO'
    powercfg /setacvalueindex 99999999-9999-9999-9999-999999999999 238c9fa8-0aad-41ed-83f4-97be242c8f20 29f6c1db-86da-48c5-9fdb-f2b67b1f44da 0x00000000 *> $null
    powercfg /setdcvalueindex 99999999-9999-9999-9999-999999999999 238c9fa8-0aad-41ed-83f4-97be242c8f20 29f6c1db-86da-48c5-9fdb-f2b67b1f44da 0x00000000 *> $null

    Write-Log "Turning off hybrid sleep for improved wake-up time" -Severity 'INFO'
    powercfg /setacvalueindex 99999999-9999-9999-9999-999999999999 238c9fa8-0aad-41ed-83f4-97be242c8f20 94ac6d29-73ce-41a6-809f-6363ba21b47e 000 *> $null
    powercfg /setdcvalueindex 99999999-9999-9999-9999-999999999999 238c9fa8-0aad-41ed-83f4-97be242c8f20 94ac6d29-73ce-41a6-809f-6363ba21b47e 000 *> $null

    Write-Log "Disabling automatic hibernation" -Severity 'INFO'
    powercfg /setacvalueindex 99999999-9999-9999-9999-999999999999 238c9fa8-0aad-41ed-83f4-97be242c8f20 9d7815a6-7ee4-497e-8888-515a05f02364 0x00000000 *> $null
    powercfg /setdcvalueindex 99999999-9999-9999-9999-999999999999 238c9fa8-0aad-41ed-83f4-97be242c8f20 9d7815a6-7ee4-497e-8888-515a05f02364 0x00000000 *> $null
    Write-Log "Disabling wake timers to prevent unwanted system wake-ups" -Severity 'INFO'
    powercfg /setacvalueindex 99999999-9999-9999-9999-999999999999 238c9fa8-0aad-41ed-83f4-97be242c8f20 bd3b718a-0680-4d9d-8ab2-e1d2b4ac806d 000 *> $null
    powercfg /setdcvalueindex 99999999-9999-9999-9999-999999999999 238c9fa8-0aad-41ed-83f4-97be242c8f20 bd3b718a-0680-4d9d-8ab2-e1d2b4ac806d 000 *> $null

    Write-Log "Optimizing USB power settings" -Severity 'INFO'

    Write-Log "Setting USB hub selective suspend timeout to immediate" -Severity 'INFO'
    powercfg /setacvalueindex 99999999-9999-9999-9999-999999999999 2a737441-1930-4402-8d77-b2bebba308a3 0853a681-27c8-4100-a2fd-82013e970683 0x00000000 *> $null
    powercfg /setdcvalueindex 99999999-9999-9999-9999-999999999999 2a737441-1930-4402-8d77-b2bebba308a3 0853a681-27c8-4100-a2fd-82013e970683 0x00000000 *> $null

    Write-Log "Disabling USB selective suspend for improved device responsiveness" -Severity 'INFO'
    powercfg /setacvalueindex 99999999-9999-9999-9999-999999999999 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 000 *> $null
    powercfg /setdcvalueindex 99999999-9999-9999-9999-999999999999 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 000 *> $null

    Write-Log "Turning off USB 3.0 link power management for maximum performance" -Severity 'INFO'
    powercfg /setacvalueindex 99999999-9999-9999-9999-999999999999 2a737441-1930-4402-8d77-b2bebba308a3 d4e98f31-5ffe-4ce1-be31-1b38b384c009 000 *> $null
    powercfg /setdcvalueindex 99999999-9999-9999-9999-999999999999 2a737441-1930-4402-8d77-b2bebba308a3 d4e98f31-5ffe-4ce1-be31-1b38b384c009 000 *> $null

    Write-Log "Setting power button action to shutdown in Start menu" -Severity 'INFO'
    powercfg /setacvalueindex 99999999-9999-9999-9999-999999999999 4f971e89-eebd-4455-a8de-9e59040e7347 a7066653-8d6c-40a8-910e-a1f54b84c7e5 002 *> $null
    powercfg /setdcvalueindex 99999999-9999-9999-9999-999999999999 4f971e89-eebd-4455-a8de-9e59040e7347 a7066653-8d6c-40a8-910e-a1f54b84c7e5 002 *> $null
    Write-Log "Disabling PCI Express link state power management for improved performance" -Severity 'INFO'
    powercfg /setacvalueindex 99999999-9999-9999-9999-999999999999 501a4d13-42af-4429-9fd1-a8218c268e20 ee12f906-d277-404b-b6da-e5fa1a576df5 000 *> $null
    powercfg /setdcvalueindex 99999999-9999-9999-9999-999999999999 501a4d13-42af-4429-9fd1-a8218c268e20 ee12f906-d277-404b-b6da-e5fa1a576df5 000 *> $null

    Write-Log "Optimizing processor power management settings" -Severity 'INFO'

    Write-Log "Setting minimum processor state to 100% for maximum performance" -Severity 'INFO'
    powercfg /setacvalueindex 99999999-9999-9999-9999-999999999999 54533251-82be-4824-96c1-47b60b740d00 893dee8e-2bef-41e0-89c6-b55d0929964c 0x00000064 *> $null
    powercfg /setdcvalueindex 99999999-9999-9999-9999-999999999999 54533251-82be-4824-96c1-47b60b740d00 893dee8e-2bef-41e0-89c6-b55d0929964c 0x00000064 *> $null

    Write-Log "Setting system cooling policy to active for better thermal management" -Severity 'INFO'
    powercfg /setacvalueindex 99999999-9999-9999-9999-999999999999 54533251-82be-4824-96c1-47b60b740d00 94d3a615-a899-4ac5-ae2b-e4d8f634367f 001 *> $null
    powercfg /setdcvalueindex 99999999-9999-9999-9999-999999999999 54533251-82be-4824-96c1-47b60b740d00 94d3a615-a899-4ac5-ae2b-e4d8f634367f 001 *> $null

    Write-Log "Setting maximum processor state to 100% for full CPU utilization" -Severity 'INFO'
    powercfg /setacvalueindex 99999999-9999-9999-9999-999999999999 54533251-82be-4824-96c1-47b60b740d00 bc5038f7-23e0-4960-96da-33abaf5935ec 0x00000064 *> $null
    powercfg /setdcvalueindex 99999999-9999-9999-9999-999999999999 54533251-82be-4824-96c1-47b60b740d00 bc5038f7-23e0-4960-96da-33abaf5935ec 0x00000064 *> $null

    Write-Log "Configuring display power settings" -Severity 'INFO'

    Write-Log "Disabling automatic display turn off" -Severity 'INFO'
    powercfg /setacvalueindex 99999999-9999-9999-9999-999999999999 7516b95f-f776-4464-8c53-06167f40cc99 3c0bc021-c8a8-4e07-a973-6b14cbcb2b7e 0x00000000 *> $null
    powercfg /setdcvalueindex 99999999-9999-9999-9999-999999999999 7516b95f-f776-4464-8c53-06167f40cc99 3c0bc021-c8a8-4e07-a973-6b14cbcb2b7e 0x00000000 *> $null
    Write-Log "Setting display brightness to 100% for optimal visibility" -Severity 'INFO'
    powercfg /setacvalueindex 99999999-9999-9999-9999-999999999999 7516b95f-f776-4464-8c53-06167f40cc99 aded5e82-b909-4619-9949-f5d71dac0bcb 0x00000064 *> $null
    powercfg /setdcvalueindex 99999999-9999-9999-9999-999999999999 7516b95f-f776-4464-8c53-06167f40cc99 aded5e82-b909-4619-9949-f5d71dac0bcb 0x00000064 *> $null

    Write-Log "Setting dimmed display brightness to 100% to maintain visibility when dimmed" -Severity 'INFO'
    powercfg /setacvalueindex 99999999-9999-9999-9999-999999999999 7516b95f-f776-4464-8c53-06167f40cc99 f1fbfde2-a960-4165-9f88-50667911ce96 0x00000064 *> $null
    powercfg /setdcvalueindex 99999999-9999-9999-9999-999999999999 7516b95f-f776-4464-8c53-06167f40cc99 f1fbfde2-a960-4165-9f88-50667911ce96 0x00000064 *> $null

    Write-Log "Disabling adaptive brightness for consistent display brightness" -Severity 'INFO'
    powercfg /setacvalueindex 99999999-9999-9999-9999-999999999999 7516b95f-f776-4464-8c53-06167f40cc99 fbd9aa66-9553-4097-ba44-ed6e9d65eab8 000 *> $null
    powercfg /setdcvalueindex 99999999-9999-9999-9999-999999999999 7516b95f-f776-4464-8c53-06167f40cc99 fbd9aa66-9553-4097-ba44-ed6e9d65eab8 000 *> $null

    Write-Log "Setting video playback bias to performance mode" -Severity 'INFO'
    powercfg /setacvalueindex 99999999-9999-9999-9999-999999999999 9596fb26-9850-41fd-ac3e-f7c3c00afd4b 10778347-1370-4ee0-8bbd-33bdacaade49 001 *> $null
    powercfg /setdcvalueindex 99999999-9999-9999-9999-999999999999 9596fb26-9850-41fd-ac3e-f7c3c00afd4b 10778347-1370-4ee0-8bbd-33bdacaade49 001 *> $null

    Write-Log "Optimizing video playback for maximum quality" -Severity 'INFO'
    powercfg /setacvalueindex 99999999-9999-9999-9999-999999999999 9596fb26-9850-41fd-ac3e-f7c3c00afd4b 34c7b99f-9a6d-4b3c-8dc7-b6693b78cef4 000 *> $null
    powercfg /setdcvalueindex 99999999-9999-9999-9999-999999999999 9596fb26-9850-41fd-ac3e-f7c3c00afd4b 34c7b99f-9a6d-4b3c-8dc7-b6693b78cef4 000 *> $null
    Write-Log "Configuring laptop-specific power settings" -Severity 'INFO'

    Write-Log "Setting Intel Graphics to maximum performance power plan" -Severity 'INFO'
    powercfg /setacvalueindex 99999999-9999-9999-9999-999999999999 44f3beca-a7c0-460e-9df2-bb8b99e0cba6 3619c3f2-afb2-4afc-b0e9-e7fef372de36 002 *> $null
    powercfg /setdcvalueindex 99999999-9999-9999-9999-999999999999 44f3beca-a7c0-460e-9df2-bb8b99e0cba6 3619c3f2-afb2-4afc-b0e9-e7fef372de36 002 *> $null

    Write-Log "Setting AMD power slider to best performance mode" -Severity 'INFO'
    powercfg /setacvalueindex 99999999-9999-9999-9999-999999999999 c763b4ec-0e50-4b6b-9bed-2b92a6ee884e 7ec1751b-60ed-4588-afb5-9819d3d77d90 003 *> $null
    powercfg /setdcvalueindex 99999999-9999-9999-9999-999999999999 c763b4ec-0e50-4b6b-9bed-2b92a6ee884e 7ec1751b-60ed-4588-afb5-9819d3d77d90 003 *> $null

    Write-Log "Maximizing ATI PowerPlay settings for best performance" -Severity 'INFO'
    powercfg /setacvalueindex 99999999-9999-9999-9999-999999999999 f693fb01-e858-4f00-b20f-f30e12ac06d6 191f65b5-d45c-4a4f-8aae-1ab8bfd980e6 001 *> $null
    powercfg /setdcvalueindex 99999999-9999-9999-9999-999999999999 f693fb01-e858-4f00-b20f-f30e12ac06d6 191f65b5-d45c-4a4f-8aae-1ab8bfd980e6 001 *> $null

    Write-Log "Setting switchable graphics to maximize performance globally" -Severity 'INFO'
    powercfg /setacvalueindex 99999999-9999-9999-9999-999999999999 e276e160-7cb0-43c6-b20b-73f5dce39954 a1662ab2-9d34-4e53-ba8b-2639b9e20857 003 *> $null
    powercfg /setdcvalueindex 99999999-9999-9999-9999-999999999999 e276e160-7cb0-43c6-b20b-73f5dce39954 a1662ab2-9d34-4e53-ba8b-2639b9e20857 003 *> $null

    Write-Log "Configuring battery settings" -Severity 'INFO'

    Write-Log "Disabling critical battery notifications" -Severity 'INFO'
    powercfg /setacvalueindex 99999999-9999-9999-9999-999999999999 e73a048d-bf27-4f12-9731-8b2076e8891f 5dbb7c9f-38e9-40d2-9749-4f8a0e9f640f 000 *> $null
    powercfg /setdcvalueindex 99999999-9999-9999-9999-999999999999 e73a048d-bf27-4f12-9731-8b2076e8891f 5dbb7c9f-38e9-40d2-9749-4f8a0e9f640f 000 *> $null
    Write-Log "Disabling automatic actions on critical battery level" -Severity 'INFO'
    powercfg /setacvalueindex 99999999-9999-9999-9999-999999999999 e73a048d-bf27-4f12-9731-8b2076e8891f 637ea02f-bbcb-4015-8e2c-a1c7b9c0b546 000 *> $null
    powercfg /setdcvalueindex 99999999-9999-9999-9999-999999999999 e73a048d-bf27-4f12-9731-8b2076e8891f 637ea02f-bbcb-4015-8e2c-a1c7b9c0b546 000 *> $null

    Write-Log "Setting low battery threshold to 0%" -Severity 'INFO'
    powercfg /setacvalueindex 99999999-9999-9999-9999-999999999999 e73a048d-bf27-4f12-9731-8b2076e8891f 8183ba9a-e910-48da-8769-14ae6dc1170a 0x00000000 *> $null
    powercfg /setdcvalueindex 99999999-9999-9999-9999-999999999999 e73a048d-bf27-4f12-9731-8b2076e8891f 8183ba9a-e910-48da-8769-14ae6dc1170a 0x00000000 *> $null

    Write-Log "Setting critical battery threshold to 0%" -Severity 'INFO'
    powercfg /setacvalueindex 99999999-9999-9999-9999-999999999999 e73a048d-bf27-4f12-9731-8b2076e8891f 9a66d8d7-4ff7-4ef9-b5a2-5a326ca2a469 0x00000000 *> $null
    powercfg /setdcvalueindex 99999999-9999-9999-9999-999999999999 e73a048d-bf27-4f12-9731-8b2076e8891f 9a66d8d7-4ff7-4ef9-b5a2-5a326ca2a469 0x00000000 *> $null

    Write-Log "Disabling low battery notifications" -Severity 'INFO'
    powercfg /setacvalueindex 99999999-9999-9999-9999-999999999999 e73a048d-bf27-4f12-9731-8b2076e8891f bcded951-187b-4d05-bccc-f7e51960c258 000 *> $null
    powercfg /setdcvalueindex 99999999-9999-9999-9999-999999999999 e73a048d-bf27-4f12-9731-8b2076e8891f bcded951-187b-4d05-bccc-f7e51960c258 000 *> $null

    Write-Log "Disabling automatic actions on low battery level" -Severity 'INFO'
    powercfg /setacvalueindex 99999999-9999-9999-9999-999999999999 e73a048d-bf27-4f12-9731-8b2076e8891f d8742dcb-3e6a-4b3c-b3fe-374623cdcf06 000 *> $null
    powercfg /setdcvalueindex 99999999-9999-9999-9999-999999999999 e73a048d-bf27-4f12-9731-8b2076e8891f d8742dcb-3e6a-4b3c-b3fe-374623cdcf06 000 *> $null
    Write-Log "Setting battery reserve level to 0%" -Severity 'INFO'
    powercfg /setacvalueindex 99999999-9999-9999-9999-999999999999 e73a048d-bf27-4f12-9731-8b2076e8891f f3c5027d-cd16-4930-aa6b-90db844a8f00 0x00000000 *> $null
    powercfg /setdcvalueindex 99999999-9999-9999-9999-999999999999 e73a048d-bf27-4f12-9731-8b2076e8891f f3c5027d-cd16-4930-aa6b-90db844a8f00 0x00000000 *> $null

    Write-Log "Configuring Battery Saver settings" -Severity 'INFO'

    Write-Log "Disabling screen dimming when Battery Saver is active" -Severity 'INFO'
    powercfg /setacvalueindex 99999999-9999-9999-9999-999999999999 de830923-a562-41af-a086-e3a2c6bad2da 13d09884-f74e-474a-a852-b6bde8ad03a8 0x00000064 *> $null
    powercfg /setdcvalueindex 99999999-9999-9999-9999-999999999999 de830923-a562-41af-a086-e3a2c6bad2da 13d09884-f74e-474a-a852-b6bde8ad03a8 0x00000064 *> $null

    Write-Log "Disabling automatic Battery Saver activation" -Severity 'INFO'
    powercfg /setacvalueindex 99999999-9999-9999-9999-999999999999 de830923-a562-41af-a086-e3a2c6bad2da e69653ca-cf7f-4f05-aa73-cb833fa90ad4 0x00000000 *> $null
    powercfg /setdcvalueindex 99999999-9999-9999-9999-999999999999 de830923-a562-41af-a086-e3a2c6bad2da e69653ca-cf7f-4f05-aa73-cb833fa90ad4 0x00000000 *> $null  
}

# Function to change Power Settings back to defaults
function Set-DefaultPowerSettings {
    Write-Log "Restoring power plan settings to defaults" -Severity 'INFO'
    powercfg -restoredefaultschemes

    Write-Log "Optimizing video quality for battery operation" -Severity 'INFO'
    cmd /c "reg add `"HKCU\Software\Microsoft\Windows\CurrentVersion\VideoSettings`" /v VideoQualityOnBattery /t REG_DWORD /d 0 /f >nul 2>&1"

    Write-Log "Re-enabling hibernate functionality" -Severity 'INFO'
    cmd /c "powercfg /hibernate on >nul 2>&1"
    cmd /c "reg delete `"HKLM\SYSTEM\CurrentControlSet\Control\Power`" /v `"HibernateEnabled`" /f >nul 2>&1"
    cmd /c "reg add `"HKLM\SYSTEM\CurrentControlSet\Control\Power`" /v `"HibernateEnabledDefault`" /t REG_DWORD /d `"1`" /f >nul 2>&1"

    Write-Log "Re-enabling lock and sleep options" -Severity 'INFO'
    cmd /c "reg delete `"HKLM\Software\Microsoft\Windows\CurrentVersion\Explorer\FlyoutMenuSettings`" /f >nul 2>&1"

    Write-Log "Re-enabling fast boot functionality" -Severity 'INFO'
    cmd /c "reg add `"HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Power`" /v `"HiberbootEnabled`" /t REG_DWORD /d `"1`" /f >nul 2>&1"

    Write-Log "Restoring CPU core parking settings" -Severity 'INFO'
    cmd /c "reg add `"HKLM\SYSTEM\ControlSet001\Control\Power\PowerSettings\54533251-82be-4824-96c1-47b60b740d00\0cc5b647-c1df-4637-891a-dec35c318583`" /v `"ValueMax`" /t REG_DWORD /d `"100`" /f >nul 2>&1"

    Write-Log "Re-enabling power throttling for better power efficiency" -Severity 'INFO'
    cmd /c "reg delete `"HKLM\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling`" /f >nul 2>&1"

    Write-Log "Hiding advanced USB power settings" -Severity 'INFO'
    cmd /c "reg add `"HKLM\System\ControlSet001\Control\Power\PowerSettings\2a737441-1930-4402-8d77-b2bebba308a3\0853a681-27c8-4100-a2fd-82013e970683`" /v `"Attributes`" /t REG_DWORD /d `"1`" /f >nul 2>&1"
    cmd /c "reg add `"HKLM\System\ControlSet001\Control\Power\PowerSettings\2a737441-1930-4402-8d77-b2bebba308a3\d4e98f31-5ffe-4ce1-be31-1b38b384c009`" /v `"Attributes`" /t REG_DWORD /d `"1`" /f >nul 2>&1"
}

# Function to change Windows Scheduled Tasks settings
function Invoke-ScheduledTaskSettings {
    param(
        [Parameter(Mandatory)]
        [TaskAction]$Action = [TaskAction]::Apply,
        [switch]$SuppressMessage
    )

    $successCount = 0
    $protectedTasks = @()
    $nonExistentTasks = @()

    # Define the list of scheduled tasks to manage
    $ScheduledTasksList = @(
        # Telemetry & Experience
        "Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser",
        "Microsoft\Windows\Application Experience\PcaPatchDbTask",
        "Microsoft\Windows\Application Experience\SdbinstMergeDbTask",
        "Microsoft\Windows\Customer Experience Improvement Program\Consolidator",
        "Microsoft\Windows\Customer Experience Improvement Program\UsbCeip",
        "Microsoft\Windows\Flighting\FeatureConfig\UsageDataFlushing",
        "Microsoft\Windows\Flighting\FeatureConfig\UsageDataReporting",
        "Microsoft\Windows\Feedback\Siuf\DmClient",
        "Microsoft\Windows\Feedback\Siuf\DmClientOnScenarioDownload",

        # Features you might not use
        "Microsoft\Windows\Maps\MapsToastTask",
        "Microsoft\Windows\Maps\MapsUpdateTask",
        "Microsoft\Windows\Shell\FamilySafetyMonitor",
        "Microsoft\Windows\Shell\FamilySafetyRefreshTask",
        "Microsoft\Windows\Shell\IndexerAutomaticMaintenance",
        "Microsoft\Windows\XblGameSave\XblGameSaveTask",
        "Microsoft\Windows\Work Folders\Work Folders Logon Synchronization",
        "Microsoft\Windows\Work Folders\Work Folders Maintenance Work",
        "Microsoft\Windows\Windows Media Sharing\UpdateLibrary",
        "Microsoft\Windows\WwanSvc\NotificationTask",
        "Microsoft\Windows\WwanSvc\OobeDiscovery",

        # Windows Error Reporting
        "Microsoft\Windows\Windows Error Reporting\QueueReporting",

        # Office & OneDrive (if not using)
        "Microsoft\Office\Office Automatic Updates",
        "Microsoft\Office\Office ClickToRun Service Monitor",
        "Microsoft\Office\OfficeTelemetryAgentFallBack",
        "Microsoft\Office\OfficeTelemetryAgentLogOn",

        # Diagnostic Tasks
        "Microsoft\Windows\Diagnosis\Scheduled",
        "Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector",
        "Microsoft\Windows\RedDiagnostic\ProcessRedDiagnosticEvents",
        "Microsoft\Windows\Power Efficiency Diagnostics\AnalyzeSystem",

        # Unnecessary System Tasks
        "Microsoft\Windows\Autochk\Proxy",
        "Microsoft\Windows\Defrag\ScheduledDefrag",
        "Microsoft\Windows\RemoteAssistance\RemoteAssistanceTask",
        "Microsoft\Windows\Time Synchronization\ForceSynchronizeTime",
        "Microsoft\Windows\UpdateOrchestrator\Report policies",
        "Microsoft\Windows\UpdateOrchestrator\Schedule Scan",
        "Microsoft\Windows\WindowsUpdate\Scheduled Start",
        "Microsoft\Windows\WaaSMedic\PerformRemediation",
        "Microsoft\Windows\InstallService\ScanForUpdates",
        "Microsoft\Windows\InstallService\ScanForUpdatesAsUser",
        "Microsoft\Windows\DiskFootprint\Diagnostics",
        "Microsoft\Windows\FileHistory\File History (maintenance mode)",
        "Microsoft\Windows\PI\Sqm-Tasks",
        "Microsoft\Windows\Application Experience\ProgramDataUpdater",
        "Microsoft\Windows\Application Experience\MareBackup",
    
        # Location & Sync Tasks
        "Microsoft\Windows\Location\WindowsActionDialog",
        "Microsoft\Windows\Location\Notifications",
        "Microsoft\Windows\Mobile Broadband Accounts\MNO Metadata Parser",
        "Microsoft\Windows\Device Setup\Metadata Refresh",
        "Microsoft\Windows\International\Synchronize Language Settings",

        # Retail & Demo
        "Microsoft\Windows\Retail Demo\CleanupOfflineContent",
        "Microsoft\Windows\PushToInstall\LoginCheck",
        "Microsoft\Windows\PushToInstall\Registration",

        # Unnecessary App Tasks
        "Microsoft\Windows\AppID\SmartScreenSpecific",
        "Microsoft\Windows\Application Experience\StartupAppTask",
        "Microsoft\Windows\CloudExperienceHost\CreateObjectTask",
        "Microsoft\Windows\HelloFace\FODCleanupTask",
        "Microsoft\Windows\Subscription\EnableLicenseAcquisition",
        "Microsoft\Windows\UNP\RunUpdateNotificationMgr"
    )

    foreach ($task in $ScheduledTasksList) {
        try {
            # The task path must start with \ and end with \
            $taskPath = "\{0}\" -f [string]::Join('\', $task.Split('\')[0..($task.Split('\').Length - 2)])
            $taskName = $task.Split('\')[-1]
            
            Write-Log "Attempting to process task: $taskName in path: $taskPath" -Severity 'INFO'
            
            $taskObj = Get-ScheduledTask -TaskName $taskName -TaskPath $taskPath -ErrorAction Stop
            
            if ($null -ne $taskObj) {
                if ($Action -eq [TaskAction]::Apply) {
                    Disable-ScheduledTask -InputObject $taskObj -ErrorAction Stop | Out-Null
                    Write-Log "Disabled task: $task" -Severity 'SUCCESS'
                }
                else {
                    Enable-ScheduledTask -InputObject $taskObj -ErrorAction Stop | Out-Null
                    Write-Log "Enabled task: $task" -Severity 'SUCCESS'
                }
                $successCount++
            }
        }
        catch {
            if ($_.Exception.Message -like "*Access is denied*") {
                $protectedTasks += $task
                Write-Log "Protected task (access denied): $task" -Severity 'WARNING'
            }
            elseif ($_.Exception.Message -like "*No matching MSFT_ScheduledTask*") {
                $nonExistentTasks += $task
                Write-Log "Task not found on system: $task" -Severity 'INFO'
            }
            else {
                Write-Log "Failed to process task: $task - $($_.Exception.Message)" -Severity 'ERROR'
            }
            continue
        }
    }

    # Show completion message if not suppressed
    if (-not $SuppressMessage) {
        $actionWord = if ($Action -eq [TaskAction]::Apply) { "disabled" } else { "enabled" }
        
        $message = "Successfully $actionWord $successCount scheduled tasks."
        
        if ($protectedTasks.Count -gt 0) {
            $message += "`n`nSkipped $($protectedTasks.Count) protected system tasks."
        }
        
        if ($nonExistentTasks.Count -gt 0) {
            $message += "`n`nSkipped $($nonExistentTasks.Count) tasks that are not present on your system."
        }

        # Only show detailed lists if there weren't too many items
        if (($protectedTasks.Count + $nonExistentTasks.Count) -lt 10) {
            if ($protectedTasks.Count -gt 0) {
                $message += "`n`nProtected tasks:`n"
                $message += $protectedTasks | ForEach-Object { "- $_" } | Out-String
            }
            
            if ($nonExistentTasks.Count -gt 0) {
                $message += "`n`nNot present on system:`n"
                $message += $nonExistentTasks | ForEach-Object { "- $_" } | Out-String
            }
        }
        
        Show-MessageBox -Message $message.TrimEnd() -Title "Scheduled Tasks Manager"
    }
}

# NOTE
# Privacy Settings, Gaming Optimizations, Windows Updates, Scheduled Tasks and Windows Services are handled by the Invoke-Settings function.

# =================================
# Customize Screen Functions
# =================================

function Set-DarkMode {
    param(
        [bool]$EnableDarkMode,
        [bool]$ChangeWallpaper = $false
    )
    
    try {
        # Apply theme settings
        $settings = $SCRIPT:RegSettings.Personalization |
        Where-Object { $_.Name -in @('AppsUseLightTheme', 'SystemUsesLightTheme') }

        foreach ($setting in $settings) {
            $value = if ($EnableDarkMode) { 
                $setting.RecommendedValue 
            }
            else { 
                $setting.DefaultValue
            }
            
            [RegistryHelper]::ApplyValue($setting, $value)
        }

        # Update transparency setting
        $transparencySetting = $SCRIPT:RegSettings.Personalization |
        Where-Object { $_.Name -eq 'EnableTransparency' } |
        Select-Object -First 1
        
        if ($transparencySetting) {
            [RegistryHelper]::ApplyValue(
                $transparencySetting,
                $transparencySetting.RecommendedValue
            )
        }

        # Handle wallpaper change if requested
        if ($ChangeWallpaper) {
            $windowsVersion = Get-WindowsVersion
            
            try {
                if ($windowsVersion -ge 22000) {
                    # Windows 11
                    $basePath = "$env:SystemRoot\Web\Wallpaper\Windows"
                    if ($EnableDarkMode) {
                        $wallpaperPath = Join-Path $basePath "img19.jpg"
                    }
                    else {
                        $wallpaperPath = Join-Path $basePath "img0.jpg"
                    }
                }
                else {
                    # Windows 10
                    $wallpaperPath = "$env:SystemRoot\Web\4K\Wallpaper\Windows\img0_3840x2160.jpg"
                }

                # Verify path exists before trying to set it
                if (Test-Path $wallpaperPath) {
                    Set-Wallpaper -wallpaperPath $wallpaperPath
                }
                else {
                    Write-Log "Default wallpaper not found at: $wallpaperPath" -Severity Warning
                    Show-MessageBox -Message "Could not find the default wallpaper file." -Icon Warning
                }
            }
            catch {
                Write-Log "Failed to set wallpaper: $_" -Severity Error
                Show-MessageBox -Message "Failed to change wallpaper: $($_.Exception.Message)" -Icon Error
            }
        }

        Update-WinGUI
        Write-Log "Dark Mode $(if ($EnableDarkMode) {'enabled'} else {'disabled'})"
        Write-Status -Message "Theme Changed Successfully" -TargetScreen CustomizeScreen
    }
    catch {
        Write-Log "Theme update failed: $_"
        throw
    }
}

# Clean Windows 10 Start Menu
function Reset-Windows10StartMenu {
    
    Write-Status "Cleaning Windows 10 Start Menu..." -TargetScreen CustomizeScreen
    # CLEAN START MENU W10
    # delete startmenulayout.xml
    Remove-Item -Recurse -Force "$env:SystemDrive\Windows\StartMenuLayout.xml" -ErrorAction SilentlyContinue | Out-Null
    # create startmenulayout.xml
    $MultilineComment = @"
<LayoutModificationTemplate xmlns:defaultlayout="http://schemas.microsoft.com/Start/2014/FullDefaultLayout" xmlns:start="http://schemas.microsoft.com/Start/2014/StartLayout" Version="1" xmlns:taskbar="http://schemas.microsoft.com/Start/2014/TaskbarLayout" xmlns="http://schemas.microsoft.com/Start/2014/LayoutModification">
    <LayoutOptions StartTileGroupCellWidth="6" />
    <DefaultLayoutOverride>
        <StartLayoutCollection>
            <defaultlayout:StartLayout GroupCellWidth="6" />
        </StartLayoutCollection>
    </DefaultLayoutOverride>
</LayoutModificationTemplate>
"@
    Set-Content -Path "C:\Windows\StartMenuLayout.xml" -Value $MultilineComment -Force -Encoding ASCII
    # assign startmenulayout.xml registry
    $layoutFile = "C:\Windows\StartMenuLayout.xml"
    $regAliases = @("HKLM", "HKCU")
    foreach ($regAlias in $regAliases) {
        $basePath = $regAlias + ":\SOFTWARE\Policies\Microsoft\Windows"
        $keyPath = $basePath + "\Explorer"
        IF (!(Test-Path -Path $keyPath)) {
            New-Item -Path $basePath -Name "Explorer" | Out-Null
        }
        Set-ItemProperty -Path $keyPath -Name "LockedStartLayout" -Value 1 | Out-Null
        Set-ItemProperty -Path $keyPath -Name "StartLayoutFile" -Value $layoutFile | Out-Null
    }
    # restart explorer
    Stop-Process -Force -Name explorer -ErrorAction SilentlyContinue | Out-Null
    Timeout /T 5 | Out-Null
    # disable lockedstartlayout registry
    foreach ($regAlias in $regAliases) {
        $basePath = $regAlias + ":\SOFTWARE\Policies\Microsoft\Windows"
        $keyPath = $basePath + "\Explorer"
        Set-ItemProperty -Path $keyPath -Name "LockedStartLayout" -Value 0
    }
    # restart explorer
    Stop-Process -Force -Name explorer -ErrorAction SilentlyContinue | Out-Null
    # delete startmenulayout.xml
    Remove-Item -Recurse -Force "$env:SystemDrive\Windows\StartMenuLayout.xml" -ErrorAction SilentlyContinue | Out-Null

}

# Clean Windows 11 Start Menu
# Source: https://raw.githubusercontent.com/FR33THYFR33THY/Ultimate-Windows-Optimization-Guide/refs/heads/main/6%20Windows/1%20Start%20Menu%20Taskbar.ps1

function Reset-Windows11StartMenu {
    [CmdletBinding()]
    param()
    
    try {

        Write-Status "Cleaning Windows 11 Start Menu..." -TargetScreen CustomizeScreen
        # Suppress progress output
        $progressPreference = 'SilentlyContinue'
        
        # Clean up existing start2.bin if it exists
        Remove-Item -Recurse -Force "$env:USERPROFILE\AppData\Local\Packages\Microsoft.Windows.StartMenuExperienceHost_cw5n1h2txyewy\LocalState\start2.bin" -ErrorAction SilentlyContinue
        
        # Base64 encoded certificate content that represents clean start menu layout
        
        $certContent = "-----BEGIN CERTIFICATE-----
4nrhSwH8TRucAIEL3m5RhU5aX0cAW7FJilySr5CE+V40mv9utV7aAZARAABc9u55
LN8F4borYyXEGl8Q5+RZ+qERszeqUhhZXDvcjTF6rgdprauITLqPgMVMbSZbRsLN
/O5uMjSLEr6nWYIwsMJkZMnZyZrhR3PugUhUKOYDqwySCY6/CPkL/Ooz/5j2R2hw
WRGqc7ZsJxDFM1DWofjUiGjDUny+Y8UjowknQVaPYao0PC4bygKEbeZqCqRvSgPa
lSc53OFqCh2FHydzl09fChaos385QvF40EDEgSO8U9/dntAeNULwuuZBi7BkWSIO
mWN1l4e+TZbtSJXwn+EINAJhRHyCSNeku21dsw+cMoLorMKnRmhJMLvE+CCdgNKI
aPo/Krizva1+bMsI8bSkV/CxaCTLXodb/NuBYCsIHY1sTvbwSBRNMPvccw43RJCU
KZRkBLkCVfW24ANbLfHXofHDMLxxFNUpBPSgzGHnueHknECcf6J4HCFBqzvSH1Tj
Q3S6J8tq2yaQ+jFNkxGRMushdXNNiTNjDFYMJNvgRL2lu606PZeypEjvPg7SkGR2
7a42GDSJ8n6HQJXFkOQPJ1mkU4qpA78U+ZAo9ccw8XQPPqE1eG7wzMGihTWfEMVs
K1nsKyEZCLYFmKwYqdIF0somFBXaL/qmEHxwlPCjwRKpwLOue0Y8fgA06xk+DMti
zWahOZNeZ54MN3N14S22D75riYEccVe3CtkDoL+4Oc2MhVdYEVtQcqtKqZ+DmmoI
5BqkECeSHZ4OCguheFckK5Eq5Yf0CKRN+RY2OJ0ZCPUyxQnWdnOi9oBcZsz2NGzY
g8ifO5s5UGscSDMQWUxPJQePDh8nPUittzJ+iplQqJYQ/9p5nKoDukzHHkSwfGms
1GiSYMUZvaze7VSWOHrgZ6dp5qc1SQy0FSacBaEu4ziwx1H7w5NZj+zj2ZbxAZhr
7Wfvt9K1xp58H66U4YT8Su7oq5JGDxuwOEbkltA7PzbFUtq65m4P4LvS4QUIBUqU
0+JRyppVN5HPe11cCPaDdWhcr3LsibWXQ7f0mK8xTtPkOUb5pA2OUIkwNlzmwwS1
Nn69/13u7HmPSyofLck77zGjjqhSV22oHhBSGEr+KagMLZlvt9pnD/3I1R1BqItW
KF3woyb/QizAqScEBsOKj7fmGA7f0KKQkpSpenF1Q/LNdyyOc77wbu2aywLGLN7H
BCdwwjjMQ43FHSQPCA3+5mQDcfhmsFtORnRZWqVKwcKWuUJ7zLEIxlANZ7rDcC30
FKmeUJuKk0Upvhsz7UXzDtNmqYmtg6vY/yPtG5Cc7XXGJxY2QJcbg1uqYI6gKtue
00Mfpjw7XpUMQbIW9rXMA9PSWX6h2ln2TwlbrRikqdQXACZyhtuzSNLK7ifSqw4O
JcZ8JrQ/xePmSd0z6O/MCTiUTFwG0E6WS1XBV1owOYi6jVif1zg75DTbXQGTNRvK
KarodfnpYg3sgTe/8OAI1YSwProuGNNh4hxK+SmljqrYmEj8BNK3MNCyIskCcQ4u
cyoJJHmsNaGFyiKp1543PktIgcs8kpF/SN86/SoB/oI7KECCCKtHNdFV8p9HO3t8
5OsgGUYgvh7Z/Z+P7UGgN1iaYn7El9XopQ/XwK9zc9FBr73+xzE5Hh4aehNVIQdM
Mb+Rfm11R0Jc4WhqBLCC3/uBRzesyKUzPoRJ9IOxCwzeFwGQ202XVlPvklXQwgHx
BfEAWZY1gaX6femNGDkRldzImxF87Sncnt9Y9uQty8u0IY3lLYNcAFoTobZmFkAQ
vuNcXxObmHk3rZNAbRLFsXnWUKGjuK5oP2TyTNlm9fMmnf/E8deez3d8KOXW9YMZ
DkA/iElnxcCKUFpwI+tWqHQ0FT96sgIP/EyhhCq6o/RnNtZvch9zW8sIGD7Lg0cq
SzPYghZuNVYwr90qt7UDekEei4CHTzgWwlSWGGCrP6Oxjk1Fe+KvH4OYwEiDwyRc
l7NRJseqpW1ODv8c3VLnTJJ4o3QPlAO6tOvon7vA1STKtXylbjWARNcWuxT41jtC
CzrAroK2r9bCij4VbwHjmpQnhYbF/hCE1r71Z5eHdWXqpSgIWeS/1avQTStsehwD
2+NGFRXI8mwLBLQN/qi8rqmKPi+fPVBjFoYDyDc35elpdzvqtN/mEp+xDrnAbwXU
yfhkZvyo2+LXFMGFLdYtWTK/+T/4n03OJH1gr6j3zkoosewKTiZeClnK/qfc8YLw
bCdwBm4uHsZ9I14OFCepfHzmXp9nN6a3u0sKi4GZpnAIjSreY4rMK8c+0FNNDLi5
DKuck7+WuGkcRrB/1G9qSdpXqVe86uNojXk9P6TlpXyL/noudwmUhUNTZyOGcmhJ
EBiaNbT2Awx5QNssAlZFuEfvPEAixBz476U8/UPb9ObHbsdcZjXNV89WhfYX04DM
9qcMhCnGq25sJPc5VC6XnNHpFeWhvV/edYESdeEVwxEcExKEAwmEZlGJdxzoAH+K
Y+xAZdgWjPPL5FaYzpXc5erALUfyT+n0UTLcjaR4AKxLnpbRqlNzrWa6xqJN9NwA
+xa38I6EXbQ5Q2kLcK6qbJAbkEL76WiFlkc5mXrGouukDvsjYdxG5Rx6OYxb41Ep
1jEtinaNfXwt/JiDZxuXCMHdKHSH40aZCRlwdAI1C5fqoUkgiDdsxkEq+mGWxMVE
Zd0Ch9zgQLlA6gYlK3gt8+dr1+OSZ0dQdp3ABqb1+0oP8xpozFc2bK3OsJvucpYB
OdmS+rfScY+N0PByGJoKbdNUHIeXv2xdhXnVjM5G3G6nxa3x8WFMJsJs2ma1xRT1
8HKqjX9Ha072PD8Zviu/bWdf5c4RrphVqvzfr9wNRpfmnGOoOcbkRE4QrL5CqrPb
VRujOBMPGAxNlvwq0w1XDOBDawZgK7660yd4MQFZk7iyZgUSXIo3ikleRSmBs+Mt
r+3Og54Cg9QLPHbQQPmiMsu21IJUh0rTgxMVBxNUNbUaPJI1lmbkTcc7HeIk0Wtg
RxwYc8aUn0f/V//c+2ZAlM6xmXmj6jIkOcfkSBd0B5z63N4trypD3m+w34bZkV1I
cQ8h7SaUUqYO5RkjStZbvk2IDFSPUExvqhCstnJf7PZGilbsFPN8lYqcIvDZdaAU
MunNh6f/RnhFwKHXoyWtNI6yK6dm1mhwy+DgPlA2nAevO+FC7Vv98Sl9zaVjaPPy
3BRyQ6kISCL065AKVPEY0ULHqtIyfU5gMvBeUa5+xbU+tUx4ZeP/BdB48/LodyYV
kkgqTafVxCvz4vgmPbnPjm/dlRbVGbyygN0Noq8vo2Ea8Z5zwO32coY2309AC7wv
Pp2wJZn6LKRmzoLWJMFm1A1Oa4RUIkEpA3AAL+5TauxfawpdtTjicoWGQ5gGNwum
+evTnGEpDimE5kUU6uiJ0rotjNpB52I+8qmbgIPkY0Fwwal5Z5yvZJ8eepQjvdZ2
UcdvlTS8oA5YayGi+ASmnJSbsr/v1OOcLmnpwPI+hRgPP+Hwu5rWkOT+SDomF1TO
n/k7NkJ967X0kPx6XtxTPgcG1aKJwZBNQDKDP17/dlZ869W3o6JdgCEvt1nIOPty
lGgvGERC0jCNRJpGml4/py7AtP0WOxrs+YS60sPKMATtiGzp34++dAmHyVEmelhK
apQBuxFl6LQN33+2NNn6L5twI4IQfnm6Cvly9r3VBO0Bi+rpjdftr60scRQM1qw+
9dEz4xL9VEL6wrnyAERLY58wmS9Zp73xXQ1mdDB+yKkGOHeIiA7tCwnNZqClQ8Mf
RnZIAeL1jcqrIsmkQNs4RTuE+ApcnE5DMcvJMgEd1fU3JDRJbaUv+w7kxj4/+G5b
IU2bfh52jUQ5gOftGEFs1LOLj4Bny2XlCiP0L7XLJTKSf0t1zj2ohQWDT5BLo0EV
5rye4hckB4QCiNyiZfavwB6ymStjwnuaS8qwjaRLw4JEeNDjSs/JC0G2ewulUyHt
kEobZO/mQLlhso2lnEaRtK1LyoD1b4IEDbTYmjaWKLR7J64iHKUpiQYPSPxcWyei
o4kcyGw+QvgmxGaKsqSBVGogOV6YuEyoaM0jlfUmi2UmQkju2iY5tzCObNQ41nsL
dKwraDrcjrn4CAKPMMfeUSvYWP559EFfDhDSK6Os6Sbo8R6Zoa7C2NdAicA1jPbt
5ENSrVKf7TOrthvNH9vb1mZC1X2RBmriowa/iT+LEbmQnAkA6Y1tCbpzvrL+cX8K
pUTOAovaiPbab0xzFP7QXc1uK0XA+M1wQ9OF3XGp8PS5QRgSTwMpQXW2iMqihYPv
Hu6U1hhkyfzYZzoJCjVsY2xghJmjKiKEfX0w3RaxfrJkF8ePY9SexnVUNXJ1654/
PQzDKsW58Au9QpIH9VSwKNpv003PksOpobM6G52ouCFOk6HFzSLfnlGZW0yyUQL3
RRyEE2PP0LwQEuk2gxrW8eVy9elqn43S8CG2h2NUtmQULc/IeX63tmCOmOS0emW9
66EljNdMk/e5dTo5XplTJRxRydXcQpgy9bQuntFwPPoo0fXfXlirKsav2rPSWayw
KQK4NxinT+yQh//COeQDYkK01urc2G7SxZ6H0k6uo8xVp9tDCYqHk/lbvukoN0RF
tUI4aLWuKet1O1s1uUAxjd50ELks5iwoqLJ/1bzSmTRMifehP07sbK/N1f4hLae+
jykYgzDWNfNvmPEiz0DwO/rCQTP6x69g+NJaFlmPFwGsKfxP8HqiNWQ6D3irZYcQ
R5Mt2Iwzz2ZWA7B2WLYZWndRCosRVWyPdGhs7gkmLPZ+WWo/Yb7O1kIiWGfVuPNA
MKmgPPjZy8DhZfq5kX20KF6uA0JOZOciXhc0PPAUEy/iQAtzSDYjmJ8HR7l4mYsT
O3Mg3QibMK8MGGa4tEM8OPGktAV5B2J2QOe0f1r3vi3QmM+yukBaabwlJ+dUDQGm
+Ll/1mO5TS+BlWMEAi13cB5bPRsxkzpabxq5kyQwh4vcMuLI0BOIfE2pDKny5jhW
0C4zzv3avYaJh2ts6kvlvTKiSMeXcnK6onKHT89fWQ7Hzr/W8QbR/GnIWBbJMoTc
WcgmW4fO3AC+YlnLVK4kBmnBmsLzLh6M2LOabhxKN8+0Oeoouww7g0HgHkDyt+MS
97po6SETwrdqEFslylLo8+GifFI1bb68H79iEwjXojxQXcD5qqJPxdHsA32eWV0b
qXAVojyAk7kQJfDIK+Y1q9T6KI4ew4t6iauJ8iVJyClnHt8z/4cXdMX37EvJ+2BS
YKHv5OAfS7/9ZpKgILT8NxghgvguLB7G9sWNHntExPtuRLL4/asYFYSAJxUPm7U2
xnp35Zx5jCXesd5OlKNdmhXq519cLl0RGZfH2ZIAEf1hNZqDuKesZ2enykjFlIec
hZsLvEW/pJQnW0+LFz9N3x3vJwxbC7oDgd7A2u0I69Tkdzlc6FFJcfGabT5C3eF2
EAC+toIobJY9hpxdkeukSuxVwin9zuBoUM4X9x/FvgfIE0dKLpzsFyMNlO4taCLc
v1zbgUk2sR91JmbiCbqHglTzQaVMLhPwd8GU55AvYCGMOsSg3p952UkeoxRSeZRp
jQHr4bLN90cqNcrD3h5knmC61nDKf8e+vRZO8CVYR1eb3LsMz12vhTJGaQ4jd0Kz
QyosjcB73wnE9b/rxfG1dRactg7zRU2BfBK/CHpIFJH+XztwMJxn27foSvCY6ktd
uJorJvkGJOgwg0f+oHKDvOTWFO1GSqEZ5BwXKGH0t0udZyXQGgZWvF5s/ojZVcK3
IXz4tKhwrI1ZKnZwL9R2zrpMJ4w6smQgipP0yzzi0ZvsOXRksQJNCn4UPLBhbu+C
eFBbpfe9wJFLD+8F9EY6GlY2W9AKD5/zNUCj6ws8lBn3aRfNPE+Cxy+IKC1NdKLw
eFdOGZr2y1K2IkdefmN9cLZQ/CVXkw8Qw2nOr/ntwuFV/tvJoPW2EOzRmF2XO8mQ
DQv51k5/v4ZE2VL0dIIvj1M+KPw0nSs271QgJanYwK3CpFluK/1ilEi7JKDikT8X
TSz1QZdkum5Y3uC7wc7paXh1rm11nwluCC7jiA==
-----END CERTIFICATE-----"
        
        # Create temp file with cert content
        New-Item "$env:TEMP\start2.txt" -Value $certContent -Force | Out-Null
        
        # Decode the cert content to binary
        certutil.exe -decode "$env:TEMP\start2.txt" "$env:TEMP\start2.bin" >$null
        
        # Copy the decoded binary to the Start Menu location
        Copy-Item "$env:TEMP\start2.bin" -Destination "$env:USERPROFILE\AppData\Local\Packages\Microsoft.Windows.StartMenuExperienceHost_cw5n1h2txyewy\LocalState" -Force | Out-Null
        
        # Clean up temp files
        Remove-Item "$env:TEMP\start2.txt" -Force -ErrorAction SilentlyContinue
        Remove-Item "$env:TEMP\start2.bin" -Force -ErrorAction SilentlyContinue

        # Sets more pins layout (less recommended)
        $regPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
        if (-not (Test-Path $regPath)) {
            New-Item -Path $regPath -Force | Out-Null
        }
        Set-ItemProperty -Path $regPath -Name "Start_Layout" -Value 1 -Type DWord -Force

        # Refresh Windows GUI
        Update-WinGUI
        
        return $true
    }
    catch {
        Write-Log "Failed to reset Windows 11 Start Menu - $($_.Exception.Message)" -Severity 'ERROR'
        return $false
    }
}

# NOTE
# Taskbar, Explorer, Notifications, Sound, Accessibility and Search are handled by the Invoke-Settings function.

#region 5. GUI Definition
# ====================================================================================================
# GUI Definition
# XAML definition and window creation for the application interface
# ====================================================================================================

$xaml = @'
<Window
	xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
	xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
	xmlns:d="http://schemas.microsoft.com/expression/blend/2008"
	xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006"
    Title="Rocket"
    Width="1050"
    Height="615"
    Background="Transparent"
    WindowStartupLocation="CenterScreen"
    WindowStyle="None"
    AllowsTransparency="True"
    ResizeMode="CanResize"
    mc:Ignorable="d">
    <!--  WindowChrome for rounded corners  -->
    <WindowChrome.WindowChrome>
        <WindowChrome 
            CaptionHeight="32"
            CornerRadius="10"
            GlassFrameThickness="-1"
            NonClientFrameEdges="None"
            UseAeroCaptionButtons="False"/>
    </WindowChrome.WindowChrome>
    <Window.Resources>
        <!--  Button Style for Primary Buttons  -->
        <Style x:Key="PrimaryButtonStyle" TargetType="Button">
            <Setter Property="Background" Value="Transparent" />
            <Setter Property="Foreground" Value="White" />
            <Setter Property="BorderBrush" Value="#FFDE00" />
            <Setter Property="FontFamily" Value="Futura" />
            <Setter Property="FontSize" Value="16" />
            <Setter Property="Width" Value="80" />
            <Setter Property="Height" Value="30" />
            <Setter Property="FontWeight" Value="SemiBold" />
            <Setter Property="Padding" Value="15,15" />
            <Setter Property="Cursor" Value="Hand" />
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border
                            Background="{TemplateBinding Background}"
                            BorderBrush="{TemplateBinding BorderBrush}"
                            BorderThickness="2"
                            CornerRadius="5">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center" />
                        </Border>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
            <Style.Triggers>
                <!--  Hover State for Enabled Button  -->
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="Background" Value="#FFDE00" />
                    <Setter Property="Foreground" Value="Black" />
                    <Setter Property="BorderBrush" Value="#FFDE00" />
                </Trigger>
                <!--  Disabled State  -->
                <Trigger Property="IsEnabled" Value="False">
                    <Setter Property="Background" Value="Transparent" />
                    <Setter Property="Foreground" Value="#D3D3D3" />
                    <Setter Property="BorderBrush" Value="#FFEB99" />
                    <Setter Property="Cursor" Value="Arrow" />
                </Trigger>
                <!--  Disabled Hover State  -->
                <MultiTrigger>
                    <MultiTrigger.Conditions>
                        <Condition Property="IsEnabled" Value="False" />
                        <Condition Property="IsMouseOver" Value="True" />
                    </MultiTrigger.Conditions>
                    <Setter Property="Background" Value="#A9A9A9" />
                    <Setter Property="Foreground" Value="#C0C0C0" />
                </MultiTrigger>
            </Style.Triggers>
        </Style>
        <Style x:Key="NavigationButtonStyle" TargetType="Button">
            <Setter Property="Width" Value="70" />
            <Setter Property="Height" Value="70" />
            <Setter Property="Background" Value="#202020" />
            <Setter Property="Foreground" Value="White" />
            <Setter Property="FontFamily" Value="Segoe UI Emoji" />
            <!-- Default font family -->
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border
                    x:Name="border"
                    Background="{TemplateBinding Background}"
                    BorderThickness="0"
                    CornerRadius="10">
                            <StackPanel VerticalAlignment="Center" HorizontalAlignment="Center">
                                <!-- Icon -->
                                <TextBlock
                            x:Name="icon"
                            Text="{TemplateBinding Tag}"
                            FontFamily="{TemplateBinding FontFamily}"
                            FontSize="24"
                            HorizontalAlignment="Center"
                            Margin="0,5,0,8"
                            Foreground="{TemplateBinding Foreground}" />
                                <!-- Text -->
                                <TextBlock
                            x:Name="text"
                            Text="{TemplateBinding Content}"
                            FontFamily="Helvetica Neue"
                            FontSize="10"
                            HorizontalAlignment="Center"
                            TextWrapping="Wrap"
                            TextAlignment="Center"
                            Foreground="{TemplateBinding Foreground}" />
                            </StackPanel>
                        </Border>
                        <ControlTemplate.Triggers>
                            <!-- Your existing triggers -->
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <DropShadowEffect x:Key="ShadowEffect" ShadowDepth="5" BlurRadius="10" Color="Black" />
        <Style x:Key="CustomTooltipStyle" TargetType="ToolTip">
            <Setter Property="Background" Value="#333333" />
            <Setter Property="Foreground" Value="White" />
            <Setter Property="FontFamily" Value="Segoe UI" />
            <Setter Property="FontSize" Value="12" />
            <Setter Property="Padding" Value="10" />
            <Setter Property="BorderThickness" Value="1" />
            <Setter Property="BorderBrush" Value="#FFDE00" />
            <Setter Property="MaxWidth" Value="400" />
            <Setter Property="HorizontalContentAlignment" Value="Left" />
        </Style>
        <!-- Help Icon Style -->
        <Style x:Key="HelpIconStyle" TargetType="TextBlock">
            <Setter Property="Text" Value="&#xE946;" />
            <Setter Property="FontFamily" Value="Segoe MDL2 Assets" />
            <Setter Property="FontSize" Value="16" />
            <Setter Property="FontWeight" Value="Normal" />
            <Setter Property="Foreground" Value="White" />
            <Setter Property="VerticalAlignment" Value="Center" />
        </Style>
        <!-- Slider Thumb Style (Pill/Vertical Line) -->
        <Style x:Key="SliderThumbStyle" TargetType="Thumb">
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Thumb">
                        <Rectangle 
                    Stroke="#FFDE00"
                    StrokeThickness="2"
                    Fill="#FFDE00"
                    Width="12"       
                            Height="28"                          
                            RadiusX="2"
                            RadiusY="2">
                            <Rectangle.RenderTransform>
                                <TranslateTransform Y="-1"/>
                            </Rectangle.RenderTransform>
                        </Rectangle>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Slider Track Style -->
        <Style x:Key="SliderRepeatButtonStyle" TargetType="RepeatButton">
            <Setter Property="Background" Value="#404040"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="RepeatButton">
                        <Border 
                    Background="{TemplateBinding Background}"
                    IsHitTestVisible="True">
                            <Border.Style>
                                <Style TargetType="Border">
                                    <!-- Default State (Slider Disabled or Value = Minimum) -->
                                    <Setter Property="Height" Value="4"/>
                                    <Setter Property="CornerRadius" Value="2"/>

                                    <!-- Enabled State (Slider Enabled and Value = Maximum) -->
                                    <Style.Triggers>
                                        <!-- Trigger for Slider Enabled -->
                                        <DataTrigger Binding="{Binding IsEnabled, RelativeSource={RelativeSource AncestorType=Slider}}" Value="True">
                                            <Setter Property="Height" Value="14"/>
                                        </DataTrigger>

                                        <!-- Trigger for Slider Value = Maximum (Right) -->
                                        <DataTrigger Binding="{Binding Value, RelativeSource={RelativeSource AncestorType=Slider}}" Value="1">
                                            <Setter Property="Height" Value="14"/>
                                        </DataTrigger>

                                        <!-- Trigger for Slider Value = Minimum (Left) -->
                                        <DataTrigger Binding="{Binding Value, RelativeSource={RelativeSource AncestorType=Slider}}" Value="0">
                                            <Setter Property="Height" Value="8"/>
                                        </DataTrigger>
                                    </Style.Triggers>
                                </Style>
                            </Border.Style>
                        </Border>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style x:Key="ToggleSliderStyle" TargetType="Slider">
            <Setter Property="Foreground" Value="#FFDE00"/>
            <Setter Property="Background" Value="#404040"/>
            <Setter Property="Minimum" Value="0"/>
            <Setter Property="Maximum" Value="1"/>
            <Setter Property="TickFrequency" Value="1"/>
            <Setter Property="IsSnapToTickEnabled" Value="True"/>
            <Setter Property="Width" Value="80"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Slider">
                        <Grid>
                            <Track x:Name="PART_Track">
                                <Track.DecreaseRepeatButton>
                                    <RepeatButton Style="{StaticResource SliderRepeatButtonStyle}" Command="Slider.DecreaseLarge"/>
                                </Track.DecreaseRepeatButton>
                                <Track.Thumb>
                                    <Thumb Style="{StaticResource SliderThumbStyle}"/>
                                </Track.Thumb>
                                <Track.IncreaseRepeatButton>
                                    <RepeatButton Style="{StaticResource SliderRepeatButtonStyle}" Command="Slider.IncreaseLarge"/>
                                </Track.IncreaseRepeatButton>
                            </Track>
                        </Grid>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style x:Key="UACSliderRepeatButtonStyle" TargetType="RepeatButton">
            <Setter Property="Background" Value="#404040"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="RepeatButton">
                        <Border 
                    Background="{TemplateBinding Background}"
                    IsHitTestVisible="True">
                            <Border.Style>
                                <Style TargetType="Border">
                                    <!-- Default State -->
                                    <Setter Property="Height" Value="4"/>
                                    <Setter Property="CornerRadius" Value="2"/>
                                </Style>
                            </Border.Style>
                        </Border>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style x:Key="UACSliderStyle" TargetType="Slider">
            <Setter Property="Foreground" Value="#FFDE00"/>
            <Setter Property="Background" Value="#404040"/>
            <Setter Property="Minimum" Value="0"/>
            <Setter Property="Maximum" Value="2"/>
            <Setter Property="TickFrequency" Value="1"/>
            <Setter Property="IsSnapToTickEnabled" Value="True"/>
            <Setter Property="Width" Value="200"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Slider">
                        <Grid>
                            <Track x:Name="PART_Track">
                                <Track.DecreaseRepeatButton>
                                    <RepeatButton Style="{StaticResource UACSliderRepeatButtonStyle}" Command="Slider.DecreaseLarge"/>
                                </Track.DecreaseRepeatButton>
                                <Track.Thumb>
                                    <Thumb Style="{StaticResource SliderThumbStyle}"/>
                                </Track.Thumb>
                                <Track.IncreaseRepeatButton>
                                    <RepeatButton Style="{StaticResource UACSliderRepeatButtonStyle}" Command="Slider.IncreaseLarge"/>
                                </Track.IncreaseRepeatButton>
                            </Track>
                            <TickBar 
                        Fill="White"
                        Placement="Top"
                        Height="4"
                        Margin="0,-15,0,0"/>
                        </Grid>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <!-- Checkbox Style -->
        <Style x:Key="CustomCheckBoxStyle" TargetType="CheckBox">
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="BorderBrush" Value="#FFDE00"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="CheckBox">
                        <Grid>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="Auto"/>
                                <ColumnDefinition Width="*"/>
                            </Grid.ColumnDefinitions>
                            <Border x:Name="CheckBoxBorder" 
                            Width="17" Height="17" 
                            BorderThickness="1.5"
                            BorderBrush="{TemplateBinding BorderBrush}"
                            Background="{TemplateBinding Background}"
                            CornerRadius="3">
                                <Border x:Name="InnerFill"
                                Margin="3"
                                Background="Transparent"
                                CornerRadius="1"/>
                            </Border>
                            <ContentPresenter Grid.Column="1"
                                    Margin="10,0,0,0"
                                    VerticalAlignment="Center"
                                    HorizontalAlignment="Left"/>
                        </Grid>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsChecked" Value="True">
                                <Setter TargetName="InnerFill" Property="Background" Value="White"/>
                            </Trigger>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="CheckBoxBorder" Property="BorderBrush" Value="#FFE94D"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </Window.Resources>
    <!--  Outer Border for rounded corners and window appearance  -->
    <Border
        Padding="10"
        Background="#202020"
        CornerRadius="10">
        <Grid Margin="-10,-10,-10,-10">
            <!--  Title in Top-Left Corner  -->
            <DockPanel
                Margin="10,5,0,0"
                HorizontalAlignment="Left"
                VerticalAlignment="Top">
                <!--  Icon  -->
                <TextBlock
                    Margin="0,-2,5,0"
                    FontFamily="Segoe UI Emoji"
                    FontSize="18"
                    Foreground="White"
                    Text="&#x1F680;" />
                <!--  Program Name  -->
                <TextBlock
                    FontFamily="Helvetica Neue"
                    FontSize="18"
                    FontWeight="Light"
                    Foreground="White">
					<Run Text="Rocket "/>
					<Run
                        FontSize="12"
                        FontStyle="Italic"
                        Foreground="Gray"
                        Text="by Red" />
                </TextBlock>
            </DockPanel>
            <!--  Close Button in Top-Right Corner  -->
            <DockPanel HorizontalAlignment="Right" VerticalAlignment="Top">
                <Button
                    x:Name="CloseButton"
                    Width="28"
                    Height="28"
                    Background="Transparent"
                    Content="&#xE10A;"
                    FontFamily="Segoe MDL2 Assets"
                    FontSize="12"
                    FontWeight="ExtraLight"
                    Foreground="White">
                    <WindowChrome.IsHitTestVisibleInChrome>True</WindowChrome.IsHitTestVisibleInChrome>
                    <Button.Template>
                        <ControlTemplate TargetType="Button">
                            <Border
                                x:Name="border"
                                Background="Transparent"
                                BorderBrush="Transparent"
                                BorderThickness="1"
                                CornerRadius="0,10,0,0">
                                <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center" />
                            </Border>
                            <ControlTemplate.Triggers>
                                <!--  Change background and border on hover  -->
                                <Trigger Property="IsMouseOver" Value="True">
                                    <Setter TargetName="border" Property="Background" Value="Red" />
                                    <Setter TargetName="border" Property="BorderBrush" Value="Red" />
                                    <!--  Visible border on hover  -->
                                </Trigger>
                                <Trigger Property="IsPressed" Value="True">
                                    <Setter TargetName="border" Property="Background" Value="DarkRed" />
                                </Trigger>
                            </ControlTemplate.Triggers>
                        </ControlTemplate>
                    </Button.Template>
                </Button>
            </DockPanel>
            <StackPanel x:Name="NavigationPanel" 
          Orientation="Vertical" 
          HorizontalAlignment="Left" 
          VerticalAlignment="Top" 
          Margin="10,56,0,0">
                <!-- Top Navigation Buttons -->
                <Button x:Name="SoftwareAppsNavButton" 
            Style="{StaticResource NavigationButtonStyle}" 
            Tag="&#x1F4BF;"
            Margin="0,0,0,10"
            Content="Software &amp; Apps"/>

                <Button x:Name="OptimizeNavButton"
            Style="{StaticResource NavigationButtonStyle}" 
            Tag="&#x1F680;"
            Margin="0,0,0,10"
            Content="Optimize"/>

                <Button x:Name="CustomizeNavButton"
            Style="{StaticResource NavigationButtonStyle}" 
            Tag="&#x1F3A8;"
            Margin="0,0,0,10"
            Content="Customize"/>

                <!-- Fixed spacer -->
                <Rectangle Height="235" Fill="Transparent"/>

                <!-- About Button -->
                <Button x:Name="AboutNavButton"
            Style="{StaticResource NavigationButtonStyle}" 
            Tag="&#xE946;" 
            FontFamily="Segoe MDL2 Assets"
            Margin="0,0,0,10"
            Content="About" />
            </StackPanel>
            <!-- Software and Apps Screen -->
            <StackPanel x:Name="SoftAppsScreen" Width="943" Height="550" HorizontalAlignment="Left" VerticalAlignment="Top" Margin="93,56,0,0" Visibility="Collapsed">
                <!-- Header -->
                <DockPanel HorizontalAlignment="Left" VerticalAlignment="Center">
                    <TextBlock Width="80" Height="70" Margin="0,0,0,0" DockPanel.Dock="Left" FontFamily="Segoe UI Emoji" FontSize="60" Foreground="White" Text="&#x1F4BF;"  LineHeight="70" LineStackingStrategy="BlockLineHeight" />
                    <StackPanel VerticalAlignment="Center">
                        <TextBlock Height="35" VerticalAlignment="Top" FontFamily="Helvetica Neue" FontSize="32" FontWeight="Bold" Foreground="White" Text="Software &amp; Apps" />
                        <TextBlock x:Name="SoftAppsStatusText" Height="22" Margin="0,5,0,0" VerticalAlignment="Bottom" FontFamily="Helvetica Neue" FontSize="14" Foreground="DarkGray" Text="Manage software installation and removal" />
                    </StackPanel>
                </DockPanel>

                <!-- Main Content -->
                <Border x:Name="SoftAppsMainContentBorder" Margin="0,5,0,0" Background="#303030" CornerRadius="10" Height="470">
                    <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
                        <StackPanel Margin="10">
                            <!-- Install Software Section -->
                            <StackPanel>
                                <Border x:Name="InstallSoftwareHeader" Background="#202020" CornerRadius="5" Margin="0,5,0,5" Effect="{StaticResource ShadowEffect}">
                                    <DockPanel VerticalAlignment="Center" HorizontalAlignment="Stretch">
                                        <TextBlock Text="Install Software" HorizontalAlignment="Left" VerticalAlignment="Center" FontSize="18" FontWeight="Bold" Foreground="White" Padding="10" DockPanel.Dock="Left" />
                                        <TextBlock Text="&#xE70D;" FontFamily="Segoe MDL2 Assets" HorizontalAlignment="Right" VerticalAlignment="Center" FontSize="16" Foreground="White" Padding="10" DockPanel.Dock="Right" />
                                    </DockPanel>
                                </Border>
                                <Border Background="#202020" CornerRadius="5" Margin="5,0,5,5">
                                    <StackPanel x:Name="InstallSoftwareContent" Margin="0,10,0,10" Visibility="Collapsed">
                                        <Grid Margin="10,5">
                                            <Grid.ColumnDefinitions>
                                                <ColumnDefinition Width="*" />
                                                <ColumnDefinition Width="Auto" />
                                            </Grid.ColumnDefinitions>
                                            <TextBlock Text="Microsoft Store" VerticalAlignment="Center" Foreground="White" FontSize="14" Margin="10,0,0,0" Grid.Column="0" />
                                            <Button Style="{StaticResource PrimaryButtonStyle}" Content="Install" Width="80" Height="30" HorizontalAlignment="Right" Grid.Column="1" x:Name="InstallStore" />
                                        </Grid>
                                        <Grid Margin="10,5">
                                            <Grid.ColumnDefinitions>
                                                <ColumnDefinition Width="*" />
                                                <ColumnDefinition Width="Auto" />
                                            </Grid.ColumnDefinitions>
                                            <TextBlock Text="UniGetUI" VerticalAlignment="Center" Foreground="White" FontSize="14" Margin="10,0,0,0" Grid.Column="0" />
                                            <Button Style="{StaticResource PrimaryButtonStyle}" Content="Install" Width="80" Height="30" HorizontalAlignment="Right" Grid.Column="1" x:Name="InstallUniGetUI" />
                                        </Grid>
                                        <Grid Margin="10,5">
                                            <Grid.ColumnDefinitions>
                                                <ColumnDefinition Width="*" />
                                                <ColumnDefinition Width="Auto" />
                                            </Grid.ColumnDefinitions>
                                            <TextBlock Text="Thorium Browser" VerticalAlignment="Center" Foreground="White" FontSize="14" Margin="10,0,0,0" Grid.Column="0" />
                                            <Button Style="{StaticResource PrimaryButtonStyle}" Content="Install" Width="80" Height="30" HorizontalAlignment="Right" Grid.Column="1" x:Name="InstallThorium" />
                                        </Grid>
                                        <Grid Margin="10,5">
                                            <Grid.ColumnDefinitions>
                                                <ColumnDefinition Width="*" />
                                                <ColumnDefinition Width="Auto" />
                                            </Grid.ColumnDefinitions>
                                            <TextBlock Text="Firefox" VerticalAlignment="Center" Foreground="White" FontSize="14" Margin="10,0,0,0" Grid.Column="0" />
                                            <Button Style="{StaticResource PrimaryButtonStyle}" Content="Install" Width="80" Height="30" HorizontalAlignment="Right" Grid.Column="1" x:Name="InstallFirefox" />
                                        </Grid>
                                        <Grid Margin="10,5">
                                            <Grid.ColumnDefinitions>
                                                <ColumnDefinition Width="*" />
                                                <ColumnDefinition Width="Auto" />
                                            </Grid.ColumnDefinitions>
                                            <TextBlock Text="Chrome" VerticalAlignment="Center" Foreground="White" FontSize="14" Margin="10,0,0,0" Grid.Column="0" />
                                            <Button Style="{StaticResource PrimaryButtonStyle}" Content="Install" Width="80" Height="30" HorizontalAlignment="Right" Grid.Column="1" x:Name="InstallChrome" />
                                        </Grid>
                                        <Grid Margin="10,5">
                                            <Grid.ColumnDefinitions>
                                                <ColumnDefinition Width="*" />
                                                <ColumnDefinition Width="Auto" />
                                            </Grid.ColumnDefinitions>
                                            <TextBlock Text="Brave" VerticalAlignment="Center" Foreground="White" FontSize="14" Margin="10,0,0,0" Grid.Column="0" />
                                            <Button Style="{StaticResource PrimaryButtonStyle}" Content="Install" Width="80" Height="30" HorizontalAlignment="Right" Grid.Column="1" x:Name="InstallBrave" />
                                        </Grid>
                                        <Grid Margin="10,5">
                                            <Grid.ColumnDefinitions>
                                                <ColumnDefinition Width="*" />
                                                <ColumnDefinition Width="Auto" />
                                            </Grid.ColumnDefinitions>
                                            <TextBlock Text="Microsoft Edge" VerticalAlignment="Center" Foreground="White" FontSize="14" Margin="10,0,0,0" Grid.Column="0" />
                                            <Button Style="{StaticResource PrimaryButtonStyle}" Content="Install" Width="80" Height="30" HorizontalAlignment="Right" Grid.Column="1" x:Name="InstallEdge" />
                                        </Grid>
                                        <Grid Margin="10,5">
                                            <Grid.ColumnDefinitions>
                                                <ColumnDefinition Width="*" />
                                                <ColumnDefinition Width="Auto" />
                                            </Grid.ColumnDefinitions>
                                            <TextBlock Text="Microsoft Edge WebView" VerticalAlignment="Center" Foreground="White" FontSize="14" Margin="10,0,0,0" Grid.Column="0" />
                                            <Button Style="{StaticResource PrimaryButtonStyle}" Content="Install" Width="80" Height="30" HorizontalAlignment="Right" Grid.Column="1" x:Name="InstallEdgeWebView" />
                                        </Grid>
                                        <Grid Margin="10,5">
                                            <Grid.ColumnDefinitions>
                                                <ColumnDefinition Width="*" />
                                                <ColumnDefinition Width="Auto" />
                                            </Grid.ColumnDefinitions>
                                            <TextBlock Text="Microsoft OneDrive" VerticalAlignment="Center" Foreground="White" FontSize="14" Margin="10,0,0,0" Grid.Column="0" />
                                            <Button Style="{StaticResource PrimaryButtonStyle}" Content="Install" Width="80" Height="30" HorizontalAlignment="Right" Grid.Column="1" x:Name="InstallOneDrive" />
                                        </Grid>
                                        <Grid Margin="10,5">
                                            <Grid.ColumnDefinitions>
                                                <ColumnDefinition Width="*" />
                                                <ColumnDefinition Width="Auto" />
                                            </Grid.ColumnDefinitions>
                                            <TextBlock Text="Xbox App for Windows" VerticalAlignment="Center" Foreground="White" FontSize="14" Margin="10,0,0,0" Grid.Column="0" />
                                            <Button Style="{StaticResource PrimaryButtonStyle}" Content="Install" Width="80" Height="30" HorizontalAlignment="Right" Grid.Column="1" x:Name="InstallXbox" />
                                        </Grid>
                                    </StackPanel>
                                </Border>
                            </StackPanel>
                            <!-- Remove Windows Apps Section -->
                            <StackPanel>
                                <Border x:Name="RemoveAppsHeader" Background="#202020" CornerRadius="5" Margin="0,5,0,5" Effect="{StaticResource ShadowEffect}">
                                    <DockPanel VerticalAlignment="Center" HorizontalAlignment="Stretch">
                                        <TextBlock Text="Remove Windows Apps" HorizontalAlignment="Left" VerticalAlignment="Center" FontSize="18" FontWeight="Bold" Foreground="White" Padding="10" DockPanel.Dock="Left" />
                                        <TextBlock Text="&#xE70D;" FontFamily="Segoe MDL2 Assets" HorizontalAlignment="Right" VerticalAlignment="Center" FontSize="16" Foreground="White" Padding="10" DockPanel.Dock="Right" />
                                    </DockPanel>
                                </Border>
                                <Border Background="#202020" CornerRadius="5" Margin="5,0,5,5">
                                    <StackPanel x:Name="RemoveAppsContent" Margin="0,10,0,10">
                                        <!-- Add a dedicated container for the dynamic checkboxes -->
                                        <StackPanel x:Name="chkPanel" Margin="0,0,0,10"></StackPanel>
                                    </StackPanel>
                                </Border>
                            </StackPanel>

                        </StackPanel>
                    </ScrollViewer>
                </Border>
            </StackPanel>
            <!-- Optimize Screen -->
            <StackPanel x:Name="OptimizeScreen" Width="943" Height="550" HorizontalAlignment="Left" VerticalAlignment="Top" Margin="93,56,0,0" Visibility="Collapsed">
                <!-- Header -->
                <DockPanel HorizontalAlignment="Left" VerticalAlignment="Center">
                    <TextBlock Width="80" Height="70" Margin="0,0,0,0" DockPanel.Dock="Left" FontFamily="Segoe UI Emoji" FontSize="60" Foreground="White" Text="&#x1F680;"  LineHeight="70" LineStackingStrategy="BlockLineHeight" />
                    <StackPanel VerticalAlignment="Center">
                        <TextBlock Height="35" VerticalAlignment="Top" FontFamily="Helvetica Neue" FontSize="32" FontWeight="Bold" Foreground="White" Text="Optimizations" />
                        <DockPanel LastChildFill="False" Width="861">
                            <TextBlock x:Name="OptimizeStatusText" Height="22" DockPanel.Dock="Left" VerticalAlignment="Bottom" FontFamily="Helvetica Neue" FontSize="14" Foreground="DarkGray" Text="Optimize your system settings and performance" />
                            <Button x:Name="OptimizeDefaultsButton" DockPanel.Dock="Right" Style="{StaticResource PrimaryButtonStyle}" Content="Defaults" Width="80" Height="30" Margin="0,0,5,0"/>
                            <Button x:Name="OptimizeApplyButton" DockPanel.Dock="Right" Style="{StaticResource PrimaryButtonStyle}" Content="Apply" Width="80" Height="30" Margin="0,0,10,0"/>
                        </DockPanel>
                    </StackPanel>
                </DockPanel>
                <!-- Main Content -->
                <Border x:Name="OptimizeMainContentBorder" Margin="0,5,0,0" Background="#303030" CornerRadius="10" Height="470">
                    <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
                        <StackPanel Margin="10">
                            <Border x:Name="WindowsSecurityHeaderBorder" Background="#202020" CornerRadius="5" Margin="0,5,0,5" Effect="{StaticResource ShadowEffect}">
                                <DockPanel VerticalAlignment="Center" HorizontalAlignment="Stretch">
                                    <TextBlock Text="Windows Security Settings" HorizontalAlignment="Left" VerticalAlignment="Center" FontSize="18" FontWeight="Bold" Foreground="White" Padding="10" DockPanel.Dock="Left" />
                                    <TextBlock Text="&#xE70D;" FontFamily="Segoe MDL2 Assets" HorizontalAlignment="Right" VerticalAlignment="Center" FontSize="16" Foreground="White" Padding="10" DockPanel.Dock="Right" />
                                </DockPanel>
                            </Border>

                            <!-- Windows Security Section -->
                            <Border Background="#202020" CornerRadius="5" Margin="5,0,5,5">
                                <StackPanel x:Name="WindowsSecurityContent" Margin="0,10,0,10" Visibility="Collapsed">
                                    <!-- UAC Notification Level Section -->
                                    <Grid Margin="10,0,0,10">
                                        <Grid.ColumnDefinitions>
                                            <ColumnDefinition Width="*"/>
                                            <ColumnDefinition Width="Auto"/>
                                        </Grid.ColumnDefinitions>

                                        <!-- Left: Title -->
                                        <StackPanel Orientation="Vertical" VerticalAlignment="Top">
                                            <TextBlock 
                                Text="UAC Notification Level (Recommended: Low)" 
                                Foreground="White" 
                                FontSize="14" 
                                Margin="25,0,0,0"/>
                                            <TextBlock 
                                x:Name="UACSliderValue" 
                                Text="Current: Low" 
                                Foreground="#FFDE00" 
                                FontSize="14" 
                                Margin="25,5,0,0"/>
                                        </StackPanel>

                                        <!-- Right: Slider -->
                                        <StackPanel Grid.Column="1" Margin="10,0">
                                            <!-- Tick Labels -->
                                            <Grid Margin="0,0,0,5">
                                                <Grid.ColumnDefinitions>
                                                    <ColumnDefinition Width="*"/>
                                                    <ColumnDefinition Width="*"/>
                                                    <ColumnDefinition Width="*"/>
                                                </Grid.ColumnDefinitions>
                                                <TextBlock Text="Low" Foreground="White" HorizontalAlignment="Left"/>
                                                <TextBlock Text="Moderate" Foreground="White" Grid.Column="1" HorizontalAlignment="Center"/>
                                                <TextBlock Text="High" Foreground="White" Grid.Column="2" HorizontalAlignment="Right"/>
                                            </Grid>

                                            <!-- Slider Control -->
                                            <Slider x:Name="UACSlider" 
                                Style="{StaticResource UACSliderStyle}"
                                Minimum="0"
                                Maximum="2"
                                TickFrequency="1"/>
                                        </StackPanel>
                                    </Grid>

                                    <!-- Windows Security Suite Section -->
                                    <Grid Margin="10,0">
                                        <Grid.ColumnDefinitions>
                                            <ColumnDefinition Width="*" />
                                            <ColumnDefinition Width="Auto" />
                                        </Grid.ColumnDefinitions>

                                        <!-- Left: Label with Tooltip -->
                                        <StackPanel Orientation="Horizontal" VerticalAlignment="Center" Margin="0,0,40,0">
                                            <TextBlock Style="{StaticResource HelpIconStyle}" Margin="0,0,10,0">
                                                <TextBlock.ToolTip>
                                                    <ToolTip Style="{StaticResource CustomTooltipStyle}">
                                                        <TextBlock>
                                             Enabled:
 <LineBreak/>                                           
 Windows Security Defaults (Recommended)
 <LineBreak/><LineBreak/>
 Disabled:
 <LineBreak/>
 All Windows Security Removed (Not Recommended):
 <LineBreak/>
 - Defender Windows Security Settings
 <LineBreak/>
 - Smartscreen
 <LineBreak/>
 - Defender Services
 <LineBreak/>
 - Defender Drivers
 <LineBreak/>
 - Windows Defender Firewall
 <LineBreak/>
 - Spectre Meltdown
 <LineBreak/>
 - Data Execution Prevention
 <LineBreak/>
 - Open File Security Warning
 <LineBreak/>
 - Windows Defender Default Definitions
 <LineBreak/>
 - Windows Defender Applicationguard
 <LineBreak/><LineBreak/>
 This will leave the PC completely vulnerable.
                                                        </TextBlock>
                                                    </ToolTip>
                                                </TextBlock.ToolTip>
                            </TextBlock>
                                            <TextBlock
                                Text="Windows Security Suite"
                                VerticalAlignment="Center"
                                Foreground="White"
                                FontSize="14" />
                                        </StackPanel>

                                        <!-- Right: Buttons -->
                                        <StackPanel Grid.Column="1" Orientation="Horizontal">
                                            <Button
                                Style="{StaticResource PrimaryButtonStyle}"
                                Content="Enable"
                                Width="80"
                                Height="30"
                                Margin="10,0,20,0"
                                x:Name="EnableWindowsSecurityButton"/>

                                            <Button
                                Style="{StaticResource PrimaryButtonStyle}"
                                Content="Disable"
                                Width="80"
                                Height="30"
                                Margin="10,0,5,0"
                                x:Name="DisableWindowsSecurityButton"/>
                                        </StackPanel>
                                    </Grid>
                                </StackPanel>
                            </Border>

                            <!-- Select All Checkbox -->
                            <Border Background="#202020" CornerRadius="5" Margin="5,5,5,5">
                                <StackPanel Orientation="Horizontal" Margin="10">
                                    <CheckBox x:Name="OptimizeSelectAllCheckbox"
Content="Select All"
Style="{StaticResource CustomCheckBoxStyle}"
FontSize="14"
Margin="27,0,0,0"/>
                                </StackPanel>
                            </Border>
                            <!-- Privacy Settings -->
                            <Border Background="#202020" CornerRadius="5" Margin="5,5,5,5">
                                <StackPanel Orientation="Horizontal" Margin="10">
                                    <TextBlock Style="{StaticResource HelpIconStyle}" Margin="0,0,10,0">
                                        <TextBlock.ToolTip>
                                            <ToolTip Style="{StaticResource CustomTooltipStyle}">
                                                <TextBlock>
                                   Disables:
<LineBreak />- Activity History &amp; User Activity Tracking
<LineBreak />- Location Services &amp; Maps
<LineBreak />- Telemetry &amp; Diagnostic Data Collection
<LineBreak />- Feedback &amp; Error Reporting
<LineBreak />- Windows Ink Workspace
<LineBreak />- Advertising ID &amp; Personalized Ads
<LineBreak />- Account Info &amp; Notifications
<LineBreak />- Language &amp; Input Data Collection
<LineBreak />- Speech Recognition
<LineBreak />- Inking &amp; Typing Data Collection
<LineBreak />- Remote Assistance
<LineBreak />- Device Metadata Collection
<LineBreak />- Windows Consumer Features
<LineBreak />- Background Apps
<LineBreak />- Cortana
<LineBreak />- WiFi Sense Features
<LineBreak />- Automatic Maintenance
<LineBreak />- Push to Install
<LineBreak />- Ads &amp; Promotional Content
<LineBreak />- Lock Screen Features &amp; Slideshows
<LineBreak />- Automatic Bitlocker Drive Encryption
<LineBreak />- TCG security device activation
<LineBreak />- Automatic restart sign-on
                                                </TextBlock>
                                            </ToolTip>
                                        </TextBlock.ToolTip>
                    </TextBlock>
                                    <CheckBox x:Name="PrivacyCheckBox"
                             Content="Privacy Settings"
                             Style="{StaticResource CustomCheckBoxStyle}"
                             FontSize="14"/>
                                </StackPanel>
                            </Border>

                            <!-- Gaming Optimizations -->
                            <Border Background="#202020" CornerRadius="5" Margin="5,5,5,5">
                                <StackPanel Orientation="Horizontal" Margin="10">
                                    <TextBlock Style="{StaticResource HelpIconStyle}" Margin="0,0,10,0">
                                        <TextBlock.ToolTip>
                                            <ToolTip Style="{StaticResource CustomTooltipStyle}">
                                                <TextBlock>
                                 - Enables Game Mode
<LineBreak />- Disables Game Bar &amp; Game DVR
<LineBreak />- Disables opening Xbox Game Bar using a controller
<LineBreak />- Disables variable refresh rate
<LineBreak />- Enables optimizations for windowed games
<LineBreak />- Enables old Nvidia sharpening
<LineBreak />- Improves system responsiveness for multimedia apps
<LineBreak />- Adjusts network for better gaming performance
<LineBreak />- Increases CPU &amp; GPU priority for gaming
<LineBreak />- Sets scheduling category to High for games
<LineBreak />- Enables hardware-accelerated GPU scheduling
<LineBreak />- Adjusts Win32 priority separation for best performance
<LineBreak />- Disables Storage Sense
                                                </TextBlock>
                                            </ToolTip>
                                        </TextBlock.ToolTip>
                    </TextBlock>
                                    <CheckBox x:Name="GamingOptimizationsCheckBox"
                             Content="Gaming Optimizations"
                             Style="{StaticResource CustomCheckBoxStyle}"
                             FontSize="14"/>
                                </StackPanel>
                            </Border>

                            <!-- Windows Updates -->
                            <Border Background="#202020" CornerRadius="5" Margin="5,5,5,5">
                                <StackPanel Orientation="Horizontal" Margin="10">
                                    <TextBlock Style="{StaticResource HelpIconStyle}" Margin="0,0,10,0">
                                        <TextBlock.ToolTip>
                                            <ToolTip Style="{StaticResource CustomTooltipStyle}">
                                                <TextBlock>
                                    Disables:
<LineBreak />- Automatic Updates
<LineBreak />- Delays Feature Updates (365 days)
<LineBreak />- Delays Security Updates (7 days)
<LineBreak />- Automatic Upgrade from Win10 to Win11
<LineBreak />- Delivery Optimization
<LineBreak />- Auto updates for Store apps
<LineBreak />- Auto archiving of unused apps
                                                </TextBlock>
                                            </ToolTip>
                                        </TextBlock.ToolTip>
                    </TextBlock>
                                    <CheckBox x:Name="WindowsUpdatesCheckBox"
                             Content="Windows Updates"
                             Style="{StaticResource CustomCheckBoxStyle}"
                             FontSize="14"/>
                                </StackPanel>
                            </Border>

                            <!-- Power Settings -->
                            <Border Background="#202020" CornerRadius="5" Margin="5,5,5,5">
                                <StackPanel Orientation="Horizontal" Margin="10">
                                    <TextBlock Style="{StaticResource HelpIconStyle}" Margin="0,0,10,0">
                                        <TextBlock.ToolTip>
                                            <ToolTip Style="{StaticResource CustomTooltipStyle}">
                                                <TextBlock>
                                    - Ultimate Power Plan (Max Performance)
<LineBreak />- Disables Hibernate, Sleep, and Fast Boot
<LineBreak />- Unparks CPU Cores
<LineBreak />- Disables Power Throttling
<LineBreak />- USB Selective Suspend Disabled
<LineBreak />- PCI Express Link State Power Management Off
<LineBreak />- Processor State Always at 100%
<LineBreak />- Display Always On, Brightness at 100%
<LineBreak />- Battery Saver Disabled
<LineBreak />- Critical Battery Actions Disabled
                                                </TextBlock>
                                            </ToolTip>
                                        </TextBlock.ToolTip>
                    </TextBlock>
                                    <CheckBox x:Name="PowerSettingsCheckBox"
                             Content="Power Settings"
                             Style="{StaticResource CustomCheckBoxStyle}"
                             FontSize="14"/>
                                </StackPanel>
                            </Border>

                            <!-- Tasks -->
                            <Border Background="#202020" CornerRadius="5" Margin="5,5,5,5">
                                <StackPanel Orientation="Horizontal" Margin="10">
                                    <TextBlock Style="{StaticResource HelpIconStyle}" Margin="0,0,10,0">
                                        <TextBlock.ToolTip>
                                            <ToolTip Style="{StaticResource CustomTooltipStyle}">
                                                <TextBlock>
Configures:
<LineBreak />- Windows Compatibility Appraiser
<LineBreak />- Program Compatibility Database Updater
<LineBreak />- Sync Database Merge Task
<LineBreak />- Customer Experience Improvement Program Consolidator
<LineBreak />- USB Customer Experience Improvement
<LineBreak />- Usage Data Flushing
<LineBreak />- Usage Data Reporting
<LineBreak />- Windows Feedback Client
<LineBreak />- Windows Feedback Client Download
<LineBreak />- Maps Toast Notifications
<LineBreak />- Maps Update Task
<LineBreak />- Family Safety Monitor
<LineBreak />- Family Safety Refresh
<LineBreak />- Windows Search Indexer Maintenance
<LineBreak />- Xbox Game Save Task
<LineBreak />- Work Folders Logon Sync
<LineBreak />- Work Folders Maintenance
<LineBreak />- Windows Media Library Update
<LineBreak />- Wireless WAN Notifications
<LineBreak />- Wireless WAN Discovery
<LineBreak />- Windows Error Reporting
<LineBreak />- Office Automatic Updates
<LineBreak />- Office ClickToRun Monitor
<LineBreak />- Office Telemetry Agent Fallback
<LineBreak />- Office Telemetry Agent Logon
<LineBreak />- Windows Diagnostic Task
<LineBreak />- Disk Diagnostic Data Collector
<LineBreak />- Red Diagnostic Events
<LineBreak />- Power Efficiency Analysis
<LineBreak />- Disk Check Proxy
<LineBreak />- Scheduled Disk Defragmentation
<LineBreak />- Remote Assistance Task
<LineBreak />- Force Time Synchronization
<LineBreak />- Update Policy Reporting
<LineBreak />- Windows Update Scan
<LineBreak />- Windows Update Scheduled Start
<LineBreak />- Windows Update Remediation
<LineBreak />- Windows Update Scanner
<LineBreak />- User Update Scanner
<LineBreak />- Disk Footprint Diagnostics
<LineBreak />- File History Maintenance
<LineBreak />- Windows SQM Tasks
<LineBreak />- Program Data Updater
<LineBreak />- Mare Backup Task
<LineBreak />- Location Dialog
<LineBreak />- Location Notifications
<LineBreak />- Mobile Broadband Parser
<LineBreak />- Device Metadata Refresh
<LineBreak />- Language Settings Sync
<LineBreak />- Retail Demo Cleanup
<LineBreak />- Push Install Login Check
<LineBreak />- Push Install Registration
<LineBreak />- SmartScreen Specific Task
<LineBreak />- Startup Application Task
<LineBreak />- Cloud Experience Object
<LineBreak />- Windows Hello Cleanup
<LineBreak />- License Acquisition Task
<LineBreak />- Update Notification Manager
                                                </TextBlock>
                                            </ToolTip>
                                        </TextBlock.ToolTip>
                    </TextBlock>
                                    <CheckBox x:Name="TasksCheckBox"
                             Content="Scheduled Tasks"
                             Style="{StaticResource CustomCheckBoxStyle}"
                             FontSize="14"/>
                                </StackPanel>
                            </Border>

                            <!-- Services -->
                            <Border Background="#202020" CornerRadius="5" Margin="5,5,5,5">
                                <StackPanel Orientation="Horizontal" Margin="10">
                                    <TextBlock Style="{StaticResource HelpIconStyle}" Margin="0,0,10,0">
                                        <TextBlock.ToolTip>
                                            <ToolTip Style="{StaticResource CustomTooltipStyle}">
                                                <TextBlock>
Disables:
<LineBreak />- AllJoyn Router Service
<LineBreak />- Application Virtualization Client
<LineBreak />- Assigned Access Manager Service
<LineBreak />- Connected User Experiences and Telemetry
<LineBreak />- Dialog Blocking Service
<LineBreak />- Net.Tcp Port Sharing Service
<LineBreak />- Remote Access Connection Manager
<LineBreak />- Remote Registry Service
<LineBreak />- User Experience Virtualization Service
<LineBreak />- Shared Protection Access Manager
<LineBreak />- OpenSSH Authentication Agent
<LineBreak />- Auto Time Zone Updater
<LineBreak />- Microsoft Update Health Service
<LineBreak />
<LineBreak />Sets other services to "Manual" where allowed.
                                                </TextBlock>
                                            </ToolTip>
                                        </TextBlock.ToolTip>
                    </TextBlock>
                                    <CheckBox x:Name="ServicesCheckBox"
                             Content="Windows Services"
                             Style="{StaticResource CustomCheckBoxStyle}"
                             FontSize="14"/>
                                </StackPanel>
                            </Border>
                        </StackPanel>
                    </ScrollViewer>
                </Border>
            </StackPanel>

            <!-- Customize Screen -->
            <StackPanel x:Name="CustomizeScreen" Width="943" Height="550" HorizontalAlignment="Left" VerticalAlignment="Top" Margin="93,56,0,0" >
                <!-- Header -->
                <DockPanel HorizontalAlignment="Left" VerticalAlignment="Center">
                    <TextBlock Width="80" Height="70" Margin="0,0,0,0" DockPanel.Dock="Left" FontFamily="Segoe UI Emoji" FontSize="60" Foreground="White" Text="&#x1F3A8;"  LineHeight="70" LineStackingStrategy="BlockLineHeight" />
                    <StackPanel VerticalAlignment="Center">
                        <TextBlock Height="35" VerticalAlignment="Top" FontFamily="Helvetica Neue" FontSize="32" FontWeight="Bold" Foreground="White" Text="Customize" />
                        <DockPanel LastChildFill="False" Width="861">
                            <TextBlock x:Name="CustomizeStatusText" Height="22" DockPanel.Dock="Left" VerticalAlignment="Bottom" FontFamily="Helvetica Neue" FontSize="14" Foreground="DarkGray" Text="Customize your system's appearance and behavior" />
                            <Button x:Name="CustomizeDefaultsButton" DockPanel.Dock="Right" Style="{StaticResource PrimaryButtonStyle}" Content="Defaults" Width="80" Height="30" Margin="0,0,5,0"/>
                            <Button x:Name="CustomizeApplyButton" DockPanel.Dock="Right" Style="{StaticResource PrimaryButtonStyle}" Content="Apply" Width="80" Height="30" Margin="0,0,10,0"/>
                        </DockPanel>
                    </StackPanel>
                </DockPanel>

                <!-- Main Content -->
                <Border x:Name="CustomizeMainContentBorder" Margin="0,5,0,0" Background="#303030" CornerRadius="10" Height="470">
                    <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
                        <StackPanel Margin="10">
                            <!-- Theme Settings -->
                            <Border Background="#202020" CornerRadius="5" Margin="5,5,5,5">
                                <StackPanel Margin="10">
                                    <!-- Dark Mode -->
                                    <Grid>
                                        <Grid.ColumnDefinitions>
                                            <ColumnDefinition Width="*" />
                                            <ColumnDefinition Width="Auto" />
                                        </Grid.ColumnDefinitions>

                                        <StackPanel Orientation="Horizontal">
                                            <TextBlock 
            Text="&#xE793;"
            FontFamily="Segoe MDL2 Assets"
            VerticalAlignment="Center" 
            Foreground="White" 
            FontSize="20"
            Margin="25,0,0,0" />
                                            <TextBlock 
            Text="Dark Mode" 
            VerticalAlignment="Center" 
            Foreground="White" 
            FontSize="14" 
            Margin="8,0,0,0" />
                                        </StackPanel>
                                        <Slider x:Name="DarkModeSlider" 
                   Style="{StaticResource ToggleSliderStyle}" 
                   Grid.Column="1"
                   HorizontalAlignment="Right"/>
                                    </Grid>
                                </StackPanel>
                            </Border>

                            <!-- Select All Checkbox -->
                            <Border Background="#202020" CornerRadius="5" Margin="5,5,5,5">
                                <StackPanel Orientation="Horizontal" Margin="10">
                                    <CheckBox x:Name="CustomizeSelectAllCheckbox"
                 Content="Select All"
                 Style="{StaticResource CustomCheckBoxStyle}"
                 FontSize="14"
                 Margin="27,0,0,0"/>
                                </StackPanel>
                            </Border>
                            <!-- Taskbar Section -->
                            <Border Background="#202020" CornerRadius="5" Margin="5,5,5,5">
                                <StackPanel Orientation="Horizontal" Margin="10">
                                    <TextBlock Style="{StaticResource HelpIconStyle}" Margin="0,0,10,0">
                                        <TextBlock.ToolTip>
                                            <ToolTip Style="{StaticResource CustomTooltipStyle}">
                                                <TextBlock>
- Hides Windows Chat icon
<LineBreak />- Disables News and Interests feed
<LineBreak />- Hides Meet Now button
<LineBreak />- Hides Task View button
<LineBreak />- Disables system tray auto-hide
<LineBreak />- Clears frequently used programs list
<LineBreak />- Hides Copilot button
<LineBreak />- Left-aligns taskbar icons
                                                </TextBlock>
                                            </ToolTip>
                                        </TextBlock.ToolTip>
                        </TextBlock>
                                    <CheckBox x:Name="TaskbarCheckBox"
                                 Content="Taskbar"
                                 Style="{StaticResource CustomCheckBoxStyle}"
                                 FontSize="14"/>
                                </StackPanel>
                            </Border>

                            <!-- Start Menu Section -->
                            <Border Background="#202020" CornerRadius="5" Margin="5,5,5,5">
                                <StackPanel Orientation="Horizontal" Margin="10">
                                    <TextBlock Style="{StaticResource HelpIconStyle}" Margin="0,0,10,0">
                                        <TextBlock.ToolTip>
                                            <ToolTip Style="{StaticResource CustomTooltipStyle}">
                                                <TextBlock>
                                        - Removes all pinned apps
<LineBreak />- Sets "More Pins" layout (less recommended)
                                                </TextBlock>
                                            </ToolTip>
                                        </TextBlock.ToolTip>
                        </TextBlock>
                                    <CheckBox x:Name="StartMenuCheckBox"
                                 Content="Start Menu"
                                 Style="{StaticResource CustomCheckBoxStyle}"
                                 FontSize="14"/>
                                </StackPanel>
                            </Border>

                            <!-- Explorer Section -->
                            <Border Background="#202020" CornerRadius="5" Margin="5,5,5,5">
                                <StackPanel Orientation="Horizontal" Margin="10">
                                    <TextBlock Style="{StaticResource HelpIconStyle}" Margin="0,0,10,0">
                                        <TextBlock.ToolTip>
                                            <ToolTip Style="{StaticResource CustomTooltipStyle}">
                                                <TextBlock>
                                        - Enables long file paths (32,767 chars)
<LineBreak />- Disables Windows Spotlight wallpaper feature
<LineBreak />- Blocks "Allow my organization to manage my device" pop-up
<LineBreak />- Removes 3D Objects and Home Folder
<LineBreak />- Opens File Explorer to "This PC"
<LineBreak />- Shows file name extensions
<LineBreak />- Disables folder tips and pop-up descriptions
<LineBreak />- Disables preview handlers and status bar
<LineBreak />- Disables sync provider notifications
<LineBreak />- Disables sharing wizard
<LineBreak />- Disables taskbar animations
<LineBreak />- Shows thumbnails instead of icons
<LineBreak />- Disables translucent selection rectangle
<LineBreak />- Disables shadows for icon labels
<LineBreak />- Disables account-related notifications
<LineBreak />- Disables recently opened items in Start and File Explorer
<LineBreak />- Disables recommendations for tips and shortcuts
<LineBreak />- Disables snap assist and window animations
<LineBreak />- Sets Alt+Tab to show open windows only
<LineBreak />- Hides frequent folders in Quick Access
<LineBreak />- Disables files from Office.com in Quick Access
<LineBreak />- Enables full path in title bar
<LineBreak />- Disables enhance pointer precision (mouse fix)
<LineBreak />- Sets appearance options to custom
<LineBreak />- Disables animations and visual effects
<LineBreak />- Enables smooth edges of screen fonts
<LineBreak />- Disables menu show delay
<LineBreak />- Disables auto-capitalization and key sounds
<LineBreak />- Removes gallery from navigation pane
<LineBreak />- Restores classic context menu
<LineBreak />- Disables Tablet Mode &amp; always use Desktop Mode
<LineBreak />- Disables voice typing microphone button
<LineBreak />- Disables typing insights
<LineBreak />- Disables Clipboard suggested actions
<LineBreak />- Disables Windows managing default printer
                                                </TextBlock>
                                            </ToolTip>
                                        </TextBlock.ToolTip>
                        </TextBlock>
                                    <CheckBox x:Name="ExplorerCheckBox"
                                 Content="Explorer"
                                 Style="{StaticResource CustomCheckBoxStyle}"
                                 FontSize="14"/>
                                </StackPanel>
                            </Border>

                            <!-- Notifications Section -->
                            <Border Background="#202020" CornerRadius="5" Margin="5,5,5,5">
                                <StackPanel Orientation="Horizontal" Margin="10">
                                    <TextBlock Style="{StaticResource HelpIconStyle}" Margin="0,0,10,0">
                                        <TextBlock.ToolTip>
                                            <ToolTip Style="{StaticResource CustomTooltipStyle}">
                                                <TextBlock>
                                        Disables:
<LineBreak />- Notifications (Incl. Lock Screen)
<LineBreak />- Notification sounds
<LineBreak />- Security and maintenance notifications
<LineBreak />- Settings app notifications
<LineBreak />- Capability access notifications
<LineBreak />- Startup app notifications
<LineBreak />- Daylight saving time change notifications
                                                </TextBlock>
                                            </ToolTip>
                                        </TextBlock.ToolTip>
                        </TextBlock>
                                    <CheckBox x:Name="NotificationsCheckBox"
                                 Content="Notifications"
                                 Style="{StaticResource CustomCheckBoxStyle}"
                                 FontSize="14"/>
                                </StackPanel>
                            </Border>

                            <!-- Sound Section -->
                            <Border Background="#202020" CornerRadius="5" Margin="5,5,5,5">
                                <StackPanel Orientation="Horizontal" Margin="10">
                                    <TextBlock Style="{StaticResource HelpIconStyle}" Margin="0,0,10,0">
                                        <TextBlock.ToolTip>
                                            <ToolTip Style="{StaticResource CustomTooltipStyle}">
                                                <TextBlock>
                                        Disables: 
<LineBreak />- Startup sounds
<LineBreak />- Audio ducking
<LineBreak />- Voice activation for all apps
<LineBreak />- Last used voice activation setting
                                                </TextBlock>
                                            </ToolTip>
                                        </TextBlock.ToolTip>
                        </TextBlock>
                                    <CheckBox x:Name="SoundCheckBox"
                                 Content="Sound"
                                 Style="{StaticResource CustomCheckBoxStyle}"
                                 FontSize="14"/>
                                </StackPanel>
                            </Border>

                            <!-- Accessibility Section -->
                            <Border Background="#202020" CornerRadius="5" Margin="5,5,5,5">
                                <StackPanel Orientation="Horizontal" Margin="10">
                                    <TextBlock Style="{StaticResource HelpIconStyle}" Margin="0,0,10,0">
                                        <TextBlock.ToolTip>
                                            <ToolTip Style="{StaticResource CustomTooltipStyle}">
                                                <TextBlock>
                                        - Disables self voice and self scan features
<LineBreak />- Disables activation and warning sounds
<LineBreak />- Configures high contrast settings
<LineBreak />- Configures keyboard response settings
<LineBreak />- Sets auto-repeat rate and delay
<LineBreak />- Configures mouse keys settings and speed
<LineBreak />- Configures sticky keys and toggle keys
<LineBreak />- Disables sound sentry effects
<LineBreak />- Disables automatic launch of accessibility tools
<LineBreak />- Disables screen magnifier features
                                                </TextBlock>
                                            </ToolTip>
                                        </TextBlock.ToolTip>
                        </TextBlock>
                                    <CheckBox x:Name="AccessibilityCheckBox"
                                 Content="Accessibility"
                                 Style="{StaticResource CustomCheckBoxStyle}"
                                 FontSize="14"/>
                                </StackPanel>
                            </Border>

                            <!-- Search Section -->
                            <Border Background="#202020" CornerRadius="5" Margin="5,5,5,5">
                                <StackPanel Orientation="Horizontal" Margin="10">
                                    <TextBlock Style="{StaticResource HelpIconStyle}" Margin="0,0,10,0">
                                        <TextBlock.ToolTip>
                                            <ToolTip Style="{StaticResource CustomTooltipStyle}">
                                                <TextBlock>
                                        Disables: 
<LineBreak />- Search history &amp; highlights
<LineBreak />- Safe search
<LineBreak />- Cloud content search for work/school account
<LineBreak />- Cloud content search for Microsoft account
<LineBreak />- Disable web search in start menu
                                                </TextBlock>
                                            </ToolTip>
                                        </TextBlock.ToolTip>
                        </TextBlock>
                                    <CheckBox x:Name="SearchCheckBox"
                                 Content="Search"
                                 Style="{StaticResource CustomCheckBoxStyle}"
                                 FontSize="14"/>
                                </StackPanel>
                            </Border>

                        </StackPanel>
                    </ScrollViewer>
                </Border>
            </StackPanel>
            <!-- About Screen -->
            <StackPanel
    x:Name="AboutScreen"
    Width="943"
    Height="550"
    HorizontalAlignment="Left"
    VerticalAlignment="Top"
    Margin="93,56,0,0"
    Visibility="Collapsed">
                <!-- Header -->
                <DockPanel HorizontalAlignment="Left" VerticalAlignment="Center">
                    <!-- About Icon -->
                    <TextBlock
            Width="70"
            Height="70"
            Margin="0,0,10,0"
            DockPanel.Dock="Left"
            FontFamily="Segoe MDL2 Assets"
            FontSize="68"
            Foreground="White"
            Text="&#xE946;" />
                    <StackPanel VerticalAlignment="Center">
                        <TextBlock
                Height="35"
                VerticalAlignment="Top"
                FontFamily="Helvetica Neue"
                FontSize="32"
                FontWeight="Bold"
                Foreground="White"
                Text="About" />
                        <TextBlock
                x:Name="AboutStatusText"
                Height="22"
                Margin="0,5,0,0"
                VerticalAlignment="Bottom"
                FontFamily="Helvetica Neue"
                FontSize="14"
                Foreground="DarkGray"
                Text="Learn more about Rocket" />
                    </StackPanel>
                </DockPanel>
                <!-- Main Content -->
                <Border x:Name="AboutMainContentBorder"
        Margin="0,5,0,0"
        Background="#303030"
        CornerRadius="10"
        Height="470">
                    <Grid Margin="10,10,10,10">
                        <StackPanel>
                            <TextBlock
                    FontFamily="Helvetica Neue"
                    FontSize="16"
                    FontWeight="Bold"
                    Foreground="White"
                    Margin="10,10,0,10"
                    Text="Rocket" />
                            <TextBlock
    FontFamily="Helvetica Neue"
    FontSize="14"
    Foreground="LightGray"
    Margin="10,0,0,10">
    <Run Text="Rocket is a PowerShell GUI application designed to optimize and customize Windows 10 and 11 systems." />
    <LineBreak />
    <Run Text="It features tools for:" />
    <LineBreak />
    <Run Text="- Software installation" />
    <LineBreak />
    <Run Text="- Bloatware removal" />
    <LineBreak />
    <Run Text="- Privacy and security enhancements" />
    <LineBreak />
    <Run Text="- Windows update settings" />
    <LineBreak />
    <Run Text="- Power settings adjustments" />
    <LineBreak />
    <Run Text="- Registry tweaks" />
    <LineBreak />
    <Run Text="- General PC optimizations" />
                            </TextBlock>
                            <TextBlock
                    FontFamily="Helvetica Neue"
                    FontSize="14"
                    Foreground="LightGray"
                    Margin="10,10,0,10"
                    Text="Version: 1.0" />
                            <TextBlock
                    FontFamily="Helvetica Neue"
                    FontSize="14"
                    Foreground="LightGray"
                    Margin="10,10,0,10"
                    Text="Author: Red" />
                            <StackPanel Orientation="Horizontal" Margin="0,10,0,0">
                                <Button
                        x:Name="WebsiteButton"
                        Style="{StaticResource PrimaryButtonStyle}"
                        Content="Website"
                        HorizontalAlignment="Left"
                        Margin="10,0,0,0"
                        VerticalAlignment="Center" />
                                <Button
                        x:Name="YouTubeButton"
                        Style="{StaticResource PrimaryButtonStyle}"
                        Content="YouTube"
                        HorizontalAlignment="Left"
                        Margin="10,0,0,0"
                        VerticalAlignment="Center" />
                            </StackPanel>
                            <TextBlock
                    FontFamily="Helvetica Neue"
                    FontSize="14"
                    Foreground="LightGray"
                    Margin="10,20,0,10"
                    Text="Support the Project" />
                            <Button
                    x:Name="SupportButton"
                    Style="{StaticResource PrimaryButtonStyle}"
                    Content="Buy me a Coffee"
                    HorizontalAlignment="Left"
                    VerticalAlignment="Center"
                    Margin="10,0,0,0" />
                        </StackPanel>
                    </Grid>
                </Border>
            </StackPanel>
        </Grid>
    </Border>
</Window>
'@

# Create the window from XAML
try {
    $reader = New-Object System.IO.StringReader $xaml
    $xmlReader = [System.Xml.XmlReader]::Create($reader)
    $window = [System.Windows.Markup.XamlReader]::Load($xmlReader)

    if (-not $window) {
        Write-Status "Failed to load XAML."
        Pause
    }
}
catch {
    Write-Status "Error loading XAML: $($_.Exception.Message)"
    Pause
}

#region 6. Control Management
# ====================================================================================================
# Control Management
# Find and initialize GUI controls
# ====================================================================================================
# =================================
# Main Window GUI Controls
# =================================

# Main Panels
$script:navigationPanel = $window.FindName("NavigationPanel")
$script:SoftAppsScreen = $window.FindName("SoftAppsScreen")
$script:optimizeScreen = $window.FindName("OptimizeScreen")
$script:customizeScreen = $window.FindName("CustomizeScreen")
$script:aboutScreen = $window.FindName("AboutScreen")

# Navigation Buttons
$closeButton = $window.FindName("CloseButton")
$softwareAppsNavButton = $window.FindName("SoftwareAppsNavButton")
$optimizeNavButton = $window.FindName("OptimizeNavButton")
$customizeNavButton = $window.FindName("CustomizeNavButton")
$aboutNavButton = $window.FindName("AboutNavButton")

# =================================
# Software & Apps Screen Controls
# =================================
$installSoftwareHeader = $window.FindName("InstallSoftwareHeader")
$installSoftwareContent = $window.FindName("InstallSoftwareContent")
$removeAppsHeader = $window.FindName("RemoveAppsHeader")
$removeAppsContent = $window.FindName("RemoveAppsContent")
$chkPanel = $window.FindName("chkPanel")

# Install Buttons
$installStore = $window.FindName("InstallStore")
$installUniGetUI = $window.FindName("InstallUniGetUI")
$installThorium = $window.FindName("InstallThorium")
$installFirefox = $window.FindName("InstallFirefox")
$installChrome = $window.FindName("InstallChrome")
$installBrave = $window.FindName("InstallBrave")
$installEdge = $window.FindName("InstallEdge")
$installEdgeWebView = $window.FindName("InstallEdgeWebView")
$installOneDrive = $window.FindName("InstallOneDrive")
$installXbox = $window.FindName("InstallXbox")

# =================================
# Optimize Screen Controls
# =================================
$OptimizeDefaultsButton = $window.FindName("OptimizeDefaultsButton")
$OptimizeApplyButton = $window.FindName("OptimizeApplyButton")
$windowsSecurityHeaderBorder = $window.FindName("WindowsSecurityHeaderBorder")
$windowsSecurityContent = $window.FindName("WindowsSecurityContent")
$uacSlider = $window.FindName("UACSlider")
$uacSliderValue = $window.FindName("UACSliderValue")
$enableWindowsSecurityButton = $window.FindName("EnableWindowsSecurityButton")
$disableWindowsSecurityButton = $window.FindName("DisableWindowsSecurityButton")

# Initialize UAC slider
$uacSlider.Minimum = 0
$uacSlider.Maximum = 2
$uacSlider.Value = Update-UACNotificationLevel -Mode Get
$uacSliderValue.Text = "Current: $(@("Low","Moderate","High")[$uacSlider.Value])"

# Optimize Checkboxes
$optimizeSelectAllCheckbox = $window.FindName("OptimizeSelectAllCheckbox")
$privacyCheckBox = $window.FindName("PrivacyCheckBox")
$gamingOptimizationsCheckBox = $window.FindName("GamingOptimizationsCheckBox")
$windowsUpdatesCheckBox = $window.FindName("WindowsUpdatesCheckBox")
$powerSettingsCheckBox = $window.FindName("PowerSettingsCheckBox")
$tasksCheckBox = $window.FindName("TasksCheckBox")
$servicesCheckBox = $window.FindName("ServicesCheckBox")

# Create array of optimize checkboxes for easier management
$optimizeCheckboxes = @(
    $privacyCheckBox,
    $gamingOptimizationsCheckBox,
    $windowsUpdatesCheckBox,
    $powerSettingsCheckBox,
    $tasksCheckBox,
    $servicesCheckBox
)

# =================================
# Customize Screen Controls
# =================================
$customizeDefaultsButton = $window.FindName("CustomizeDefaultsButton")
$customizeApplyButton = $window.FindName("CustomizeApplyButton")

# Customize Checkboxes & Slider
$darkModeSlider = $window.FindName("DarkModeSlider")
$customizeSelectAllCheckbox = $window.FindName("CustomizeSelectAllCheckbox")
$taskbarCheckBox = $window.FindName("TaskbarCheckBox")
$startMenuCheckBox = $window.FindName("StartMenuCheckBox")
$explorerCheckBox = $window.FindName("ExplorerCheckBox")
$notificationsCheckBox = $window.FindName("NotificationsCheckBox")
$soundCheckBox = $window.FindName("SoundCheckBox")
$accessibilityCheckBox = $window.FindName("AccessibilityCheckBox")
$searchCheckBox = $window.FindName("SearchCheckBox")

# Create array of all customize checkboxes
$customizeCheckboxes = @(
    $taskbarCheckBox,
    $startMenuCheckBox,
    $explorerCheckBox,
    $notificationsCheckBox,
    $soundCheckBox,
    $accessibilityCheckBox,
    $searchCheckBox
)

# Initialize Dark Mode state
$darkModeSlider.Value = if (Get-CurrentTheme) { 1 } else { 0 }

# About Screen
$websiteButton = $window.FindName("WebsiteButton")
$youTubeButton = $window.FindName("YouTubeButton")
$supportButton = $window.FindName("SupportButton")

# Initialize screens
Initialize-Screens
# Initialize Software Install Handlers
Initialize-InstallationHandlers

#region 7. Event Handlers
# ====================================================================================================
# Event Handlers
# Event handling logic for GUI elements
# ====================================================================================================
# =================================
# Main Window GUI Handlers
# =================================
# Close Button
$CloseButton.Add_Click({
        # Define paths
        $configPath = Join-Path $env:ProgramFiles "Rocket\Config"
        $preferencesFile = Join-Path $configPath "preferences.json"
        $showDialog = $true

        # Check if the user has previously opted out
        if (Test-Path $preferencesFile) {
            try {
                $preferences = Get-Content $preferencesFile | ConvertFrom-Json
                if ($preferences.DontShowSupport) {
                    $showDialog = $false
                }
            }
            catch {
                # If there's an error reading preferences, show the dialog anyway
                $showDialog = $true
            }
        }

        if ($showDialog) {
            $heart = [char]0x2764
            $response = Show-MessageBox -Message "Thanks for using Rocket! $heart

If you found this tool helpful, please consider:

- Making a small donation via Buy me a Coffee

Click 'Yes' to show your support!" `
                -Title "Support Rocket" `
                -Buttons "YesNo" `
                -Icon "Information"

            if ($response -eq 'Yes') {
                Start-Process ""
                Start-Process "buymeacoffee.com/redxuk"
            }
            else {
                # If they click No, save that preference
                try {
                    if (-not (Test-Path $configPath)) {
                        New-Item -ItemType Directory -Path $configPath -Force | Out-Null
                    }

                    @{
                        DontShowSupport = $true
                    } | ConvertTo-Json | Set-Content -Path $preferencesFile -Force
                }
                catch {
                    Write-Status "Unable to save preference: $($_.Exception.Message)" -TargetScreen "SoftAppsScreen"
                }
            }
        }
    
        Exit
    })

$window.Add_SizeChanged({
        # Get the window's current size
        $windowWidth = $window.ActualWidth
        $windowHeight = $window.ActualHeight
    
        # Calculate new dimensions for screens
        $newWidth = $windowWidth - 93 - 20  # Subtracting NavigationPanel width and margins
        $newHeight = $windowHeight - 56 - 20  # Subtracting top margin and extra margins
    
        # Update all screen dimensions using the screens dictionary
        foreach ($screen in $script:screens.Values) {
            $screen.Width = $newWidth
            $screen.Height = $newHeight

            # Find and adjust the main content border based on screen name
            $mainContentBorderName = "$($screen.Name -replace 'Screen','')MainContentBorder"
            $mainContent = $screen.FindName($mainContentBorderName)
            if ($mainContent) {
                $mainContent.Height = $newHeight - 80  # Subtract height of header area
            }

            # Update DockPanel widths for screens with buttons
            if ($screen.Name -eq "OptimizeScreen") {
                $buttonDockPanel = ($screen.Children[0] -as [System.Windows.Controls.DockPanel]).Children[1].Children[1]
                if ($buttonDockPanel) {
                    $buttonDockPanel.Width = $newWidth - 82
                }
            }
            elseif ($screen.Name -eq "CustomizeScreen") {
                $buttonDockPanel = ($screen.Children[0] -as [System.Windows.Controls.DockPanel]).Children[1].Children[1]
                if ($buttonDockPanel) {
                    $buttonDockPanel.Width = $newWidth - 82
                }
            }
        }

        # Update the spacer Rectangle height to match the content
        $spacerRect = $NavigationPanel.Children | Where-Object { $_ -is [System.Windows.Shapes.Rectangle] }
        if ($spacerRect) {
            # Calculate new spacer height based on window height
            $spacerRect.Height = $newHeight - 315  # Adjust this value to fine-tune the About button position
        }
    })

# Handle double-click on title bar for maximize/restore
$window.Add_MouseDoubleClick({
        param($sender, $e)
    
        # Only trigger if double-click happens on the top bar area
        if ($e.GetPosition($window).Y -le 32) {
            if ($window.WindowState -eq [System.Windows.WindowState]::Maximized) {
                $window.WindowState = [System.Windows.WindowState]::Normal
            }
            else {
                $window.WindowState = [System.Windows.WindowState]::Maximized
            }
        }
    })

# Screen switching event handlers
$SoftwareAppsNavButton.Add_Click({
        Switch-Screen -SelectedButton $SoftwareAppsNavButton -TargetScreenName 'SoftAppsScreen'
    })

$OptimizeNavButton.Add_Click({
        Switch-Screen -SelectedButton $OptimizeNavButton -TargetScreenName 'OptimizeScreen'
    })

$CustomizeNavButton.Add_Click({
        Switch-Screen -SelectedButton $CustomizeNavButton -TargetScreenName 'CustomizeScreen'
    })

$AboutNavButton.Add_Click({
        Switch-Screen -SelectedButton $AboutNavButton -TargetScreenName 'AboutScreen'
    })


# =================================
# Software & Apps Handlers
# =================================
# Collapsible Section Handlers
$installSoftwareHeader.Add_MouseDown({
        if ($installSoftwareContent.Visibility -eq "Collapsed") {
            $installSoftwareContent.Visibility = "Visible"
        }
        else {
            $installSoftwareContent.Visibility = "Collapsed"
        }
    })

$removeAppsHeader.Add_MouseDown({
        if ($removeAppsContent.Visibility -eq "Collapsed") {
            $removeAppsContent.Visibility = "Visible"
        }
        else {
            $removeAppsContent.Visibility = "Collapsed"
        }
    })

# Note: Installation handled by Initialize-InstallationHandlers

# =================================
# Remove Bloatware Handlers
# =================================
# Reset to store dynamic checkboxes
$checkBoxes = @()

$chkPanel = $window.FindName("chkPanel")
if (-not $chkPanel) {
    throw "chkPanel element not found. Ensure the XAML has a StackPanel with x:Name='chkPanel'."
}

# Clear existing content in the panel
$chkPanel.Children.Clear()

# Create a UniformGrid for dynamic checkboxes
$uniformGrid = New-Object System.Windows.Controls.Primitives.UniformGrid
$uniformGrid.Columns = 6 # Limit to 6 checkboxes per row
$uniformGrid.Margin = [System.Windows.Thickness]::new(10)

# Add "Select All" checkbox
$selectAllChk = New-Object System.Windows.Controls.CheckBox
$selectAllChk.Content = "Select All"
$selectAllChk.IsChecked = $true
$selectAllChk.FontSize = 14
$selectAllChk.FontWeight = "Bold"
$selectAllChk.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#FFDE00")
$selectAllChk.Margin = [System.Windows.Thickness]::new(6)
$selectAllChk.Style = $window.FindResource("CustomCheckBoxStyle")
$uniformGrid.Children.Add($selectAllChk)

# Track seen apps to avoid duplicates
$seenApps = @{}

foreach ($app in $UsefulAppx.GetEnumerator()) {
    if (-not $seenApps.ContainsKey($app.Value.FriendlyName)) {
        # Special handling for "Xbox" group
        if ($app.Value.FriendlyName -eq "Xbox") {
            $xboxPackages = $UsefulAppx.GetEnumerator() | 
            Where-Object { $_.Value.FriendlyName -eq "Xbox" } | 
            ForEach-Object { $_.Key }
            
            $chk = New-Object System.Windows.Controls.CheckBox
            $chk.Content = "Xbox"
            $chk.IsChecked = $true
            $chk.FontSize = 14
            $chk.Foreground = [System.Windows.Media.Brushes]::White
            $chk.Margin = [System.Windows.Thickness]::new(5)
            $chk.Tag = $xboxPackages
            $chk.Style = $window.FindResource("CustomCheckBoxStyle")
            $uniformGrid.Children.Add($chk)
            $checkBoxes += $chk
            $seenApps[$app.Value.FriendlyName] = $true
            continue
        }

        # Default handling for other apps
        $chk = New-Object System.Windows.Controls.CheckBox
        $chk.Content = $app.Value.FriendlyName
        $chk.IsChecked = $true
        $chk.FontSize = 14
        $chk.Foreground = [System.Windows.Media.Brushes]::White
        $chk.Margin = [System.Windows.Thickness]::new(5)
        $chk.Tag = $app.Key
        $chk.Style = $window.FindResource("CustomCheckBoxStyle")
        $uniformGrid.Children.Add($chk)
        $checkBoxes += $chk
        $seenApps[$app.Value.FriendlyName] = $true
    }
}

# Add Microsoft Edge checkbox
$chk = New-Object System.Windows.Controls.CheckBox
$chk.Content = "Microsoft Edge"
$chk.IsChecked = $true
$chk.FontSize = 14
$chk.Foreground = [System.Windows.Media.Brushes]::White
$chk.Margin = [System.Windows.Thickness]::new(5)
$chk.Tag = "Edge"  # Special tag to identify Edge
$chk.Style = $window.FindResource("CustomCheckBoxStyle")
$uniformGrid.Children.Add($chk)
$checkBoxes += $chk

# Add OneDrive checkbox
$chk = New-Object System.Windows.Controls.CheckBox
$chk.Content = "OneDrive"
$chk.IsChecked = $true
$chk.FontSize = 14
$chk.Foreground = [System.Windows.Media.Brushes]::White
$chk.Margin = [System.Windows.Thickness]::new(5)
$chk.Tag = "OneDrive"  # Special tag to identify OneDrive
$chk.Style = $window.FindResource("CustomCheckBoxStyle")
$uniformGrid.Children.Add($chk)
$checkBoxes += $chk

# Add Recall checkbox
$chk = New-Object System.Windows.Controls.CheckBox
$chk.Content = "Recall"
$chk.IsChecked = $true
$chk.FontSize = 14
$chk.Foreground = [System.Windows.Media.Brushes]::White
$chk.Margin = [System.Windows.Thickness]::new(5)
$chk.Tag = "Recall"  # Special tag to identify Recall
$chk.Style = $window.FindResource("CustomCheckBoxStyle")
$uniformGrid.Children.Add($chk)
$checkBoxes += $chk

# Add "Useless Bloatware" checkbox
$chk = New-Object System.Windows.Controls.CheckBox
$chk.Content = "Useless Bloatware"
$chk.IsChecked = $true
$chk.FontSize = 14
$chk.Foreground = [System.Windows.Media.Brushes]::White
$chk.Margin = [System.Windows.Thickness]::new(5)
$chk.Tag = @($Bloatappx.Keys)
$chk.Style = $window.FindResource("CustomCheckBoxStyle")
$uniformGrid.Children.Add($chk)
$checkBoxes += $chk

# Add the tooltip symbol next to the "Useless Bloatware" checkbox
$helpIcon = New-Object System.Windows.Controls.TextBlock
$helpIcon.Margin = [System.Windows.Thickness]::new(6, 0, 0, 0)

# Apply the HelpIconStyle from XAML
$helpIconStyle = $window.FindResource("HelpIconStyle")
if ($helpIconStyle -ne $null) {
    $helpIcon.Style = $helpIconStyle
}

# Generate friendly names as a string for the tooltip
$BloatList = $Bloatappx.GetEnumerator() | ForEach-Object {
    "- $($_.Value.FriendlyName)"
} | Out-String

$LegacyList = "`nLegacy Features:`n" + ($LegacyCapabilities.GetEnumerator() | ForEach-Object {
        "- $($_.Value.FriendlyName)"
    } | Out-String)

# Add tooltip content
$tooltip = New-Object System.Windows.Controls.ToolTip
$tooltip.Content = "Useless Bloatware: `n$BloatList$LegacyList"

# Apply the CustomTooltipStyle
$customTooltipStyle = $window.FindResource("CustomTooltipStyle")
if ($customTooltipStyle -ne $null) {
    $tooltip.Style = $customTooltipStyle
}

$helpIcon.ToolTip = $tooltip

# Add the tooltip symbol to the same row in the grid
$uniformGrid.Children.Add($helpIcon) 

# Add the UniformGrid to the chkPanel
$chkPanel.Children.Add($uniformGrid)

# Add "Select All" functionality
$handlingSelectAll = $false

$selectAllChk.Add_Checked({
        if (-not $handlingSelectAll) {
            foreach ($chk in $checkBoxes) {
                $chk.IsChecked = $true
            }
        }
    })

$selectAllChk.Add_Unchecked({
        if (-not $handlingSelectAll) {
            foreach ($chk in $checkBoxes) {
                $chk.IsChecked = $false
            }
        }
    })

# Function to update "Select All" state
function Update-SelectAllState {
    # Prevent cascading updates
    $handlingSelectAll = $true

    # Determine if all checkboxes (excluding "Select All") are checked
    $allChecked = $true
    foreach ($chk in $checkBoxes) {
        if ($chk -ne $selectAllChk -and $chk.IsChecked -ne $true) {
            $allChecked = $false
            break
        }
    }
    
    # Update the "Select All" checkbox state
    $selectAllChk.IsChecked = $allChecked

    # Allow cascading updates again
    $handlingSelectAll = $false
}

# Add event handlers to each dynamically created checkbox
foreach ($chk in $checkBoxes) {
    if ($chk -ne $selectAllChk) {
        $chk.Add_Checked({ Update-SelectAllState })
        $chk.Add_Unchecked({ Update-SelectAllState })
    }
}

# Add "Remove Selected Apps" button below the checkboxes but above static content
$removeAppsButton = New-Object System.Windows.Controls.Button
$removeAppsButton.Content = "Remove Apps"
$removeAppsButton.Width = 130
$removeAppsButton.Height = 35
$removeAppsButton.HorizontalAlignment = "Right"
$removeAppsButton.Margin = [System.Windows.Thickness]::new(0, 0, 10, 0)
$removeAppsButton.Style = $window.FindResource("PrimaryButtonStyle")

# Insert the button at the correct position in RemoveAppsContent
$removeAppsContent = $window.FindName("RemoveAppsContent")
$removeAppsContent.Children.Insert(1, $removeAppsButton) # Insert after chkPanel but before static content

# Call Remove-SelectedBloatware when removing bloatware
$RemoveAppsButton.Add_Click({ Remove-SelectedBloatware })

# ==========================
# Optimize Screen Handlers
# ==========================
# Collapsible Section
$windowsSecurityHeaderBorder.Add_MouseDown({
        if ($windowsSecurityContent.Visibility -eq "Collapsed") {
            $windowsSecurityContent.Visibility = "Visible"
        }
        else {
            $windowsSecurityContent.Visibility = "Collapsed"
        }
    })


# UAC Slider Handler
$UACSlider.Add_ValueChanged({
        try {
            $levelNames = @("Low", "Moderate", "High")
            Update-UACNotificationLevel -Mode Set -Level $this.Value
            $UACSliderValue.Text = "Current: $($levelNames[$this.Value])"
        }
        catch {
            $UACSliderValue.Text = "Error: Update Failed"
            [System.Media.SystemSounds]::Hand.Play()
            Write-Log "UAC slider update failed: $($_.Exception.Message)" -Severity Error
        }
    })

# Windows Security Suite Handlers
$EnableWindowsSecurityButton.Add_Click({ Enable-WindowsSecuritySuite })
$DisableWindowsSecurityButton.Add_Click({ Disable-WindowsSecuritySuite })

# Select All checkbox handler
$optimizeSelectAllCheckbox.Add_Click({
        $isChecked = $optimizeSelectAllCheckbox.IsChecked
        foreach ($checkbox in $optimizeCheckboxes) {
            $checkbox.IsChecked = $isChecked
        }
    })

# Individual checkbox handlers
foreach ($checkbox in $optimizeCheckboxes) {
    $checkbox.Add_Click({
            # Check if all boxes are checked
            $allChecked = $optimizeCheckboxes | ForEach-Object { $_.IsChecked } | Select-Object -Unique
            if ($allChecked.Count -eq 1) {
                $optimizeSelectAllCheckbox.IsChecked = $allChecked[0]
            }
            else {
                $optimizeSelectAllCheckbox.IsChecked = $null  # Set to indeterminate state
            }
        })
}

# Optimize Screen Apply Button Handler
$OptimizeApplyButton.Add_Click({
        [System.Windows.Input.Mouse]::OverrideCursor = [System.Windows.Input.Cursors]::Wait
    
        try {
            $results = @{
                Privacy  = $false
                Gaming   = $false
                Updates  = $false
                Power    = $false
                Tasks    = $false
                Services = $false
            }
        
            # Build list of selected operations
            $selectedCategories = @()
            if ($privacyCheckBox.IsChecked) { 
                $selectedCategories += 'Privacy'
                $results.Privacy = $true
            }
            if ($gamingOptimizationsCheckBox.IsChecked) { 
                $selectedCategories += 'Gaming'
                $results.Gaming = $true
            }
            if ($windowsUpdatesCheckBox.IsChecked) { 
                $selectedCategories += 'Updates'
                $results.Updates = $true
            }
            if ($servicesCheckBox.IsChecked) { 
                $selectedCategories += 'Services'
                $results.Services = $true
            }
        
            if ($selectedCategories.Count -gt 0) {
                Write-Status "Applying registry optimizations..." -TargetScreen OptimizeScreen
                Update-WPFControls
                Invoke-Settings -Categories $selectedCategories -Action Apply -SuppressMessage
            }
        
            if ($powerSettingsCheckBox.IsChecked) {
                Write-Status "Configuring power settings..." -TargetScreen OptimizeScreen
                Update-WPFControls
                Set-RecommendedPowerSettings | Out-Null
                $results.Power = $true
            }
        
            if ($tasksCheckBox.IsChecked) {
                Write-Status "Configuring scheduled tasks. Please wait..." -TargetScreen OptimizeScreen
                Update-WPFControls
                Invoke-ScheduledTaskSettings -Action Apply -SuppressMessage
                $results.Tasks = $true
            }
        
            # Construct final message
            $message = "Optimization completed:`n"
            if ($results.Privacy) { $message += "`n[+] Privacy settings optimized" }
            if ($results.Gaming) { $message += "`n[+] Gaming optimizations applied" }
            if ($results.Updates) { $message += "`n[+] Windows Update settings configured" }
            if ($results.Power) { $message += "`n[+] Power settings optimized for performance" }
            if ($results.Tasks) { $message += "`n[+] Scheduled tasks optimized" }
            if ($results.Services) { $message += "`n[+] Windows services optimized" }
            $message += "`n`nPlease restart your computer for all changes to take effect."
        
            Write-Status "Optimizations complete" -TargetScreen OptimizeScreen
            Update-WPFControls
            Show-MessageBox -Message $message -Title "Optimization Complete" -Icon Information
        }
        catch {
            Write-Log "Error during optimization: $($_.Exception.Message)" -Severity 'ERROR'
            Write-Status "Error occurred during optimization" -TargetScreen OptimizeScreen
            Show-MessageBox -Message "An error occurred during optimization.`n`n$($_.Exception.Message)" -Title "Error" -Icon Error
        }
        finally {
            [System.Windows.Input.Mouse]::OverrideCursor = $null
        }
    })

# Optimize Screen Defaults Button Handler
$OptimizeDefaultsButton.Add_Click({
        [System.Windows.Input.Mouse]::OverrideCursor = [System.Windows.Input.Cursors]::Wait
        try {
            $results = @{
                Privacy  = $false
                Gaming   = $false
                Updates  = $false
                Power    = $false
                Tasks    = $false
                Services = $false
            }

            # Handle registry-based settings first
            $selectedCategories = @()
            if ($privacyCheckBox.IsChecked) { 
                $selectedCategories += 'Privacy'
                $results.Privacy = $true
            }
            if ($gamingOptimizationsCheckBox.IsChecked) { 
                $selectedCategories += 'Gaming'
                $results.Gaming = $true
            }
            if ($windowsUpdatesCheckBox.IsChecked) { 
                $selectedCategories += 'Updates'
                $results.Updates = $true
            }
            if ($servicesCheckBox.IsChecked) { 
                $selectedCategories += 'Services'
                $results.Services = $true
            }

            if ($selectedCategories.Count -gt 0) {
                Write-Status "Restoring default registry settings..." -TargetScreen OptimizeScreen
                Update-WPFControls
                Invoke-Settings -Categories $selectedCategories -Action Rollback
            }

            # Handle non-registry settings
            if ($powerSettingsCheckBox.IsChecked) {
                Write-Status "Restoring default power settings..." -TargetScreen OptimizeScreen
                Update-WPFControls
                Set-DefaultPowerSettings
                $results.Power = $true
            }
            if ($tasksCheckBox.IsChecked) {
                Write-Status "Restoring default scheduled tasks. Please wait..." -TargetScreen OptimizeScreen
                Update-WPFControls
                Invoke-ScheduledTaskSettings -Action Rollback
                $results.Tasks = $true
            }

            # Construct final message
            $message = "Default settings restored:`n"
            if ($results.Privacy) { $message += "`n[+] Privacy settings restored to Windows defaults" }
            if ($results.Gaming) { $message += "`n[+] Gaming optimizations reverted to default" }
            if ($results.Updates) { $message += "`n[+] Windows Update settings restored to default" }
            if ($results.Power) { $message += "`n[+] Power settings restored to balanced plan" }
            if ($results.Tasks) { $message += "`n[+] Scheduled tasks restored to default state" }
            if ($results.Services) { $message += "`n[+] Windows services restored to default configuration" }
            $message += "`n`nPlease restart your computer for all changes to take effect."

            Write-Status "Defaults restored" -TargetScreen OptimizeScreen
            Update-WPFControls
            Show-MessageBox -Message $message -Title "Restore Complete" -Icon Information

            # Uncheck all boxes including Select All AFTER processing
            $optimizeSelectAllCheckbox.IsChecked = $false
            foreach ($checkbox in $optimizeCheckboxes) {
                $checkbox.IsChecked = $false
            }
        }
        finally {
            [System.Windows.Input.Mouse]::OverrideCursor = $null
        }
    })

# ==========================
# Customize Screen Handlers
# ==========================

# Dark Mode Slider Handler
$DarkModeSlider.Add_ValueChanged({
        # Add a flag to prevent recursive calls
        if ($script:isHandlingValueChanged) { return }
        $script:isHandlingValueChanged = $true

        $isDark = $this.Value -eq 1
        try {
            # Prompt user about wallpaper change
            $result = [System.Windows.MessageBox]::Show(
                "Would you like to change to the default $(if ($isDark) {'dark'} else {'light'}) theme wallpaper?",
                "Theme Change",
                [System.Windows.MessageBoxButton]::YesNoCancel,
                [System.Windows.MessageBoxImage]::Question
            )
    
            switch ($result) {
                'Yes' {
                    Set-DarkMode -EnableDarkMode $isDark -ChangeWallpaper $true
                }
                'No' {
                    Set-DarkMode -EnableDarkMode $isDark -ChangeWallpaper $false
                }
                'Cancel' {
                    # Reset slider to previous state
                    $this.Value = if ($isDark) { 0 } else { 1 }
                }
            }
        }
        catch {
            [System.Windows.MessageBox]::Show(
                "Failed to switch themes: $($_.Exception.Message)",
                "Theme Error",
                "OK",
                "Error"
            )
            # Reset to previous state
            $this.Value = if ($isDark) { 0 } else { 1 }
        }
        finally {
            $script:isHandlingValueChanged = $false
        }
    })

# Select All checkbox handler
$customizeSelectAllCheckbox.Add_Click({
        $isChecked = $customizeSelectAllCheckbox.IsChecked
        foreach ($checkbox in $customizeCheckboxes) {
            $checkbox.IsChecked = $isChecked
        }
    })

# Individual checkbox handlers
foreach ($checkbox in $customizeCheckboxes) {
    $checkbox.Add_Click({
            # Check if all boxes are checked
            $allChecked = $customizeCheckboxes | ForEach-Object { $_.IsChecked } | Select-Object -Unique
            if ($allChecked.Count -eq 1) {
                $customizeSelectAllCheckbox.IsChecked = $allChecked[0]
            }
            else {
                $customizeSelectAllCheckbox.IsChecked = $null  # Set to indeterminate state
            }
        })
}

# Customize Screen Apply Button Handler
$CustomizeApplyButton.Add_Click({
        [System.Windows.Input.Mouse]::OverrideCursor = [System.Windows.Input.Cursors]::Wait
        try {
            $results = @{
                Taskbar       = $false
                StartMenu     = $false
                Explorer      = $false
                Notifications = $false
                Sound         = $false
                Accessibility = $false
                Search        = $false
            }
    
            $selectedCategories = @()
            $windowsVersion = Get-WindowsVersion
    
            if ($taskbarCheckBox.IsChecked) { 
                $selectedCategories += 'Taskbar'
                $results.Taskbar = $true
            }
            if ($startMenuCheckBox.IsChecked) { 
                $selectedCategories += 'StartMenu'
                $results.StartMenu = $true
            }
            if ($explorerCheckBox.IsChecked) { 
                $selectedCategories += 'Explorer'
                $results.Explorer = $true
            }
            if ($notificationsCheckBox.IsChecked) { 
                $selectedCategories += 'Notifications'
                $results.Notifications = $true
            }
            if ($soundCheckBox.IsChecked) { 
                $selectedCategories += 'Sound'
                $results.Sound = $true
            }
            if ($accessibilityCheckBox.IsChecked) { 
                $selectedCategories += 'Accessibility'
                $results.Accessibility = $true
            }
            if ($searchCheckBox.IsChecked) { 
                $selectedCategories += 'Search'
                $results.Search = $true
            }

            if ($selectedCategories.Count -gt 0) {
                Write-Status "Applying customization settings..." -TargetScreen CustomizeScreen
                Update-WPFControls

                # Handle Start Menu differently based on Windows version
                if ($results.StartMenu) {
                    if ($windowsVersion -ge 22000) {
                        # Windows 11 - use binary replacement method
                        $startMenuSuccess = Reset-Windows11StartMenu
                        if (-not $startMenuSuccess) {
                            $results.StartMenu = $false  # Mark as failed
                        }
                    }
                    else {
                        # Windows 10 - use existing method
                        $startMenuSuccess = Reset-Windows10StartMenu
                        if (-not $startMenuSuccess) {
                            $results.StartMenu = $false  # Mark as failed
                        }
                    }
                    # Remove StartMenu from categories since we handled it separately
                    $selectedCategories = $selectedCategories | Where-Object { $_ -ne 'StartMenu' }
                }

                # Apply remaining settings using existing method
                if ($selectedCategories.Count -gt 0) {
                    Invoke-Settings -Categories $selectedCategories -Action Apply
                }

                # Construct final message
                $message = "Customization completed:`n"
                if ($results.Taskbar) { $message += "`n[+] Taskbar settings applied" }
                if ($results.StartMenu) { $message += "`n[+] Start Menu settings applied" }
                if ($results.Explorer) { $message += "`n[+] Explorer settings applied" }
                if ($results.Notifications) { $message += "`n[+] Notification settings applied" }
                if ($results.Sound) { $message += "`n[+] Sound settings applied" }
                if ($results.Accessibility) { $message += "`n[+] Accessibility settings applied" }
                if ($results.Search) { $message += "`n[+] Search settings applied" }
                $message += "`n`nPlease restart your computer for all changes to take effect."

                Write-Status "Customization complete" -TargetScreen CustomizeScreen
                Update-WPFControls
                Show-MessageBox -Message $message -Title "Customization Complete" -Icon Information
            }
        }
        finally {
            [System.Windows.Input.Mouse]::OverrideCursor = $null
        }
    })

# Customize Screen Apply Button Handler
$CustomizeDefaultsButton.Add_Click({
        [System.Windows.Input.Mouse]::OverrideCursor = [System.Windows.Input.Cursors]::Wait
        try {
            $results = @{
                Taskbar       = $false
                StartMenu     = $false
                Explorer      = $false
                Notifications = $false
                Sound         = $false
                Accessibility = $false
                Search        = $false
            }
        
            $selectedCategories = @()
        
            if ($taskbarCheckBox.IsChecked) { 
                $selectedCategories += 'Taskbar'
                $results.Taskbar = $true
            }
            if ($startMenuCheckBox.IsChecked) { 
                $selectedCategories += 'StartMenu'
                $results.StartMenu = $true
            }
            if ($explorerCheckBox.IsChecked) { 
                $selectedCategories += 'Explorer'
                $results.Explorer = $true
            }
            if ($notificationsCheckBox.IsChecked) { 
                $selectedCategories += 'Notifications'
                $results.Notifications = $true
            }
            if ($soundCheckBox.IsChecked) { 
                $selectedCategories += 'Sound'
                $results.Sound = $true
            }
            if ($accessibilityCheckBox.IsChecked) { 
                $selectedCategories += 'Accessibility'
                $results.Accessibility = $true
            }
            if ($searchCheckBox.IsChecked) { 
                $selectedCategories += 'Search'
                $results.Search = $true
            }

            if ($selectedCategories.Count -gt 0) {
                Write-Status "Restoring default customization settings..." -TargetScreen CustomizeScreen
                Update-WPFControls
                Invoke-Settings -Categories $selectedCategories -Action Rollback

                # Construct final message
                $message = "Default settings restored:`n"
                if ($results.Taskbar) { $message += "`n[+] Taskbar settings restored" }
                if ($results.StartMenu) { $message += "`n[+] Start Menu settings restored" }
                if ($results.Explorer) { $message += "`n[+] Explorer settings restored" }
                if ($results.Notifications) { $message += "`n[+] Notification settings restored" }
                if ($results.Sound) { $message += "`n[+] Sound settings restored" }
                if ($results.Accessibility) { $message += "`n[+] Accessibility settings restored" }
                if ($results.Search) { $message += "`n[+] Search settings restored" }
                $message += "`n`nPlease restart your computer for all changes to take effect."

                Write-Status "Defaults restored" -TargetScreen CustomizeScreen
                Update-WPFControls
                Show-MessageBox -Message $message -Title "Restore Complete" -Icon Information
            }
        
            # Uncheck all boxes including Select All
            $customizeSelectAllCheckbox.IsChecked = $false
            foreach ($checkbox in $customizeCheckboxes) {
                $checkbox.IsChecked = $false
            }
        }
        finally {
            [System.Windows.Input.Mouse]::OverrideCursor = $null
        }
    })

# ==========================
# About Screen Handlers
# ==========================

$WebsiteButton.Add_Click({
        Start-Process "https://lazypandaclothing.com"
    })

$YouTubeButton.Add_Click({
        Start-Process "https://youtube.com/@LazyPandaXP"
    })

$SupportButton.Add_Click({
        Start-Process "buymeacoffee.com/redxuk"
    })


#region 8. Main Execution
# ====================================================================================================
# Main Execution
# Application startup and main window display
# ====================================================================================================

# Make window draggable
$window.Add_MouseLeftButtonDown({
        $window.DragMove()
    }) | Out-Null

# Display disclaimer message before showing main window
$agreement = Show-MessageBox -Message "Welcome to Rocket!

This tool enhances your Windows experience by modifying system settings.

By continuing, you agree that:

- You are using this software at your own risk
- The authors accept no liability for any issues that may occur

Press 'OK' to agree and continue, or 'Cancel' to exit." `
    -Title "Rocket - Important Notice" `
    -Buttons "OKCancel" `
    -Icon "Warning"

# Exit if user doesn't agree OR clicks Cancel/X
if ($agreement -ne 'OK') {
    exit
}

# Create registry backup and initialize logging
Start-Log
Write-Log -Message "Script started" -Severity 'INFO'

$backupPath = Backup-Registry
if ($backupPath) {
    Show-MessageBox -Message "Welcome to Rocket!

A registry backup has been created at:
$backupPath

The log file is being saved to:
$SCRIPT:LogPath

You can use the registry file to restore your registry if needed." `
        -Title "Backup Information" `
        -Buttons "OK" `
        -Icon "Information"
}

# Show the window
try {
    Clear-Host
    $window.ShowDialog() | Out-Null
}
finally {
    Stop-Log
}
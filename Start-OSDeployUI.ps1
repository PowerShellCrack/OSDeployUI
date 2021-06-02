<#
.SYNOPSIS
    A OSDeploy User Interface.

.DESCRIPTION
   A PowerShell driven UI for the OSDeploy module

.NOTES
    Author		: Dick Tracy II <richard.tracy@microsoft.com>
	Source		: https://github.com/PowerShellCrack/OSDeployUI
    Version		: 1.0.0
    #Requires -Version 3.0

.EXAMPLE
    .\Start-OSDeployUI.ps1

#>

$VerbosePreference = 'SilentlyContinue'
$DebugPreference = 'SilentlyContinue'
#*=============================================
##* Runtime Function - REQUIRED
##*=============================================
#region FUNCTION: Check if running in WinPE
Function Test-WinPE{
    return Test-Path -Path Registry::HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlset\Control\MiniNT
}
#endregion

#region FUNCTION: Check if running in ISE
Function Test-IsISE {
    # try...catch accounts for:
    # Set-StrictMode -Version latest
    try {
        return ($null -ne $psISE);
    }
    catch {
        return $false;
    }
}
#endregion

#region FUNCTION: Check if running in Visual Studio Code
Function Test-VSCode{
    if($env:TERM_PROGRAM -eq 'vscode') {
        return $true;
    }
    Else{
        return $false;
    }
}
#endregion

#region FUNCTION: Find script path for either ISE or console
Function Get-ScriptPath {
    <#
        .SYNOPSIS
            Finds the current script path even in ISE or VSC
        .LINK
            Test-VSCode
            Test-IsISE
    #>
    param(
        [switch]$Parent
    )

    Begin{}
    Process{
        if ($PSScriptRoot -eq "")
        {
            if (Test-IsISE)
            {
                $ScriptPath = $psISE.CurrentFile.FullPath
            }
            elseif(Test-VSCode){
                $context = $psEditor.GetEditorContext()
                $ScriptPath = $context.CurrentFile.Path
            }Else{
                $ScriptPath = (Get-location).Path
            }
        }
        else
        {
            $ScriptPath = $PSCommandPath
        }
    }
    End{

        If($Parent){
            Split-Path $ScriptPath -Parent
        }Else{
            $ScriptPath
        }
    }

}
#endregion

function Get-ParameterOption {
    param(
        $Command,
        $Parameter
    )

    $parameters = Get-Command -Name $Command | Select-Object -ExpandProperty Parameters
    $type = $parameters[$Parameter].ParameterType
    if($type.IsEnum) {
        [System.Enum]::GetNames($type)
    } else {
        $parameters[$Parameter].Attributes.ValidValues
    }
}
#endregion
Function Convert-ImagetoBase64String{
    Param([String]$path)
    [convert]::ToBase64String((get-content $path -encoding byte))
}


#region FUNCTION: Grab all machine platform details
Function Get-PlatformInfo {
# Returns device Manufacturer, Model and BIOS version, populating global variables for use in other functions/ validation
# Note that platformType is appended to psobject by Get-PlatformValid - type is manually defined by user to ensure accuracy
    [CmdletBinding()]
    [OutputType([PsObject])]
    Param()
    try{
        $CIMSystemEncloure = Get-CIMInstance Win32_SystemEnclosure -ErrorAction Stop
        $CIMComputerSystem = Get-CIMInstance CIM_ComputerSystem -ErrorAction Stop
        $CIMBios = Get-CIMInstance Win32_BIOS -ErrorAction Stop


        [boolean]$Is64Bit = [boolean]((Get-WmiObject -Class 'Win32_Processor' | Where-Object { $_.DeviceID -eq 'CPU0' } | Select-Object -ExpandProperty 'AddressWidth') -eq 64)
        If ($Is64Bit) { [string]$envOSArchitecture = '64-bit' } Else { [string]$envOSArchitecture = '32-bit' }

        New-Object -TypeName PsObject -Property @{
            "computerName" = [system.environment]::MachineName
            "computerDomain" = $CIMComputerSystem.Domain
            "platformBIOS" = $CIMBios.SMBIOSBIOSVersion
            "platformManufacturer" = $CIMComputerSystem.Manufacturer
            "platformModel" = $CIMComputerSystem.Model
            "AssetTag" = $CIMSystemEncloure.SMBiosAssetTag
            "SerialNumber" = $CIMBios.SerialNumber
            "Architecture" = $envOSArchitecture
            }
    }
    catch{Write-Output "CRITICAL" "Failed to get information from Win32_Computersystem/ Win32_BIOS"}
}
#endregion

#https://powershellone.wordpress.com/2021/02/24/using-powershell-and-regex-to-extract-text-between-delimiters/
function Get-TextWithin {
    <#
        .SYNOPSIS
            Get the text between two surrounding characters (e.g. brackets, quotes, or custom characters)
        .DESCRIPTION
            Use RegEx to retrieve the text within enclosing characters.
	    .PARAMETER Text
            The text to retrieve the matches from.
        .PARAMETER WithinChar
            Single character, indicating the surrounding characters to retrieve the enclosing text for. 
            If this paramater is used the matching ending character is "guessed" (e.g. '(' = ')')
        .PARAMETER StartChar
            Single character, indicating the start surrounding characters to retrieve the enclosing text for. 
        .PARAMETER EndChar
            Single character, indicating the end surrounding characters to retrieve the enclosing text for. 
        .EXAMPLE
            # Retrieve all text within single quotes
		    $s=@'
here is 'some data'
here is "some other data"
this is 'even more data'
'@
             Get-TextWithin $s "'"
    .EXAMPLE
    # Retrieve all text within custom start and end characters
    $s=@'
here is /some data\
here is /some other data/
this is /even more data\
'@
    Get-TextWithin $s -StartChar / -EndChar \
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory,
            ValueFromPipeline = $true,
            Position = 0)]
        $Text,
        [Parameter(ParameterSetName = 'Single', Position = 1)]
        [char]$WithinChar = '"',
        [Parameter(ParameterSetName = 'Double')]
        [char]$StartChar,
        [Parameter(ParameterSetName = 'Double')]
        [char]$EndChar,
        [Parameter(ParameterSetName = 'Regex')]
        [regex]$Regex
    )
    $htPairs = @{
        '(' = ')'
        '[' = ']'
        '{' = '}'
        '<' = '>'
    }
    if ($PSBoundParameters.ContainsKey('Regex')) {
        [regex]::Matches($Text, $Regex).Value
    }Else{
        if ($PSBoundParameters.ContainsKey('WithinChar')) {
            $StartChar = $EndChar = $WithinChar
            if ($htPairs.ContainsKey([string]$WithinChar)) {
                $EndChar = $htPairs[[string]$WithinChar]
            }
        }
        $pattern = @"
(?<=\$StartChar).+?(?=\$EndChar)
"@
        [regex]::Matches($Text, $pattern).Value
    }
}

  
Function Show-OSDeployUI{
    ##*=============================================
    ##* VARIABLE DECLARATION
    ##*=============================================
    #region VARIABLES: Building paths & values
    # Use function to get paths because Powershell ISE & other editors have differnt results
    [string]$scriptPath = Get-ScriptPath
    [string]$scriptName = [IO.Path]::GetFileNameWithoutExtension($scriptPath)
    [string]$scriptRoot = Split-Path -Path $scriptPath -Parent

    [string]$ImageURL = 'https://gblobscdn.gitbook.com/spaces%2F-LpnxLqvh8u2fEz86kIM%2Favatar-rectangle.png'
    # LOAD APP XAML (Built by Visual Studio 2019)
    #==========================================

    #=======================================================
    # LOAD ASSEMBLIES
    #=======================================================
    [System.Reflection.Assembly]::LoadWithPartialName('WindowsFormsIntegration') | out-null # Call the EnableModelessKeyboardInterop
    [System.Reflection.Assembly]::LoadWithPartialName('PresentationFramework') | out-null
    [System.Reflection.Assembly]::LoadWithPartialName('PresentationCore')      | out-null
    [System.Reflection.Assembly]::LoadWithPartialName('System.Windows.Forms')  | out-null

    #================================================
    # LOAD UI XAML (Designed with Visual Studio 2019)
    #================================================
    $xamlpath = @"
<Window x:Class="OSDeployUI.OSDeployWindow"
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    xmlns:d="http://schemas.microsoft.com/expression/blend/2008"
    xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006"
    xmlns:local="clr-namespace:OSDeployUI"
    mc:Ignorable="d"
    Title="OSDeployWindow" 
    Height="600" Width="1024"
    ResizeMode="NoResize"
    WindowStartupLocation="CenterScreen"
    WindowStyle="None">
<Window.Resources>
    <ResourceDictionary>


        <ControlTemplate x:Key="ComboBoxToggleButtonStyle" TargetType="{x:Type ToggleButton}">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition />
                    <ColumnDefinition Width="20" />
                </Grid.ColumnDefinitions>
                <Border x:Name="Border"
                    Grid.ColumnSpan="2"
                    BorderThickness="1">
                    <Border.BorderBrush>
                        <SolidColorBrush Color="#FF1D3245"/>
                    </Border.BorderBrush>
                    <Border.Background>
                        <SolidColorBrush Color="White"/>
                    </Border.Background>
                </Border>
                <Border Grid.Column="0"
                    Margin="1" >
                    <Border.BorderBrush>
                        <SolidColorBrush Color="LightBlue"/>
                    </Border.BorderBrush>
                    <Border.Background>
                        <SolidColorBrush Color="LightGray"/>
                    </Border.Background>
                </Border>
                <Path x:Name="Arrow"
                  Grid.Column="1"
                  HorizontalAlignment="Center"
                  VerticalAlignment="Center"
                  Data="M0,0 L0,2 L4,6 L8,2 L8,0 L4,4 z" 
                  Fill="#444444">
                </Path>
            </Grid>
        </ControlTemplate>

        <Style x:Key="SimpleComboBoxStyle" TargetType="{x:Type ComboBox}">
            <Setter Property="SnapsToDevicePixels" Value="true" />
            <Setter Property="OverridesDefaultStyle" Value="true" />
            <Setter Property="ScrollViewer.HorizontalScrollBarVisibility" Value="Auto" />
            <Setter Property="ScrollViewer.VerticalScrollBarVisibility" Value="Auto" />
            <Setter Property="ScrollViewer.CanContentScroll" Value="true" />
            <Setter Property="MinWidth" Value="120" />
            <Setter Property="MinHeight" Value="20" />
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="{x:Type ComboBox}">
                        <Grid>
                            <ToggleButton x:Name="ToggleButton"
                                        Template="{StaticResource ComboBoxToggleButtonStyle}"
                                        Grid.Column="2"
                                        Focusable="false"
                                        ClickMode="Press"
                                        IsChecked="{Binding IsDropDownOpen, Mode=TwoWay, RelativeSource={RelativeSource TemplatedParent}}"/>
                            <ContentPresenter x:Name="ContentSite"
                                            IsHitTestVisible="False"
                                            Content="{TemplateBinding SelectionBoxItem}"
                                            ContentTemplate="{TemplateBinding SelectionBoxItemTemplate}"
                                            ContentTemplateSelector="{TemplateBinding ItemTemplateSelector}"
                                            Margin="3,3,23,3"
                                            VerticalAlignment="Stretch"
                                            HorizontalAlignment="Left">
                            </ContentPresenter>
                            <TextBox x:Name="PART_EditableTextBox"
                                   HorizontalAlignment="Left"
                                   VerticalAlignment="Bottom"
                                   Margin="3,3,23,3"
                                   Focusable="True"
                                   Background="White"
                                   Visibility="Hidden"
                                   IsReadOnly="{TemplateBinding IsReadOnly}" >
                                <TextBox.Template>
                                    <ControlTemplate TargetType="TextBox" >
                                        <Border Name="PART_ContentHost" Focusable="False" />
                                    </ControlTemplate>
                                </TextBox.Template>
                            </TextBox>
                            <Popup x:Name="Popup"
                                 Placement="Bottom"
                                 IsOpen="{TemplateBinding IsDropDownOpen}"
                                 AllowsTransparency="False"
                                 Focusable="False"
                                 PopupAnimation="Slide">
                                <Grid x:Name="DropDown"
                                  Background="White"
                                  SnapsToDevicePixels="True"
                                  MinWidth="{TemplateBinding ActualWidth}"
                                  MaxHeight="{TemplateBinding MaxDropDownHeight}">
                                    <Border x:Name="DropDownBorder"
                                        BorderThickness="1">
                                        <Border.BorderBrush>
                                            <SolidColorBrush Color="{DynamicResource BorderMediumColor}" />
                                        </Border.BorderBrush>
                                        <Border.Background>
                                            <SolidColorBrush Color="{DynamicResource ControlLightColor}" />
                                        </Border.Background>
                                    </Border>
                                    <ScrollViewer Margin="4,6,4,6"
                                              SnapsToDevicePixels="True">
                                        <StackPanel IsItemsHost="True"
                                                KeyboardNavigation.DirectionalNavigation="Contained" />
                                    </ScrollViewer>
                                </Grid>
                            </Popup>
                        </Grid>
                        <ControlTemplate.Triggers>
                            <Trigger Property="HasItems" Value="false">
                                <Setter TargetName="DropDownBorder" Property="MinHeight" Value="95" />
                            </Trigger>
                            <Trigger Property="HasItems" Value="True">
                                <Setter Property="Background" Value="White" />
                            </Trigger>
                            <Trigger Property="IsGrouping" Value="true">
                                <Setter Property="ScrollViewer.CanContentScroll" Value="false" />
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>


        <!-- Sub TabItem Style -->
        <!-- TabControl Style-->
        <Style x:Key="ModernStyleTabControl" TargetType="TabControl">
            <Setter Property="OverridesDefaultStyle" Value="true"/>
            <Setter Property="SnapsToDevicePixels" Value="true"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="{x:Type TabControl}">
                        <Grid KeyboardNavigation.TabNavigation="Local">
                            <Grid.RowDefinitions>
                                <RowDefinition Height="40" />
                                <RowDefinition Height="*" />
                            </Grid.RowDefinitions>

                            <TabPanel x:Name="HeaderPanel"
                                Grid.Row="0"
                                Panel.ZIndex="1"
                                IsItemsHost="True"
                                KeyboardNavigation.TabIndex="1"
                                Background="#FF1D3245" />

                            <Border x:Name="Border"
                                Grid.Row="0"
                                BorderThickness="1"
                                BorderBrush="Black"
                                Background="#FF1D3245">

                                <ContentPresenter x:Name="PART_SelectedContentHost"
                                      Margin="0,0,0,0"
                                      ContentSource="SelectedContent" />
                            </Border>
                            <Border Grid.Row="1"
                                    BorderThickness="0"
                                    Background="#6da5e0"
                                    Panel.ZIndex="-1">
                                <ContentPresenter Margin="4" />
                            </Border>
                        </Grid>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style x:Key="ModernStyleTabItem" TargetType="{x:Type TabItem}">
            <Setter Property="Template">
                <Setter.Value>

                    <ControlTemplate TargetType="{x:Type TabItem}">
                        <Grid>
                            <Border
                                Name="Border"
                                Margin="10,10,10,10"
                                CornerRadius="0">
                                <ContentPresenter x:Name="ContentSite" VerticalAlignment="Center"
                                    HorizontalAlignment="Center" ContentSource="Header"
                                    RecognizesAccessKey="True" />
                            </Border>
                        </Grid>

                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter Property="Foreground" Value="#FF9C9C9C" />
                                <Setter Property="FontSize" Value="16" />
                                <Setter TargetName="Border" Property="BorderThickness" Value="1,0,1,1" />
                                <Setter TargetName="Border" Property="BorderBrush" Value="#FF1D3245" />
                            </Trigger>
                            <Trigger Property="IsMouseOver" Value="False">
                                <Setter Property="Foreground" Value="#FF666666" />
                                <Setter Property="FontSize" Value="16" />
                                <Setter TargetName="Border" Property="BorderThickness" Value="1,0,1,1" />
                                <Setter TargetName="Border" Property="BorderBrush" Value="#FF1D3245" />
                            </Trigger>
                            <Trigger Property="IsSelected" Value="True">
                                <Setter Property="Panel.ZIndex" Value="100" />
                                <Setter Property="Foreground" Value="white" />
                                <Setter Property="FontSize" Value="16" />
                                <Setter TargetName="Border" Property="BorderThickness" Value="1,0,1,1" />
                                <Setter TargetName="Border" Property="BorderBrush" Value="#FF1D3245" />
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style TargetType="{x:Type Button}">
            <Setter Property="Background" Value="#FF1D3245" />
            <Setter Property="Foreground" Value="#FFE8EDF9" />
            <Setter Property="FontSize" Value="15" />
            <Setter Property="SnapsToDevicePixels" Value="True" />

            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button" >

                        <Border Name="border" 
                            BorderThickness="1"
                            Padding="4,2" 
                            BorderBrush="#336891" 
                            CornerRadius="6" 
                            Background="#0078d7">
                            <ContentPresenter HorizontalAlignment="Center" 
                                            VerticalAlignment="Center" 
                                            TextBlock.TextAlignment="Center"
                                            />
                        </Border>

                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="border" Property="BorderBrush" Value="#FFE8EDF9" />
                            </Trigger>

                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="border" Property="BorderBrush" Value="#FF1D3245" />
                                <Setter Property="Button.Foreground" Value="#FF1D3245" />
                                <Setter Property="Effect">
                                    <Setter.Value>
                                        <DropShadowEffect ShadowDepth="0" Color="#FF1D3245" Opacity="1" BlurRadius="10"/>
                                    </Setter.Value>
                                </Setter>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="border" Property="BorderBrush" Value="#336891" />
                                <Setter Property="Button.Foreground" Value="#336891" />
                            </Trigger>
                            <Trigger Property="IsFocused" Value="False">
                                <Setter TargetName="border" Property="BorderBrush" Value="#336891" />
                                <Setter Property="Button.Background" Value="#336891" />
                            </Trigger>

                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style x:Key="CheckRadioFocusVisual">
            <Setter Property="Control.Template">
                <Setter.Value>
                    <ControlTemplate>
                        <Rectangle Margin="14,0,0,0" SnapsToDevicePixels="true" Stroke="{DynamicResource {x:Static SystemColors.ControlTextBrushKey}}" StrokeThickness="1" StrokeDashArray="1 2"/>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style x:Key="SliderCheckBox" TargetType="{x:Type CheckBox}">
            <Setter Property="Foreground" Value="{DynamicResource {x:Static SystemColors.ControlTextBrushKey}}"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Cursor" Value="Hand" />
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="{x:Type CheckBox}">
                        <ControlTemplate.Resources>
                            <Storyboard x:Key="StoryboardIsChecked">
                                <DoubleAnimationUsingKeyFrames Storyboard.TargetProperty="(UIElement.RenderTransform).(TransformGroup.Children)[3].(TranslateTransform.X)" Storyboard.TargetName="CheckFlag">
                                    <EasingDoubleKeyFrame KeyTime="0" Value="0"/>
                                    <EasingDoubleKeyFrame KeyTime="0:0:0.2" Value="14"/>
                                </DoubleAnimationUsingKeyFrames>
                            </Storyboard>
                            <Storyboard x:Key="StoryboardIsCheckedOff">
                                <DoubleAnimationUsingKeyFrames Storyboard.TargetProperty="(UIElement.RenderTransform).(TransformGroup.Children)[3].(TranslateTransform.X)" Storyboard.TargetName="CheckFlag">
                                    <EasingDoubleKeyFrame KeyTime="0" Value="14"/>
                                    <EasingDoubleKeyFrame KeyTime="0:0:0.2" Value="0"/>
                                </DoubleAnimationUsingKeyFrames>
                            </Storyboard>
                        </ControlTemplate.Resources>
                        <BulletDecorator Background="Transparent" SnapsToDevicePixels="true">
                            <BulletDecorator.Bullet>
                                <Border x:Name="ForegroundPanel" BorderThickness="1" Width="35" Height="20" CornerRadius="10">
                                    <Canvas>
                                        <Border Background="White" x:Name="CheckFlag" CornerRadius="10" VerticalAlignment="Center" BorderThickness="1" Width="19" Height="18" RenderTransformOrigin="0.5,0.5">
                                            <Border.RenderTransform>
                                                <TransformGroup>
                                                    <ScaleTransform/>
                                                    <SkewTransform/>
                                                    <RotateTransform/>
                                                    <TranslateTransform/>
                                                </TransformGroup>
                                            </Border.RenderTransform>
                                            <Border.Effect>
                                                <DropShadowEffect ShadowDepth="1" Direction="180" />
                                            </Border.Effect>
                                        </Border>
                                    </Canvas>
                                </Border>
                            </BulletDecorator.Bullet>
                            <ContentPresenter HorizontalAlignment="{TemplateBinding HorizontalContentAlignment}" Margin="{TemplateBinding Padding}" RecognizesAccessKey="True" SnapsToDevicePixels="{TemplateBinding SnapsToDevicePixels}" VerticalAlignment="Center"/>
                        </BulletDecorator>
                        <ControlTemplate.Triggers>
                            <Trigger Property="HasContent" Value="true">
                                <Setter Property="FocusVisualStyle" Value="{StaticResource CheckRadioFocusVisual}"/>
                                <Setter Property="Padding" Value="4,0,0,0"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="false">
                                <Setter Property="Foreground" Value="{DynamicResource {x:Static SystemColors.GrayTextBrushKey}}"/>
                            </Trigger>
                            <Trigger Property="IsChecked" Value="True">
                                <!--<Setter TargetName="ForegroundPanel" Property="Background" Value="{DynamicResource Accent}" />-->
                                <Setter TargetName="ForegroundPanel" Property="Background" Value="Green" />
                                <Trigger.EnterActions>
                                    <BeginStoryboard x:Name="BeginStoryboardCheckedTrue" Storyboard="{StaticResource StoryboardIsChecked}" />
                                    <RemoveStoryboard BeginStoryboardName="BeginStoryboardCheckedFalse" />
                                </Trigger.EnterActions>
                            </Trigger>
                            <Trigger Property="IsChecked" Value="False">
                                <Setter TargetName="ForegroundPanel" Property="Background" Value="Gray" />
                                <Trigger.EnterActions>
                                    <BeginStoryboard x:Name="BeginStoryboardCheckedFalse" Storyboard="{StaticResource StoryboardIsCheckedOff}" />
                                    <RemoveStoryboard BeginStoryboardName="BeginStoryboardCheckedTrue" />
                                </Trigger.EnterActions>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

    </ResourceDictionary>
</Window.Resources>
<Grid>
    <Label Content="2021 osd.osdeploy.com, GNU GPL 3.0" VerticalAlignment="Top" HorizontalAlignment="Right" FontSize="8" Foreground="#FFCBCACA" HorizontalContentAlignment="Right" Margin="0,10,10,0" Width="235"/>
    <Label x:Name="lblVersion" Content="ver 1.0" VerticalAlignment="Top" HorizontalAlignment="Right" FontSize="8" Foreground="#FFCBCACA" HorizontalContentAlignment="Right" Margin="0,22,10,0" Width="235"/>
    <Image x:Name="imgLogo" HorizontalAlignment="Center" VerticalAlignment="Top" Source=".\resources\osdlogo.png" Height="72" Width="Auto" Margin="422,22,416,0"/>
    <TextBlock HorizontalAlignment="Center" Text="Operating System Deployment in the Cloud" VerticalAlignment="Top" FontSize="48" Margin="10,82,15,0" TextAlignment="Center" FontFamily="Segoe UI Light" Width="999"/>
    <TextBlock HorizontalAlignment="Center" Text="Let's get the basic things out of the way" VerticalAlignment="Top" FontSize="16" FontFamily="Segoe UI Light" Margin="15,148,10,0" TextAlignment="Center" Height="26" Width="999"/>

    <Label x:Name="lblOSBuild" Content="Which Operating System build would you like to deploy?" HorizontalAlignment="Center" FontSize="16" VerticalAlignment="Top" Width="446" HorizontalContentAlignment="Left" Margin="30,199,548,0"/>
    <Label Content="Build" HorizontalAlignment="Center" FontSize="16" VerticalAlignment="Top" Width="85" HorizontalContentAlignment="Right" Margin="51,235,888,0" FontWeight="Bold" Foreground="Red"/>
    <ComboBox x:Name="cmbOSBuildList" HorizontalAlignment="Center" VerticalAlignment="Top" Width="364" Height="30" FontSize="18" Margin="146,235,514,0" Style="{DynamicResource SimpleComboBoxStyle}" />
    <Label x:Name="lblOSEdition" Content="What Edition will this Operating System be?" HorizontalAlignment="Center" FontSize="16" VerticalAlignment="Top"  Width="446" HorizontalContentAlignment="Left" Margin="30,295,548,0"  />
    <Label Content="Edition" HorizontalAlignment="Center" FontSize="16" VerticalAlignment="Top" Width="85" HorizontalContentAlignment="Right" Margin="51,332,888,0" FontWeight="Bold" Foreground="Red"/>
    <ComboBox x:Name="cmbOSEditionList" HorizontalAlignment="Center" Margin="146,332,514,0" VerticalAlignment="Top" Width="364" Height="30" FontSize="18" Style="{DynamicResource SimpleComboBoxStyle}" />
    <Label x:Name="lblOSLanguage" Content="What will the default Language be?" HorizontalAlignment="Center" FontSize="16" VerticalAlignment="Top" Width="480" HorizontalContentAlignment="Left" Margin="30,389,514,0"/>
    <Label Content="Language" HorizontalAlignment="Center" FontSize="16" VerticalAlignment="Top" Width="84" HorizontalContentAlignment="Right" Margin="52,420,888,0" FontWeight="Bold" Foreground="Red"/>
    <ComboBox x:Name="cmbOSLanguageList" HorizontalAlignment="Center" Margin="146,422,514,0" VerticalAlignment="Top" Width="364" Height="30" FontSize="18" Style="{DynamicResource SimpleComboBoxStyle}" />

    <GroupBox Header="Additional Options" HorizontalAlignment="Left" Height="181" Margin="745,195,0,0" VerticalAlignment="Top" Width="246" Foreground="Gray" />
    <CheckBox x:Name="chkSkipODT"  Content="Skip Office 365 Install" HorizontalAlignment="Center" Margin="791,226,73,0" VerticalAlignment="Top" Width="160" Style="{DynamicResource SliderCheckBox}" />
    <CheckBox x:Name="chkUseOSDZTI"  Content="Use OSD ZTI Settings" HorizontalAlignment="Center" Margin="791,300,73,0" VerticalAlignment="Top" Width="160" Style="{DynamicResource SliderCheckBox}" />
    <CheckBox x:Name="chkSkipAP"  Content="Skip AutoPilot OOBE" HorizontalAlignment="Center" Margin="791,262,73,0" VerticalAlignment="Top" Width="160" Style="{DynamicResource SliderCheckBox}" />
    <CheckBox x:Name="chkScreenshots" Content="Take Screenshots" HorizontalAlignment="Center" Margin="791,339,73,0" VerticalAlignment="Top" Width="160" Style="{DynamicResource SliderCheckBox}" />


    <TabControl x:Name="tabControlAdvance" Style="{DynamicResource ModernStyleTabControl}" HorizontalAlignment="Center" VerticalAlignment="Bottom" Margin="10,0,10,5" Width="999" Height="100">

        <TabItem x:Name="tabHardware" Header="Hardware" Style="{DynamicResource ModernStyleTabItem}" >
            <Grid Background="#004275">
                <Grid Margin="0,50,2,-61">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="auto" MinWidth="121"></ColumnDefinition>
                        <ColumnDefinition></ColumnDefinition>
                        <ColumnDefinition Width="auto" MinWidth="121"></ColumnDefinition>
                        <ColumnDefinition></ColumnDefinition>
                    </Grid.ColumnDefinitions>
                    <Grid.RowDefinitions>
                        <RowDefinition></RowDefinition>
                    </Grid.RowDefinitions>
                    <Label Content="Manufacturer:" Grid.Row="0" Grid.Column="0" HorizontalAlignment="Right" FontSize="16"  VerticalAlignment="Top" Foreground="Black" Height="43" Width="121" HorizontalContentAlignment="Right" VerticalContentAlignment="Center"/>
                    <TextBox x:Name="txtManufacturer" Grid.Row="0" Grid.Column="1" HorizontalAlignment="Left" TextWrapping="NoWrap" FontSize="18" Width="367" VerticalContentAlignment="Center" BorderBrush="#FF8595AB" Foreground="#FF8595AB" Padding="2,0,0,0" Height="43" VerticalAlignment="Top"/>
                    <Label Content="Product:" Grid.Row="0" Grid.Column="2" HorizontalAlignment="Right" FontSize="16" VerticalAlignment="Top" Foreground="Black" Height="40" Width="120" HorizontalContentAlignment="Right" VerticalContentAlignment="Center" Margin="0,3,0.5,0"/>
                    <TextBox x:Name="txtProduct" Grid.Row="0" Grid.Column="3" HorizontalAlignment="Left" TextWrapping="NoWrap" FontSize="18" Width="367" VerticalContentAlignment="Center" BorderBrush="#FF8595AB" Foreground="#FF8595AB" Padding="2,0,0,0" Height="43" VerticalAlignment="Top"/>
                </Grid>
            </Grid>
        </TabItem>
        <TabItem x:Name="tabCustomImage" Header="Custom Image" Style="{DynamicResource ModernStyleTabItem}" >
            <Grid Background="#004275">
                <Grid Margin="0,50,2,-61">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="auto" MinWidth="148"></ColumnDefinition>
                        <ColumnDefinition Width="149"></ColumnDefinition>
                        <ColumnDefinition Width="572*"></ColumnDefinition>
                        <ColumnDefinition Width="47*"></ColumnDefinition>
                        <ColumnDefinition Width="79*"></ColumnDefinition>
                    </Grid.ColumnDefinitions>
                    <Grid.RowDefinitions>
                        <RowDefinition></RowDefinition>
                    </Grid.RowDefinitions>
                    <CheckBox x:Name="chkFindImage" Grid.Column="0" Content="Auto find image" HorizontalAlignment="Left" VerticalAlignment="Center" Height="20" Width="137" Margin="10,14,0,15"/>
                    <Label Content="Custom image url:" HorizontalAlignment="Center" FontSize="16" VerticalAlignment="Center" Width="146"  HorizontalContentAlignment="Right" VerticalContentAlignment="Center" Height="44" Margin="146,2,5,3" Grid.ColumnSpan="2" />
                    <TextBox x:Name="txtCustomImage" Grid.Column="2" HorizontalAlignment="Left" TextWrapping="NoWrap" FontSize="18" Width="562" VerticalContentAlignment="Center" BorderBrush="#FF8595AB" Foreground="#FF8595AB" Padding="2,0,0,0" Height="43" VerticalAlignment="Top"/>
                    <Label Grid.Column="2" Content="Index" HorizontalAlignment="Center" FontSize="16" VerticalAlignment="Center" Width="74"  HorizontalContentAlignment="Right" VerticalContentAlignment="Center" Height="44" Margin="549,2,75,3" Grid.ColumnSpan="3"/>
                    <ComboBox x:Name="cmbImageIndex" Grid.Column="4" HorizontalAlignment="Center" Width="62" Height="38" FontSize="18" VerticalAlignment="Center" VerticalContentAlignment="Center" Margin="7,2,10,9"/>
                </Grid>
            </Grid>
        </TabItem>
        <TabItem x:Name="tabDeviceName" Header="Device Name" Style="{DynamicResource ModernStyleTabItem}" >
            <Grid Background="#004275">
                <Grid Margin="0,50,2,-61">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="auto" MinWidth="148"></ColumnDefinition>
                        <ColumnDefinition Width="*"></ColumnDefinition>
                    </Grid.ColumnDefinitions>
                    <Grid.RowDefinitions>
                        <RowDefinition></RowDefinition>
                    </Grid.RowDefinitions>

                    <Label Grid.Column="0" Content="What would you like the device name to be?" HorizontalAlignment="Center" FontSize="16" VerticalAlignment="Center" Width="327"  HorizontalContentAlignment="Right" VerticalContentAlignment="Center" Height="44" />
                    <TextBox x:Name="txtComputerName" Grid.Column="1" HorizontalAlignment="Left" TextWrapping="NoWrap" FontSize="18" Width="562" VerticalContentAlignment="Center" BorderBrush="#FF8595AB" Foreground="#FF8595AB" Padding="2,0,0,0" Height="43" VerticalAlignment="Top"/>

                </Grid>
            </Grid>
        </TabItem>

    </TabControl>
    <Button x:Name="btnStart" Content="Start Deployment" Height="90" Width="246" HorizontalAlignment="Center" VerticalAlignment="Top" FontSize="18" Padding="10" Margin="745,391,33,0"/>
</Grid>
</Window>
"@

    [xml]$XAML = $xamlpath -replace 'mc:Ignorable="d"','' -replace "x:N",'N' -replace '^<Win.*', '<Window'
    
    $AppReader=(New-Object System.Xml.XmlNodeReader $XAML)
    try{
        $OSDeployUI=[Windows.Markup.XamlReader]::Load($AppReader)
    }
    catch{
        $ErrorMessage = $_.Exception.Message
        Write-Host "Unable to load Windows.Markup.XamlReader. Some possible causes for this problem include:
        - .NET Framework is missing
        - PowerShell must be launched with PowerShell -sta
        - invalid XAML code was encountered
        - The error message was [$ErrorMessage]" -ForegroundColor White -BackgroundColor Red
        Exit
    }

    $XAML.SelectNodes("//*[@Name]") | ForEach-Object { Set-Variable -Name "OSDeployUI_$($_.Name)" -Value $OSDeployUI.FindName($_.Name)}

    #================================
    # SET PROPERTY IN UI
    #================================
    $OSDeployUI_tabDeviceName.Visibility = 'hidden'
    [string]$OSDeployUI_lblVersion.Content = "Version $AppVersion"

    If(-Not[string]::IsNullOrEmpty($ImageURL) ){
        $OSDeployUI_imgLogo.source = $ImageURL
    }
    [string]$OSDeployUI_tabControlAdvance.Visibility = 'hidden'

    $DeviceInfo = Get-PlatformInfo
    [string]$OSDeployUI_txtProduct.Text = $DeviceInfo.PlatformModel
    [string]$OSDeployUI_txtManufacturer.Text = $DeviceInfo.PlatformManufacturer

    $OSBuild = Get-ParameterOption -Command 'Start-OSDCloud' -Parameter 'OSBuild'
    $OSBuild | %{$OSDeployUI_cmbOSBuildList.Items.Add("Windows 10 [$_]") | Out-Null}

    $OSEdition = Get-ParameterOption -Command 'Start-OSDCloud' -Parameter 'OSEdition'
    $OSEdition | %{$OSDeployUI_cmbOSEditionList.Items.Add("Windows 10 [$_]") | Out-Null}

    $UILanguageTable = @{
        'Arabic (Saudi Arabia)' = "ar-SA"
        'Bulgarian (Bulgaria)' = "bg-BG"
        'Chinese (PRC)' = "zh-CN"
        'Chinese (Taiwan)' = "zh-TW"
        'Croatian (Croatia)' = "hr-HR"
        'Czech (Czech Republic)' = "cs-CZ"
        'Danish (Denmark)' = "da-DK"
        'Dutch (Netherlands)' = "nl-NL"
        'English (United States)' = "en-US"
        'English (United Kingdom)' = "en-GB"
        'Estonian (Estonia)' = "et-EE"
        'Finnish (Finland)' = "fi-FI"
        'French (Canada)' = "fr-CA"
        'French (France)' = "fr-FR"
        'German (Germany)' = "de-DE"
        'Greek (Greece)' = "el-GR"
        'Hebrew (Israel)' = "he-IL"
        'Hungarian (Hungary)' = "hu-HU"
        'Italian (Italy)' = "it-IT"
        'Japanese (Japan)' = "ja-JP"
        'Korean (Korea)' = "ko-KR"
        'Latvian (Latvia)' = "lv-LV"
        'Lithuanian (Lithuania)' = "lt-LT"
        'Norwegian, Bokmål (Norway)' = "nb-NO"
        'Polish (Poland)' = "pl-PL"
        'Portuguese (Brazil)' = "pt-BR"
        'Portuguese (Portugal)' = "pt-PT"
        'Romanian (Romania)' = "ro-RO"
        'Russian (Russia)' = "ru-RU"
        'Serbian (Latin, Serbia)' = "sr-Latn-RS"
        'Slovak (Slovakia)' = "sk-SK"
        'Slovenian (Slovenia)' = "sl-SI"
        'Spanish (Mexico)' = "es-MX"
        'Spanish (Spain)' = "es-ES"
        'Swedish (Sweden)' = "sv-SE"
        'Thai (Thailand)' = "th-TH"
        'Turkish (Turkey)' = "tr-TR"
        'Ukrainian (Ukraine)' = "uk-UA"
    }

    $OSLanguage = Get-ParameterOption -Command 'Start-OSDCloud' -Parameter 'OSLanguage'
    $UILanguageTable.GetEnumerator() | %{($_.Name + ' - ' + $_.Value)} | %{$OSDeployUI_cmbOSLanguageList.Items.Add($_) | Out-Null}

    @('1','2','3','4','5','6','7','8','9') | %{$OSDeployUI_cmbImageIndex.Items.Add($_) | Out-Null}
    $OSDeployUI_cmbImageIndex.SelectedItem = '1'

    #====================================
    # CHANGE EVENTS
    #====================================

    #Chain Dropdowns to ensure an item is selected
    $OSDeployUI_btnStart.IsEnabled = $False
    $OSDeployUI_cmbOSEditionList.IsEnabled = $False
    $OSDeployUI_cmbOSLanguageList.IsEnabled = $False

    $OSDeployUI_cmbOSBuildList.Add_SelectionChanged({
        $OSDeployUI_cmbOSEditionList.IsEnabled = $true
        #If($OSDeployUI_cmbOSBuildList.SelectedItem -ne 'Windows 10 [Enterprise]'){
        #    $OSDeployUI_chkUseOSDZTI.IsChecked = $False
        #}
    })

    $OSDeployUI_cmbOSEditionList.Add_SelectionChanged({
        $OSDeployUI_cmbOSLanguageList.IsEnabled = $true

    })

    $OSDeployUI_cmbOSLanguageList.Add_SelectionChanged({
        $OSDeployUI_btnStart.IsEnabled = $true
    })

    #Default selection to enterprise option if checked
    [System.Windows.RoutedEventHandler]$Script:CheckedEventHandler = {
        $OSDeployUI_cmbOSBuildList.SelectedItem = $OSDeployUI_cmbOSBuildList.Items[0]
        $OSDeployUI_cmbOSEditionList.SelectedItem = 'Windows 10 [Enterprise]'
        $OSDeployUI_cmbOSLanguageList.SelectedItem = 'English (United States) - en-US'
    }
    $OSDeployUI_chkUseOSDZTI.AddHandler([System.Windows.Controls.CheckBox]::CheckedEvent, $CheckedEventHandler)

    #Disable custom image if auto is checked
    [System.Windows.RoutedEventHandler]$Script:CheckedEventHandler = {
            $OSDeployUI_txtCustomImage.IsEnabled = $False
            $OSDeployUI_cmbImageIndex.IsEnabled = $False
    }
    $OSDeployUI_chkFindImage.AddHandler([System.Windows.Controls.CheckBox]::CheckedEvent, $CheckedEventHandler)

    #Disable custom image if auto is checked
    [System.Windows.RoutedEventHandler]$Script:UnCheckedEventHandler = {
            $OSDeployUI_txtCustomImage.IsEnabled = $True
            $OSDeployUI_cmbImageIndex.IsEnabled = $True
    }
    $OSDeployUI_chkFindImage.AddHandler([System.Windows.Controls.CheckBox]::UncheckedEvent, $UnCheckedEventHandler)

    $OSDeployUI.Add_MouseLeftButtonDown({
        $OSDeployUI.DragMove()
    })

    #====================================
    # BUTTON EVENTS
    #====================================

    #Region CLICKACTION: Begin will be enabled if validated is run
    $OSDeployUI_btnStart.Add_Click({

        #Splat Parameters with values
        $OSCloudParams = @{
            OSBuild = (Get-TextWithin -Text $OSDeployUI_cmbOSBuildList.SelectedItem -WithinChar '[')
            OSEdition = (Get-TextWithin -Text $OSDeployUI_cmbOSEditionList.SelectedItem -WithinChar '[')
            OSLanguage = (Get-TextWithin -Text $OSDeployUI_cmbOSLanguageList.SelectedItem -Regex '[^\s]+$')
            SkipAutopilot=$OSDeployUI_chkSkipAP.IsChecked
            SkipODT=$OSDeployUI_chkSkipODT.IsChecked
            ZTI=$OSDeployUI_chkUseOSDZTI.IsChecked
            Screenshot=$OSDeployUI_chkScreenshots.IsChecked
            FindImageFile=$OSDeployUI_chkFindImage.IsChecked
        }

        #append hashtable if product is different than device model
        if($OSDeployUI_txtProduct.Text -ne $DeviceInfo.PlatformModel)
        {
            $OSCloudParams += @{
                Product=$OSDeployUI_txtProduct.Text
            }
        }

        #append hashtable if manufacturer is different than device
        if($OSDeployUI_txtManufacturer.Text -ne $DeviceInfo.PlatformManufacturer)
        {
            $OSCloudParams += @{
                Manufacturer=$OSDeployUI_txtManufacturer.Text
            }
        }

        #append hashtable if custom image path is specified
        if( -Not([string]::IsNullOrEmpty($OSDeployUI_txtCustomImage.Text)) )
        {
            $OSCloudParams += @{
                ImageFileUrl=$OSDeployUI_txtCustomImage.Text
                ImageIndex=$OSDeployUI_cmbImageIndex.SelectedItem
            }
        }

        #append hashtable if computer name is specified
        if( -Not([string]::IsNullOrEmpty($OSDeployUI_txtComputerName.Text)) )
        {
            $OSCloudParams += @{
                DeviceName=$OSDeployUI_txtComputerName.Text
            }
        }
        #>

        #Make hash a global hash for export
        $Global:OSCloudParams = $OSCloudParams

        $OSDeployUI.Close() | Out-Null
    })

    ##*==============================
    ##* LOAD FORM - APP CONTENT AND BUTTONS
    ##*==============================
    #Console control

    #Slower method to present form for non modal (no popups)
    #$OSDeployUI.ShowDialog() | Out-Null

    # Allow input to window for TextBoxes, etc
    [Void][System.Windows.Forms.Integration.ElementHost]::EnableModelessKeyboardInterop($OSDeployUI)

    #for ISE testing only: Add ESC key as a way to exit UI
    $KeyCode = {
        [System.Windows.Input.KeyEventArgs]$keyup = $args[1]
        if ($keyup.Key -eq 'F12')
        {
            If($OSDeployUI_tabControlAdvance.Visibility -ne 'Visible'){
                #write-host 'Advanced mode enabled'
                $OSDeployUI_tabControlAdvance.Visibility = 'Visible'
                If($HideVersion){$OSDeployUI_lblVersion.Visibility = 'Visible'}
            }Else{
                #write-host 'Advanced mode disabled'
                $OSDeployUI_tabControlAdvance.Visibility = 'Hidden'
                If($HideVersion){$OSDeployUI_lblVersion.Visibility = 'Hidden'}
            }
        }
        ElseIf($keyup.Key -eq 'ESC'){
            $OSDeployUI.Close() | Out-Null
        }
    }

    $null = $OSDeployUI.add_KeyUp($KeyCode)

    $OSDeployUI.Add_Closing({
        [System.Windows.Forms.Application]::Exit()
    })

    $async1 = $OSDeployUI.Dispatcher.InvokeAsync({

        #make sure this display on top of every window
        $OSDeployUI.Topmost = $true
        # Running this without $appContext & ::Run would actually cause a really poor response.
        $OSDeployUI.Show() | Out-Null
        # This makes it pop up
        $OSDeployUI.Activate() | Out-Null

        #$OSDeployUI.window.ShowDialog()
    })
    $async1.Wait() | Out-Null

    ## Force garbage collection to start form with slightly lower RAM usage.
    [System.GC]::Collect() | Out-Null
    [System.GC]::WaitForPendingFinalizers() | Out-Null

    # Create an application context for it to all run within.
    # This helps with responsiveness, especially when Exiting.
    $appContext1 = New-Object System.Windows.Forms.ApplicationContext
    [void][System.Windows.Forms.Application]::Run($appContext1)

    #[Environment]::Exit($ExitCode);

    #output whatif results
    If(Test-WinPE){
        # Credits to - http://powershell.cz/2013/04/04/hide-and-show-console-window-from-gui/
        If($HideConsole){
            $windowcode = '[DllImport("user32.dll")] public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);'
            $asyncwindow = Add-Type -MemberDefinition $windowcode -name Win32ShowWindowAsync -namespace Win32Functions -PassThru
            $null = $asyncwindow::ShowWindowAsync((Get-Process -PID $pid).MainWindowHandle, 0)
        }
        Start-OSDCloud @Global:OSCloudParams
    }
    Else{
        $StringOutput = ($Global:OSCloudParams.GetEnumerator() | %{ If($_.Value -eq $true){"-" + $_.Key}ElseIf($_.Value -ne $false){"-" + $_.Key + ' ' + $_.Value} }) -join ' '
        write-host ('What if: Performing function call "Start-OSDeploy" with Parameters "{0}".' -f $StringOutput) -ForegroundColor Yellow
    }
}
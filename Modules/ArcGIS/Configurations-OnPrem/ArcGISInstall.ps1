Configuration ArcGISInstall{
    param(
        [Parameter(Mandatory=$false)]
        [System.Management.Automation.PSCredential]
        $ServiceCredential,

        [Parameter(Mandatory=$false)]
        [System.Boolean]
        $ServiceCredentialIsDomainAccount = $false,

        [Parameter(Mandatory=$false)]
        [System.Boolean]
        $ServiceCredentialIsMSA = $false,

        [Parameter(Mandatory=$false)]
        [System.Boolean]
        $EnableMSILogging = $false
    )

    Import-DscResource -ModuleName PSDesiredStateConfiguration
    Import-DSCResource -ModuleName @{ModuleName="ArcGIS";ModuleVersion="3.3.0"}
    Import-DscResource -Name ArcGIS_Install
    Import-DscResource -Name ArcGIS_InstallMsiPackage
    Import-DscResource -Name ArcGIS_InstallPatch

    Node $AllNodes.NodeName {

        if($Node.Thumbprint){
            LocalConfigurationManager
            {
                CertificateId = $Node.Thumbprint
            }
        }

        $NodeRoleArray = @()
        if($Node.Role -icontains "Server")
        {
            $NodeRoleArray += "Server"
        }
        if($Node.Role -icontains "Portal")
        {
            $NodeRoleArray += "Portal"
        }
        if(($Node.Role -icontains "Server" -or $Node.Role -icontains "Portal") -and $ConfigurationData.ConfigData.Insights){
            $NodeRoleArray += "Insights"
        }
        if($Node.Role -icontains "DataStore")
        {
            $NodeRoleArray += "DataStore"
        }
        if($Node.Role -icontains "ServerWebAdaptor")
        {
            $NodeRoleArray += "ServerWebAdaptor"
        }
        if($Node.Role -icontains "PortalWebAdaptor")
        {
            $NodeRoleArray += "PortalWebAdaptor"
        }
        if($Node.Role -icontains "Desktop")
        {
            $NodeRoleArray += "Desktop"
        }
        if($Node.Role -icontains "Pro")
        {
            $NodeRoleArray += "Pro"
        }
        if($Node.Role -icontains "LicenseManager")
        {
            $NodeRoleArray += "LicenseManager"
        }
        if($Node.Role -icontains "SQLServerClient"){
            $NodeRoleArray += "SQLServerClient"
        }

        for ( $i = 0; $i -lt $NodeRoleArray.Count; $i++ )
        {
            $NodeRole = $NodeRoleArray[$i]
            Switch($NodeRole)
            {
                'Server'
                {
                    $ServerTypeName = if($ConfigurationData.ConfigData.ServerRole -ieq "NotebookServer" -or $ConfigurationData.ConfigData.ServerRole -ieq "MissionServer" ){ $ConfigurationData.ConfigData.ServerRole }else{ "Server" }

                    $ServerInstallArguments = "/qn ACCEPTEULA=YES InstallDir=`"$($ConfigurationData.ConfigData.Server.Installer.InstallDir)`""
                    if($ServerTypeName -ieq "Server"){
                        if($ConfigurationData.ConfigData.Version -ieq "10.9.1"){ # TODO - Make this more generalized at a later date
                            $EnableArcMapRuntime = if($ConfigurationData.ConfigData.Server.Installer.ContainsKey("EnableArcMapRuntime")){ $ConfigurationData.ConfigData.Server.Installer.EnableArcMapRuntime }else{ $True }
                            $ServerInstallArguments = "/qn ACCEPTEULA=YES InstallDir=`"$($ConfigurationData.ConfigData.Server.Installer.InstallDir)`""
                            if($ConfigurationData.ConfigData.Server.Installer.EnableDotnetSupport -and $EnableArcMapRuntime){
                                $ServerInstallArguments += " INSTALLDIR1=`"$($ConfigurationData.ConfigData.Server.Installer.InstallDirPython)`""
                            }elseif($ConfigurationData.ConfigData.Server.Installer.EnableDotnetSupport -and -not($EnableArcMapRuntime)){
                                $ServerInstallArguments += " ADDLOCAL=DotNetSupport"
                            }elseif($EnableArcMapRuntime -and -not($ConfigurationData.ConfigData.Server.Installer.EnableDotnetSupport)){
                                $ServerInstallArguments += " ADDLOCAL=ArcMap INSTALLDIR1=`"$($ConfigurationData.ConfigData.Server.Installer.InstallDirPython)`""
                            }else{
                                $ServerInstallArguments += " ADDLOCAL=GIS_Server"
                            }
                        }else{
                            $ServerInstallArguments = "/qn ACCEPTEULA=YES InstallDir=`"$($ConfigurationData.ConfigData.Server.Installer.InstallDir)`" INSTALLDIR1=`"$($ConfigurationData.ConfigData.Server.Installer.InstallDirPython)`""
                        }                        
                    }

                    ArcGIS_Install ServerInstall
                    {
                        Name = $ServerTypeName
                        Version = $ConfigurationData.ConfigData.Version
                        Path = $ConfigurationData.ConfigData.Server.Installer.Path
                        Arguments = $ServerInstallArguments
                        ServiceCredential = $ServiceCredential
                        ServiceCredentialIsDomainAccount =  $ServiceCredentialIsDomainAccount
                        ServiceCredentialIsMSA = $ServiceCredentialIsMSA
                        EnableMSILogging = $EnableMSILogging
                        Ensure = "Present"
                    }

                    if($ServerTypeName -ieq "Server" -and $ConfigurationData.ConfigData.Server.Extensions){
                        foreach ($Extension in $ConfigurationData.ConfigData.Server.Extensions.GetEnumerator())
                        {
                            $Arguments = "/qn"
                            if($Extension.Value.Features -and $Extension.Value.Features.Count -gt 0){
								$Features = $null
								if($Extension.Value.Features -icontains "ALL"){
									$Features = "ALL"
								}else{
									$Extension.Value.Features | % {
										if($null -eq $Features){ 
											$Features = $_
										}else{
											$Features += ",$_"
										}
									}
								}

                                $Arguments += " ADDLOCAL=$Features"
                            }

                            ArcGIS_Install "Server$($Extension.Key)InstallExtension"
                            {
                                Name = "Server$($Extension.Key)"
                                Version = $ConfigurationData.ConfigData.Version
                                Path = $Extension.Value.Installer.Path
                                Arguments = $Arguments
                                EnableMSILogging = $EnableMSILogging
                                Ensure = "Present"
                            }
                        }
                    }

                    if ($ConfigurationData.ConfigData.Server.Installer.PatchesDir) {
                        ArcGIS_InstallPatch ServerInstallPatch
                        {
                            Name = $ServerTypeName
                            Version = $ConfigurationData.ConfigData.Version
                            PatchesDir = $ConfigurationData.ConfigData.Server.Installer.PatchesDir
                            Ensure = "Present"
                        }
                    }

                    if($ConfigurationData.ConfigData.ServerRole -ieq "NotebookServer" -and $ConfigurationData.ConfigData.Server.Installer.NotebookServerSamplesDataPath) 
                    {
                        if($ConfigurationData.ConfigData.Version.Split(".")[1] -gt 8){
                            ArcGIS_Install "NotebookServerSamplesData$($Node.NodeName)"
                            { 
                                Name = "NotebookServerSamplesData"
                                Version = $ConfigurationData.ConfigData.Version
                                Path = $ConfigurationData.ConfigData.Server.Installer.NotebookServerSamplesDataPath
                                Arguments = "/qn"
                                ServiceCredential = $ServiceCredential
                                ServiceCredentialIsDomainAccount =  $ServiceCredentialIsDomainAccount
                                ServiceCredentialIsMSA = $ServiceCredentialIsMSA
                                EnableMSILogging = $EnableMSILogging
                                Ensure = "Present"
                            }
                        }
                    }
                    
                    if($ConfigurationData.ConfigData.WorkflowManagerServer) 
                    {
                        ArcGIS_Install WorkflowManagerServerInstall
                        {
                            Name = "WorkflowManagerServer"
                            Version = $ConfigurationData.ConfigData.Version
                            Path = $ConfigurationData.ConfigData.WorkflowManagerServer.Installer.Path
                            Arguments = "/qn"
                            ServiceCredential = $ServiceCredential
                            ServiceCredentialIsDomainAccount =  $ServiceCredentialIsDomainAccount
                            ServiceCredentialIsMSA = $ServiceCredentialIsMSA
                            EnableMSILogging = $EnableMSILogging
                            Ensure = "Present"
                        }
                    }

                    if($ConfigurationData.ConfigData.GeoEventServer) 
                    { 
                        ArcGIS_Install GeoEventServerInstall
                        {
                            Name = "GeoEvent"
                            Version = $ConfigurationData.ConfigData.Version
                            Path = $ConfigurationData.ConfigData.GeoEventServer.Installer.Path
                            Arguments = if($ConfigurationData.ConfigData.GeoEventServer.EnableGeoeventSDK){ "/qn ADDLOCAL=GeoEvent,SDK"}else{ "/qn" };
                            ServiceCredential = $ServiceCredential
                            ServiceCredentialIsDomainAccount =  $ServiceCredentialIsDomainAccount
                            ServiceCredentialIsMSA = $ServiceCredentialIsMSA
                            EnableMSILogging = $EnableMSILogging
                            Ensure = "Present"
                        }

                        if ($ConfigurationData.ConfigData.GeoEventServer.Installer.PatchesDir) {
                            ArcGIS_InstallPatch GeoeventServerInstallPatch
                            {
                                Name = "GeoEvent"
                                Version = $ConfigurationData.ConfigData.Version
                                PatchesDir = $ConfigurationData.ConfigData.GeoEventServer.Installer.PatchesDir
                                Ensure = "Present"
                            }
                        }
                    }
                }
                'Portal'
                {        
                    ArcGIS_Install "PortalInstall$($Node.NodeName)"
                    { 
                        Name = "Portal"
                        Version = $ConfigurationData.ConfigData.Version
                        Path = $ConfigurationData.ConfigData.Portal.Installer.Path
                        Arguments = "/qn ACCEPTEULA=YES INSTALLDIR=`"$($ConfigurationData.ConfigData.Portal.Installer.InstallDir)`" CONTENTDIR=`"$($ConfigurationData.ConfigData.Portal.Installer.ContentDir)`""
                        ServiceCredential = $ServiceCredential
                        ServiceCredentialIsDomainAccount =  $ServiceCredentialIsDomainAccount
                        ServiceCredentialIsMSA = $ServiceCredentialIsMSA
                        EnableMSILogging = $EnableMSILogging
                        Ensure = "Present"
                    }

                    $VersionArray = $ConfigurationData.ConfigData.Version.Split(".")
                    $MajorVersion = $VersionArray[1]
                    $MinorVersion = if($VersionArray.Length -gt 2){ $VersionArray[2] }else{ 0 }

                    if((($MajorVersion -eq 7 -and $MinorVersion -eq 1) -or ($MajorVersion -ge 8)) -and $ConfigurationData.ConfigData.Portal.Installer.WebStylesPath){
                        ArcGIS_Install "WebStylesInstall$($Node.NodeName)"
                        { 
                            Name = "WebStyles"
                            Version = $ConfigurationData.ConfigData.Version
                            Path = $ConfigurationData.ConfigData.Portal.Installer.WebStylesPath
                            Arguments = "/qn"
                            ServiceCredential = $ServiceCredential
                            ServiceCredentialIsDomainAccount =  $ServiceCredentialIsDomainAccount
                            ServiceCredentialIsMSA = $ServiceCredentialIsMSA
                            EnableMSILogging = $EnableMSILogging
                            Ensure = "Present"
                        }
                    }

                    if ($ConfigurationData.ConfigData.Portal.Installer.PatchesDir) {
                        ArcGIS_InstallPatch PortalInstallPatch
                        {
                            Name = "Portal"
                            Version = $ConfigurationData.ConfigData.Version
                            PatchesDir = $ConfigurationData.ConfigData.Portal.Installer.PatchesDir
                            Ensure = "Present"
                        }
                    }

                    if($ConfigurationData.ConfigData.WorkflowManagerWebApp) 
                    {
                        ArcGIS_Install WorkflowManagerWebAppInstall
                        {
                            Name = "WorkflowManagerWebApp"
                            Version = $ConfigurationData.ConfigData.Version
                            Path = $ConfigurationData.ConfigData.WorkflowManagerWebApp.Installer.Path
                            Arguments = "/qn ACCEPTEULA=Yes"
                            ServiceCredential = $ServiceCredential
                            ServiceCredentialIsDomainAccount =  $ServiceCredentialIsDomainAccount
                            ServiceCredentialIsMSA = $ServiceCredentialIsMSA
                            EnableMSILogging = $EnableMSILogging
                            Ensure = "Present"
                        }
                    }
                }
                'Insights'
                {
                    ArcGIS_Install InsightsInstall
                    {
                        Name = "Insights"
                        Version = $ConfigurationData.ConfigData.InsightsVersion
                        Path = $ConfigurationData.ConfigData.Insights.Installer.Path
                        Arguments = "/qn ACCEPTEULA=YES"
                        ServiceCredential = $ServiceCredential
                        ServiceCredentialIsDomainAccount =  $ServiceCredentialIsDomainAccount
                        ServiceCredentialIsMSA = $ServiceCredentialIsMSA
                        EnableMSILogging = $EnableMSILogging
                        Ensure = "Present"
                    }

                    if ($ConfigurationData.ConfigData.Insights.Installer.PatchesDir) {
                        ArcGIS_InstallPatch InsightsInstallPatch
                        {
                            Name = "Insights"
                            Version = $ConfigurationData.ConfigData.InsightsVersion
                            PatchesDir = $ConfigurationData.ConfigData.Insights.Installer.PatchesDir
                            Ensure = "Present"
                        }
                    }
                }
                'DataStore'
                {
                    ArcGIS_Install DataStoreInstall
                    { 
                        Name = "DataStore"
                        Version = $ConfigurationData.ConfigData.Version
                        Path = $ConfigurationData.ConfigData.DataStore.Installer.Path
                        Arguments = "/qn ACCEPTEULA=YES InstallDir=`"$($ConfigurationData.ConfigData.DataStore.Installer.InstallDir)`""
                        ServiceCredential = $ServiceCredential
                        ServiceCredentialIsDomainAccount =  $ServiceCredentialIsDomainAccount
                        ServiceCredentialIsMSA = $ServiceCredentialIsMSA
                        EnableMSILogging = $EnableMSILogging
                        Ensure = "Present"
                    }

                    if ($ConfigurationData.ConfigData.DataStore.Installer.PatchesDir) {
                        ArcGIS_InstallPatch DataStoreInstallPatch
                        {
                            Name = "DataStore"
                            Version = $ConfigurationData.ConfigData.Version
                            PatchesDir = $ConfigurationData.ConfigData.DataStore.Installer.PatchesDir
                            Ensure = "Present"
                        }
                    } 
                }
                {($_ -eq "ServerWebAdaptor") -or ($_ -eq "PortalWebAdaptor")}
                {
                    $PortalWebAdaptorSkip = $False
                    if(($Node.Role -icontains 'ServerWebAdaptor') -and ($Node.Role -icontains 'PortalWebAdaptor'))
                    {
                        if($NodeRole -ieq "PortalWebAdaptor")
                        {
                            $PortalWebAdaptorSkip = $True
                        }
                    }
                    
                    if(-not($PortalWebAdaptorSkip))
                    {
                        $WAMajorVersion = $ConfigurationData.ConfigData.Version.Split(".")[1]
                        
                        $WebsiteId = if($ConfigurationData.ConfigData.WebAdaptor.WebSiteId){ $ConfigurationData.ConfigData.WebAdaptor.WebSiteId }else{ 1 } 
                        if(($Node.Role -icontains 'PortalWebAdaptor') -and $ConfigurationData.ConfigData.PortalContext)
                        {
                            $PortalWAArguments = "/qn ACCEPTEULA=YES VDIRNAME=$($ConfigurationData.ConfigData.PortalContext) WEBSITE_ID=$($WebSiteId)"
                            if($WAMajorVersion -gt 5){
                                $PortalWAArguments += " CONFIGUREIIS=TRUE"
                            }
                            ArcGIS_Install WebAdaptorInstallPortal
                            { 
                                Name = "PortalWebAdaptor"
                                Version = $ConfigurationData.ConfigData.Version
                                Path = $ConfigurationData.ConfigData.WebAdaptor.Installer.Path
                                Arguments = $PortalWAArguments
                                WebAdaptorContext = $ConfigurationData.ConfigData.PortalContext
                                EnableMSILogging = $EnableMSILogging
                                Ensure = "Present"
                            }
                        }

                        if(($Node.Role -icontains 'ServerWebAdaptor') -and $Node.ServerContext)
                        {
                            $ServerWAArguments = "/qn ACCEPTEULA=YES VDIRNAME=$($Node.ServerContext) WEBSITE_ID=$($WebSiteId)"
                            if($WAMajorVersion -gt 5){
                                $ServerWAArguments += " CONFIGUREIIS=TRUE"
                            }
                            ArcGIS_Install WebAdaptorInstallServer
                            { 
                                Name = "ServerWebAdaptor"
                                Version = $ConfigurationData.ConfigData.Version
                                Path = $ConfigurationData.ConfigData.WebAdaptor.Installer.Path
                                Arguments = $ServerWAArguments
                                WebAdaptorContext = $Node.ServerContext
                                EnableMSILogging = $EnableMSILogging
                                Ensure = "Present"
                            }
                        }
                    }

                    if ($ConfigurationData.ConfigData.WebAdaptor.Installer.PatchesDir -and -not($PortalWebAdaptorSkip)) {
                        ArcGIS_InstallPatch WebAdaptorInstallPatch
                        {
                            Name = "WebAdaptor"
                            Version = $ConfigurationData.ConfigData.Version
                            PatchesDir = $ConfigurationData.ConfigData.WebAdaptor.Installer.PatchesDir
                            Ensure = "Present"
                        }
                    }
                }
                'SQLServerClient'
                {
                    if($ConfigurationData.ConfigData.SQLServerClient){
                        $TempFolder = "$($env:SystemDrive)\Temp"
                        if(Test-Path $TempFolder){ Remove-Item -Path $TempFolder -Recurse }
                        if(-not(Test-Path $TempFolder)){ New-Item $TempFolder -ItemType directory }

                        foreach($Client in $ConfigurationData.ConfigData.SQLServerClient){
                            $ODBCDriverName = $Client.Name
                            $FileName = Split-Path $Client.InstallerPath -leaf

                            File "SetupCopy$($ODBCDriverName.Replace(' ', '_'))"
                            {
                                Ensure = "Present"
                                Type = "File"
                                SourcePath = $Client.InstallerPath
                                DestinationPath = "$TempFolder\$FileName"  
                            }
                        
                            ArcGIS_InstallMsiPackage "AIMP_$($ODBCDriverName.Replace(' ', '_'))"
                            {
                                Name = $ODBCDriverName
                                Path = $ExecutionContext.InvokeCommand.ExpandString("$TempFolder\$FileName")
                                Ensure = "Present"
                                ProductId = $Client.ProductId
                                Arguments = $Client.Arguments
                            } 
                        }

                        if(Test-Path $TempFolder){ Remove-Item -Path $TempFolder -Recurse }
                    }
                }
                'Desktop' {
                    $Arguments =""
                    if($ConfigurationData.ConfigData.Desktop.SeatPreference -ieq "Fixed"){
                        $Arguments = "/qn ACCEPTEULA=YES ADDLOCAL=`"$($ConfigurationData.ConfigData.Desktop.InstallFeatures)`" INSTALLDIR=`"$($ConfigurationData.ConfigData.Desktop.Installer.InstallDir)`" INSTALLDIR1=`"$($ConfigurationData.ConfigData.Desktop.Installer.InstallDirPython)`" DESKTOP_CONFIG=`"$($ConfigurationData.ConfigData.Desktop.DesktopConfig)`" MODIFYFLEXDACL=`"$($ConfigurationData.ConfigData.Desktop.ModifyFlexdAcl)`""
                    }else{
                        $Arguments = "/qn ACCEPTEULA=YES ADDLOCAL=`"$($ConfigurationData.ConfigData.Desktop.InstallFeatures)`" INSTALLDIR=`"$($ConfigurationData.ConfigData.Desktop.Installer.InstallDir)`" INSTALLDIR1=`"$($ConfigurationData.ConfigData.Desktop.Installer.InstallDirPython)`" ESRI_LICENSE_HOST=`"$($ConfigurationData.ConfigData.Desktop.EsriLicenseHost)`" SOFTWARE_CLASS=`"$($ConfigurationData.ConfigData.Desktop.SoftwareClass)`" SEAT_PREFERENCE=`"$($ConfigurationData.ConfigData.Desktop.SeatPreference)`" DESKTOP_CONFIG=`"$($ConfigurationData.ConfigData.Desktop.DesktopConfig)`"  MODIFYFLEXDACL=`"$($ConfigurationData.ConfigData.Desktop.ModifyFlexdAcl)`""
                    }

                    if ($ConfigurationData.ConfigData.Desktop.BlockAddIns -match '^[0-4]+$') {
                        $Arguments += " BLOCKADDINS=$($ConfigurationData.ConfigData.Desktop.BlockAddIns)" #ensure valid blockaddin value / defauts to allow all addins (0)
                    }

                    if(-not($ConfigurationData.ConfigData.Desktop.ContainsKey("EnableEUEI")) -or ($ConfigurationData.ConfigData.Desktop.ContainsKey("EnableEUEI") -and -not($ConfigurationData.ConfigData.Desktop.EnableEUEI))){
						$Arguments += " ENABLEEUEI=0"
                    }

                    ArcGIS_Install DesktopInstall
                    { 
                        Name = "Desktop"
                        Version = $ConfigurationData.ConfigData.DesktopVersion
                        Path = $ConfigurationData.ConfigData.Desktop.Installer.Path
                        Arguments =   $Arguments
                        EnableMSILogging = $EnableMSILogging
                        Ensure = "Present"
                    }

                    if($ConfigurationData.ConfigData.Desktop.Extensions){
                        foreach ($Extension in $ConfigurationData.ConfigData.Desktop.Extensions.GetEnumerator()) 
                        {
                            $Arguments = "/qn"
                            if($Extension.Value.Features -and $Extension.Value.Features.Count -gt 0){
								$Features = $null
								if($Extension.Value.Features -icontains "ALL"){
									$Features = "ALL"
								}else{
									$Extension.Value.Features | % {
										if($null -eq $Features){ 
											$Features = $_
										}else{
											$Features += ",$_"
										}
									}
								}

                                $Arguments += " ADDLOCAL=$Features"
                            }

                            ArcGIS_Install "Desktop$($Extension.Key)InstallExtension"
                            {
                                Name = "Desktop$($Extension.Key)"
                                Version = $ConfigurationData.ConfigData.DesktopVersion
                                Path = $Extension.Value.Installer.Path
                                Arguments = $Arguments
                                EnableMSILogging = $EnableMSILogging
                                Ensure = "Present"
                            }
                        }
                    }

                    if ($ConfigurationData.ConfigData.Desktop.Installer.PatchesDir) {
                        ArcGIS_InstallPatch DesktopInstallPatch
                        {
                            Name = "Desktop"
                            Version = $ConfigurationData.ConfigData.DesktopVersion
                            PatchesDir = $ConfigurationData.ConfigData.Desktop.Installer.PatchesDir
                            Ensure = "Present"
                        }
                    }
                }
                'Pro'
                {
                    # Installation Notes: https://pro.arcgis.com/en/pro-app/get-started/arcgis-pro-installation-administration.htm
                    $PortalList = if($ConfigurationData.ConfigData.Pro.PortalList){ $ConfigurationData.ConfigData.Pro.PortalList }else{ "https://arcgis.com" }
                    $Arguments = "/qn ACCEPTEULA=YES Portal_List=`"$PortalList`" AUTHORIZATION_TYPE=`"$($ConfigurationData.ConfigData.Pro.AuthorizationType)`""

                    # TODO: The SOFTWARE_CLASS does not get added if not supported, should this fail? Currently it uses the default handling mechanism. 
                    if ($ConfigurationData.ConfigData.Pro.SoftwareClass){
                        if (@("viewer","editor","professional") -icontains $ConfigurationData.ConfigData.Pro.SoftwareClass.ToLower()) {
                            $Arguments += " SOFTWARE_CLASS=`"$($ConfigurationData.ConfigData.Pro.SoftwareClass)`""
                        }
                    }

                    if (-not ([string]::IsNullOrEmpty($ConfigurationData.ConfigData.Pro.Installer.InstallDir))){
                        $Arguments += " INSTALLDIR=`"$($ConfigurationData.ConfigData.Pro.Installer.InstallDir)`""
                    }

                    if ($ConfigurationData.ConfigData.Pro.BlockAddIns -match '^[0-5]+$') {
                        $Arguments += " BLOCKADDINS=$($ConfigurationData.ConfigData.Pro.BlockAddIns)" #ensure valid blockaddin value / defauts to allow all addins (0)
                    }

                    if($ConfigurationData.ConfigData.Pro.AuthorizationType -ieq "CONCURRENT_USE"){
                        $Arguments += " ESRI_LICENSE_HOST=`"$($ConfigurationData.ConfigData.Pro.EsriLicenseHost)`"" 
                    }

                    # Pro installed for all users. Per User installs for Pro not supported
                    $Arguments += " ALLUSERS=1"

                    if(-not($ConfigurationData.ConfigData.Pro.ContainsKey("LockAuthSettings")) -or ($ConfigurationData.ConfigData.Pro.ContainsKey("LockAuthSettings") -and -not($ConfigurationData.ConfigData.Pro.LockAuthSettings)) ){
						$Arguments += " LOCK_AUTH_SETTINGS=False"
                    }
					
					if(-not($ConfigurationData.ConfigData.Pro.ContainsKey("EnableEUEI")) -or ($ConfigurationData.ConfigData.Pro.ContainsKey("EnableEUEI") -and -not($ConfigurationData.ConfigData.Pro.EnableEUEI)) ){
						$Arguments += " ENABLEEUEI=0"
                    }
					
					if(-not($ConfigurationData.ConfigData.Pro.ContainsKey("CheckForUpdatesAtStartup")) -or ($ConfigurationData.ConfigData.Pro.ContainsKey("CheckForUpdatesAtStartup") -and -not($ConfigurationData.ConfigData.Pro.CheckForUpdatesAtStartup)) ){
						$Arguments += " CHECKFORUPDATESATSTARTUP=0"
                    }

                    ArcGIS_Install ProInstall{
                        Name = "Pro"
                        Version = $ConfigurationData.ConfigData.ProVersion
                        Path = $ConfigurationData.ConfigData.Pro.Installer.Path
                        Arguments = $Arguments
                        EnableMSILogging = $EnableMSILogging
                        Ensure = "Present"
                    }

                    if($ConfigurationData.ConfigData.Pro.Extensions){
                        foreach ($Extension in $ConfigurationData.ConfigData.Pro.Extensions.GetEnumerator()) 
                        {
                            $Arguments = "/qn"
                            if($Extension.Value.Features -and $Extension.Value.Features.Count -gt 0){
								$Features = $null
								if($Extension.Value.Features -icontains "ALL"){
									$Features = "ALL"
								}else{
									$Extension.Value.Features | % {
										if($null -eq $Features){ 
											$Features = $_
										}else{
											$Features += ",$_"
										}
									}
								}

                                $Arguments += " ADDLOCAL=$Features"
                            }

                            ArcGIS_Install "Pro$($Extension.Key)InstallExtension"
                            {
                                Name = "Pro$($Extension.Key)"
                                Version = $ConfigurationData.ConfigData.ProVersion
                                Path = $Extension.Value.Installer.Path
                                Arguments = $Arguments
                                EnableMSILogging = $EnableMSILogging
                                Ensure = "Present"
                            }
                        }
                    }

                    if ($ConfigurationData.ConfigData.Pro.Installer.PatchesDir) {
                        ArcGIS_InstallPatch ProInstallPatch
                        {
                            Name = "Pro"
                            Version = $ConfigurationData.ConfigData.ProVersion
                            PatchesDir = $ConfigurationData.ConfigData.Pro.Installer.PatchesDir
                            Ensure = "Present"
                        }
                    }
                }
                'LicenseManager'
                {
                    ArcGIS_Install LicenseManagerInstall{
                        Name = "LicenseManager"
                        Version = $ConfigurationData.ConfigData.LicenseManagerVersion
                        Path = $ConfigurationData.ConfigData.LicenseManager.Installer.Path
                        Arguments = "/qn ACCEPTEULA=YES INSTALLDIR=`"$($ConfigurationData.ConfigData.LicenseManager.Installer.InstallDir)`""
                        EnableMSILogging = $EnableMSILogging
                        Ensure = "Present"
                    }
                }
            }
        }
    }
}
Configuration DataStoreUpgradeConfigure{
    param(
        [System.String]
        $Version,

        [System.Management.Automation.PSCredential]
        $ServerPrimarySiteAdminCredential,

        [System.String]
        $ServerMachineName,

        [System.String]
        $ContentDirectoryLocation,

        [System.String]
        $InstallDir
    )
    
    Import-DscResource -ModuleName PSDesiredStateConfiguration 
    Import-DSCResource -ModuleName @{ModuleName="ArcGIS";ModuleVersion="3.3.0"} 
    Import-DscResource -Name ArcGIS_DataStoreUpgrade
    
    Node $AllNodes.NodeName {
        if($Node.Thumbprint){
            LocalConfigurationManager
            {
                CertificateId = $Node.Thumbprint
            }
        }
        
        $ServerHostName = (Get-FQDN $ServerMachineName)

        ArcGIS_DataStoreUpgrade DataStoreConfigUpgrade
        {
            ServerHostName = $ServerHostName
            Ensure = 'Present'
            SiteAdministrator = $ServerPrimarySiteAdminCredential
            ContentDirectory = $ContentDirectoryLocation
            InstallDir = $InstallDir
        }
    }
}
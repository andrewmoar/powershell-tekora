
$pw = ConvertTo-SecureString "$($ENV:srvpwd)" -AsPlainText -Force
$cred = new-object -typename System.Management.Automation.PSCredential -argumentlist "tekora",$pw
$PSSession = New-PSSession -ComputerName ${env:SERVER} -Credential $cred
#copy deployConfig
Invoke-Command -Session $PSSession -ScriptBlock {
$jenkinsFolder = "c:\jenkins\4i_new\"
if (! (Test-Path $jenkinsFolder ))
{
New-Item -ItemType "directory" -Path $jenkinsFolder
} else {
    Write-Output "Directory $jenkinsFolder is exist"
}
}  

Copy-Item -Path "C:\jenkins\4I.Local\Projects\${env:customer}\deployConfig.json" -Destination "c:\jenkins\4i_new\" -ToSession $PSSession
$array = @("adm","v3","v4") 
foreach ($item in $array){
    Copy-Item -Path "C:\jenkins\publish\$item`.zip" -Destination "c:\jenkins\4i_new\" -ToSession $PSSession
}


$pw = ConvertTo-SecureString "$($ENV:srvpwd)" -AsPlainText -Force
$cred = new-object -typename System.Management.Automation.PSCredential -argumentlist "tekora",$pw
$SessionOptions = New-PSSessionOption –SkipCACheck –SkipCNCheck –SkipRevocationCheck


$PSSession = New-PSSession -ComputerName ${env:SERVER} -Credential $cred -SessionOption $SessionOptions



Invoke-Command -Session $PSSession -ScriptBlock {
  
$4i_local_repo = "C:\jenkins\4I.Local"

Import-Module WebAdministration

# declare variables

$date = get-date -uformat '%Y%m%d_%H%M%S'
$deploy_path = "C:\jenkins\4i_new\"
  
#parse json

$AppPathFromJson = Get-Content -Raw -Path c:\jenkins\4i_new\deployConfig.json | Out-String | ConvertFrom-Json
$v3Path = $AppPathFromJson.TekoraTest.v3Url.ToString()
$v4Path = $AppPathFromJson.TekoraTest.v4Url.ToString()
$AdmPath = $AppPathFromJson.TekoraTest.admUrl.ToString()
$backupFolder = $AppPathFromJson.TekoraTest.backupDir
$migrationUrl = $AppPathFromJson.TekoraTest.migrationsApplyUrl
$clientName = $AppPathFromJson.TekoraTest.address.split('.')[0]


###check or create backup dir
if (! (Test-Path $backupFolder ))
{
New-Item -ItemType "directory" -Path $backupFolder
} else {
    Write-Output "Directory $backupFolder is exist"
}
  
#pass dict with destination of applications
  
$appDict = @{}
$appDict.add( 'adm', "$($AdmPath)" )
$appDict.add( 'v3', "$($v3Path)" )
$appDict.add( 'v4', "$($v4Path)" )

iisreset /stop                                    
$appDict.GetEnumerator() | ForEach-Object{
    Write-Output "Key = $($_.key)"
    Write-Output "Value = $($_.value)"
  
    #backup old application version
  
    if ( (Test-Path "$($_.value)" )) {
        $fullbackupFolder = ("$backupFolder" + "\" + $clientName +  "_" + "$date" + "\" + "$($_.key)" )
        
        if (! (Test-Path $fullbackupFolder ))
        {
            New-Item -ItemType "directory" -Path "$fullbackupFolder"
        }
        #create zipped backup
                             
        $compress = @{
  			Path = "$($_.value)"
  			CompressionLevel = "Fastest"
  			DestinationPath = ($fullbackupFolder + '.zip' )
		}
		Compress-Archive @compress                     
        #remove empty directories                    
        Remove-Item -Path $fullbackupFolder -Recurse
    }
    #deploy new application version                         
    Expand-Archive -Path ($deploy_path + "$($_.key)"  + ".zip" ) -DestinationPath "$($_.value)" -Force  
    
                                   
}
                                       
iisreset /start                               

}

                                       
#skip tls check
add-type @"
using System.Net;
using System.Security.Cryptography.X509Certificates;
public class TrustAllCertsPolicy : ICertificatePolicy {
    public bool CheckValidationResult(
        ServicePoint srvPoint, X509Certificate certificate,
        WebRequest request, int certificateProblem) {
        return true;
    }
}
"@
$AllProtocols = [System.Net.SecurityProtocolType]'Ssl3,Tls,Tls11,Tls12'
[System.Net.ServicePointManager]::SecurityProtocol = $AllProtocols
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy  
  
#get migration url from json file
                             
$AppPathFromJson = Get-Content -Raw -Path "C:\jenkins\4I.Local\Projects\${env:customer}\deployConfig.json" | Out-String | ConvertFrom-Json

$migrationUrl = $AppPathFromJson.TekoraTest.migrationsApplyUrl  
                                       
#invoke web request for migrations
Write-Host "command: Invoke-WebRequest -Uri "$migrationUrl" "                                       
Invoke-WebRequest -Uri "$migrationUrl"    

Remove-PSSession -Session $PSSession

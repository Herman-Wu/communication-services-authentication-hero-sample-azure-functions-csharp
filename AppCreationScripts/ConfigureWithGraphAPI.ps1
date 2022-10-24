<#
.SYNOPSIS
    This PowerShell script is to create app registration for service, client, postman and aadHelper

.PARAMETER TenantId
    The parameter TenantId is the AAD tenant id

.PARAMETER ClientId
    The parameter ClientId is clientId of master app registration you have created before running this script

.PARAMETER ClientSecret
    The parameter ClientSecret is clientSecret of master app registration you have created before running this script
#>
param(
    [Parameter(Mandatory=$True, HelpMessage='Tenant ID (This is a GUID which represents the "Directory ID" of the AzureAD tenant into which you want to create the apps')]
    [string] $TenantId,
    [Parameter(Mandatory=$True, HelpMessage='Client Id of Main App)')]
    [string] $ClientId,
    [Parameter(Mandatory=$True, HelpMessage='Client Secret of Main App)')]
    [string] $ClientSecret
)

Function Get-GraphToken([string] $tenantId, [string] $clientId, [string] $clientSecret) {
    $url = "https://login.microsoftonline.com/$($tenantId)/oauth2/token"
    $body = "grant_type=client_credentials&client_id=$($clientId)&client_secret=$($clientSecret)&resource=https://graph.microsoft.com"
    $header = @{
       "Content-Type" = 'application/x-www-form-urlencoded'
    }
    $request = Invoke-RestMethod -Method 'Post' -Uri $url -Body $body -Header $header
    $graphToken = $request.access_token
    return $graphToken
}

Function New-AzureADApplication([string] $appName, [string] $replyUrl, [string] $token) {
    $url = "https://graph.microsoft.com/v1.0/applications"
    $redirectUris = @("$replyUrl")
    $urlArray = ConvertTo-json -InputObject $redirectUris
    $header = @{
        Authorization = "Bearer $token"
    }
    $postBody = @"
    {
        "displayName": "$appName",
        "signInAudience": "AzureADMyOrg",
        "web": {
            "redirectUris": $urlArray,
            "implicitGrantSettings": {
                "enableIdTokenIssuance": "true"
            }
        }
    }
"@

    $appRegistration = Invoke-RestMethod -Method 'POST' -Uri $url -Body $postBody -ContentType 'application/json' -Headers $header
    return $appRegistration      
}

Function Update-Application([string] $objectId, [string] $token, [string] $body) {
    $url = "https://graph.microsoft.com/v1.0/applications/$objectId"
    $header = @{
        Authorization = "Bearer $token"
    }
    [void] (Invoke-RestMethod -Method 'Patch' -Uri $url -Body $body -ContentType 'application/json' -Headers $header)   
}



Function Get-AzureADServicePrincipal([string] $applicationDisplayName, [string] $token)
{
    $url = "https://graph.microsoft.com/v1.0/servicePrincipals?`$filter=displayName eq '$applicationDisplayName'"
    $header = @{
        Authorization = "Bearer $token"
    }
    $resp = Invoke-RestMethod -Method 'Get' -Uri $url -Headers $header
    $value = $resp.value
    if ($value.count -eq 0) 
    {
        return $null
    }
    return $value[0]
}


Function Get-RequiredPermissions([string]$applicationDisplayName, [string]$requiredDelegatedPermissions, [string]$requiredApplicationPermissions, $servicePrincipal, [string] $token)
{
    # If we are passed the service principal we use it directly, otherwise we find it from the display name (which might not be unique)
    if ($servicePrincipal)
    {
        $sp = $servicePrincipal
    }
    else
    {
        $sp = Get-AzureADServicePrincipal -applicationDisplayName $applicationDisplayName -token $token
    }
    $appid = $sp.appId
    
    $resourceAccess = New-Object -TypeName System.Collections.ArrayList

    # $sp.Oauth2Permissions | Select Id,AdminConsentDisplayName,Value: To see the list of all the Delegated permissions for the application:
    if ($requiredDelegatedPermissions)
    {
        Add-ResourcePermission -resourceAccess $resourceAccess -requiredPermissions $requiredDelegatedPermissions -exposedPermissions $sp.oauth2PermissionScopes -permissionType "Scope"
    }
    
    # $sp.AppRoles | Select Id,AdminConsentDisplayName,Value: To see the list of all the Application permissions for the application
    if ($requiredApplicationPermissions)
    {
        Add-ResourcePermission -resourceAccess $resourceAccess -requiredPermissions $requiredDelegatedPermissions -exposedPermissions $sp.appRoles -permissionType "Role"
    }

    $requiredResourceAccess = @{
        "resourceAppId"=$appid
        "resourceAccess"=$resourceAccess
    }
    return $requiredResourceAccess
}

Function Add-ResourcePermission($resourceAccess, [string]$requiredPermissions, $exposedPermissions, [string]$permissionType)
{
    foreach($permission in $requiredPermissions.Trim().Split("|"))
    {
        foreach($exposedPermission in $exposedPermissions)
        {
            if ($exposedPermission.value -eq $permission)
            {
                    $permissionObj = @{
                        "type" = $permissionType
                        "id" = $exposedPermission.id
                    }
                    [void]$resourceAccess.Add($permissionObj)
                    
                 }
        }
    }
}

Function Add-Scope([string] $appId, [string] $objectId, [string] $token, [string] $appName) {
    $scopeId = New-Guid
    $body = @"
    {
        "identifierUris": ["api://$appId"],
        "api": {
            "requestedAccessTokenVersion": 2,
            "oauth2PermissionScopes": [
                {
			        "adminConsentDescription": "Allow the application to access $appName on behalf of the signed-in user.",
			        "adminConsentDisplayName": "Access $appName",
			        "isEnabled": true,
                    "id": "$scopeId",
			        "type": "User",
			        "userConsentDescription": "Allow the application to access $appName on your behalf.",
			        "userConsentDisplayName": "Access $appName",
			        "value": "access_as_user"
		        }
            ]
        }
        
    }
"@
    Update-Application -objectId $objectId -token $token -body $body 
       
}

Function Create-ServicePrincipal([string] $appId) {
    $url = "https://graph.microsoft.com/v1.0/servicePrincipals"
    $header = @{
        Authorization = "Bearer $token"
    }
    $postBody = @"
    {
        "appId": "$appId"        
    }
"@
    $resp = Invoke-RestMethod -Method 'Post' -Uri $url -Body $postBody -ContentType 'application/json' -Headers $header
}

Function Create-Secret([string] $objectId, [string] $name) {
    $url = "https://graph.microsoft.com/v1.0/applications/$objectId/addPassword"
    $header = @{
        Authorization = "Bearer $token"
    }
    $startDateTime = (Get-Date).TOUniversalTime()
    $endDateTime = $startDateTime.AddYears(1)
    $startDateTimeS = $startDateTime.ToString("yyyy-MM-ddTHH:mm:ss.fffffffZ")
    $endDateTimeS = $endDateTime.ToString("yyyy-MM-ddTHH:mm:ss.fffffffZ")
    $postBody = @"
    {
        "passwordCredential": {
            "displayName": "$name",
            "startDateTime": "$startDateTimeS",
            "endDateTime": "$endDateTimeS"
        }   
    }
"@
    $resp = Invoke-RestMethod -Method 'Post' -Uri $url -Body $postBody -ContentType 'application/json' -Headers $header
    return $resp.secretText
}

Function Set-RequiredResourceAccess([string] $objectId, $requiredResourceAccesses, [string] $token) {
    $accessArray = ConvertTo-json -InputObject $requiredResourceAccesses -Depth 4
    $body = @"
    {
        "requiredResourceAccess": $accessArray  
    } 
"@

    Update-Application -objectId $objectId -token $token -body $body      
}

Function Add-UserAndAdminRoles([string] $objectId, [string] $token) {
    $userRole = @{
			allowedMemberTypes= ("User", "Application");
			description= "user role";
			displayName= "user";
			isEnabled= "true";
            id = "$([guid]::NewGuid())";
			value= "user"
		}
    $adminRole = @{
			allowedMemberTypes= ("User", "Application");
			description= "admin role";
			displayName= "admin";
			isEnabled= "true";
            id = "$([guid]::NewGuid())"
			value= "admin"
		}
    $appRoles = @($userRole, $adminRole) | ConvertTo-json -Depth 4
    $body = @"
    {
        "appRoles": $appRoles  
    } 
"@
    Update-Application -objectId $objectId -token $token -body $body      
}

# Replace the value of an appsettings of a given key in an XML App.Config file.
Function Replace-Setting([string] $configFilePath, [string] $placeholderValue, [string] $newValue)
{
    $lines = Get-Content $configFilePath
    $index = 0
    while($index -lt $lines.Length)
    {
        $line = $lines[$index]
        if ($line.Contains($placeholderValue))
        {
            $lines[$index] = $line.replace($placeholderValue, $newValue)
            Break
        }
        $index++
    }
    Set-Content -Path $configFilePath -Value $lines -Force
}


Function Update-Line([string] $line, [string] $value)
{
    $index = $line.IndexOf('=')
    $delimiter = ';'
    if ($index -eq -1)
    {
        $index = $line.IndexOf(':')
        $delimiter = ','
    }
    if ($index -ige 0)
    {
        $oldLine = $line
        $line = $line.Substring(0, $index+1) + " "+'"'+$value+'"'
        if ($oldLine.IndexOf($delimiter) -ige 0) {
            $line = $line + $delimiter
            Write-Host "  - Old Line '$oldLine'"
        }
    }
    return $line
}

Function Update-TextFile([string] $configFilePath, [System.Collections.HashTable] $dictionary)
{
    $lines = Get-Content $configFilePath
    $index = 0
    while($index -lt $lines.Length)
    {
        $line = $lines[$index]
        foreach($key in $dictionary.Keys)
        {
            if ($line.Contains($key))
            {
                $lines[$index] = Update-Line $line $dictionary[$key]
            }
        }
        $index++
    }

    Set-Content -Path $configFilePath -Value $lines -Force
}

Function Create-AzureADApplications([string] $token) {
    # Create the service AAD application
    Write-Host "Creating the AAD application auther-server-sample-webApi"
    $serviceAppName = "auther-server-sample-webApi"
    $serviceUrl = "https://localhost:5000/"
    
    $serviceAadApplication = New-AzureADApplication -appName $serviceAppName -replyUrl $serviceUrl -token $token 

    $serviceObjectId = $serviceAadApplication.id
    $serviceAppId = $serviceAadApplication.appId

    $serviceRequiredPermissions = Get-RequiredPermissions -applicationDisplayName "Microsoft Graph" `
                                                -requiredDelegatedPermissions "User.Read|User.ReadWrite.All|Directory.ReadWrite.All" `
                                                -token $token `
    
    $serviceRequiredResourceAccesses = [System.Collections.ArrayList]@($serviceRequiredPermissions)
    Set-RequiredResourceAccess -objectId $serviceObjectId -requiredResourceAccesses $serviceRequiredResourceAccesses -token $token
    
    Add-Scope -appId $serviceAppId -objectId $serviceObjectId -token $token -appName $serviceAppName
    # create the service principal of the newly created application 
    Create-ServicePrincipal -appId $serviceAppId

    $serviceSecret = Create-Secret -objectId $serviceObjectId -name "app secret for webapi"

    #add user&admin roles
    Add-UserAndAdminRoles -objectId $serviceObjectId -token $token
    Write-Host "Done creating the service application auther-server-sample-webApi"

    # URL of the AAD application in the Azure portal
    # Future? $servicePortalUrl = "https://portal.azure.com/#@"+$tenantName+"/blade/Microsoft_AAD_RegisteredApps/ApplicationMenuBlade/Overview/appId/"+$serviceAadApplication.AppId+"/objectId/"+$serviceAadApplication.ObjectId+"/isMSAApp/"
    $servicePortalUrl = "https://portal.azure.com/#blade/Microsoft_AAD_RegisteredApps/ApplicationMenuBlade/CallAnAPI/appId/"+$serviceAppId+"/objectId/"+$serviceObjectId+"/isMSAApp/"
    Add-Content -Value "<tr><td>service</td><td>$serviceAppId</td><td><a href='$servicePortalUrl'>auther-server-sample-webApi</a></td></tr>" -Path createdApps.html

    # Create the client AAD application
    Write-Host "Creating the AAD application auther-server-sample-webClient"

    $clientAppName = "auther-server-sample-webClient"
    
    $clientAadApplication = New-AzureADApplication -appName $clientAppName -replyUrl "http://localhost:3000/" -token $token

    $clientAppId = $clientAadApplication.appId
    $clientObjectId = $clientAadApplication.id

    Create-ServicePrincipal -appId $clientAppId
    
    Write-Host "clientAppId:$($clientAppId)"
    Write-Host "Done creating the client application auther-server-sample-webClient"

    # URL of the AAD application in the Azure portal
    # Future? $clientPortalUrl = "https://portal.azure.com/#@"+$tenantName+"/blade/Microsoft_AAD_RegisteredApps/ApplicationMenuBlade/Overview/appId/"+$clientAadApplication.AppId+"/objectId/"+$clientAadApplication.ObjectId+"/isMSAApp/"
    $clientPortalUrl = "https://portal.azure.com/#blade/Microsoft_AAD_RegisteredApps/ApplicationMenuBlade/CallAnAPI/appId/"+$clientAppId+"/objectId/"+$clientObjectId+"/isMSAApp/"
    Add-Content -Value "<tr><td>client</td><td>$clientAppId</td><td><a href='$clientPortalUrl'>\auther-server-sample-webClient</a></td></tr>" -Path createdApps.html

    $clientRequiredResourceAccesses = [System.Collections.ArrayList]::new()
    
    # Add Required Resources Access (from 'client' to 'service')
    Write-Host "Getting access from 'client' to 'service'"
    $requiredServicePermissions = Get-RequiredPermissions -applicationDisplayName "auther-server-sample-webApi" `
                                                -requiredDelegatedPermissions "access_as_user" `
                                                -token $token `


    [void]$clientRequiredResourceAccesses.Add($requiredServicePermissions)  

    # Add Required Resources Access for managing Azure Communication Services calls.
    Write-Host "Getting access for Azure Communication Resource to manage calls'"
    $requiredACSPermissions = Get-RequiredPermissions -applicationDisplayName "Azure Communication Services" `
                                                -requiredDelegatedPermissions "Teams.ManageCalls" `
                                                -token $token `

    [void]$clientRequiredResourceAccesses.Add($requiredACSPermissions)                                          

    Set-RequiredResourceAccess -objectId $clientObjectId -token $token -requiredResourceAccesses $clientRequiredResourceAccesses
    Write-Host "Granted permissions."

    # Update config file for 'service'
   $configFile = $pwd.Path + "\..\src\AdvancedAuth.API.Func\appsettings.json"
   Write-Host "Updating app setting in ($configFile)"
   $dictionary = @{ "TenantId" = $TenantId;"ClientId" = $serviceAadApplication.AppId;"ClientSecret" = $serviceSecret };
   Update-TextFile -configFilePath $configFile -dictionary $dictionary

   # Update config file for 'MinimalClient - UI used for testing the service'
   #$configFile = $pwd.Path + "\..\MinimalClient\src\authConfig.js"
   #Write-Host "Updating the sample code ($configFile)"
   #Replace-Setting -configFilePath $configFile -placeholderValue "<your_client_id>" -newValue ($clientAadApplication.AppId)
   #Replace-Setting -configFilePath $configFile -placeholderValue "<your_tenant_id>" -newValue ($TenantId)
   #Replace-Setting -configFilePath $configFile -placeholderValue "<server api scope>" -newValue (("api://"+$serviceAadApplication.AppId+"/access_as_user"))
   Write-Host ""
   Write-Host -ForegroundColor Green "------------------------------------------------------------------------------------------------" 
   Write-Host "IMPORTANT: Please follow the instructions below to complete a few manual step(s) in the Azure portal":
   Write-Host "- For 'service'"
   Write-Host "  - Navigate to '$servicePortalUrl'"
   Write-Host "  - If you are a tenant admin, you can navigate to the API Permissions page and select 'Grant admin consent for (your tenant)' for all the Graph Api permissions, otherwise please follow up with your tenant admin to grant those permissions. You can follow the link https://docs.microsoft.com/azure/active-directory/manage-apps/grant-admin-consent." -ForegroundColor Red
   Write-Host "  - Do remember assign user with corresponding role in Enterprise Applications." -ForegroundColor Red  
   Write-Host "- For 'MinimalClient - UI for testing the service'"
   Write-Host "  - Navigate to '$clientPortalUrl'"
   #Write-Host "  - Navigate to the Manifest page and change 'replyUrlsWithType[].type' to 'Spa'." -ForegroundColor Red 
   Write-Host "  - If you are a tenant admin, you can navigate to the API Permissions page and select 'Grant admin consent for (your tenant)' to grant admin consent only to Azure Communication Services permissions, otherwise please follow up with your tenant admin to grant those permissions. You can follow the link https://docs.microsoft.com/azure/active-directory/manage-apps/grant-admin-consent." -ForegroundColor Red 

   Write-Host -ForegroundColor Green "------------------------------------------------------------------------------------------------" 
     
   Add-Content -Value "</tbody></table></body></html>" -Path createdApps.html

}

   
# Get token and create app registrations
$token = Get-GraphToken -clientSecret $ClientSecret -clientId $ClientId -tenantId $TenantId
Create-AzureADApplications -token $token



                    


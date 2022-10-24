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
    #Write-Host $graphToken
    return $graphToken
}

Function Get-AzureADApplication([string] $applicationDisplayName, [string] $token)
{
    $url = "https://graph.microsoft.com/v1.0/applications?`$filter=displayName eq '$applicationDisplayName'"
    $header = @{
        Authorization = "Bearer $token"
    }
    $resp = Invoke-RestMethod -Method 'Get' -Uri $url -Headers $header
    $value = $resp.value
    if ($value.count -eq 0) 
    {
        Write-Host "No application with name $applicationDisplayName"
        return $null
    }
    return $value
}

Function Remove-AzureADApplication([string] $id, [string] $token)
{
    $url = "https://graph.microsoft.com/v1.0/applications/$id"
    $header = @{
        Authorization = "Bearer $token"
    }
    [void] (Invoke-RestMethod -Method 'Delete' -Uri $url -Headers $header)
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
        Write-Host "No service principal with name $applicationDisplayName"
        return $null
    }
    return $value
}

Function Remove-AzureADServicePrincipal([string] $id, [string] $token)
{
    $url = "https://graph.microsoft.com/v1.0/servicePrincipals/$id"
    $header = @{
        Authorization = "Bearer $token"
    }
    [void] (Invoke-RestMethod -Method 'Delete' -Uri $url -Headers $header)
}

Function Cleanup
{   
    # Fetch graph token
    $token = Get-GraphToken -tenantId $TenantId -clientId $ClientId -clientSecret $ClientSecret
    # Removes the applications
    Write-Host "Cleaning-up applications from tenant with tenantid='$TenantId'"

    Write-Host "Removing 'service' (auther-server-sample-webApi) if needed"
    $apps = Get-AzureADApplication -applicationDisplayName "auther-server-sample-webApi" -token $token
    foreach ($app in $apps) 
    {
        Write-Host "Removed application auther-server-sample-webApi with id $($app.id)"
        Remove-AzureADApplication -id $app.id -token $token
    }
    # also remove service principals of this app
    $servicePrincipals = Get-AzureADServicePrincipal -applicationDisplayName "auther-server-sample-webApi" -token $token
    foreach ($sp in $servicePrincipals) 
    {
        Write-Host "Removed service principal auther-server-sample-webApi with id $($sp.id)"
        Remove-AzureADApplication -id $app.id -token $token
    }

    Write-Host "Removing 'client' (auther-server-sample-webClient) if needed"
    $clientApps = Get-AzureADApplication -applicationDisplayName "auther-server-sample-webClient" -token $token
    foreach ($app in $clientApps) 
    {
        Write-Host "Removed application auther-server-sample-webClient with id $($app.id)"
        Remove-AzureADApplication -id $app.id -token $token
    }
    # also remove service principals of this app
    $clientSps = Get-AzureADServicePrincipal -applicationDisplayName "auther-server-sample-webClient" -token $token
    foreach ($sp in $clientSps) 
    {
        Write-Host "Removed service principal auther-server-sample-webClient with id $($sp.id)"
        Remove-AzureADApplication -id $app.id -token $token
    }
    
}

#Get-GraphToken -tenantId $TenantId -clientId $ClientId -clientSecret $ClientSecret
Cleanup -TenantId $TenantId -ClientId $ClientId -ClientSecret $ClientSecret

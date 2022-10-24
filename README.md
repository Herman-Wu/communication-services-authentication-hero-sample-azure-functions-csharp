# Azure Communication Services - Authentication Sample

This sample is a modified version form [Azure Communication Services Solutions - Authentication Server Sample](https://github.com/Azure-Samples/communication-services-authentication-hero-csharp).


It has with following changes and improvements.

- Use Azure Functions instead of Azure Web App.
  Azure Functions is more cost-effective for small ~ medium size organization which doesn’t have thousands of users. It could save the service cost in most of the cases.
- Use Azure Key Vault
  Use Azure Key Vault as the secure store for secrets. It stores  ACS access token and AAD App secret.
- Register Application in AAD using Graph API
  PowerShell AAD module only works on Windows. Changing it to Graph API can make the deployment script user-friendly to Mac users. It’s also easier to integrate with deployment pipeline (e.g., terraform)
- Running C# Azure Functions in an isolated process
  [.Net .NET isolated process](https://learn.microsoft.com/en-us/azure/azure-functions/dotnet-isolated-process-guide) provides deep integration between the host process and the functions. This allows you to decouple your function code from the Azure Functions runtime.
- Use Bicep to deploy the sample application
  Bicep is a domain-specific language (DSL) that uses declarative syntax to deploy Azure resources. It has better support for agile iterative developing process than imperative ressource provision. 

The overall architecture is still similar to the original one.

![](https://github.com/Azure-Samples/communication-services-authentication-hero-csharp/raw/main/docs/images/ACS-Authentication-Server-Sample_Overview-Flow.png)



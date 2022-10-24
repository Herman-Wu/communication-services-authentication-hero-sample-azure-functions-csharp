using AdvancedAuth.Core.Common.Interfaces;
using AdvancedAuth.Core.Common.Models;
using AdvancedAuth.Core.Common.Services;
using Functions.Worker.ContextAccessor;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Graph;
using Microsoft.Identity.Client;
using Microsoft.Identity.Web;

namespace AdvancedAuth.Core.Common.Extensions
{
    public static class ServiceCollectionExtensions
    {
        public static void AddAppSettings(
            this IServiceCollection services, IConfiguration configuration)
        {
            // Add CommunicationServicesSettingsModel to the service container with Configure and bound to configuration
            services.Configure<CommunicationServicesSettings>(
                configuration.GetSection(CommunicationServicesSettings.CommunicationServicesSettingsName));
            // Add GraphSettingsModel to the service container with Configure and bound to configuration
            services.Configure<GraphSettingsModel>(
                configuration.GetSection(GraphSettingsModel.GraphSettingsName));

        }

        /// <summary>
        /// Add core services (e.g. ACS service | Graph service) to the service container.
        /// </summary>
        /// <param name="services">A collection of service descriptors.</param>
        public static void AddCoreServices(this IServiceCollection services)
        {
            // Add ACS service
            services.AddSingleton<IACSService, ACSService>();
            // Add Graph service
            services.AddScoped<IGraphService, GraphService>();
        }

        /// <summary>
        /// Add all downstream apis to the service container.
        /// </summary>
        /// <param name="services">A collection of service descriptors.</param>
        /// <param name="configuration">Represents a set of key/value application configuration properties.</param>
        public static void AddDownstreamApis(this IServiceCollection services, IConfiguration configuration)
        {
            // Add the Microsoft Graph api as one of downstream apis
            // For more information, see https://docs.microsoft.com/azure/active-directory/develop/scenario-web-api-call-api-app-configuration?tabs=aspnetcore#option-1-call-microsoft-graph
            services.AddAuthentication(sharedOptions =>
            {
                sharedOptions.DefaultScheme = Microsoft.Identity.Web.Constants.Bearer;
                sharedOptions.DefaultChallengeScheme = Microsoft.Identity.Web.Constants.Bearer;
            });

            var scopes = configuration.GetSection("Graph").GetValue<string>("Scopes").Split(" ");
            services.AddMicrosoftIdentityWebApiAuthentication(configuration, AzureActiveDirectorySettingsModel.AzureActiveDirectorySettingsName)
                    .EnableTokenAcquisitionToCallDownstreamApi()
                    .AddInMemoryTokenCaches()
                    .AddMicrosoftGraph(
                     x =>
                    {
                        AzureActiveDirectorySettingsModel ad_setting = new AzureActiveDirectorySettingsModel();
                        configuration.GetSection(AzureActiveDirectorySettingsModel.AzureActiveDirectorySettingsName).Bind(ad_setting);

                        //
                        var sp = services.BuildServiceProvider();
                        var fc = sp.GetService<IFunctionContextAccessor>();
                        var token = fc.FunctionContext.Items["token"];

                        var cca = ConfidentialClientApplicationBuilder
                            .Create(ad_setting.ClientId)
                            .WithTenantId(ad_setting.TenantId)
                            .WithClientSecret(ad_setting.ClientSecret)
                            .Build();

                        // DelegateAuthenticationProvider is a simple auth provider implementation
                        // that allows you to define an async function to retrieve a token
                        // Alternatively, you can create a class that implements IAuthenticationProvider
                        // for more complex scenarios
                        var authProvider = new DelegateAuthenticationProvider(async (request) =>
                        {
                            // Use Microsoft.Identity.Client to retrieve token
                            var assertion = new UserAssertion(token.ToString());
                            var result = await cca.AcquireTokenOnBehalfOf(scopes, assertion).ExecuteAsync();

                            request.Headers.Authorization =
                                new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", result.AccessToken);
                        });

                        return new GraphServiceClient(authProvider);
                    }, scopes);
        }
    }
}

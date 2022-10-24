// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License. See LICENSE.md in the project root for license information.

using System.Threading.Tasks;
using System.Web.Http.Controllers;
using AdvancedAuth.Core.Common.Extensions;
using AdvancedAuth.Core.Common.Interfaces;
using AdvancedAuth.Core.Common.Models;
using AdvancedAuth.Core.Common.Services;
using Functions.Worker.ContextAccessor;
using IsolatedFunctionAuth.Middleware;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Http;
using Microsoft.Azure.Functions.Worker.Configuration;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Graph;
using Microsoft.Identity.Web;
using Microsoft.IdentityModel.Logging;

namespace AdvancedAuth.API.Func
{
    public class Program
    {
        public static void Main()
        {
            IdentityModelEventSource.ShowPII = true;
            var host = new HostBuilder()
                .ConfigureFunctionsWorkerDefaults(builder =>
                {
                    builder.UseFunctionContextAccessor();
                    builder.UseMiddleware<AuthenticationMiddleware>();
                    builder.UseMiddleware<AuthorizationMiddleware>();
                    builder.UseMiddleware<ExceptionLoggingMiddleware>();

                    builder.Services.AddOptions<CommunicationServicesSettings>()
                        .Configure<IConfiguration>((settings, configuration) =>
                        {
                            configuration.GetSection(CommunicationServicesSettings.CommunicationServicesSettingsName).Bind(settings);
                        });
                    builder.Services.AddOptions<GraphSettingsModel>()
                        .Configure<IConfiguration>((settings, configuration) =>
                        {
                            configuration.GetSection(GraphSettingsModel.GraphSettingsName).Bind(settings);
                        });


                })
                .ConfigureServices((context, services) =>
                {
                    services.AddFunctionContextAccessor();

                    services.AddDownstreamApis(context.Configuration);
                    // Add ACS service
                    services.AddSingleton<IACSService, ACSService>();
                    // Add Graph service
                    services.AddScoped<IGraphService, GraphService>();



                })
                .ConfigureAppConfiguration(config =>
                {
                    config.AddJsonFile("appsettings.json", false, false).AddEnvironmentVariables().Build();
                })
                .UseDefaultServiceProvider((_, options) =>
                {
                    options.ValidateScopes = true;
                    options.ValidateOnBuild = true;
                })
                .Build();

            host.Run();
        }
    }
}

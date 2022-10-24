// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License. See LICENSE.md in the project root for license information.

using System;
using System.Net;
using System.Threading.Tasks;
using AdvancedAuth.Core.Common.Interfaces;
using AdvancedAuth.Core.Common.Models;
using Azure.Communication;
using Azure.Core;
using IsolatedFunctionAuth.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Http;
using Microsoft.Extensions.Logging;

namespace AdvancedAuth.API.Func
{
    // If an Authorize attribute is placed at class-level,
    // requests to any function within the class
    // must pass the authorization checks
    [Authorize(
        Scopes = new[] { Scopes.OBOFlow },
        UserRoles = new[] { UserRoles.User, UserRoles.Admin },
        AppRoles = new[] { AppRoles.AccessAllFunctions })]
    public class ACSTokenFunction
    {
        private readonly ILogger _logger;
        private readonly IACSService _acsService;
        private readonly IGraphService _graphService;


        // Error message
        private const string NoAuthorizationCodeError = "Fail to get the authorization code from the request header";
        private const string NoIdentityMappingError = "There is no identity mapping information stored in Microsoft Graph";

        public ACSTokenFunction(ILoggerFactory loggerFactory, IACSService acsService, IGraphService graphService)
        {
            _logger = loggerFactory.CreateLogger<ACSTokenFunction>();
            _acsService = acsService ?? throw new ArgumentNullException(nameof(acsService));
            _graphService = graphService ?? throw new ArgumentNullException(nameof(graphService));
        }



        [Authorize(
        Scopes = new[] { Scopes.OBOFlow, Scopes.FunctionsAccess },
        UserRoles = new[] { UserRoles.User, UserRoles.Admin }
         )]
        [Function("GetACSToken")]
        public async Task<HttpResponseData> GetACSToken([HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = "token")] HttpRequestData req)
        {
            _logger.LogInformation("C# HTTP trigger function processed a request.");

            CommunicationUserIdentifierAndTokenResponse acsIdentityTokenResponse;

            // Retrieve ACS Identity from Microsoft Graph
            string acsUserId = await _graphService.GetACSUserId();

            if (acsUserId == null)
            {
                // User doesn't exist
                var response_notfound = req.CreateResponse(HttpStatusCode.NotFound);
                response_notfound.WriteString(NoIdentityMappingError);
                return response_notfound;
                //return StatusCode(StatusCodes.Status404NotFound, NoIdentityMappingError);
            }
            else // User exists
            {
                AccessToken acsToken = await _acsService.CreateACSToken(acsUserId);
                acsIdentityTokenResponse = new CommunicationUserIdentifierAndTokenResponse(acsToken, new CommunicationUserIdentifier(acsUserId));

                var response_created = req.CreateResponse(HttpStatusCode.Created);

                await response_created.WriteAsJsonAsync(acsIdentityTokenResponse);

                return response_created;
            }
        }
    }
}

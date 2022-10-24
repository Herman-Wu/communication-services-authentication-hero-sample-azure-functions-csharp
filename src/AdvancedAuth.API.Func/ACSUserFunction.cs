// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License. See LICENSE.md in the project root for license information.

using System;
using System.Collections.Generic;
using System.Net;
using System.Threading.Tasks;
using AdvancedAuth.Core.Common.Interfaces;
using AdvancedAuth.Core.Common.Models;
using IsolatedFunctionAuth.Authorization;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Http;
using Microsoft.Extensions.Logging;
using Microsoft.Graph;

namespace AdvancedAuth.API.Func
{
    [Authorize(
    Scopes = new[] { Scopes.OBOFlow },
    UserRoles = new[] { UserRoles.User, UserRoles.Admin },
    AppRoles = new[] { AppRoles.AccessAllFunctions })]
    public class ACSUserFunction
    {
        private readonly ILogger _logger;
        private readonly IACSService _acsService;
        private readonly IGraphService _graphService;

        private const string NoIdentityMappingError = "There is no identity mapping information stored in Microsoft Graph";

        public ACSUserFunction(ILoggerFactory loggerFactory, IACSService acsService, IGraphService graphService)
        {
            _logger = loggerFactory.CreateLogger<ACSUserFunction>();
            _acsService = acsService ?? throw new ArgumentNullException(nameof(acsService));
            _graphService = graphService ?? throw new ArgumentNullException(nameof(graphService));
        }

        [Authorize(
         Scopes = new[] { Scopes.OBOFlow, Scopes.FunctionsAccess },
         UserRoles = new[] { UserRoles.User, UserRoles.Admin }
        )]
        [Function("GetACSUser")]
        public async Task<HttpResponseData> GetACSUser([HttpTrigger(AuthorizationLevel.Function, "get", Route = "user")] HttpRequestData req)
        {
            _logger.LogInformation("C# HTTP trigger function processed a request.");

            string acsUserId = await _graphService.GetACSUserId();
            if (acsUserId == null) // User doesn't exist
            {
                var response_notfound = req.CreateResponse(HttpStatusCode.NotFound);
                response_notfound.WriteString(NoIdentityMappingError);
                return response_notfound;
            }
            else // User exists
            {
                var response_ok = req.CreateResponse(HttpStatusCode.OK);
                await response_ok.WriteAsJsonAsync(new IdentityMapping(acsUserId));
                return response_ok;
            }
        }

        [Authorize(
            Scopes = new[] { Scopes.OBOFlow, Scopes.FunctionsAccess },
            UserRoles = new[] { UserRoles.User, UserRoles.Admin }
                )]
        [Function("CreateACSUser")]
        public async Task<HttpResponseData> CreateACSUser([HttpTrigger(AuthorizationLevel.Anonymous, "post", Route = "user")] HttpRequestData req)
        {
            _logger.LogInformation("C# HTTP trigger function processed a request.");

            string acsUserId = await _graphService.GetACSUserId();

            if (acsUserId == null)
            {
                // Create a Communication Services identity.
                acsUserId = await _acsService.CreateACSUserIdentity();
                await _graphService.AddIdentityMapping(acsUserId);

                var response_created = req.CreateResponse(HttpStatusCode.Created);
                await response_created.WriteAsJsonAsync(new IdentityMapping(acsUserId));
                return response_created;
            }
            else
            {
                var response_ok = req.CreateResponse(HttpStatusCode.OK);
                await response_ok.WriteAsJsonAsync(new IdentityMapping(acsUserId));
                return response_ok;
            }

        }

        [Authorize(
            Scopes = new[] { Scopes.OBOFlow, Scopes.FunctionsAccess },
            UserRoles = new[] { UserRoles.User, UserRoles.Admin }
                )]
        [Function("DeleteACSUser")]
        public async Task<HttpResponseData> DeleteACSUser([HttpTrigger(AuthorizationLevel.Anonymous, "delete", Route = "user")] HttpRequestData req)
        {
            _logger.LogInformation("C# HTTP trigger function processed a request.");

            string acsUserId = await _graphService.GetACSUserId();
            // Delete the identity mapping from the user's roaming profile information using Microsoft Graph Open Extension
            await _graphService.DeleteIdentityMapping();
            // Delete the ACS user identity which revokes all active access tokens
            // and prevents users from issuing access tokens for the identity.
            // It also removes all the persisted content associated with the identity.
            await _acsService.DeleteACSUserIdentity(acsUserId);

            var response = req.CreateResponse(HttpStatusCode.NoContent);
            return response;
        }

        [Authorize(
            Scopes = new[] { Scopes.OBOFlow, Scopes.FunctionsAccess },
               UserRoles = new[] { UserRoles.User, UserRoles.Admin }
                )]
        [Function("GetACSUserGroupIDs")]
        public async Task<HttpResponseData> GetACSUserGroupIDs([HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = "group")] HttpRequestData req)
        {
            _logger.LogInformation("C# HTTP trigger function processed a request.");

            CommunicationUserGroupResponse userGroups = await _graphService.GetUserGroups();

            if (userGroups == null) // User doesn't exist
            {
                var response_notfound = req.CreateResponse(HttpStatusCode.NotFound);
                response_notfound.WriteString(NoIdentityMappingError);
                return response_notfound;
            }
            else // User exists
            {
                var response_ok = req.CreateResponse(HttpStatusCode.OK);
                await response_ok.WriteAsJsonAsync(userGroups);
                return response_ok;
            }
        }
    }
}

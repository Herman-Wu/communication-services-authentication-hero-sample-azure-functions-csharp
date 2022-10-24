using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using Microsoft.Graph;

namespace AdvancedAuth.Core.Common.Models
{
    public class CommunicationUserGroupResponse
    {
        public List<CommunicationUserGroup> UserGroups { get; }
        public string AcsID { get; }
        /// <summary>
        /// Initializes a new instance of the <see cref="CommunicationUserIdentifierAndTokenResponse"/> class.
        /// Creates a new instance of CommunicationUserIdentifierAndTokenResponse using the provided ACS AccessToken and User.
        /// </summary>
        /// <param name="accessToken">The value of the Azure.Communication.Identity.CommunicationUserIdentifierAndToken.AccessToken property.</param>
        /// <param name="user">The value of the Azure.Communication.Identity.CommunicationUserIdentifierAndToken.User property.</param>
        public CommunicationUserGroupResponse(IUserMemberOfCollectionWithReferencesPage memberOfGroups, string acsId)
        {
            List<CommunicationUserGroup> acsGroups = new List<CommunicationUserGroup>();

            if (memberOfGroups?.Count > 0)
            {
                foreach (var directoryObject in memberOfGroups)
                {
                    // We only want groups, so ignore DirectoryRole objects.
                    if (directoryObject is Group)
                    {
                        Group? group = directoryObject as Group;
                        acsGroups.Add(new CommunicationUserGroup() { GroupID = group.Id, GroupName = group.DisplayName });
                    }
                }
            }
            AcsID = acsId;
            UserGroups = acsGroups;
        }

        public class CommunicationUserGroup
        {
            public string? GroupName { get; set; }
            public string? GroupID { get; set; }
        }
    }
}

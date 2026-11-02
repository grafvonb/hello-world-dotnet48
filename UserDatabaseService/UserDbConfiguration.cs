using System.Data.Entity;
using System.Data.Entity.SqlServer;

namespace UserDatabaseService
{
    public sealed class UserDbConfiguration : DbConfiguration
    {
        public UserDbConfiguration()
        {
            SetProviderServices("System.Data.SqlClient", SqlProviderServices.Instance);
            SetDatabaseInitializer<UserDbContext>(null);
        }
    }
}

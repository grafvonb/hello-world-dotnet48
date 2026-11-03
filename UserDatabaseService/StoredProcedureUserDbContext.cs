using System.Data.Entity;

namespace UserDatabaseService
{
    internal sealed class StoredProcedureUserDbContext : DbContext
    {
        static StoredProcedureUserDbContext()
        {
            Database.SetInitializer<StoredProcedureUserDbContext>(null);
        }

        public StoredProcedureUserDbContext(string connectionString) : base(connectionString)
        {
            Configuration.ProxyCreationEnabled = false;
            Configuration.LazyLoadingEnabled = false;
        }
    }
}

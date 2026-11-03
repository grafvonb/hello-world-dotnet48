using System;

namespace UserDatabaseService
{
    public static class UserServiceFactory
    {
        public static IUserService Create(string implementation, string connectionString)
        {
            var choice = string.IsNullOrWhiteSpace(implementation) ? "Sql" : implementation.Trim();
            if (choice.Equals("Sql", StringComparison.OrdinalIgnoreCase))
                return new SqlUserService(connectionString);
            if (choice.Equals("EntityFramework", StringComparison.OrdinalIgnoreCase))
                return new EfUserService(connectionString);
            if (choice.Equals("EntityFrameworkStoredProcedures", StringComparison.OrdinalIgnoreCase))
                return new EfStoredProcedureUserService(connectionString);

            throw new ArgumentException("Unknown user service implementation.", nameof(implementation));
        }
    }
}

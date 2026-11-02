using System;

namespace UserDatabaseService
{
    public sealed class DuplicateLoginException : InvalidOperationException
    {
        public DuplicateLoginException(string login, Exception innerException)
            : base("A user with login '" + login + "' already exists.", innerException)
        {
        }
    }
}

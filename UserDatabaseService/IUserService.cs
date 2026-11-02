using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;

namespace UserDatabaseService
{
    public interface IUserService
    {
        /// <summary>Creates the database if absent and applies the embedded, repeatable schema.</summary>
        Task CreateOrUpdateDatabaseAsync(CancellationToken cancellationToken = default(CancellationToken));

        Task<IReadOnlyList<User>> GetAllAsync(CancellationToken cancellationToken = default(CancellationToken));

        /// <summary>Returns null when the login does not exist.</summary>
        Task<User> GetByLoginAsync(string login, CancellationToken cancellationToken = default(CancellationToken));

        /// <summary>Returns existing users matching any supplied login, ordered by login.</summary>
        Task<IReadOnlyList<User>> GetByLoginsAsync(IEnumerable<string> logins, CancellationToken cancellationToken = default(CancellationToken));

        /// <summary>Throws DuplicateLoginException when the login is already taken.</summary>
        Task CreateAsync(User user, CancellationToken cancellationToken = default(CancellationToken));

        /// <summary>Updates name and age using login as the key. Returns false if not found.</summary>
        Task<bool> UpdateAsync(User user, CancellationToken cancellationToken = default(CancellationToken));

        /// <summary>Returns false if the login does not exist.</summary>
        Task<bool> DeleteAsync(string login, CancellationToken cancellationToken = default(CancellationToken));
    }
}

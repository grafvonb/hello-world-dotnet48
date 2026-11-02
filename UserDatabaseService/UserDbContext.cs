using System.ComponentModel.DataAnnotations.Schema;
using System.Data.Entity;

namespace UserDatabaseService
{
    [DbConfigurationType(typeof(UserDbConfiguration))]
    internal sealed class UserDbContext : DbContext
    {
        public UserDbContext(string connectionString) : base(connectionString)
        {
            Configuration.ProxyCreationEnabled = false;
            Configuration.LazyLoadingEnabled = false;
        }

        public DbSet<User> Users { get; set; }

        protected override void OnModelCreating(DbModelBuilder modelBuilder)
        {
            var user = modelBuilder.Entity<User>();
            user.ToTable("User", "dbo");
            user.HasKey(value => value.Login);
            user.Property(value => value.Login).IsRequired().IsUnicode().HasMaxLength(100)
                .HasDatabaseGeneratedOption(DatabaseGeneratedOption.None);
            user.Property(value => value.Name).IsRequired().IsUnicode().HasMaxLength(100);
            user.Property(value => value.Age).IsRequired();
        }
    }
}

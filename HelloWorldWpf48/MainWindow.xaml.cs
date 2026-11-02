using System;
using System.Configuration;
using System.Data.SqlClient;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Threading;
using UserDatabaseService;

namespace HelloWorldWpf48
{
    public partial class MainWindow : Window
    {
        private enum LoadState { Initial, Loading, Populated, Empty, Failed, Closed }

        private readonly Func<IUserService> serviceFactory;
        private readonly CancellationTokenSource lifetime = new CancellationTokenSource();
        private LoadState state = LoadState.Initial;
        private bool started;
        private bool isLoading;

        public MainWindow() : this(CreateUserService)
        {
        }

        public MainWindow(Func<IUserService> serviceFactory)
        {
            if (serviceFactory == null)
                throw new ArgumentNullException(nameof(serviceFactory));

            this.serviceFactory = serviceFactory;
            InitializeComponent();
            Loaded += WindowLoaded;
            Closed += WindowClosed;
            RetryButton.Click += RetryClicked;
        }

        private static IUserService CreateUserService()
        {
            var setting = ConfigurationManager.ConnectionStrings["UserDatabase"];
            if (setting == null || string.IsNullOrWhiteSpace(setting.ConnectionString))
                throw new ConfigurationErrorsException("The UserDatabase connection is required.");

            return new SqlUserService(setting.ConnectionString);
        }

        private async void WindowLoaded(object sender, RoutedEventArgs e)
        {
            if (started)
                return;
            started = true;
            await LoadUsersAsync();
        }

        private async void RetryClicked(object sender, RoutedEventArgs e)
        {
            if (state == LoadState.Failed && !isLoading)
                await LoadUsersAsync();
        }

        private async Task LoadUsersAsync()
        {
            if (isLoading || state == LoadState.Closed)
                return;

            isLoading = true;
            Present(LoadState.Loading, "Loading users...");
            try
            {
                // Let layout and rendering run before even a synchronously completed source.
                await Dispatcher.Yield(DispatcherPriority.Background);
                if (state == LoadState.Closed)
                    return;

                var service = serviceFactory();
                if (service == null)
                    throw new InvalidOperationException("The user source is unavailable.");
                var users = await service.GetAllAsync(lifetime.Token);
                if (state == LoadState.Closed)
                    return;
                if (users == null)
                    throw new InvalidOperationException("The user source returned no collection.");

                UsersGrid.ItemsSource = users;
                Present(users.Count == 0 ? LoadState.Empty : LoadState.Populated,
                    users.Count == 0 ? "No users found" : "");
            }
            catch (Exception exception)
            {
                if (state != LoadState.Closed)
                    Present(LoadState.Failed, FailureMessage(exception));
            }
            finally
            {
                isLoading = false;
                if (state == LoadState.Closed)
                    lifetime.Dispose();
            }
        }

        private static string FailureMessage(Exception exception)
        {
            if (exception is ConfigurationErrorsException || exception is ArgumentException)
                return "The user database connection is not configured correctly. Check the application settings.";
            if (exception is OperationCanceledException)
                return "Loading was canceled. Try again.";

            var sql = exception as SqlException;
            if (sql != null)
            {
                switch (sql.Number)
                {
                    case 18456:
                    case 229:
                    case 230:
                        return "Access to user data was denied. Check your database permissions.";
                    case 208:
                        return "User storage is unavailable or has not been prepared. Check database setup and access.";
                    case 4060:
                        return "The user database cannot be opened. Check availability and access.";
                }
            }
            return "Users could not be loaded. Check availability and access, then retry.";
        }

        private void Present(LoadState next, string message = "")
        {
            if (state == LoadState.Closed)
                return;

            state = next;
            UsersGrid.Visibility = next == LoadState.Populated ? Visibility.Visible : Visibility.Collapsed;
            LoadStatusText.Text = message;
            LoadStatusText.Visibility = next == LoadState.Populated ? Visibility.Collapsed : Visibility.Visible;
            RetryButton.Visibility = next == LoadState.Failed ? Visibility.Visible : Visibility.Collapsed;
            RetryButton.IsEnabled = next == LoadState.Failed;
        }

        private void WindowClosed(object sender, EventArgs e)
        {
            state = LoadState.Closed;
            lifetime.Cancel();
            if (!isLoading)
                lifetime.Dispose();
        }
    }
}

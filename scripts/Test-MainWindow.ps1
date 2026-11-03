param(
    [ValidateSet('Debug', 'Release')][string]$Configuration = 'Debug',
    [ValidateSet('All', 'US1', 'US2', 'US3')][string]$Phase = 'All',
    [string]$SqlServer,
    [ValidateSet('Sql', 'EntityFramework', 'EntityFrameworkStoredProcedures', 'Both', 'All')][string]$Implementation = 'Sql',
    [switch]$Interactive
)
$ErrorActionPreference = 'Stop'
if ([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
    throw 'Run with Windows PowerShell -STA.'
}
$build = Join-Path $PSScriptRoot "..\HelloWorldWpf48\bin\$Configuration"
$exe = Join-Path $build 'HelloWorldWpf48.exe'
$service = Join-Path $build 'UserDatabaseService.dll'
if (!(Test-Path $exe)) { throw 'Build the solution first.' }
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml, System.Configuration
Add-Type -Path (Join-Path $build 'EntityFramework.dll')
Add-Type -Path (Join-Path $build 'EntityFramework.SqlServer.dll')
Add-Type -Path $service
$applicationAssembly = [Reflection.Assembly]::LoadFrom($exe)
$references = @(
    $service, (Join-Path $build 'EntityFramework.dll'), 'System.dll', 'System.Core.dll', 'System.Configuration.dll', 'System.Data.dll',
    [Windows.Window].Assembly.Location,
    [Windows.Media.Visual].Assembly.Location,
    [Windows.Threading.Dispatcher].Assembly.Location,
    [System.Xaml.XamlReader].Assembly.Location
)
$sourceCode = @'
using System;
using System.Data.Entity;
using System.Data.Entity.Infrastructure.Interception;
using System.Collections.Generic;
using System.Configuration;
using System.Diagnostics;
using System.Linq;
using System.Reflection;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Threading;
using UserDatabaseService;

public sealed class WindowUserSource : IUserService
{
    public readonly Queue<Func<CancellationToken, Task<IReadOnlyList<User>>>> Outcomes =
        new Queue<Func<CancellationToken, Task<IReadOnlyList<User>>>>();
    public int Calls;
    public int OtherCalls;
    public CancellationToken LastToken;
    public Task<IReadOnlyList<User>> GetAllAsync(CancellationToken token)
    {
        Calls++;
        LastToken = token;
        return Outcomes.Dequeue()(token);
    }
    private Exception Unexpected() { OtherCalls++; return new Exception("Unexpected service operation."); }
    public Task CreateOrUpdateDatabaseAsync(CancellationToken token) { throw Unexpected(); }
    public Task<User> GetByLoginAsync(string login, CancellationToken token) { throw Unexpected(); }
    public Task<IReadOnlyList<User>> GetByLoginsAsync(IEnumerable<string> logins, CancellationToken token) { throw Unexpected(); }
    public Task CreateAsync(User user, CancellationToken token) { throw Unexpected(); }
    public Task<bool> UpdateAsync(User user, CancellationToken token) { throw Unexpected(); }
    public Task<bool> DeleteAsync(string login, CancellationToken token) { throw Unexpected(); }
}


public sealed class EfWindowProbe : DbCommandInterceptor
{
    public int UserReads;
    public int ProcedureReads;
    public override void ReaderExecuting(System.Data.Common.DbCommand command,
        DbCommandInterceptionContext<System.Data.Common.DbDataReader> context)
    {
        if (command.CommandText == "EXEC dbo.User_GetAll;") Interlocked.Increment(ref ProcedureReads);
        if (command.CommandText.Contains("[User]")) Interlocked.Increment(ref UserReads);
    }
}

public sealed class ColdModelGate : IDbConnectionInterceptor, IDisposable
{
    public readonly ManualResetEventSlim Started = new ManualResetEventSlim();
    public readonly ManualResetEventSlim Release = new ManualResetEventSlim();
    private int entered;
    public void Opening(System.Data.Common.DbConnection connection, DbConnectionInterceptionContext context)
    {
        if (Interlocked.CompareExchange(ref entered, 1, 0) == 0)
        {
            Started.Set();
            if (!Release.Wait(3000)) throw new Exception("Cold initialization blocked the UI test timeout.");
        }
    }
    public void BeginningTransaction(System.Data.Common.DbConnection connection, BeginTransactionInterceptionContext context) { }
    public void BeganTransaction(System.Data.Common.DbConnection connection, BeginTransactionInterceptionContext context) { }
    public void Closing(System.Data.Common.DbConnection connection, DbConnectionInterceptionContext context) { }
    public void Closed(System.Data.Common.DbConnection connection, DbConnectionInterceptionContext context) { }
    public void ConnectionStringGetting(System.Data.Common.DbConnection connection, DbConnectionInterceptionContext<System.String> context) { }
    public void ConnectionStringGot(System.Data.Common.DbConnection connection, DbConnectionInterceptionContext<System.String> context) { }
    public void ConnectionStringSetting(System.Data.Common.DbConnection connection, DbConnectionPropertyInterceptionContext<System.String> context) { }
    public void ConnectionStringSet(System.Data.Common.DbConnection connection, DbConnectionPropertyInterceptionContext<System.String> context) { }
    public void ConnectionTimeoutGetting(System.Data.Common.DbConnection connection, DbConnectionInterceptionContext<System.Int32> context) { }
    public void ConnectionTimeoutGot(System.Data.Common.DbConnection connection, DbConnectionInterceptionContext<System.Int32> context) { }
    public void DatabaseGetting(System.Data.Common.DbConnection connection, DbConnectionInterceptionContext<System.String> context) { }
    public void DatabaseGot(System.Data.Common.DbConnection connection, DbConnectionInterceptionContext<System.String> context) { }
    public void DataSourceGetting(System.Data.Common.DbConnection connection, DbConnectionInterceptionContext<System.String> context) { }
    public void DataSourceGot(System.Data.Common.DbConnection connection, DbConnectionInterceptionContext<System.String> context) { }
    public void Disposing(System.Data.Common.DbConnection connection, DbConnectionInterceptionContext context) { }
    public void Disposed(System.Data.Common.DbConnection connection, DbConnectionInterceptionContext context) { }
    public void EnlistingTransaction(System.Data.Common.DbConnection connection, EnlistTransactionInterceptionContext context) { }
    public void EnlistedTransaction(System.Data.Common.DbConnection connection, EnlistTransactionInterceptionContext context) { }
    public void Opened(System.Data.Common.DbConnection connection, DbConnectionInterceptionContext context) { }
    public void ServerVersionGetting(System.Data.Common.DbConnection connection, DbConnectionInterceptionContext<System.String> context) { }
    public void ServerVersionGot(System.Data.Common.DbConnection connection, DbConnectionInterceptionContext<System.String> context) { }
    public void StateGetting(System.Data.Common.DbConnection connection, DbConnectionInterceptionContext<System.Data.ConnectionState> context) { }
    public void StateGot(System.Data.Common.DbConnection connection, DbConnectionInterceptionContext<System.Data.ConnectionState> context) { }
    public void Dispose() { Started.Dispose(); Release.Dispose(); }
}

public static class MainWindowChecks
{
    private static Type windowType;
    private static readonly List<Window> windows = new List<Window>();
    private static readonly List<Exception> unhandled = new List<Exception>();
    private static int assertions;

    private static void Assert(bool condition, string message)
    {
        assertions++;
        if (!condition) throw new Exception("FAIL: " + message);
    }
    private static void Pump()
    {
        var frame = new DispatcherFrame();
        var timer = new DispatcherTimer(DispatcherPriority.Background);
        timer.Interval = TimeSpan.FromMilliseconds(10);
        timer.Tick += delegate { timer.Stop(); frame.Continue = false; };
        timer.Start();
        try { Dispatcher.PushFrame(frame); } finally { timer.Stop(); }
    }
    private static void Until(Func<bool> condition, string description)
    {
        var watch = Stopwatch.StartNew();
        while (!condition())
        {
            if (watch.ElapsedMilliseconds > 5000) throw new Exception("Timeout: " + description);
            Pump();
        }
    }
    private static Window NewWindow(Func<IUserService> factory)
    {
        var constructor = windowType.GetConstructor(new[] { typeof(Func<IUserService>) });
        Assert(constructor != null, "MainWindow must support a lazy service factory.");
        var window = (Window)constructor.Invoke(new object[] { factory });
        windows.Add(window);
        return window;
    }
    private static DataGrid Grid(Window w) { return (DataGrid)w.FindName("UsersGrid"); }
    private static TextBlock Status(Window w) { return (TextBlock)w.FindName("LoadStatusText"); }
    private static Button Retry(Window w) { return (Button)w.FindName("RetryButton"); }
    private static bool Failed(Window w) { return Retry(w).IsVisible && Retry(w).IsEnabled; }
    private static void ClickRetry(Window w) { Retry(w).RaiseEvent(new RoutedEventArgs(ButtonBase.ClickEvent)); }
    private static Task<IReadOnlyList<User>> Failure(Exception error)
    {
        var pending = new TaskCompletionSource<IReadOnlyList<User>>();
        pending.SetException(error);
        return pending.Task;
    }
    private static IReadOnlyList<User> Rows(int count)
    {
        var users = new List<User>();
        for (int i = 0; i < count; i++)
            users.Add(new User {
                Name = i == 0 || i == count - 1 ? new string('N', 100) : i < 3 ? "Same Name" : "\u0141ukasz " + i,
                Login = i == 0 ? new string('a', 100) : i == count - 1 ? new string('z', 100) : "user" + i.ToString("D4"),
                Age = i % 90
            });
        return users.AsReadOnly();
    }
    private static void Populated()
    {
        foreach (int count in new[] { 1, 100, 1000 })
        {
            var source = new WindowUserSource();
            var pending = new TaskCompletionSource<IReadOnlyList<User>>();
            source.Outcomes.Enqueue(token => pending.Task);
            int factories = 0;
            var w = NewWindow(() => { factories++; return source; });
            Assert(factories == 0, "Factory is lazy.");
            var watch = Stopwatch.StartNew();
            w.Show();
            Until(() => source.Calls == 1 && Status(w).IsVisible, "initial loading");
            var loadingMs = watch.ElapsedMilliseconds;
            Assert(loadingMs < 1000 && Status(w).Text == "Loading users...", "Loading feedback within one second.");
            Assert(!Retry(w).IsVisible || !Retry(w).IsEnabled, "Retry unavailable during loading.");
            w.RaiseEvent(new RoutedEventArgs(FrameworkElement.LoadedEvent));
            Pump();
            Assert(source.Calls == 1, "Repeated Loaded starts no extra request.");
            var expected = Rows(count);
            watch.Restart();
            pending.SetResult(expected);
            Until(() => Grid(w).IsVisible && Grid(w).Items.Count == count, "populated grid");
            w.UpdateLayout();
            var displayMs = watch.ElapsedMilliseconds;
            Assert(displayMs < 1000 && Grid(w).ActualHeight > 0, "Result layout within one second.");
            Assert(!Status(w).IsVisible && !Retry(w).IsVisible, "Success clears status and Retry.");
            Assert(Grid(w).IsReadOnly && !Grid(w).CanUserAddRows && !Grid(w).CanUserDeleteRows &&
                !Grid(w).CanUserSortColumns && Grid(w).EnableRowVirtualization, "Read-only virtualized grid.");
            Assert(Grid(w).Columns.Select(c => c.Header.ToString()).SequenceEqual(new[] { "Name", "Login", "Age" }), "Explicit field headers.");
            Assert(AutomationProperties.GetAutomationId(Grid(w)) == "UsersGrid" &&
                !string.IsNullOrWhiteSpace(AutomationProperties.GetName(Grid(w))) &&
                AutomationProperties.GetAutomationId(Status(w)) == "LoadStatusText" &&
                AutomationProperties.GetAutomationId(Retry(w)) == "RetryButton" &&
                !string.IsNullOrWhiteSpace(AutomationProperties.GetName(Retry(w))), "Accessible names and stable IDs.");
            for (int i = 0; i < count; i++)
            {
                var actual = (User)Grid(w).Items[i];
                Assert(actual.Name == expected[i].Name && actual.Login == expected[i].Login && actual.Age == expected[i].Age,
                    "Values and ordering preserved at row " + i);
            }
            Grid(w).ScrollIntoView(expected[0], Grid(w).Columns[0]);
            w.UpdateLayout();
            var firstName = Grid(w).Columns[0].GetCellContent(expected[0]) as TextBlock;
            Assert(firstName != null && firstName.Text == expected[0].Name && firstName.TextWrapping == TextWrapping.Wrap,
                "First Name binding renders complete wrapped text.");
            Grid(w).ScrollIntoView(expected[count - 1], Grid(w).Columns[2]);
            Pump();
            w.UpdateLayout();
            var lastLogin = Grid(w).Columns[1].GetCellContent(expected[count - 1]) as TextBlock;
            var lastAge = Grid(w).Columns[2].GetCellContent(expected[count - 1]) as TextBlock;
            Assert(lastLogin != null && lastLogin.Text == expected[count - 1].Login &&
                lastAge != null && lastAge.Text == expected[count - 1].Age.ToString(),
                "Last Login and Age bindings render complete values.");
            Assert(source.OtherCalls == 0, "No setup or write calls.");
            w.Close();
            Pump();
            Console.WriteLine("PASS: {0} rows; loading {1} ms; supplied-result layout {2} ms", count, loadingMs, displayMs);
        }
    }
    private static void Closing()
    {
        foreach (string outcome in new[] { "cancel", "success", "fault" })
        {
            var source = new WindowUserSource();
            var pending = new TaskCompletionSource<IReadOnlyList<User>>();
            source.Outcomes.Enqueue(token => {
                if (outcome == "cancel") token.Register(() => pending.TrySetCanceled());
                return pending.Task;
            });
            var w = NewWindow(() => source);
            w.Show();
            Until(() => source.Calls == 1, "pending close");
            var status = Status(w).Text;
            var items = Grid(w).ItemsSource;
            var retry = Retry(w).Visibility;
            var watch = Stopwatch.StartNew();
            w.Close();
            Assert(watch.ElapsedMilliseconds < 1000 && !w.IsVisible, "Closure does not wait for I/O.");
            Assert(source.LastToken.IsCancellationRequested, "Closing requests cancellation.");
            if (outcome == "success") pending.SetResult(Rows(1));
            if (outcome == "fault") pending.SetException(new Exception("private late error"));
            Pump(); Pump();
            Assert(Status(w).Text == status && ReferenceEquals(Grid(w).ItemsSource, items) &&
                Retry(w).Visibility == retry, "No post-close presentation mutation.");
            Assert(source.OtherCalls == 0, "No writes on close.");
            Console.WriteLine("PASS: close while pending, provider outcome " + outcome);
        }
        int calls = 0;
        var early = NewWindow(() => { calls++; return new WindowUserSource(); });
        early.Show();
        early.Close();
        Pump();
        Assert(calls == 0, "Closing before deferred source access skips the factory.");
    }
    private static void Empty()
    {
        var source = new WindowUserSource();
        source.Outcomes.Enqueue(token => Task.FromResult(Rows(0)));
        var w = NewWindow(() => source);
        w.Show();
        Until(() => Status(w).Text == "No users found", "empty result");
        Assert(Status(w).IsVisible && !Grid(w).IsVisible && Grid(w).Items.Count == 0 &&
            !Retry(w).IsVisible && source.OtherCalls == 0, "Successful empty state without writes.");
        w.Close();
        Console.WriteLine("PASS: successful empty state");
    }
    private static void Failures()
    {
        foreach (Exception error in new Exception[] {
            new ConfigurationErrorsException("secret connection"), new ArgumentException("secret password"),
            new InvalidOperationException("private server"), new OperationCanceledException("private cancellation") })
        {
            var w = NewWindow(() => { throw error; });
            w.Show();
            Until(() => Failed(w), "factory failure");
            Assert(Status(w).IsVisible && !Grid(w).IsVisible && !Status(w).Text.Contains("secret") &&
                !Status(w).Text.Contains("private"), "Sanitized exclusive error state.");
            if (error is ConfigurationErrorsException || error is ArgumentException)
                Assert(Status(w).Text.Contains("configured"), "Configuration-specific feedback.");
            w.Close();
        }
        foreach (int recoveredCount in new[] { 0, 3 })
        {
            var source = new WindowUserSource();
            var pending = new TaskCompletionSource<IReadOnlyList<User>>();
            source.Outcomes.Enqueue(token => Failure(new Exception("secret")));
            source.Outcomes.Enqueue(token => Failure(new Exception("second secret")));
            source.Outcomes.Enqueue(token => pending.Task);
            var w = NewWindow(() => source);
            w.Show();
            Until(() => Failed(w), "first failure");
            ClickRetry(w);
            Until(() => Failed(w) && source.Calls == 2, "repeated failure");
            ClickRetry(w);
            Until(() => source.Calls == 3, "retry loading");
            Assert(Status(w).Text == "Loading users..." && !Retry(w).IsEnabled, "Retry resets failure.");
            ClickRetry(w);
            Pump();
            Assert(source.Calls == 3, "Synthetic repeated clicks cannot overlap requests.");
            pending.SetResult(Rows(recoveredCount));
            Until(() => recoveredCount == 0 ? Status(w).Text == "No users found" : Grid(w).IsVisible, "recovery");
            Assert(!Retry(w).IsVisible && Grid(w).Items.Count == recoveredCount && source.OtherCalls == 0, "Current result without duplicates or writes.");
            w.Close();
        }
        var canceled = new WindowUserSource();
        canceled.Outcomes.Enqueue(token => {
            var p = new TaskCompletionSource<IReadOnlyList<User>>(); p.SetCanceled(); return p.Task;
        });
        var open = NewWindow(() => canceled);
        open.Show();
        Until(() => Failed(open), "open-window cancellation");
        Assert(Status(open).Text.Contains("canceled"), "Open cancellation allows retry.");
        open.Close();

        var closing = new WindowUserSource();
        var late = new TaskCompletionSource<IReadOnlyList<User>>();
        closing.Outcomes.Enqueue(token => Failure(new Exception("initial")));
        closing.Outcomes.Enqueue(token => late.Task);
        var retryWindow = NewWindow(() => closing);
        retryWindow.Show();
        Until(() => Failed(retryWindow), "failure before close-during-retry");
        ClickRetry(retryWindow);
        Until(() => closing.Calls == 2, "pending retry");
        var prior = Status(retryWindow).Text;
        retryWindow.Close();
        late.SetException(new Exception("late retry error"));
        Pump(); Pump();
        Assert(Status(retryWindow).Text == prior && closing.OtherCalls == 0, "Close during retry is terminal.");
        Console.WriteLine("PASS: factory failures, repeated failures/retries, populated/empty recovery, cancellation and retry closure");
    }

    private static void SqlCommand(string connection, string commandText)
    {
        using (var c = new System.Data.SqlClient.SqlConnection(connection))
        using (var command = c.CreateCommand())
        {
            c.Open(); command.CommandText = commandText; command.ExecuteNonQuery();
        }
    }
    private static object Scalar(string connection, string commandText)
    {
        using (var c = new System.Data.SqlClient.SqlConnection(connection))
        using (var command = c.CreateCommand())
        {
            c.Open(); command.CommandText = commandText; return command.ExecuteScalar();
        }
    }
    private static void Configure(string value)
    {
        // This is the disposable validation host's config, never the installed app/PowerShell config.
        var config = ConfigurationManager.OpenExeConfiguration(ConfigurationUserLevel.None);
        config.ConnectionStrings.ConnectionStrings.Remove("UserDatabase");
        if (value != null)
            config.ConnectionStrings.ConnectionStrings.Add(new ConnectionStringSettings("UserDatabase", value, "System.Data.SqlClient"));
        config.Save(ConfigurationSaveMode.Modified);
        ConfigurationManager.RefreshSection("connectionStrings");
    }

    private static void ConfigureImplementation(string value)
    {
        var config = ConfigurationManager.OpenExeConfiguration(ConfigurationUserLevel.None);
        config.AppSettings.Settings.Remove("UserServiceImplementation");
        if (value != null) config.AppSettings.Settings.Add("UserServiceImplementation", value);
        config.Save(ConfigurationSaveMode.Modified);
        ConfigurationManager.RefreshSection("appSettings");
    }

    private static void CloseDuringColdModel(string connection, string implementation)
    {
        using (var gate = new ColdModelGate())
        {
            DbInterception.Add(gate);
            try
            {
                var realSource = UserServiceFactory.Create(implementation, connection);
                var source = new WindowUserSource();
                Task<IReadOnlyList<User>> pending = null;
                source.Outcomes.Enqueue(token => { pending = realSource.GetAllAsync(token); return pending; });
                var w = NewWindow(() => source);
                var watch = Stopwatch.StartNew();
                w.Show();
                Until(() => gate.Started.IsSet, "cold EF model preparation");
                Assert(watch.ElapsedMilliseconds < 1000 && Status(w).IsVisible &&
                    Status(w).Text == "Loading users...", "UI processes events during cold EF initialization.");
                var text = Status(w).Text;
                watch.Restart();
                w.Close();
                Assert(watch.ElapsedMilliseconds < 1000, "Close remains immediate during cold model work.");
                gate.Release.Set();
                Until(() => pending != null && pending.IsCompleted, "canceled cold EF work");
                Pump();
                Assert(pending.IsCanceled && Status(w).Text == text && source.OtherCalls == 0,
                    "Cold EF cancellation is observed without late UI mutation or writes.");
                Console.WriteLine("PASS: " + implementation + " - responsive cold model preparation, immediate close and cancellation");
            }
            finally { gate.Release.Set(); DbInterception.Remove(gate); }
        }
    }

    private static Window ProductionWindow()
    {
        var w = (Window)Activator.CreateInstance(windowType);
        windows.Add(w); w.Show(); return w;
    }
    private static void SqlChecks(Assembly assembly, string server, string implementation, string scenario, string name, bool interactive)
    {
        windowType = assembly.GetType("HelloWorldWpf48.MainWindow", true);
        var builder = new System.Data.SqlClient.SqlConnectionStringBuilder {
            DataSource = server, InitialCatalog = name, IntegratedSecurity = true, ConnectTimeout = 3
        };
        var connection = builder.ConnectionString;
        builder.InitialCatalog = "master";
        var master = builder.ConnectionString;
        var source = new SqlUserService(connection);
        DbConfiguration.LoadConfiguration(typeof(IUserService).Assembly.GetType("UserDatabaseService.UserDbContext", true));
        var probe = new EfWindowProbe();
        DbInterception.Add(probe);
        ConfigureImplementation(implementation);
        var app = new Application { ShutdownMode = ShutdownMode.OnExplicitShutdown };
        app.DispatcherUnhandledException += (s, e) => { unhandled.Add(e.Exception); e.Handled = true; };
        try
        {
            // Parent-owned fixture was prepared in a different process: this EF request is cold.
            Configure(connection);
            if (scenario == "ColdClose")
            {
                CloseDuringColdModel(connection, implementation);
                return;
            }
            var watch = Stopwatch.StartNew();
            var empty = ProductionWindow();
            bool uiReady = false;
            empty.Dispatcher.BeginInvoke(DispatcherPriority.ContextIdle, new Action(() => uiReady = true));
            Until(() => uiReady, "responsive initial UI");
            Assert(watch.ElapsedMilliseconds < 1000, "Loading UI responds within one second.");
            Console.WriteLine("PASS: {0} - first window UI dispatch {1} ms", implementation, watch.ElapsedMilliseconds);
            Until(() => Status(empty).Text == "No users found", "real SQL empty result");
            Assert(implementation == "EntityFrameworkStoredProcedures" ? probe.ProcedureReads > 0 && probe.UserReads == 0 :
                implementation == "EntityFramework" ? probe.UserReads > 0 && probe.ProcedureReads == 0 :
                probe.UserReads == 0 && probe.ProcedureReads == 0,
                "Configured window actually uses the selected query implementation.");
            empty.Close();
            foreach (string value in new[] { null, "", " ", " sQL ", " eNTITYfRAMEWORK ", " eNTITYfRAMEWORKsTOREDpROCEDURES " })
            {
                var selected = UserServiceFactory.Create(value, connection);
                var expected = value != null && value.Trim().Equals("EntityFrameworkStoredProcedures", StringComparison.OrdinalIgnoreCase)
                    ? "EfStoredProcedureUserService" : value != null && value.Trim().Equals("EntityFramework", StringComparison.OrdinalIgnoreCase)
                    ? "EfUserService" : "SqlUserService";
                Assert(selected.GetType().Name == expected, "Factory selection/default/case/trim.");
            }
            foreach (string value in implementation == "EntityFrameworkStoredProcedures"
                ? new[] { null, " ", " sQL ", " eNTITYfRAMEWORKsTOREDpROCEDURES " } : new[] { null, " ", " sQL " })
            {
                ConfigureImplementation(value);
                var defaultView = ProductionWindow();
                Until(() => Status(defaultView).Text == "No users found", "default or explicit Sql view");
                defaultView.Close();
            }
            ConfigureImplementation("invalid choice");
            var badChoice = ProductionWindow();
            Until(() => Failed(badChoice), "invalid implementation");
            Assert(Status(badChoice).Text.Contains("configured"), "Unknown implementation gives configuration feedback.");
            badChoice.Close();
            ConfigureImplementation(implementation);
            foreach (var row in new[] {
                new User { Name = "Same Name", Login = "alice", Age = 0 },
                new User { Name = "Same Name", Login = "bob", Age = 30 },
                new User { Name = "\u0141ukasz", Login = "unicode", Age = 42 } })
                source.CreateAsync(row).GetAwaiter().GetResult();
            var before = string.Join("|", source.GetAllAsync().GetAwaiter().GetResult().Select(u => u.Login + ":" + u.Name + ":" + u.Age));
            var populated = ProductionWindow();
            Until(() => Grid(populated).IsVisible, "real SQL populated result");
            Assert(Grid(populated).Items.Count == 3 && ((User)Grid(populated).Items[0]).Age == 0, "Real configured source populates expected rows.");
            populated.Close();
            var after = string.Join("|", source.GetAllAsync().GetAwaiter().GetResult().Select(u => u.Login + ":" + u.Name + ":" + u.Age));
            Assert(before == after, "Real application viewing preserves rows.");
            Console.WriteLine("PASS: " + implementation + " - default constructor/config path; empty/populated/duplicate names/Unicode/zero; data unchanged");

            if (implementation == "EntityFrameworkStoredProcedures")
            {
                SqlCommand(connection, "DROP PROCEDURE dbo.User_GetAll;");
                var missing = ProductionWindow();
                Until(() => Failed(missing), "missing read procedure");
                Assert(Status(missing).Text.Contains("storage") && Retry(missing).IsEnabled && !Grid(missing).IsVisible,
                    "Missing procedure gives safe setup feedback");
                Assert(Scalar(connection, "SELECT OBJECT_ID(N'dbo.User_GetAll',N'P');") == DBNull.Value,
                    "Window did not install missing procedure");
                new EfStoredProcedureUserService(connection).CreateOrUpdateDatabaseAsync().GetAwaiter().GetResult();
                ClickRetry(missing);
                Until(() => Grid(missing).IsVisible, "explicit procedure repair followed by Retry");
                Assert(Grid(missing).Items.Count == 3, "Explicit repair and Retry preserves fixture users");
                missing.Close();
                Console.WriteLine("PASS: EntityFrameworkStoredProcedures - SQL2812, no implicit repair, explicit setup and Retry");
            }

            foreach (string invalid in new[] { null, "invalid connection value" })
            {
                Configure(invalid);
                var bad = ProductionWindow();
                Until(() => Failed(bad), "real missing/invalid configuration");
                Assert(Status(bad).Text.Contains("configured"), "Real configuration failure is categorized.");
                bad.Close();
            }
            Console.WriteLine("PASS: " + implementation + " - host missing and invalid connection settings");

            builder.InitialCatalog = name + "_Absent";
            Configure(builder.ConnectionString);
            var absent = ProductionWindow();
            Until(() => Failed(absent), "unavailable database");
            Assert(Status(absent).Text != "No users found", "Unavailable database is not empty.");
            absent.Close();
            Assert(Scalar(master, "SELECT DB_ID(N'" + name + "_Absent')") == DBNull.Value, "Application did not create unavailable database.");

            Configure(connection);
            SqlCommand(connection, "EXEC sys.sp_rename N'dbo.User', N'User_ValidationHidden';");
            var unprepared = ProductionWindow();
            Until(() => Failed(unprepared), "unprepared user storage");
            Assert(Status(unprepared).Text.Contains("storage"), "Missing user storage category.");
            Assert(Scalar(connection, "SELECT OBJECT_ID(N'dbo.[User]', N'U')") == DBNull.Value, "Application did not recreate user table.");
            unprepared.Close();
            SqlCommand(connection, "EXEC sys.sp_rename N'dbo.User_ValidationHidden', N'User';");
            Console.WriteLine("PASS: " + implementation + " - unavailable database/unprepared table; no automatic database/schema setup");

            // An intentionally nonexistent SQL login proves provider access rejection without
            // creating accounts or changing server authentication/security settings.
            var denied = new System.Data.SqlClient.SqlConnectionStringBuilder(connection) {
                IntegratedSecurity = false, UserID = "UserListDenied_" + Guid.NewGuid().ToString("N"),
                Password = Guid.NewGuid().ToString("N")
            };
            string activeConnection = denied.ConnectionString;
            var retry = NewWindow(() => UserServiceFactory.Create(implementation, activeConnection));
            retry.Show();
            Until(() => Failed(retry), "SQL access rejection");
            Assert(Status(retry).Text.Contains("denied"), "SQL access error category.");
            activeConnection = connection;
            ClickRetry(retry);
            Until(() => Grid(retry).IsVisible, "SQL retry recovery");
            Assert(Grid(retry).Items.Count == 3 && !Retry(retry).IsVisible, "Real SQL retry loads current rows.");
            retry.Close();
            Assert(before == string.Join("|", source.GetAllAsync().GetAwaiter().GetResult().Select(u => u.Login + ":" + u.Name + ":" + u.Age)), "Negative cases and retry preserve fixture data.");
            Assert(unhandled.Count == 0, "No unhandled SQL-window errors.");
            Console.WriteLine("PASS: " + implementation + " - provider access denial followed by one Retry; data preserved");
            Console.WriteLine("PASS: " + implementation + " - " + assertions + " real-source assertions");
            if (interactive)
            {
                var view = (Window)Activator.CreateInstance(windowType);
                windows.Add(view); view.Title = implementation + " - real source inspection"; view.ShowDialog();
            }
        }
        finally
        {
            foreach (var w in windows) if (w.IsVisible) w.Close();
            app.Shutdown();
            DbInterception.Remove(probe);
            System.Data.SqlClient.SqlConnection.ClearAllPools();
            // The parent owns cleanup, including failed child processes.
        }
    }
    [STAThread]
    public static int Main(string[] args)
    {
        try
        {
            string name = args[4];
            Guid identity;
            const string prefix = "UserListWindowTest_";
            if (!name.StartsWith(prefix, StringComparison.Ordinal) || !Guid.TryParseExact(name.Substring(prefix.Length), "N", out identity))
                throw new Exception("Invalid owned fixture name.");
            var builder = new System.Data.SqlClient.SqlConnectionStringBuilder {
                DataSource = args[1], InitialCatalog = name, IntegratedSecurity = true, ConnectTimeout = 30
            };
            var connection = builder.ConnectionString;
            if (args[3] == "Prepare")
            {
                IUserService setup = args[2] == "EntityFrameworkStoredProcedures"
                    ? (IUserService)new EfStoredProcedureUserService(connection) : new SqlUserService(connection);
                setup.CreateOrUpdateDatabaseAsync().GetAwaiter().GetResult();
                return 0;
            }
            if (args[3] == "Cleanup")
            {
                builder.InitialCatalog = "master";
                System.Data.SqlClient.SqlConnection.ClearAllPools();
                SqlCommand(builder.ConnectionString, "IF DB_ID(N'" + name + "') IS NOT NULL BEGIN ALTER DATABASE [" + name +
                    "] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [" + name + "]; END;");
                Console.WriteLine("Removed owned SQL fixture: " + name);
                return 0;
            }
            if (args[3] == "Order")
            {
                // No configuration pre-registration or interceptor can mask discovery order here.
                string second = args[2] == "EntityFramework" ? "EntityFrameworkStoredProcedures" : "EntityFramework";
                var firstRows = UserServiceFactory.Create(args[2], connection).GetAllAsync().GetAwaiter().GetResult();
                var nextRows = UserServiceFactory.Create(second, connection).GetAllAsync().GetAwaiter().GetResult();
                Assert(firstRows.Count == nextRows.Count, "Both EF discovery orders work");
                Console.WriteLine("PASS: normal configuration discovery " + args[2] + " -> " + second);
                return 0;
            }
            SqlChecks(Assembly.LoadFrom(args[0]), args[1], args[2], args[3], name, args[5] == "True");
            return 0;
        }
        catch (Exception error)
        {
            var sql = error as System.Data.SqlClient.SqlException;
            Console.Error.WriteLine(sql == null ? error.Message : "SQL validation failed with provider error " + sql.Number);
            return 1;
        }
    }

    public static void Run(Assembly assembly, string phase, bool interactive)
    {
        windowType = assembly.GetType("HelloWorldWpf48.MainWindow", true);
        var app = Application.Current ?? new Application();
        app.ShutdownMode = ShutdownMode.OnExplicitShutdown;
        DispatcherUnhandledExceptionEventHandler errors = (s, e) => { unhandled.Add(e.Exception); e.Handled = true; };
        app.DispatcherUnhandledException += errors;
        try
        {
            if (phase == "All" || phase == "US1") { Populated(); Closing(); }
            if (phase == "All" || phase == "US2") Empty();
            if (phase == "All" || phase == "US3") Failures();
            Pump();
            Assert(unhandled.Count == 0, "No unhandled dispatcher errors.");
            Console.WriteLine("PASS: " + assertions + " assertions");
            if (interactive)
            {
                var source = new WindowUserSource();
                source.Outcomes.Enqueue(token => Task.FromResult(Rows(1000)));
                var w = NewWindow(() => source);
                w.Title = "User list - keyboard validation";
                w.ShowDialog();
                var recovery = new WindowUserSource();
                recovery.Outcomes.Enqueue(token => Failure(new Exception("interactive failure")));
                recovery.Outcomes.Enqueue(token => Task.FromResult(Rows(3)));
                var retryView = NewWindow(() => recovery);
                retryView.Title = "User list - keyboard Retry validation";
                retryView.ShowDialog();
                var waiting = new WindowUserSource();
                waiting.Outcomes.Enqueue(token => {
                    var p = new TaskCompletionSource<IReadOnlyList<User>>();
                    token.Register(() => p.TrySetCanceled());
                    return p.Task;
                });
                var waitingView = NewWindow(() => waiting);
                waitingView.Title = "User list - move and close while loading";
                waitingView.ShowDialog();
            }
        }
        finally
        {
            foreach (var w in windows) if (w.IsVisible) w.Close();
            app.DispatcherUnhandledException -= errors;
            app.Shutdown();
        }
    }
}
'@
if ($SqlServer) {
    # Separate executable gives ConfigurationManager a disposable config file.
    $validationDirectory = Join-Path $env:TEMP ('UserListSqlHost_' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $validationDirectory | Out-Null
    try {
        Get-ChildItem $build -File | Where-Object { $_.Extension -in '.exe', '.dll', '.config' } |
            Copy-Item -Destination $validationDirectory
        $hostExe = Join-Path $validationDirectory 'UserListSqlHost.exe'
        # CodeDom emits without loading the executable into this PowerShell process.
        $compiler = New-Object Microsoft.CSharp.CSharpCodeProvider
        try {
            $parameters = New-Object System.CodeDom.Compiler.CompilerParameters
            $parameters.GenerateExecutable = $true
            $parameters.OutputAssembly = $hostExe
            foreach ($reference in $references) { $null = $parameters.ReferencedAssemblies.Add($reference) }
            $result = $compiler.CompileAssemblyFromSource($parameters, $sourceCode)
            if ($result.Errors.HasErrors) {
                throw (($result.Errors | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine)
            }
        } finally { $compiler.Dispose() }
        Copy-Item ($exe + '.config') ($hostExe + '.config')
        $stdout = Join-Path $validationDirectory 'stdout.txt'
        $stderr = Join-Path $validationDirectory 'stderr.txt'
        function Invoke-OwnedHost([string]$Mode, [string]$Scenario, [string]$Fixture) {
            $arguments = @(('"{0}"' -f (Join-Path $validationDirectory 'HelloWorldWpf48.exe')),
                ('"{0}"' -f $SqlServer), $Mode, $Scenario, $Fixture, $Interactive.IsPresent.ToString())
            $process = Start-Process -FilePath $hostExe -ArgumentList $arguments -Wait -PassThru -NoNewWindow -RedirectStandardOutput $stdout -RedirectStandardError $stderr
            Get-Content -LiteralPath $stdout
            if ($process.ExitCode -ne 0) {
                Get-Content -LiteralPath $stderr | Write-Host
                throw "SQL window validation failed: $Mode / $Scenario."
            }
        }
        $implementations = if ($Implementation -eq 'All') { @('Sql', 'EntityFramework', 'EntityFrameworkStoredProcedures') }
            elseif ($Implementation -eq 'Both') { @('Sql', 'EntityFramework') } else { @($Implementation) }
        foreach ($mode in $implementations) {
            $fixture = 'UserListWindowTest_' + [Guid]::NewGuid().ToString('N')
            try {
                Invoke-OwnedHost $mode 'Prepare' $fixture
                $scenarios = if ($mode -eq 'Sql') { @('Full') } else { @('Full', 'ColdClose') }
                foreach ($scenario in $scenarios) { Invoke-OwnedHost $mode $scenario $fixture }
                if ($mode -eq 'EntityFrameworkStoredProcedures') {
                    Invoke-OwnedHost $mode 'Order' $fixture
                    Invoke-OwnedHost 'EntityFramework' 'Order' $fixture
                }
            } finally {
                Invoke-OwnedHost $mode 'Cleanup' $fixture
            }
        }
    } finally {
        Remove-Item -LiteralPath $validationDirectory -Recurse -Force
    }
} else {
    Add-Type -ReferencedAssemblies $references -TypeDefinition $sourceCode
    [MainWindowChecks]::Run($applicationAssembly, $Phase, $Interactive.IsPresent)
}

param(
    [ValidateSet('Debug', 'Release')][string]$Configuration = 'Debug',
    [ValidateSet('All', 'US1', 'US2', 'US3')][string]$Phase = 'All',
    [string]$SqlServer,
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
Add-Type -Path $service
$applicationAssembly = [Reflection.Assembly]::LoadFrom($exe)
$references = @(
    $service, 'System.dll', 'System.Core.dll', 'System.Configuration.dll', 'System.Data.dll',
    [Windows.Window].Assembly.Location,
    [Windows.Media.Visual].Assembly.Location,
    [Windows.Threading.Dispatcher].Assembly.Location,
    [System.Xaml.XamlReader].Assembly.Location
)
$sourceCode = @'
using System;
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
    private static Window ProductionWindow()
    {
        var w = (Window)Activator.CreateInstance(windowType);
        windows.Add(w); w.Show(); return w;
    }
    private static void SqlChecks(Assembly assembly, string server)
    {
        windowType = assembly.GetType("HelloWorldWpf48.MainWindow", true);
        var name = "UserListWindowTest_" + Guid.NewGuid().ToString("N");
        var builder = new System.Data.SqlClient.SqlConnectionStringBuilder {
            DataSource = server, InitialCatalog = name, IntegratedSecurity = true, ConnectTimeout = 3
        };
        var connection = builder.ConnectionString;
        builder.InitialCatalog = "master";
        var master = builder.ConnectionString;
        var source = new SqlUserService(connection);
        var app = new Application { ShutdownMode = ShutdownMode.OnExplicitShutdown };
        app.DispatcherUnhandledException += (s, e) => { unhandled.Add(e.Exception); e.Handled = true; };
        try
        {
            // Explicit fixture setup happens outside application loading.
            source.CreateOrUpdateDatabaseAsync().GetAwaiter().GetResult();
            Configure(connection);
            var empty = ProductionWindow();
            Until(() => Status(empty).Text == "No users found", "real SQL empty result");
            empty.Close();
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
            Console.WriteLine("PASS: SQL default constructor/config path; empty/populated/duplicate names/Unicode/zero; data unchanged");

            foreach (string invalid in new[] { null, "invalid connection value" })
            {
                Configure(invalid);
                var bad = ProductionWindow();
                Until(() => Failed(bad), "real missing/invalid configuration");
                Assert(Status(bad).Text.Contains("configured"), "Real configuration failure is categorized.");
                bad.Close();
            }
            Console.WriteLine("PASS: SQL host missing and invalid connection settings");

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
            Console.WriteLine("PASS: SQL unavailable database/unprepared table; no automatic database/schema setup");

            // An intentionally nonexistent SQL login proves provider access rejection without
            // creating accounts or changing server authentication/security settings.
            var denied = new System.Data.SqlClient.SqlConnectionStringBuilder(connection) {
                IntegratedSecurity = false, UserID = "UserListDenied_" + Guid.NewGuid().ToString("N"),
                Password = Guid.NewGuid().ToString("N")
            };
            string activeConnection = denied.ConnectionString;
            var retry = NewWindow(() => new SqlUserService(activeConnection));
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
            Console.WriteLine("PASS: SQL provider access denial followed by one Retry; data preserved");
            Console.WriteLine("PASS: " + assertions + " SQL assertions");
        }
        finally
        {
            foreach (var w in windows) if (w.IsVisible) w.Close();
            app.Shutdown();
            System.Data.SqlClient.SqlConnection.ClearAllPools();
            // Name is generated by this test; no normal database or principal is touched.
            SqlCommand(master, "IF DB_ID(N'" + name + "') IS NOT NULL BEGIN ALTER DATABASE [" + name +
                "] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [" + name + "]; END;");
            Console.WriteLine("Removed owned SQL fixture: " + name);
        }
    }
    [STAThread]
    public static int Main(string[] args)
    {
        try { SqlChecks(Assembly.LoadFrom(args[0]), args[1]); return 0; }
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
        $arguments = @(('"{0}"' -f (Join-Path $validationDirectory 'HelloWorldWpf48.exe')), ('"{0}"' -f $SqlServer))
        $process = Start-Process -FilePath $hostExe -ArgumentList $arguments -Wait -PassThru -NoNewWindow -RedirectStandardOutput $stdout -RedirectStandardError $stderr
        Get-Content -LiteralPath $stdout
        if ($process.ExitCode -ne 0) {
            Get-Content -LiteralPath $stderr | Write-Host
            throw 'SQL window validation failed.'
        }
    } finally {
        Remove-Item -LiteralPath $validationDirectory -Recurse -Force
    }
} else {
    Add-Type -ReferencedAssemblies $references -TypeDefinition $sourceCode
    [MainWindowChecks]::Run($applicationAssembly, $Phase, $Interactive.IsPresent)
}

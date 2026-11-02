using System.Windows;

namespace HelloWorldWpf48
{
    public partial class MainWindow : Window
    {
        public MainWindow()
        {
            InitializeComponent();
        }

        private void SayHello_Click(object sender, RoutedEventArgs e)
        {
            GreetingText.Text = "Hello from C# 7.3!";
        }
    }
}

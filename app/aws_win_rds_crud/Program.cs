using Microsoft.EntityFrameworkCore;
using aws_win_rds_crud;

var builder = WebApplication.CreateBuilder(args);

var connectionString = Environment.GetEnvironmentVariable("APP_DB_CONNECTION")
                      ?? builder.Configuration.GetConnectionString("DefaultConnection")
                      ?? "Server=localhost;Database=AppDb;Trusted_Connection=True;TrustServerCertificate=True;";

Console.WriteLine($"Using connection string: {connectionString?.Substring(0, Math.Min(50, connectionString.Length))}...");

builder.Services.AddDbContext<AppDbContext>(options =>
    options.UseSqlServer(connectionString));

builder.Services.AddRazorPages();

var app = builder.Build();

// Always show detailed errors for debugging
app.UseDeveloperExceptionPage();

// Run migrations automatically on startup (safe for demo)
try
{
    Console.WriteLine("Starting database migration...");
    using (var scope = app.Services.CreateScope())
    {
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        db.Database.Migrate();
        Console.WriteLine("Database migration completed successfully.");
    }
}
catch (Exception ex)
{
    Console.WriteLine($"Database migration failed: {ex.Message}");
    Console.WriteLine($"Stack trace: {ex.StackTrace}");
    // Don't exit - let the app start anyway so we can see the error page
}

app.UseHttpsRedirection();
app.UseStaticFiles();

app.UseRouting();

app.MapRazorPages();

Console.WriteLine("Application starting...");
app.Run();


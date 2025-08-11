using Microsoft.EntityFrameworkCore;
using aws_win_rds_crud;

var builder = WebApplication.CreateBuilder(args);

var connectionString = Environment.GetEnvironmentVariable("APP_DB_CONNECTION")
                      ?? builder.Configuration.GetConnectionString("DefaultConnection")
                      ?? "Server=localhost;Database=AppDb;Trusted_Connection=True;TrustServerCertificate=True;";

builder.Services.AddDbContext<AppDbContext>(options =>
    options.UseSqlServer(connectionString));

builder.Services.AddRazorPages();

var app = builder.Build();

// Run migrations automatically on startup (safe for demo)
using (var scope = app.Services.CreateScope())
{
    var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
    db.Database.Migrate();
}

if (!app.Environment.IsDevelopment())
{
    app.UseExceptionHandler("/Error");
    app.UseHsts();
}

app.UseHttpsRedirection();
app.UseStaticFiles();

app.UseRouting();

app.MapRazorPages();

app.Run();


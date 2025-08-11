using Microsoft.AspNetCore.Mvc.RazorPages;
using aws_win_rds_crud;

namespace aws_win_rds_crud.Pages
{
    public class IndexModel : PageModel
    {
        private readonly AppDbContext _db;
        public List<Product> Products { get; set; } = new();
        public IndexModel(AppDbContext db) { _db = db; }
        public void OnGet()
        {
            Products = _db.Products.OrderBy(p => p.Id).ToList();
        }
    }
}


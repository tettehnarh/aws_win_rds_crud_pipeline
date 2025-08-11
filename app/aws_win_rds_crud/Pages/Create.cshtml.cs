using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;
using aws_win_rds_crud;

namespace aws_win_rds_crud.Pages
{
    public class CreateModel : PageModel
    {
        private readonly AppDbContext _db;
        [BindProperty]
        public Product Product { get; set; } = new();
        public CreateModel(AppDbContext db) { _db = db; }
        public IActionResult OnPost()
        {
            if (!ModelState.IsValid) return Page();
            _db.Products.Add(Product);
            _db.SaveChanges();
            return RedirectToPage("/Index");
        }
    }
}


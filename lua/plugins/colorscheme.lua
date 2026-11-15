return {
  {
    "catppuccin/nvim",
    opts = function(_, opts)
      opts.transparent_background = vim.g.transparent_background == true
    end,
  },

  {
    "vldslvv/LazyVim",
    opts = {
      colorscheme = "catppuccin-frappe",
    },
  },
}

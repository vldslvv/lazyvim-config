return {
  {
    "catppuccin/nvim",
    opts = function(_, opts)
      opts.transparent_background = vim.g.transparent_background == true
      opts.custom_highlights = function(colors)
        -- Keep hidden-item counts muted, but easier to read.
        return { NeoTreeMessage = { fg = colors.overlay0, style = { "italic" } } }
      end
    end,
  },

  {
    "vldslvv/LazyVim",
    opts = {
      colorscheme = "catppuccin-frappe",
    },
  },
}

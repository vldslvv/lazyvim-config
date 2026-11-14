return {
  {
    "akinsho/bufferline.nvim",
    opts = function(_, opts)
      opts.options = opts.options or {}
      opts.options.always_show_bufferline = true
      opts.options.max_name_length = 32
      local inherited_formatter = opts.options.name_formatter
      opts.options.name_formatter = function(buffer)
        if vim.bo[buffer.bufnr].buftype == "terminal" then
          local purpose = vim.b[buffer.bufnr].workspace_terminal_name or "Shell"
          local title = vim.trim((vim.b[buffer.bufnr].term_title or ""):gsub("%c", " "))
          local prefix = purpose .. " · "
          local width = opts.options.max_name_length - vim.fn.strdisplaywidth(prefix)
          if title == "" or width < 1 then
            return purpose
          end
          -- Keep the purpose and the end of long titles (usually the useful path).
          if vim.fn.strdisplaywidth(title) > width then
            while vim.fn.strdisplaywidth(title) > width - 1 do
              title = vim.fn.strcharpart(title, 1)
            end
            title = "…" .. title
          end
          return prefix .. title
        end
        return inherited_formatter and inherited_formatter(buffer) or buffer.name
      end

      -- Preserve Catppuccin's provider and refresh palette colors on ColorScheme.
      local inherited = opts.highlights
      opts.highlights = function(defaults)
        local palette = require("catppuccin.palettes").get_palette()
        local theme = type(inherited) == "function" and inherited(defaults) or inherited or {}
        local highlights = vim.tbl_deep_extend("force", {}, defaults.highlights, theme)

        -- Keep inactive names readable, including buffers visible in other splits.
        for _, name in ipairs({ "background", "buffer", "buffer_visible", "duplicate", "duplicate_visible" }) do
          highlights[name].fg = palette.subtext1
        end

        -- Every part of the active buffer needs the same background, including
        -- diagnostic filename overrides. Tab-page highlights are independent.
        for name, highlight in pairs(highlights) do
          if name:match("_selected$") and not name:match("^tab_") then
            highlight.bg = "#b88a73" -- muted peach, softer than the palette accent
            if name ~= "separator_selected" then
              highlight.fg = palette.crust
              highlight.bold = false
              highlight.italic = false
            end
          end
        end
        return highlights
      end
    end,
  },
}

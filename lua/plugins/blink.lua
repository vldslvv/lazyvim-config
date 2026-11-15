return {

  {
    "saghen/blink.cmp",
    init = function()
      vim.api.nvim_create_autocmd("User", {
        pattern = "VeryLazy",
        once = true,
        callback = function()
          Snacks.toggle({
            name = "Completion Popup",
            get = function()
              return vim.g.blink_enable_auto_completion == true
            end,
            set = function(state)
              vim.g.blink_enable_auto_completion = state
              local cmp = package.loaded["blink.cmp"]
              if not state and cmp then
                cmp.cancel()
              end
            end,
          }):map("<leader>u.")
        end,
      })
    end,
    opts = function(_, opts)
      opts = opts or {}

      -- Disable completion itself so hidden suggestions cannot be accepted in prose files.
      local enabled = opts.enabled
      opts.enabled = function()
        if vim.bo.filetype == "text" or vim.bo.filetype == "markdown" then
          return false
        end
        if type(enabled) == "function" then
          return enabled()
        end
        return enabled ~= false
      end

      local prose_filetypes = {
        gitcommit = true,
        markdown = true,
        text = true,
      }

      local comment_node_types = {
        block_comment = true,
        comment = true,
        comment_content = true,
        line_comment = true,
      }

      local function is_prose_context()
        if prose_filetypes[vim.bo.filetype] then
          return true
        end

        local ok, node = pcall(vim.treesitter.get_node)
        while ok and node do
          if comment_node_types[node:type()] then
            return true
          end
          node = node:parent()
        end

        return false
      end

      opts.completion = opts.completion or {}
      opts.completion.menu = opts.completion.menu or {}
      -- Read the toggle on every request; Ctrl-Space can still open the menu manually.
      opts.completion.menu.auto_show = function()
        return vim.g.blink_enable_auto_completion == true and not is_prose_context()
      end

      -- Enter accepts completion only while the popup is visible.
      -- Cancel hidden suggestions before falling back to normal Enter behavior.
      opts.keymap = vim.tbl_extend("force", opts.keymap or {}, {
        ["<CR>"] = {
          function(cmp)
            if cmp.is_menu_visible() then
              return cmp.select_and_accept()
            end
            cmp.cancel()
          end,
          "fallback",
        },
        ["<C-c>"] = { "hide", "fallback" },
      })

      return opts
    end,
  },
}

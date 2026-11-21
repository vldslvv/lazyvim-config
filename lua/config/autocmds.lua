-- Loaded by LazyVim alongside its default autocmds.
require("config.autocmds.hover").setup()
require("config.autocmds.neogit").setup()

-- Reload externally changed files even while Neovim is unfocused.
vim.opt.autoread = true
vim.fn.timer_start(1000, function()
  local mode = vim.fn.mode()
  if mode == "n" then
    vim.cmd("checktime")
  elseif mode == "t" then
    -- Defer checks that could prompt about unsaved edits or missing files.
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      local buf = vim.api.nvim_win_get_buf(win)
      local options = vim.bo[buf]
      if options.buftype == "" and not options.modified and vim.fn.getbufvar(buf, "&autoread") == 1 then
        local name = vim.api.nvim_buf_get_name(buf)
        if vim.fn.filereadable(name) == 1 then
          vim.cmd.checktime(tostring(buf))
        end
      end
    end
  end
end, { ["repeat"] = -1 })

-- Keep terminal jobs available when a file replaces their window.
vim.api.nvim_create_autocmd("TermOpen", {
  group = vim.api.nvim_create_augroup("workspace_terminals", { clear = true }),
  callback = function(event)
    vim.bo[event.buf].buflisted = true
    vim.bo[event.buf].bufhidden = "hide"
  end,
})

-- Use four spaces for C/C++ (including headers) and Python.
local filetypes = vim.api.nvim_create_augroup("workspace_filetypes", { clear = true })
vim.api.nvim_create_autocmd("FileType", {
  group = filetypes,
  pattern = { "cpp", "c", "python" },
  callback = function(event)
    vim.bo[event.buf].shiftwidth = 4
    vim.bo[event.buf].tabstop = 4
    vim.bo[event.buf].expandtab = true
  end,
})

-- Enable formatting on save for Lua despite the global default.
vim.api.nvim_create_autocmd("FileType", {
  group = filetypes,
  pattern = "lua",
  callback = function(event)
    vim.b[event.buf].autoformat = true
  end,
})

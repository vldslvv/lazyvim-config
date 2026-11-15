local M = {}
local refresh_timer

function M.setup()
  if refresh_timer then
    vim.fn.timer_stop(refresh_timer)
  end
  -- External working-tree edits don't trigger Neogit's .git watcher.
  refresh_timer = vim.fn.timer_start(1000, function()
    if vim.fn.mode() ~= "n" or vim.fn.getcmdwintype() ~= "" then
      return
    end
    local status = package.loaded["neogit.buffers.status"]
    if status and status.is_open() then
      status.instance():dispatch_refresh(nil, "external_changes")
    end
  end, { ["repeat"] = -1 })

  vim.api.nvim_create_autocmd({ "FileType", "BufWinEnter" }, {
    group = vim.api.nvim_create_augroup("NeogitWrap", { clear = true }),
    callback = function(event)
      if vim.bo[event.buf].filetype ~= "NeogitStatus" then
        return
      end

      -- Neogit disables wrapping after FileType, so apply it once setup finishes.
      vim.schedule(function()
        if not vim.api.nvim_buf_is_valid(event.buf) or vim.bo[event.buf].filetype ~= "NeogitStatus" then
          return
        end
        for _, win in ipairs(vim.fn.win_findbuf(event.buf)) do
          vim.wo[win].wrap = true
          vim.wo[win].linebreak = true
        end
      end)
    end,
  })
end

return M

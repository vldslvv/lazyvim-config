return {
  {
    "linux-cultist/venv-selector.nvim",
    opts = {
      options = {
        statusline_func = {
          lualine = function()
            local venv = require("venv-selector").venv()
            if not venv or venv == "" then
              return ""
            end
            return "󰈺 " .. venv .. " "
          end,
        },
      },
    },
    config = function(_, opts)
      local selector = require("venv-selector")
      selector.setup(opts)

      -- Import the environment activated in the shell before starting Neovim.
      local env, env_type = vim.env.VIRTUAL_ENV, "venv"
      if not env or env == "" then
        env, env_type = vim.env.CONDA_PREFIX, "anaconda"
      end
      if not env or env == "" then
        return
      end

      local executable = "bin/python"
      if vim.fn.has("win32") == 1 then
        executable = env_type == "anaconda" and "python.exe" or "Scripts/python.exe"
      end
      local python = vim.fs.joinpath(env, executable)
      if vim.fn.executable(python) == 1 then
        selector.activate_from_path(python, env_type)
      end
    end,
  },
}

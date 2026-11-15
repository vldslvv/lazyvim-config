return {
  {
    "stevearc/conform.nvim",
    opts = {
      formatters_by_ft = {
        c = { "clang-format" },
        cpp = { "clang-format" },
        python = { "ruff_format" },
        -- cmake = { "cmake_format" },
      },
      formatters = {
        injected = { options = { ignore_errors = true } },
        -- clang-format reads the project's .clang-format (or _clang-format).
        -- ruff_format discovers project settings using the buffer's filename.
      },
    },
  },
}

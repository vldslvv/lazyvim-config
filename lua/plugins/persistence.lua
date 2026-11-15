return {
  {
    "folke/persistence.nvim",
    event = { "BufReadPre", "FileType neo-tree", "FileType NeogitStatus" },
    init = function()
      require("local_plugins.session_restore").setup()
    end,
  },
}

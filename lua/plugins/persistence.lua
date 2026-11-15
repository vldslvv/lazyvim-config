return {
  {
    "folke/persistence.nvim",
    init = function()
      require("local_plugins.session_restore").setup()
    end,
  },
}

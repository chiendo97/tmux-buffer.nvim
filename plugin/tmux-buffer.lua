vim.api.nvim_create_user_command("TmuxBuffer", function()
  require("tmux-buffer").pick()
end, {})

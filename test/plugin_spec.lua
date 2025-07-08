local describe = require("plenary.busted").describe
local it = require("plenary.busted").it
local before_each = require("plenary.busted").before_each
local after_each = require("plenary.busted").after_each

describe("plugin: tmux-buffer", function()
  before_each(function()
    -- Clear any existing commands before each test
    pcall(vim.api.nvim_del_user_command, "TmuxBuffer")
  end)

  after_each(function()
    -- Clean up after tests
    pcall(vim.api.nvim_del_user_command, "TmuxBuffer")
    package.loaded["tmux-buffer"] = nil
    package.loaded["tmux-buffer.init"] = nil
  end)

  it("registers the :TmuxBuffer command", function()
    -- Manually load the plugin
    vim.cmd("source plugin/tmux-buffer.lua")
    local commands = vim.api.nvim_get_commands({})
    assert.not_nil(commands.TmuxBuffer)
  end)

  it("command has correct attributes", function()
    vim.cmd("source plugin/tmux-buffer.lua")
    local commands = vim.api.nvim_get_commands({})
    local tmux_buffer_cmd = commands.TmuxBuffer

    assert.not_nil(tmux_buffer_cmd)
    assert.is_false(tmux_buffer_cmd.bang)
    assert.is_false(tmux_buffer_cmd.bar)
    assert.equals("0", tmux_buffer_cmd.nargs)
  end)

  it("command calls the correct module function", function()
    -- Mock the module to verify it's called
    local mock_pick = require("luassert.stub")()
    package.loaded["tmux-buffer"] = { pick = mock_pick }

    vim.cmd("source plugin/tmux-buffer.lua")
    vim.cmd("TmuxBuffer")

    assert.stub(mock_pick).was_called()
  end)

  it("handles missing module gracefully", function()
    -- Ensure module is not loaded
    package.loaded["tmux-buffer"] = nil
    package.loaded["tmux-buffer.init"] = nil

    vim.cmd("source plugin/tmux-buffer.lua")

    -- This should not error even if module can't be loaded initially
    assert.has_no.errors(function()
      local commands = vim.api.nvim_get_commands({})
      assert.not_nil(commands.TmuxBuffer)
    end)
  end)
end)

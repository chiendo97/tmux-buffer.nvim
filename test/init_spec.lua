local describe = require("plenary.busted").describe
local it = require("plenary.busted").it
local before_each = require("plenary.busted").before_each
local after_each = require("plenary.busted").after_each
local mock = require("luassert.mock")
local stub = require("luassert.stub")

describe("tmux-buffer.init", function()
  local tmux_buffer
  local original_vim_system
  local original_vim_notify
  local original_vim_ui_select
  local original_vim_fn_setreg

  before_each(function()
    -- Fresh require to avoid module caching issues
    package.loaded["tmux-buffer.init"] = nil
    tmux_buffer = require("tmux-buffer.init")

    -- Store originals for restoration
    original_vim_system = vim.system
    original_vim_notify = vim.notify
    original_vim_ui_select = vim.ui.select
    original_vim_fn_setreg = vim.fn.setreg
  end)

  after_each(function()
    -- Restore original functions
    vim.system = original_vim_system
    vim.notify = original_vim_notify
    vim.ui.select = original_vim_ui_select
    vim.fn.setreg = original_vim_fn_setreg

    -- Clean up module cache
    package.loaded["tmux-buffer.init"] = nil
  end)

  describe("pick function", function()
    it("should handle tmux command failure", function()
      local notify_spy = stub(vim, "notify")
      stub(vim, "system").returns({
        wait = function()
          return { code = 1, stdout = "", stderr = "tmux: no server running" }
        end,
      })

      tmux_buffer.pick()

      assert
        .stub(notify_spy)
        .was_called_with("Failed to run 'tmux list-buffers'. Is tmux running?", vim.log.levels.ERROR)
    end)

    it("should handle no tmux buffers found", function()
      local notify_spy = stub(vim, "notify")
      stub(vim, "system").returns({
        wait = function()
          return { code = 0, stdout = "", stderr = "" }
        end,
      })

      tmux_buffer.pick()

      assert.stub(notify_spy).was_called_with("No tmux buffers found.", vim.log.levels.INFO)
    end)

    it("should parse tmux buffer list correctly", function()
      local ui_select_spy = stub(vim.ui, "select")
      stub(vim, "system").returns({
        wait = function()
          return {
            code = 0,
            stdout = 'buffer0: 13 bytes: "Hello, World!"\nbuffer1: 25 bytes: "Another buffer content"\n',
            stderr = "",
          }
        end,
      })

      tmux_buffer.pick()

      assert.stub(ui_select_spy).was_called()
      local call_args = ui_select_spy.calls[1].refs[1]

      -- Check that choices were parsed correctly
      assert.equals(2, #call_args)
      assert.equals("buffer0", call_args[1].name)
      assert.equals("13 bytes", call_args[1].size)
      assert.equals("Hello, World!", call_args[1].content_preview)
      assert.equals("buffer1", call_args[2].name)
      assert.equals("25 bytes", call_args[2].size)
      assert.equals("Another buffer content", call_args[2].content_preview)
    end)

    it("should handle quoted content preview", function()
      local ui_select_spy = stub(vim.ui, "select")
      stub(vim, "system").returns({
        wait = function()
          return {
            code = 0,
            stdout = 'buffer0: 20 bytes: "Quoted content here"\n',
            stderr = "",
          }
        end,
      })

      tmux_buffer.pick()

      local call_args = ui_select_spy.calls[1].refs[1]
      assert.equals("Quoted content here", call_args[1].content_preview)
    end)

    it("should format items correctly with truncation", function()
      local ui_select_spy = stub(vim.ui, "select")
      local long_content = string.rep("a", 150)
      stub(vim, "system").returns({
        wait = function()
          return {
            code = 0,
            stdout = string.format('buffer0: 150 bytes: "%s"\n', long_content),
            stderr = "",
          }
        end,
      })

      tmux_buffer.pick()

      local call_args = ui_select_spy.calls[1].refs
      local format_item = call_args[2].format_item

      local formatted = format_item({
        name = "buffer0",
        size = "150 bytes",
        content_preview = long_content,
      })

      -- Should be truncated to 100 chars + "..."
      assert.truthy(string.find(formatted, "%.%.%.$"))
      assert.truthy(#formatted < #long_content + 50) -- Much shorter than original
    end)

    it("should format items correctly without truncation", function()
      local ui_select_spy = stub(vim.ui, "select")
      stub(vim, "system").returns({
        wait = function()
          return {
            code = 0,
            stdout = 'buffer0: 13 bytes: "Short content"\n',
            stderr = "",
          }
        end,
      })

      tmux_buffer.pick()

      local call_args = ui_select_spy.calls[1].refs
      local format_item = call_args[2].format_item

      local formatted = format_item({
        name = "buffer0",
        size = "13 bytes",
        content_preview = "Short content",
      })

      assert.equals("buffer0 (13 bytes): Short content", formatted)
    end)

    it("should copy selected buffer content to clipboard", function()
      local setreg_spy = stub(vim.fn, "setreg")
      local notify_spy = stub(vim, "notify")
      local ui_select_callback

      stub(vim.ui, "select").invokes(function(choices, opts, callback)
        ui_select_callback = callback
      end)

      stub(vim, "system").returns({
        wait = function()
          return {
            code = 0,
            stdout = 'buffer0: 20 bytes: "Hello\\nWorld\\nTest"\n',
            stderr = "",
          }
        end,
      })

      tmux_buffer.pick()

      -- Simulate user selection
      ui_select_callback({
        name = "buffer0",
        size = "20 bytes",
        content_preview = "Hello\\nWorld\\nTest",
      })

      assert.stub(setreg_spy).was_called_with("+", "Hello\nWorld\nTest")
      assert.stub(notify_spy).was_called_with("Copied content of buffer0 to clipboard.")
    end)

    it("should handle user cancellation", function()
      local setreg_spy = stub(vim.fn, "setreg")
      local notify_spy = stub(vim, "notify")
      local ui_select_callback

      stub(vim.ui, "select").invokes(function(choices, opts, callback)
        ui_select_callback = callback
      end)

      stub(vim, "system").returns({
        wait = function()
          return {
            code = 0,
            stdout = 'buffer0: 13 bytes: "Hello, World!"\n',
            stderr = "",
          }
        end,
      })

      tmux_buffer.pick()

      -- Simulate user cancellation (nil choice)
      ui_select_callback(nil)

      assert.stub(setreg_spy).was_not_called()
      -- Only the initial system call should have been made, no copy notification
      assert.equals(0, #notify_spy.calls)
    end)

    it("should handle malformed tmux output gracefully", function()
      local ui_select_spy = stub(vim.ui, "select")
      stub(vim, "system").returns({
        wait = function()
          return {
            code = 0,
            stdout = "invalid line format\nbuffer0: malformed\n",
            stderr = "",
          }
        end,
      })

      tmux_buffer.pick()

      -- Should still call ui.select but with empty choices
      assert.stub(ui_select_spy).was_called()
      local call_args = ui_select_spy.calls[1].refs[1]
      assert.equals(0, #call_args)
    end)

    it("should handle newline replacement correctly", function()
      local setreg_spy = stub(vim.fn, "setreg")
      local ui_select_callback

      stub(vim.ui, "select").invokes(function(choices, opts, callback)
        ui_select_callback = callback
      end)

      stub(vim, "system").returns({
        wait = function()
          return {
            code = 0,
            stdout = 'buffer0: 30 bytes: "Line 1\\nLine 2\\nLine 3"\n',
            stderr = "",
          }
        end,
      })

      tmux_buffer.pick()

      ui_select_callback({
        name = "buffer0",
        size = "30 bytes",
        content_preview = "Line 1\\nLine 2\\nLine 3",
      })

      assert.stub(setreg_spy).was_called_with("+", "Line 1\nLine 2\nLine 3")
    end)

    it("should handle buffers with special characters", function()
      local ui_select_spy = stub(vim.ui, "select")
      stub(vim, "system").returns({
        wait = function()
          return {
            code = 0,
            stdout = 'buffer0: 25 bytes: "Special chars: @#$%^&*()"\n',
            stderr = "",
          }
        end,
      })

      tmux_buffer.pick()

      local call_args = ui_select_spy.calls[1].refs[1]
      assert.equals("Special chars: @#$%^&*()", call_args[1].content_preview)
    end)
  end)
end)

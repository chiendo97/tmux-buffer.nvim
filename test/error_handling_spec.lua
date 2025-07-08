local describe = require("plenary.busted").describe
local it = require("plenary.busted").it
local before_each = require("plenary.busted").before_each
local after_each = require("plenary.busted").after_each
local stub = require("luassert.stub")

describe("tmux-buffer error handling", function()
  local tmux_buffer
  local original_vim_system
  local original_vim_notify
  local original_vim_ui_select
  local original_vim_fn_setreg

  before_each(function()
    package.loaded["tmux-buffer.init"] = nil
    tmux_buffer = require("tmux-buffer.init")

    -- Store originals
    original_vim_system = vim.system
    original_vim_notify = vim.notify
    original_vim_ui_select = vim.ui.select
    original_vim_fn_setreg = vim.fn.setreg
  end)

  after_each(function()
    -- Restore originals
    vim.system = original_vim_system
    vim.notify = original_vim_notify
    vim.ui.select = original_vim_ui_select
    vim.fn.setreg = original_vim_fn_setreg
    package.loaded["tmux-buffer.init"] = nil
  end)

  describe("robust error handling", function()
    it("should handle vim.system throwing an error", function()
      local notify_spy = stub(vim, "notify")
      stub(vim, "system").throws("System error")

      -- Should not crash when vim.system throws
      assert.has_no.errors(function()
        tmux_buffer.pick()
      end)
    end)

    it("should handle vim.ui.select being unavailable", function()
      stub(vim, "system").returns({
        wait = function()
          return {
            code = 0,
            stdout = 'buffer0: 13 bytes: "Hello, World!"\n',
            stderr = "",
          }
        end,
      })

      -- Remove vim.ui.select to simulate it being unavailable
      vim.ui.select = nil

      -- Should not crash when vim.ui.select is unavailable
      assert.has_no.errors(function()
        tmux_buffer.pick()
      end)
    end)

    it("should handle setreg failures gracefully", function()
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

      stub(vim.fn, "setreg").throws("Register error")
      local notify_spy = stub(vim, "notify")

      tmux_buffer.pick()

      -- Should not crash when setreg fails
      assert.has_no.errors(function()
        ui_select_callback({
          name = "buffer0",
          size = "13 bytes",
          content_preview = "Hello, World!",
        })
      end)
    end)

    it("should handle empty stdout from tmux command", function()
      local notify_spy = stub(vim, "notify")
      stub(vim, "system").returns({
        wait = function()
          return { code = 0, stdout = nil, stderr = "" }
        end,
      })

      assert.has_no.errors(function()
        tmux_buffer.pick()
      end)
    end)

    it("should handle stdout with only whitespace", function()
      local notify_spy = stub(vim, "notify")
      stub(vim, "system").returns({
        wait = function()
          return { code = 0, stdout = "   \n\t\n   ", stderr = "" }
        end,
      })

      tmux_buffer.pick()

      assert.stub(notify_spy).was_called_with("No tmux buffers found.", vim.log.levels.INFO)
    end)

    it("should handle buffers with empty content", function()
      local ui_select_spy = stub(vim.ui, "select")
      stub(vim, "system").returns({
        wait = function()
          return {
            code = 0,
            stdout = 'buffer0: 0 bytes: ""\n',
            stderr = "",
          }
        end,
      })

      tmux_buffer.pick()

      local call_args = ui_select_spy.calls[1].refs[1]
      assert.equals(1, #call_args)
      assert.equals("", call_args[1].content_preview)
    end)

    it("should handle very large buffer content", function()
      local ui_select_spy = stub(vim.ui, "select")
      local huge_content = string.rep("x", 10000)
      stub(vim, "system").returns({
        wait = function()
          return {
            code = 0,
            stdout = string.format('buffer0: 10000 bytes: "%s"\n', huge_content),
            stderr = "",
          }
        end,
      })

      assert.has_no.errors(function()
        tmux_buffer.pick()
      end)

      local call_args = ui_select_spy.calls[1].refs
      local format_item = call_args[2].format_item

      -- Should truncate properly
      local formatted = format_item({
        name = "buffer0",
        size = "10000 bytes",
        content_preview = huge_content,
      })

      assert.truthy(string.find(formatted, "%.%.%.$"))
    end)

    it("should handle partial regex match in buffer parsing", function()
      local ui_select_spy = stub(vim.ui, "select")
      stub(vim, "system").returns({
        wait = function()
          return {
            code = 0,
            stdout = 'buffer0: incomplete line\nbuffer1: 13 bytes: "Valid buffer"\n',
            stderr = "",
          }
        end,
      })

      tmux_buffer.pick()

      local call_args = ui_select_spy.calls[1].refs[1]
      -- Should only include the valid buffer
      assert.equals(1, #call_args)
      assert.equals("buffer1", call_args[1].name)
    end)
  end)

  describe("clipboard operations", function()
    it("should use the correct clipboard register", function()
      local setreg_spy = stub(vim.fn, "setreg")
      local ui_select_callback

      stub(vim.ui, "select").invokes(function(choices, opts, callback)
        ui_select_callback = callback
      end)

      stub(vim, "system").returns({
        wait = function()
          return {
            code = 0,
            stdout = 'buffer0: 5 bytes: "test"\n',
            stderr = "",
          }
        end,
      })

      tmux_buffer.pick()
      ui_select_callback({
        name = "buffer0",
        size = "5 bytes",
        content_preview = "test",
      })

      -- Should use the "+" register (system clipboard)
      assert.stub(setreg_spy).was_called_with("+", "test")
    end)

    it("should handle content with special escape sequences", function()
      local setreg_spy = stub(vim.fn, "setreg")
      local ui_select_callback

      stub(vim.ui, "select").invokes(function(choices, opts, callback)
        ui_select_callback = callback
      end)

      stub(vim, "system").returns({
        wait = function()
          return {
            code = 0,
            stdout = 'buffer0: 20 bytes: "tab\\there\\nline\\rcarriage"\n',
            stderr = "",
          }
        end,
      })

      tmux_buffer.pick()
      ui_select_callback({
        name = "buffer0",
        size = "20 bytes",
        content_preview = "tab\\there\\nline\\rcarriage",
      })

      -- Should convert \\n to actual newlines, but leave other escapes as-is
      assert.stub(setreg_spy).was_called_with("+", "tab\\there\nline\\rcarriage")
    end)
  end)
end)

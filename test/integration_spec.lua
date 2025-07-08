local describe = require("plenary.busted").describe
local it = require("plenary.busted").it
local before_each = require("plenary.busted").before_each
local after_each = require("plenary.busted").after_each

describe("tmux-buffer integration", function()
  local tmux_buffer

  before_each(function()
    -- Fresh require to avoid module caching issues
    package.loaded["tmux-buffer.init"] = nil
    tmux_buffer = require("tmux-buffer.init")
  end)

  after_each(function()
    -- Clean up module cache
    package.loaded["tmux-buffer.init"] = nil
  end)

  describe("module structure", function()
    it("should export the pick function", function()
      assert.is_function(tmux_buffer.pick)
    end)
  end)

  describe("tmux command construction", function()
    it("should call tmux with correct arguments", function()
      local system_spy = require("luassert.stub")(vim, "system")
      system_spy.returns({
        wait = function()
          return { code = 1, stdout = "", stderr = "" }
        end,
      })

      tmux_buffer.pick()

      assert.stub(system_spy).was_called_with({ "tmux", "list-buffers" }, { text = true })

      -- Restore original function
      vim.system = system_spy.original
    end)
  end)
end)

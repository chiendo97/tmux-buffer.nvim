-- Test helper utilities for tmux-buffer tests
local M = {}

-- Helper function to create mock tmux output
function M.create_tmux_output(buffers)
  local lines = {}
  for _, buffer in ipairs(buffers) do
    local line = string.format('%s: %s: "%s"', buffer.name, buffer.size, buffer.content)
    table.insert(lines, line)
  end
  return table.concat(lines, "\n") .. "\n"
end

-- Helper function to create a successful tmux system response
function M.create_success_response(stdout)
  return {
    wait = function()
      return {
        code = 0,
        stdout = stdout or "",
        stderr = "",
      }
    end,
  }
end

-- Helper function to create a failed tmux system response
function M.create_error_response(code, stderr)
  return {
    wait = function()
      return {
        code = code or 1,
        stdout = "",
        stderr = stderr or "tmux error",
      }
    end,
  }
end

-- Helper function to capture vim.ui.select calls
function M.capture_ui_select()
  local captured_calls = {}
  local original_select = vim.ui.select

  vim.ui.select = function(choices, opts, callback)
    table.insert(captured_calls, {
      choices = choices,
      opts = opts,
      callback = callback,
    })
  end

  return {
    calls = captured_calls,
    restore = function()
      vim.ui.select = original_select
    end,
  }
end

-- Sample buffer data for testing
M.sample_buffers = {
  {
    name = "buffer0",
    size = "13 bytes",
    content = "Hello, World!",
  },
  {
    name = "buffer1",
    size = "25 bytes",
    content = "Another buffer content",
  },
  {
    name = "buffer2",
    size = "30 bytes",
    content = "Buffer with\\nnewlines\\nhere",
  },
}

return M

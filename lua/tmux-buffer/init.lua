local M = {}

function M.pick()
  local list_buffers = vim.system({ "tmux", "list-buffers" }, { text = true }):wait()
  if list_buffers.code ~= 0 then
    vim.notify("Failed to run 'tmux list-buffers'. Is tmux running?", vim.log.levels.ERROR)
    return
  end

  local lines = vim.split(list_buffers.stdout, "\n", { trimempty = true })

  if #lines == 0 then
    vim.notify("No tmux buffers found.", vim.log.levels.INFO)
    return
  end

  local choices = {}
  for _, line in ipairs(lines) do
    local name, size, content_preview = string.match(line, "^(buffer%d+): (%d+ bytes): (.*)$")
    if name then
      -- unquote preview
      if content_preview:sub(1, 1) == '"' and content_preview:sub(-1) == '"' then
        content_preview = content_preview:sub(2, -2)
      end

      table.insert(choices, {
        name = name,
        size = size,
        content_preview = content_preview,
      })
    end
  end

  vim.ui.select(choices, {
    prompt = "Select a tmux buffer:",
    format_item = function(item)
      -- truncate long previews
      local preview = item.content_preview
      if #preview > 100 then
        preview = preview:sub(1, 100) .. "..."
      end
      return string.format("%s (%s): %s", item.name, item.size, preview)
    end,
  }, function(choice)
    if not choice then
      return
    end

    local content = choice.content_preview:gsub("\\n", "\n")

    vim.fn.setreg("+", content)
    vim.notify("Copied content of " .. choice.name .. " to clipboard.")
  end)
end

return M

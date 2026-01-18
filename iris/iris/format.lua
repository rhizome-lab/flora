-- Iris session formatting for LLM context
-- Usage: local format = require("iris.format")

local M = {}

-- Format a content block for display
local function format_content_block(block)
    if block.type == "text" then
        return block.text
    elseif block.type == "tool_use" then
        local input_str = ""
        if type(block.input) == "table" then
            local parts = {}
            for k, v in pairs(block.input) do
                if type(v) == "string" then
                    -- Truncate long values
                    local display = #v > 200 and v:sub(1, 200) .. "..." or v
                    table.insert(parts, k .. ": " .. display)
                else
                    table.insert(parts, k .. ": " .. tostring(v))
                end
            end
            input_str = table.concat(parts, ", ")
        end
        return string.format("[Tool: %s] %s", block.name, input_str)
    elseif block.type == "tool_result" then
        local content = block.content or ""
        -- Truncate long results
        if #content > 500 then
            content = content:sub(1, 500) .. "\n... [truncated]"
        end
        local status = block.is_error and " (error)" or ""
        return string.format("[Result%s]\n%s", status, content)
    elseif block.type == "thinking" then
        -- Include thinking but mark it
        local text = block.text or ""
        if #text > 300 then
            text = text:sub(1, 300) .. "..."
        end
        return string.format("[Thinking] %s", text)
    end
    return ""
end

-- Format a message for display
local function format_message(msg)
    local parts = {}
    table.insert(parts, string.format("## %s", msg.role:upper()))

    for _, block in ipairs(msg.content or {}) do
        local formatted = format_content_block(block)
        if formatted ~= "" then
            table.insert(parts, formatted)
        end
    end

    return table.concat(parts, "\n")
end

-- Format a turn for display
local function format_turn(turn, idx)
    local parts = {}
    table.insert(parts, string.format("--- Turn %d ---", idx))

    for _, msg in ipairs(turn.messages or {}) do
        table.insert(parts, format_message(msg))
    end

    if turn.token_usage then
        local usage = turn.token_usage
        table.insert(parts, string.format(
            "[Tokens: %d in, %d out]",
            usage.input or 0,
            usage.output or 0
        ))
    end

    return table.concat(parts, "\n\n")
end

-- Format a full session for LLM context
-- Options:
--   max_turns: limit number of turns (default: all)
--   include_thinking: include thinking blocks (default: false)
--   include_tokens: include token counts (default: true)
function M.session_for_llm(session, opts)
    opts = opts or {}
    local max_turns = opts.max_turns
    local include_tokens = opts.include_tokens ~= false

    local parts = {}

    -- Session metadata
    table.insert(parts, "# Session Overview")
    table.insert(parts, string.format("Format: %s", session.format or "unknown"))

    if session.metadata then
        local meta = session.metadata
        if meta.model then
            table.insert(parts, string.format("Model: %s", meta.model))
        end
        if meta.project then
            table.insert(parts, string.format("Project: %s", meta.project))
        end
        if meta.timestamp then
            table.insert(parts, string.format("Time: %s", meta.timestamp))
        end
    end

    if include_tokens and session.total_tokens then
        local tokens = session.total_tokens
        table.insert(parts, string.format(
            "Total tokens: %d input, %d output",
            tokens.input or 0,
            tokens.output or 0
        ))
    end

    table.insert(parts, string.format("Turns: %d", #(session.turns or {})))
    table.insert(parts, "")

    -- Turns
    table.insert(parts, "# Conversation")
    local turns = session.turns or {}
    local turn_count = max_turns and math.min(max_turns, #turns) or #turns

    for i = 1, turn_count do
        table.insert(parts, format_turn(turns[i], i))
    end

    if max_turns and #turns > max_turns then
        table.insert(parts, string.format("\n[... %d more turns omitted ...]", #turns - max_turns))
    end

    return table.concat(parts, "\n")
end

-- Create a brief summary of a session (for multi-session analysis)
function M.session_summary(session)
    local parts = {}

    -- Basic info
    local meta = session.metadata or {}
    table.insert(parts, string.format("Session: %s", meta.session_id or session.path or "unknown"))
    table.insert(parts, string.format("Format: %s, Model: %s", session.format or "?", meta.model or "?"))
    table.insert(parts, string.format("Turns: %d, Messages: %d", #(session.turns or {}), session.message_count or 0))

    -- Tool usage stats
    local tool_counts = {}
    for _, turn in ipairs(session.turns or {}) do
        for _, msg in ipairs(turn.messages or {}) do
            for _, block in ipairs(msg.content or {}) do
                if block.type == "tool_use" then
                    local name = block.name or "unknown"
                    tool_counts[name] = (tool_counts[name] or 0) + 1
                end
            end
        end
    end

    if next(tool_counts) then
        local tool_strs = {}
        for name, count in pairs(tool_counts) do
            table.insert(tool_strs, string.format("%s: %d", name, count))
        end
        table.insert(parts, "Tools: " .. table.concat(tool_strs, ", "))
    end

    -- First user message as context
    for _, turn in ipairs(session.turns or {}) do
        for _, msg in ipairs(turn.messages or {}) do
            if msg.role == "user" then
                for _, block in ipairs(msg.content or {}) do
                    if block.type == "text" and block.text then
                        local preview = block.text:sub(1, 200)
                        if #block.text > 200 then preview = preview .. "..." end
                        table.insert(parts, "Initial task: " .. preview)
                        return table.concat(parts, "\n")
                    end
                end
            end
        end
    end

    return table.concat(parts, "\n")
end

return M

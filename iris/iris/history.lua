-- Iris history/state tracking for temporal coherence
-- Usage: local history = require("iris.history")

local M = {}

-- Default history file path (relative to project root)
local HISTORY_FILE = ".iris/history.json"

-- Simple JSON encoding for history state
local function json_encode_string(s)
    return '"' .. s:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n'):gsub('\r', '\\r'):gsub('\t', '\\t') .. '"'
end

local function json_encode_array(arr)
    local parts = {}
    for _, v in ipairs(arr) do
        if type(v) == "string" then
            table.insert(parts, json_encode_string(v))
        elseif type(v) == "table" then
            table.insert(parts, json_encode_table(v))
        else
            table.insert(parts, tostring(v))
        end
    end
    return "[" .. table.concat(parts, ", ") .. "]"
end

local function json_encode_table(t)
    -- Check if it's an array
    if #t > 0 then
        return json_encode_array(t)
    end
    -- Object
    local parts = {}
    for k, v in pairs(t) do
        local key = json_encode_string(k)
        local val
        if type(v) == "string" then
            val = json_encode_string(v)
        elseif type(v) == "table" then
            val = json_encode_table(v)
        elseif type(v) == "number" then
            val = tostring(v)
        elseif type(v) == "boolean" then
            val = v and "true" or "false"
        else
            val = "null"
        end
        table.insert(parts, key .. ": " .. val)
    end
    return "{" .. table.concat(parts, ", ") .. "}"
end

-- Simple JSON parsing for history state
local function json_decode(str)
    -- Very basic JSON parser for our specific format
    local state = {}

    -- Extract topics_covered array
    local topics_str = str:match('"topics_covered"%s*:%s*%[(.-)%]')
    if topics_str then
        state.topics_covered = {}
        for topic in topics_str:gmatch('"([^"]*)"') do
            table.insert(state.topics_covered, topic)
        end
    else
        state.topics_covered = {}
    end

    -- Extract sessions_processed array
    local sessions_str = str:match('"sessions_processed"%s*:%s*%[(.-)%]')
    if sessions_str then
        state.sessions_processed = {}
        for session in sessions_str:gmatch('"([^"]*)"') do
            table.insert(state.sessions_processed, session)
        end
    else
        state.sessions_processed = {}
    end

    -- Extract last_run
    state.last_run = str:match('"last_run"%s*:%s*"([^"]*)"')

    -- Extract run_count
    local count = str:match('"run_count"%s*:%s*(%d+)')
    state.run_count = count and tonumber(count) or 0

    return state
end

-- Get the history file path for a project
function M.get_path(project_root)
    project_root = project_root or "."
    return project_root .. "/" .. HISTORY_FILE
end

-- Load history state from file
-- Returns: state table or empty state if file doesn't exist
function M.load(project_root)
    local path = M.get_path(project_root)
    local file = io.open(path, "r")
    if not file then
        return {
            topics_covered = {},
            sessions_processed = {},
            last_run = nil,
            run_count = 0,
        }
    end

    local content = file:read("*a")
    file:close()

    local ok, state = pcall(json_decode, content)
    if not ok or not state then
        return {
            topics_covered = {},
            sessions_processed = {},
            last_run = nil,
            run_count = 0,
        }
    end

    return state
end

-- Save history state to file
-- Returns: true on success, nil + error on failure
function M.save(state, project_root)
    local path = M.get_path(project_root)

    -- Ensure .iris directory exists
    local dir = path:match("(.+)/[^/]+$")
    if dir then
        os.execute("mkdir -p " .. dir)
    end

    local file, err = io.open(path, "w")
    if not file then
        return nil, err
    end

    -- Pretty-print JSON
    local json = "{\n"
    json = json .. '  "topics_covered": ' .. json_encode_array(state.topics_covered or {}) .. ",\n"
    json = json .. '  "sessions_processed": ' .. json_encode_array(state.sessions_processed or {}) .. ",\n"
    json = json .. '  "last_run": ' .. (state.last_run and json_encode_string(state.last_run) or "null") .. ",\n"
    json = json .. '  "run_count": ' .. (state.run_count or 0) .. "\n"
    json = json .. "}\n"

    file:write(json)
    file:close()

    return true
end

-- Add topics to history (deduplicates)
function M.add_topics(state, topics)
    local existing = {}
    for _, t in ipairs(state.topics_covered or {}) do
        existing[t:lower()] = true
    end

    for _, topic in ipairs(topics) do
        local key = topic:lower()
        if not existing[key] then
            table.insert(state.topics_covered, topic)
            existing[key] = true
        end
    end
end

-- Mark a session as processed
function M.mark_session(state, session_id)
    local existing = {}
    for _, s in ipairs(state.sessions_processed or {}) do
        existing[s] = true
    end

    if not existing[session_id] then
        table.insert(state.sessions_processed, session_id)
    end
end

-- Check if a session has been processed
function M.is_processed(state, session_id)
    for _, s in ipairs(state.sessions_processed or {}) do
        if s == session_id then
            return true
        end
    end
    return false
end

-- Update last run timestamp
function M.touch(state)
    state.last_run = os.date("!%Y-%m-%dT%H:%M:%SZ")
    state.run_count = (state.run_count or 0) + 1
end

-- Format history for inclusion in LLM prompt
function M.format_for_prompt(state)
    if not state.topics_covered or #state.topics_covered == 0 then
        return nil  -- No history to include
    end

    local parts = {}
    table.insert(parts, "## Previous Writing History\n")
    table.insert(parts, "You've previously written about these topics:")

    for _, topic in ipairs(state.topics_covered) do
        table.insert(parts, "- " .. topic)
    end

    table.insert(parts, "\nFocus on what's NEW or DIFFERENT. Don't repeat insights you've already shared.")
    table.insert(parts, "If you notice connections to previous topics, you can reference them briefly")
    table.insert(parts, '(e.g., "Building on what I said about X...").\n')

    return table.concat(parts, "\n")
end

-- Extract topics from LLM output using simple heuristics
-- Returns array of topic strings
function M.extract_topics(text)
    local topics = {}
    local seen = {}

    -- Look for markdown headers as topics
    for header in text:gmatch("\n##?#?%s+([^\n]+)") do
        local topic = header:gsub("^%s+", ""):gsub("%s+$", "")
        if #topic > 3 and #topic < 100 and not seen[topic:lower()] then
            table.insert(topics, topic)
            seen[topic:lower()] = true
        end
    end

    -- Look for "I learned about X" patterns
    for topic in text:gmatch("[Ii] learned about ([^%.,:]+)") do
        topic = topic:gsub("^%s+", ""):gsub("%s+$", "")
        if #topic > 3 and #topic < 50 and not seen[topic:lower()] then
            table.insert(topics, topic)
            seen[topic:lower()] = true
        end
    end

    -- Look for "working on X" patterns
    for topic in text:gmatch("working on ([^%.,:]+)") do
        topic = topic:gsub("^%s+", ""):gsub("%s+$", "")
        if #topic > 3 and #topic < 50 and not seen[topic:lower()] then
            table.insert(topics, topic)
            seen[topic:lower()] = true
        end
    end

    return topics
end

return M

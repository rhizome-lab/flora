-- Iris: Agent-authored insights from coding sessions
-- Usage: spore run . -- <session-path>
--        spore run . -- --list
--        spore run . -- --recent [N]

-- Capabilities are injected by spore based on config
-- caps.sessions.project - session parsing
-- caps.llm.default - LLM completion

local prompts = require("iris.prompts")
local format = require("iris.format")
local history = require("iris.history")

-- Get sessions capability (injected by spore)
local function get_sessions()
    if caps and caps.sessions and caps.sessions.project then
        return caps.sessions.project
    end
    error("sessions capability not configured - add [caps.sessions] to .spore/config.toml")
end

-- Get LLM capability (injected by spore)
local function get_llm()
    if caps and caps.llm and caps.llm.default then
        return caps.llm.default
    end
    error("llm capability not configured - add [caps.llm] to .spore/config.toml")
end

local M = {}

-- Re-export submodules
M.prompts = prompts
M.format = format
M.history = history

-- Generate insight from a single session
-- Options:
--   voice: voice profile name (default, technical, reflective)
--   track_progress: boolean - enable history tracking for deduplication
--   project_root: string - root for .iris/history.json (default: cwd)
function M.analyze_session(session_path, opts)
    opts = opts or {}
    local voice = opts.voice or "default"
    local track = opts.track_progress
    local project_root = opts.project_root
    local sessions_cap = get_sessions()
    local llm_cap = get_llm()

    -- Load history if tracking enabled
    local state = track and history.load(project_root) or nil

    -- Parse session
    local session, err = sessions_cap:parse(session_path)
    if not session then
        return nil, "Failed to parse session: " .. (err or "unknown error")
    end

    -- Get session ID for tracking
    local session_id = session.metadata and session.metadata.session_id
        or session_path:match("([^/]+)%.jsonl?$")
        or session_path

    -- Skip if already processed (when tracking)
    if state and history.is_processed(state, session_id) then
        print("[iris] Session already processed: " .. session_id)
        return nil, "session already processed"
    end

    -- Format session for LLM
    local context = format.session_for_llm(session, {
        max_turns = 50,  -- Limit context size
        include_thinking = false,
    })

    -- Add history context if tracking
    if state then
        local history_context = history.format_for_prompt(state)
        if history_context then
            context = history_context .. "\n---\n\n" .. context
        end
    end

    -- Build prompt
    local system = prompts.system_prompt(prompts.SINGLE_SESSION, voice)

    -- Generate insight
    print("[iris] Analyzing session...")
    local response = llm_cap:complete(system, context)

    -- Update history if tracking
    if state then
        local topics = history.extract_topics(response)
        history.add_topics(state, topics)
        history.mark_session(state, session_id)
        history.touch(state)
        history.save(state, project_root)
        print("[iris] Updated history: " .. #topics .. " topics extracted")
    end

    return {
        insight = response,
        session = {
            path = session_path,
            format = session.format,
            turns = #(session.turns or {}),
            messages = session.message_count,
        },
        topics_extracted = state and history.extract_topics(response) or nil,
    }
end

-- Analyze multiple sessions for patterns
-- Options:
--   voice: voice profile name
--   track_progress: boolean - enable history tracking
--   project_root: string - root for .iris/history.json
function M.analyze_sessions(session_paths, opts)
    opts = opts or {}
    local voice = opts.voice or "default"
    local track = opts.track_progress
    local project_root = opts.project_root
    local sessions_cap = get_sessions()
    local llm_cap = get_llm()

    -- Load history if tracking enabled
    local state = track and history.load(project_root) or nil

    -- Parse and summarize each session (skip already processed if tracking)
    local summaries = {}
    local processed_ids = {}
    for _, path in ipairs(session_paths) do
        local session = sessions_cap:parse(path)
        if session then
            local session_id = session.metadata and session.metadata.session_id
                or path:match("([^/]+)%.jsonl?$")
                or path

            if state and history.is_processed(state, session_id) then
                print("[iris] Skipping already processed: " .. session_id)
            else
                table.insert(summaries, format.session_summary(session))
                table.insert(processed_ids, session_id)
            end
        else
            print("[iris] Warning: Failed to parse " .. path)
        end
    end

    if #summaries == 0 then
        return nil, "No new sessions to analyze"
    end

    -- Build context
    local context = ""

    -- Add history context if tracking
    if state then
        local history_context = history.format_for_prompt(state)
        if history_context then
            context = history_context .. "\n---\n\n"
        end
    end

    context = context .. "# Sessions to Analyze\n\n"
    for i, summary in ipairs(summaries) do
        context = context .. string.format("## Session %d\n%s\n\n", i, summary)
    end

    -- Build prompt
    local system = prompts.system_prompt(prompts.MULTI_SESSION, voice)

    -- Generate insight
    print(string.format("[iris] Analyzing %d sessions...", #summaries))
    local response = llm_cap:complete(system, context)

    -- Update history if tracking
    if state then
        local topics = history.extract_topics(response)
        history.add_topics(state, topics)
        for _, sid in ipairs(processed_ids) do
            history.mark_session(state, sid)
        end
        history.touch(state)
        history.save(state, project_root)
        print("[iris] Updated history: " .. #topics .. " topics extracted")
    end

    return {
        insight = response,
        session_count = #summaries,
        topics_extracted = state and history.extract_topics(response) or nil,
    }
end

-- List available sessions
function M.list_sessions(project_path, format_filter)
    local sessions_cap = get_sessions()
    return sessions_cap:list(project_path, format_filter)
end

-- Get available formats
function M.formats()
    local sessions_cap = get_sessions()
    return sessions_cap:formats()
end

-- CLI help
local function show_help()
    print([[
Iris: Agent-authored insights from coding sessions

Usage:
  iris <session-path>           Analyze a single session
  iris --list [project]         List available sessions
  iris --recent [N]             Analyze N most recent sessions (default: 1)
  iris --multi <path> [path...] Analyze multiple sessions for patterns

Options:
  --voice <name>      Voice profile: default, technical, reflective
  --format <name>     Filter by session format (claude-code, gemini-cli, etc.)
  --output <file>     Write output to file instead of stdout
  -h, --help          Show this help

Temporal Coherence:
  --track-progress    Track topics to avoid repetition (.iris/history.json)
  --show-history      Show what topics have been covered
  --clear-history     Clear the history state

Examples:
  iris --recent 5 --voice technical
  iris --recent 10 --track-progress    # Track what's been written
  iris --multi session1.jsonl session2.jsonl
]])
end

-- Parse CLI arguments
local function parse_args(argv)
    local opts = {
        paths = {},
        voice = "default",
    }

    local i = 1
    while i <= #argv do
        local arg = argv[i]

        if arg == "-h" or arg == "--help" then
            opts.help = true
        elseif arg == "--list" then
            opts.list = true
            if argv[i + 1] and not argv[i + 1]:match("^%-") then
                i = i + 1
                opts.project = argv[i]
            end
        elseif arg == "--recent" then
            opts.recent = true
            if argv[i + 1] and argv[i + 1]:match("^%d+$") then
                i = i + 1
                opts.recent_count = tonumber(argv[i])
            else
                opts.recent_count = 1
            end
        elseif arg == "--multi" then
            opts.multi = true
        elseif arg == "--voice" then
            i = i + 1
            opts.voice = argv[i]
        elseif arg == "--format" then
            i = i + 1
            opts.format_filter = argv[i]
        elseif arg == "--output" or arg == "-o" then
            i = i + 1
            opts.output = argv[i]
        -- Temporal coherence options
        elseif arg == "--track-progress" then
            opts.track_progress = true
        elseif arg == "--show-history" then
            opts.show_history = true
        elseif arg == "--clear-history" then
            opts.clear_history = true
        elseif not arg:match("^%-") then
            table.insert(opts.paths, arg)
        end

        i = i + 1
    end

    return opts
end

-- Main entry point
-- CLI entry point (spore.args is set when run via `spore run . -- arg1 arg2`)
local cli_args = spore and spore.args
if cli_args then
    local opts = parse_args(cli_args)

    if opts.help then
        show_help()
        os.exit(0)
    end

    -- Show history
    if opts.show_history then
        local state = history.load()
        print("Iris History State:")
        print("  Topics covered: " .. #(state.topics_covered or {}))
        for _, topic in ipairs(state.topics_covered or {}) do
            print("    - " .. topic)
        end
        print("  Sessions processed: " .. #(state.sessions_processed or {}))
        print("  Run count: " .. (state.run_count or 0))
        if state.last_run then
            print("  Last run: " .. state.last_run)
        end
        os.exit(0)
    end

    -- Clear history
    if opts.clear_history then
        local state = {
            topics_covered = {},
            sessions_processed = {},
            last_run = nil,
            run_count = 0,
        }
        history.save(state)
        print("[iris] History cleared")
        os.exit(0)
    end

    -- List sessions
    if opts.list then
        local sessions_cap = get_sessions()
        local available = sessions_cap:list(opts.project, opts.format_filter)
        if #available == 0 then
            print("No sessions found.")
            if opts.project then
                print("Searched in: " .. opts.project)
            end
            print("\nAvailable formats: " .. table.concat(sessions_cap:formats(), ", "))
        else
            print(string.format("Found %d sessions:\n", #available))
            for _, info in ipairs(available) do
                print(string.format("  [%s] %s", info.format, info.path))
            end
        end
        os.exit(0)
    end

    -- Recent sessions
    if opts.recent then
        local sessions_cap = get_sessions()
        local available = sessions_cap:list(opts.project, opts.format_filter)
        if #available == 0 then
            print("No sessions found.")
            os.exit(1)
        end

        -- Sort by mtime (most recent first) - already sorted by spore-sessions
        local count = math.min(opts.recent_count, #available)
        local paths = {}
        for i = 1, count do
            table.insert(paths, available[i].path)
        end

        local result, err
        if count == 1 then
            result, err = M.analyze_session(paths[1], opts)
        else
            result, err = M.analyze_sessions(paths, opts)
        end

        if not result then
            print("Error: " .. (err or "unknown"))
            os.exit(1)
        end

        local output = result.insight
        if opts.output then
            local f = io.open(opts.output, "w")
            if f then
                f:write(output)
                f:close()
                print("[iris] Written to " .. opts.output)
            else
                print("Error: Could not write to " .. opts.output)
                os.exit(1)
            end
        else
            print("\n" .. output)
        end
        os.exit(0)
    end

    -- Multi-session analysis
    if opts.multi then
        if #opts.paths < 2 then
            print("Error: --multi requires at least 2 session paths")
            os.exit(1)
        end

        local result, err = M.analyze_sessions(opts.paths, opts)
        if not result then
            print("Error: " .. (err or "unknown"))
            os.exit(1)
        end

        local output = result.insight
        if opts.output then
            local f = io.open(opts.output, "w")
            if f then
                f:write(output)
                f:close()
                print("[iris] Written to " .. opts.output)
            else
                print("Error: Could not write to " .. opts.output)
                os.exit(1)
            end
        else
            print("\n" .. output)
        end
        os.exit(0)
    end

    -- Single session analysis
    if #opts.paths == 1 then
        local result, err = M.analyze_session(opts.paths[1], opts)
        if not result then
            print("Error: " .. (err or "unknown"))
            os.exit(1)
        end

        local output = result.insight
        if opts.output then
            local f = io.open(opts.output, "w")
            if f then
                f:write(output)
                f:close()
                print("[iris] Written to " .. opts.output)
            else
                print("Error: Could not write to " .. opts.output)
                os.exit(1)
            end
        else
            print("\n" .. output)
        end
        os.exit(0)
    end

    -- No valid action
    show_help()
    os.exit(1)
else
    return M
end

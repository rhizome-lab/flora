-- Iris: Agent-authored insights from coding sessions
-- Usage: spore run . -- <session-path>
--        spore run . -- --list
--        spore run . -- --recent [N]

-- Capabilities are injected by spore based on config
-- caps.sessions.project - session parsing
-- caps.llm.default - LLM completion

local prompts = require("iris.prompts")
local format = require("iris.format")

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

-- Generate insight from a single session
-- Options:
--   voice: voice profile name (default, technical, reflective)
function M.analyze_session(session_path, opts)
    opts = opts or {}
    local voice = opts.voice or "default"
    local sessions_cap = get_sessions()
    local llm_cap = get_llm()

    -- Parse session
    local session, err = sessions_cap:parse(session_path)
    if not session then
        return nil, "Failed to parse session: " .. (err or "unknown error")
    end

    -- Format session for LLM
    local context = format.session_for_llm(session, {
        max_turns = 50,  -- Limit context size
        include_thinking = false,
    })

    -- Build prompt
    local system = prompts.system_prompt(prompts.SINGLE_SESSION, voice)

    -- Generate insight
    print("[iris] Analyzing session...")
    local response = llm_cap:complete(system, context)

    return {
        insight = response,
        session = {
            path = session_path,
            format = session.format,
            turns = #(session.turns or {}),
            messages = session.message_count,
        }
    }
end

-- Analyze multiple sessions for patterns
function M.analyze_sessions(session_paths, opts)
    opts = opts or {}
    local voice = opts.voice or "default"
    local sessions_cap = get_sessions()
    local llm_cap = get_llm()

    -- Parse and summarize each session
    local summaries = {}
    for _, path in ipairs(session_paths) do
        local session = sessions_cap:parse(path)
        if session then
            table.insert(summaries, format.session_summary(session))
        else
            print("[iris] Warning: Failed to parse " .. path)
        end
    end

    if #summaries == 0 then
        return nil, "No valid sessions to analyze"
    end

    -- Build context
    local context = "# Sessions to Analyze\n\n"
    for i, summary in ipairs(summaries) do
        context = context .. string.format("## Session %d\n%s\n\n", i, summary)
    end

    -- Build prompt
    local system = prompts.system_prompt(prompts.MULTI_SESSION, voice)

    -- Generate insight
    print(string.format("[iris] Analyzing %d sessions...", #summaries))
    local response = llm_cap:complete(system, context)

    return {
        insight = response,
        session_count = #summaries,
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
  --provider <name>   LLM provider
  --model <name>      Model name
  --format <name>     Filter by session format (claude-code, gemini-cli, etc.)
  --output <file>     Write output to file instead of stdout
  -h, --help          Show this help

Examples:
  iris ~/.claude/projects/myproject/sessions/abc123.jsonl
  iris --list ~/git/myproject
  iris --recent 5 --voice technical
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
        elseif arg == "--provider" then
            i = i + 1
            opts.provider = argv[i]
        elseif arg == "--model" then
            i = i + 1
            opts.model = argv[i]
        elseif arg == "--format" then
            i = i + 1
            opts.format_filter = argv[i]
        elseif arg == "--output" or arg == "-o" then
            i = i + 1
            opts.output = argv[i]
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

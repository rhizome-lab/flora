-- Iris: Agent-authored insights from coding sessions
-- Usage: spore run . <session-path>
--        spore run . --list
--        spore run . --recent [N]

local sessions = require("spore.sessions")
local prompts = require("iris.prompts")
local format = require("iris.format")

local M = {}

-- Re-export submodules
M.prompts = prompts
M.format = format

-- Generate insight from a single session
-- Options:
--   voice: voice profile name (default, technical, reflective)
--   provider: LLM provider (default: from config)
--   model: model name (default: from config)
function M.analyze_session(session_path, opts)
    opts = opts or {}
    local voice = opts.voice or "default"
    local provider = opts.provider
    local model = opts.model

    -- Parse session
    local session, err = sessions.parse(session_path)
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
    local response = llm.chat(provider, model, system, context)

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
    local provider = opts.provider
    local model = opts.model

    -- Parse and summarize each session
    local summaries = {}
    for _, path in ipairs(session_paths) do
        local session = sessions.parse(path)
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
    local response = llm.chat(provider, model, system, context)

    return {
        insight = response,
        session_count = #summaries,
    }
end

-- List available sessions
function M.list_sessions(project_path, format_filter)
    return sessions.list(project_path, format_filter)
end

-- Get available formats
function M.formats()
    return sessions.formats()
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
if args and #args >= 0 then
    local opts = parse_args(args)

    if opts.help then
        show_help()
        os.exit(0)
    end

    -- List sessions
    if opts.list then
        local available = sessions.list(opts.project, opts.format_filter)
        if #available == 0 then
            print("No sessions found.")
            if opts.project then
                print("Searched in: " .. opts.project)
            end
            print("\nAvailable formats: " .. table.concat(sessions.formats(), ", "))
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
        local available = sessions.list(opts.project, opts.format_filter)
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

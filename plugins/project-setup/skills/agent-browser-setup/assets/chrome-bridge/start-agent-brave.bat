@echo off
rem Starts a separate Brave instance for the Claude agent, with its own user
rem data dir. Remote debugging is per instance, so turning it on here exposes
rem only this browser - not your everyday Brave session.
rem See README.md next to this script (One-time setup on Windows).
rem
rem Run it on Windows (double-click, or a shortcut to it). Extra arguments are
rem passed to Brave, e.g. a URL to open.
setlocal

rem Where the agent's profile lives. Delete the folder to start from scratch.
if not defined AGENT_BRAVE_DIR set "AGENT_BRAVE_DIR=%LOCALAPPDATA%\BraveAgent"
rem Debugging port. Must match CHROME_DEBUG_PORT for the MCP server in the
rem dev container (.mcp.json).
if not defined AGENT_BRAVE_PORT set "AGENT_BRAVE_PORT=9333"

rem 1. Find brave.exe - installed per machine or per user. Set BRAVE to
rem    override.
set "BRAVE_REL=BraveSoftware\Brave-Browser\Application\brave.exe"
if not defined BRAVE if exist "%ProgramFiles%\%BRAVE_REL%" set "BRAVE=%ProgramFiles%\%BRAVE_REL%"
if not defined BRAVE if exist "%ProgramFiles(x86)%\%BRAVE_REL%" set "BRAVE=%ProgramFiles(x86)%\%BRAVE_REL%"
if not defined BRAVE if exist "%LOCALAPPDATA%\%BRAVE_REL%" set "BRAVE=%LOCALAPPDATA%\%BRAVE_REL%"
if not defined BRAVE (
  echo brave.exe not found. Set BRAVE to its full path and run again.
  pause
  exit /b 1
)

rem 2. A new profile has no "Local State" yet. Open the page where remote
rem    debugging is turned on, since that is the one manual step.
set "START_URL="
if not exist "%AGENT_BRAVE_DIR%\Local State" set "START_URL=brave://inspect/#remote-debugging"

rem 3. Pin the debugging port. Brave starts its server on the port in the first
rem    line of DevToolsActivePort and only falls back to 9222 (then a random
rem    port) when the file is missing or the port is busy. Writing the file
rem    first keeps the port fixed, so the container config never has to change.
if not exist "%AGENT_BRAVE_DIR%" mkdir "%AGENT_BRAVE_DIR%"
> "%AGENT_BRAVE_DIR%\DevToolsActivePort" echo %AGENT_BRAVE_PORT%

rem 4. Launch. If this instance is already running, Brave just opens a new
rem    window in it.
start "" "%BRAVE%" --user-data-dir="%AGENT_BRAVE_DIR%" --no-first-run --no-default-browser-check %START_URL% %*

if defined START_URL (
  echo Agent Brave started for the first time:
  echo   profile: %AGENT_BRAVE_DIR%
  echo   port:    %AGENT_BRAVE_PORT%
  echo.
  echo On the brave://inspect page that opened, turn on remote debugging.
  echo It should say "Server running at: 127.0.0.1:%AGENT_BRAVE_PORT%".
  echo Then log in to whatever the agent needs, in this window only.
  pause
)

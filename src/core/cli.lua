---- -*- Mode: Lua; -*-
----
---- cli.lua
----
---- © Copyright IBM Corporation 2016, 2017.
---- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
---- AUTHOR: Jamie A. Jennings

-- This code is fed to the lua interpreter by a shell script.  The script supplies the first two
-- args (ROSIE_HOME and ROSIE_DEV) before the user-supplied Rosie CLI args.  ROSIE_HOME is the
-- full path to a Rosie install directory, and ROSIE_DEV is the string "true" if the CLI was
-- launched in "development mode", which drops into a Lua repl after loading Rosie:
--     "-D" is an 'undocumented' command line switch which, when it appears as the first command
--     line argument to the Rosie run script, will launch Rosie in development mode.  The code
--     below does not need to process that switch.

ROSIE_HOME = arg[1]
ROSIE_DEV = (arg[2]=="true")

if not ROSIE_HOME then
	io.stderr:write("Installation error: Lua variable ROSIE_HOME is not defined\n")
	os.exit(-2)
end

-- Reconstruct the command line using all the arg information available.  For readability, we
-- replace instances of ROSIE_HOME with the string "ROSIE_HOME" at the start of each arg.
local s=0; while arg[s] do s=s-1; end; s=s+1	                     -- Find first arg
local function munge_arg(a)                                          -- Replace
   local s, e = a:find(ROSIE_HOME, 1, true)
   if s then return "ROSIE_HOME" .. a:sub(e+1); else return a; end
end
local str=""; for i=s,#arg do str=str..munge_arg(arg[i]).." "; end   -- Assemble string
ROSIE_COMMAND = str:sub(1,-1)                                        -- Remove trailing space

-- Shift args by 2, to remove ROSIE_HOME and ROSIE_DEV
table.move(arg, 3, #arg, 1); arg[#arg-1]=nil; arg[#arg]=nil;

-- Start the Rosie Pattern Engine
loader, msg = loadfile(ROSIE_HOME .. "/lib/submodule.luac", "b")
if not loader then
   loader, msg = loadfile(ROSIE_HOME .. "/submodules/lua-modules/submodule.lua", "t")
   if not loader then error("Error loading module system: " .. msg); end
end
mod = loader(); package.loaded.submodule = mod;
rosie_mod = mod.new("rosie", ROSIE_HOME, 
		    "lib",						       -- .luac
		    "src/core;src;submodules/lua-modules;submodules/argparse/src", -- .lua
		    "lib")						       -- .so
mod.import("submodule", rosie_mod)
rosie = mod.import("init", rosie_mod)
package.loaded.rosie = rosie

assert(type(rosie_mod)=="table", "Return value from init was not the rosie module (a table)")

ROSIE_VERSION = rosie_mod.env.ROSIE_VERSION
ROSIE_INFO = rosie_mod.env.ROSIE_INFO

function open_modules()
   engine_module = assert(rosie_mod.env.engine_module, "failed to load engine_module")
   engine = assert(engine_module.engine, "engine not defined")
   argparse = assert(rosie_mod.env.argparse, "failed to load argparse")
   common = assert(rosie_mod.env.common)
   json = assert(rosie_mod.env.cjson)
   list = assert(rosie_mod.env.list)
   environment = assert(rosie_mod.env.environment)
   lpeg = assert(rosie_mod.env.lpeg)
   ui = assert(rosie_mod.env.ui)
end

ok, msg = pcall(open_modules)
if not ok then print("Error in cli when opening modules: " .. msg); end

function create_cl_engine()
   CL_ENGINE = rosie.engine.new("command line engine")
   if (not CL_ENGINE) then error("Internal error: could not obtain new engine: " .. msg); end
end

ok, msg = pcall(create_cl_engine)
if not ok then print("Error in cli when creating cli engine: " .. msg); end

local function print_rosie_info()
   local function printf(fmt, ...)
      print(string.format(fmt, ...))
   end
   local fmt = "%20s = %s"
   for _,info in ipairs(ROSIE_INFO) do printf(fmt, info.name, info.value); end
   local log = io.open(ROSIE_HOME .. "/build.log", "r")
   if log then
      print()
      local line = log:read("l")
      while line do
	 local name, val = line:match('([^ ]+) (.*)')
	 printf(fmt, name, val)
	 line = log:read("l")
      end
   end
end

local function greeting()
   io.write("Rosie " .. ROSIE_VERSION .. "\n")
end

local function set_encoder(name)
   local encode_fcn = rosie.encoders[name]
   if encode_fcn==nil then
      local msg = "invalid output encoder: " .. tostring(name)
      if ROSIE_DEV then error(msg)
      else io.write(msg, "\n"); os.exit(-1); end
   end
   CL_ENGINE:output(encode_fcn)
end

local function load_string(en, input)
   local ok, results, messages = pcall(en.load, en, input)
   if not ok then
      if ROSIE_DEV then error(results)		    -- error(messages:concat("\n"));
      else io.write("Cannot load rpl: \n", results); os.exit(-1); end
   end
   return results, messages
end

local function setup_engine(args)
   -- (1a) Load the manifest
   if args.manifest then
      if args.verbose then
	 io.stdout:write("Compiling files listed in manifest ", args.manifest, "\n")
      end
      local success, messages = pcall(rosie.file.load, CL_ENGINE, args.manifest, "manifest")
      if not success then
	 io.stdout:write(table.concat(messages, "\n"), "\n")
	 os.exit(-4)
      else
	 if args.verbose then
	    for _, msg in ipairs(messages) do io.stdout:write(msg, "\n"); end
	 end
      end
   end -- load manifest

   -- (1b) Load an rpl file
   if args.rpls then
      for _,file in pairs(args.rpls) do
	 if args.verbose then
	    io.stdout:write("Compiling additional file ", file, "\n")
	 end
	 local success, msg = pcall(rosie.file.load, CL_ENGINE, file, "rpl")
	 if not success then
	    io.stdout:write(msg, "\n")
	    os.exit(-4)
	 end
      end
   end

   -- (1c) Load an rpl string from the command line
   if args.statements then
      for _,stm in pairs(args.statements) do
	 if args.verbose then
	    io.stdout:write(string.format("Compiling additional rpl code %q\n", stm))
	 end
	 local success, msg = load_string(CL_ENGINE, stm)
	 if not success then
	    io.stdout:write(msg, "\n")
	    os.exit(-4)
	 end
      end
   end

   -- (2) Compile the expression
   if args.pattern then
      local expression
      if args.fixed_strings then
	 expression = '"' .. args.pattern:gsub('"', '\\"') .. '"' -- TODO: rosie.expr.literal(arg[2])
      else
	 expression = args.pattern
      end
      local flavor = (args.command=="grep") and "search" or "match"
      local ok, msgs
      ok, compiled_pattern, msgs = pcall(CL_ENGINE.compile, CL_ENGINE, expression, flavor)
      if not ok then
	 io.stdout:write(compiled_pattern, "\n")
	 os.exit(-4)
      elseif not compiled_pattern then
	 io.stdout:write(table.concat(msgs, '\n'), '\n')
	 os.exit(-4)
      end
   end
end

local function readable_file(fn)
   local f, msg = io.open(fn, "r")
   if not f then
      assert (type(msg)=="string")
      if msg:find("No such file") then return nil, "No such file"
      elseif msg:find("Permission denied") then return nil, "Permission denied"
      else return nil, "Cannot open file"; end
   end
   -- now we have a file, but it could be a directory
   local try, msg, code = f:read(0)
   if not try then
      -- not sure we can count on the undocumented numeric codes.
      -- if msg is nil then the file is readable, but is empty.
      if (type(msg)=="string") then
	 if msg:find("Is a directory") then return nil, "Is a directory"
	 else return nil, "Cannot read file"; end
      end
   end
   f:close()
   return true
end

infilename, outfilename, errfilename = nil, nil, nil

local function process_pattern_against_file(args, infilename)
   assert(compiled_pattern, "Rosie: missing pattern?")
   assert(engine_module.rplx.is(compiled_pattern), "Rosie: compiled pattern not rplx?")

	-- (3) Set up the input, output and error parameters
	if infilename=="-" then infilename = ""; end	    -- stdin
	outfilename = ""				    -- stdout
	errfilename = "/dev/null"
	if args.all then errfilename = ""; end	            -- stderr

	-- (4) Set up what kind of encoding we want done on the output
	local default_encoder = (args.command=="grep") and "line" or "color"
	set_encoder(args.encode or default_encoder)

	local ok, msg = readable_file(infilename)
	if (args.verbose) or (#args.filename > 1) then
	   if ok then io.write(infilename, ":\n"); end    -- print name of file before its output
	end
	if not ok then
	   io.stderr:write(infilename, ": ", msg, "\n")
	   return
	end

	-- (5) Iterate through the lines in the input file
	local match_function = (args.command=="trace") and rosie.file.tracematch or rosie.file.match 

	local ok, cin, cout, cerr =
	   pcall(match_function, CL_ENGINE, compiled_pattern, nil, infilename, outfilename, errfilename, args.wholefile)

	if not ok then io.write(cin, "\n"); return; end	-- cin is error message (a string) in this case

	-- (6) Print summary
	if args.verbose then
		local fmt = "Rosie: %d input items processed (%d matches, %d items unmatched)\n"
		io.stderr:write(string.format(fmt, cin, cout, cerr))
	end
end

local function setup_and_run_tests(args)
   -- first, set up the rosie CLI engine and automatically load the file being tested (after
   -- loading all the other stuff per the other command line args and defaults)
   if not args.rpls then
      args.rpls = { args.filename }
   else
      table.insert(args.rpls, args.filename)
   end
   setup_engine(args);
      
   local function startswith(str,sub)
      return string.sub(str,1,string.len(sub))==sub
   end
   -- from http://www.inf.puc-rio.br/~roberto/lpeg/lpeg.html
   local function split(s, sep)
      sep = lpeg.P(sep)
      local elem = lpeg.C((1 - sep)^0)
      local p = lpeg.Ct(elem * (sep * elem)^0)
      return lpeg.match(p, s)
   end
   local function find_test_lines(str)
      local num = 0
      local lines = {}
      for _,line in pairs(split(str, "\n")) do
	 if startswith(line,'-- test') then
	    table.insert(lines, line)
	    num = num + 1
	 end
      end
      return num, lines
   end
   local f = io.open(args.filename, 'r')
   local num_patterns, test_lines = find_test_lines(f:read('*a'))
   f:close()
   if num_patterns > 0 then
      local function test_accepts_exp(exp, q)
	 local res, pos = CL_ENGINE:match(exp, q)
	 if pos ~= 0 then return false end
	 return true
      end
      local function test_rejects_exp(exp, q)
	 local res, pos = CL_ENGINE:match(exp, q)
	 if pos == 0 then return false end
	 return true
      end
      local test_funcs = {test_rejects_exp=test_rejects_exp,test_accepts_exp=test_accepts_exp}
      local test_patterns =
	 [==[
	    testKeyword = "accepts" / "rejects"
	    test_line = "-- test" identifier testKeyword quoted_string (ignore "," ignore quoted_string)*
         ]==]

      rosie.file.load(CL_ENGINE, "$sys/rpl/rpl-1.0.rpl", "rpl")
      load_string(CL_ENGINE, test_patterns)
      set_encoder(false)
      local failures = 0
      local exp = "test_line"
      for _,p in pairs(test_lines) do
	 local m, left = CL_ENGINE:match(exp, p)
	 -- FIXME: need to test for failure to match
	 local name = m.subs[1].text
	 local testtype = m.subs[2].text
	 local testfunc = test_funcs["test_" .. testtype .. "_exp"]
	 local literals = 3 -- literals will start at subs offset 3
	 -- if we get here we have at least one per test_line expression rule
	 while literals <= #m.subs do
	    local teststr = m.subs[literals].text
	    teststr = common.unescape_string(teststr) -- allow, e.g. \" inside the test string
	    if not testfunc(name, teststr) then
	       print("FAIL: " .. name .. " did not " .. testtype:sub(1,-2) .. " " .. teststr)
	       failures = failures + 1
	    end
	    literals = literals + 1
	 end
      end
      if failures == 0 then
	 print("All tests passed")
      else
	 os.exit(-1)
      end
   else
      print("No tests found")
   end
   os.exit()
end


local function run(args)
   if not args.command then
      if ROSIE_DEV then greeting(); return
      else
	 print("Usage: rosie command|help [options] pattern file [...])")
	 os.exit(-1)
      end
   end
   if (args.command=="info") or (args.command=="help") then
      if args.command=="info" then
	 print_rosie_info()
      else
	 print(parser:get_help())
      end
      os.exit()
   end
   
   if args.verbose then greeting(); end

   if args.command == "test" then
      -- lightweight pattern test framework does a custom setup
      setup_and_run_tests(args);
   end
   
   setup_engine(args);

   if args.command == "list" then
      if not args.verbose then greeting(); end
      local env = CL_ENGINE:lookup()
      ui.print_env(env, args.filter)
      os.exit()
   end

   if args.command == "repl" then
      repl_mod = mod.import("repl", rosie_mod)
      if not args.verbose then greeting(); end
      repl_mod.repl(CL_ENGINE)
      os.exit()
   end

   for _,fn in ipairs(args.filename) do
      process_pattern_against_file(args, fn)
   end
end -- function run

----------------------------------------------------------------------------------------
-- Parser for command line args
----------------------------------------------------------------------------------------

-- create Parser
function create_arg_parser()
   parser = argparse("rosie", "Rosie " .. ROSIE_VERSION)
   parser:add_help(false)
   parser:require_command(false)
   --:epilog("Additional information.")
   -- global flags/options can go here
   -- -h,--help is generated automatically
   -- usage message is generated automatically
   parser:flag("--version", "Print rosie version")
   :action(function(args,_,exceptions)
	      greeting()
	      os.exit()
	   end)
   parser:flag("--verbose", "Output additional messages")
   :default(false)
   :action("store_true")
   parser:option("--manifest", "Load a manifest file (follow with a single dash '-' for none)")
   :default("$sys/MANIFEST")
   :args(1)
   parser:option("--rpl", "Inline RPL statements")
   :args(1)
   :count("*") -- allow multiple RPL statements
   :target("statements") -- set name of variable index (args.statements)
   parser:option("-f --file", "Load an RPL file")
   :args(1)
   :count("*") -- allow multiple loads of a file
   :target("rpls") -- set name of variable index (args.rpls)

   local output_choices={}
   for k,v in pairs(rosie.encoders) do
      if type(k)=="string" then table.insert(output_choices, k); end
   end
   local output_choices_string = output_choices[1]
   for i=2,#output_choices do
      output_choices_string = output_choices_string .. ", " .. output_choices[i]
   end

   parser:option("-o --output", "Output style, one of: " .. output_choices_string)
   :convert(function(a)
	       -- validation of argument, will fail if not in choices array
	       for j=1,#output_choices do
		  if a == output_choices[j] then
		     return a
		  end
	       end
	       return nil
	    end)
   :args(1) -- consume argument after option
   
   -- target variable for commands
   parser:command_target("command")
   local cmd_info = parser:command("help")
   :description("Print this help message")
   -- grep command
   local cmd_grep = parser:command("grep")
   :description("In the style of Unix grep, match the pattern anywhere in each input line")
   -- info command
   local cmd_info = parser:command("info")
   :description("Print rosie installation information")
   -- patterns command
   local cmd_patterns = parser:command("list")
   :description("List installed patterns")
   cmd_patterns:argument("filter")
   :description("Filter pattern names that have substring 'filter'")
   :args("?")
   -- match command
   local cmd_match = parser:command("match")
   :description("Match the given RPL pattern against the input")
   -- repl command
   local cmd_repl = parser:command("repl")
   :description("Start the read-eval-print loop for interactive pattern development and debugging")
   -- test command
   local cmd_test = parser:command("test")
   :description("Execute pattern tests written within the target rpl file(s)")
   cmd_test:argument("filename", "RPL filename")
   -- trace command
   local cmd_trace = parser:command("trace")
   :description("Match while tracing all steps (generates MUCH output)")

   for _, cmd in ipairs{cmd_match, cmd_trace, cmd_grep} do
      -- match/trace/grep flags (true/false)
      cmd:flag("-w --wholefile", "Read the whole input file as single string")
      :default(false)
      :action("store_true")
      cmd:flag("-a --all", "Output non-matching lines to stderr")
      :default(false)
      :action("store_true")
      cmd:flag("-F --fixed-strings", "Interpret the pattern as a fixed string, not an RPL pattern")
      :default(false)
      :action("store_true")

      -- match/trace/grep arguments (required options)
      cmd:argument("pattern", "RPL pattern")
      cmd:argument("filename", "Input filename")
      :args("+")
      :default("-")			      -- in case no filenames are passed, default to stdin
      :defmode("arg")			      -- needed to make the default work
   end
end

ok, msg = pcall(create_arg_parser)
if not ok then print("Error in cli when creating arg parser: " .. msg); end

local args = parser:parse()
run(args)

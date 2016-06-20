---- -*- Mode: Lua; -*-                                                                           
----
---- lapi.lua     Rosie API in Lua, for Lua programs
----
---- © Copyright IBM Corporation 2016.
---- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
---- AUTHOR: Jamie A. Jennings

local common = require "common"
local compile = require "compile"
local parse = require "parse"
require "engine"
local manifest = require "manifest"
local eval = require "eval"
require "color-output"

-- temporary:
require "grep"
lpeg = require "lpeg"
Cp = lpeg.Cp

assert(ROSIE_HOME, "The path to the Rosie installation, ROSIE_HOME, is not set")

function reconstitute_pattern_definition(id, p)
   if p then
      return ( --((p.alias and "alias ") or "") .. id .. " = " ..
	       ((p.original_ast and parse.reveal_ast(p.original_ast)) or
	        (p.ast and parse.reveal_ast(p.ast)) or
	      "// built-in RPL pattern //"))
   else
      error("undefined identifier: " .. id)
   end
end

----------------------------------------------------------------------------------------
local lapi = {}

local function arg_error(msg)
   error("Argument error: " .. msg, 0)
end

----------------------------------------------------------------------------------------
-- Managing the environment (engine functions)
----------------------------------------------------------------------------------------

function lapi.inspect_engine(en)
   if not engine.is(en) then arg_error("not an engine: " .. tostring(en)); end
   return en:inspect()
end

-- !@# Change optional-name to configuration table

function lapi.new_engine(optional_name)	    -- optional manifest? file list? code string?
   optional_name = (optional_name and tostring(optional_name)) or "<anonymous>"
   return engine(optional_name, compile.new_env())
end

function lapi.get_environment(en)
   if not engine.is(en) then arg_error("not an engine: " .. tostring(en)); end
   return compile.flatten_env(en.env)
end

function lapi.clear_environment(en)
   if not engine.is(en) then arg_error("not an engine: " .. tostring(en)); end
   en.env = compile.new_env()
end

----------------------------------------------------------------------------------------
-- Loading manifests, files, strings
----------------------------------------------------------------------------------------

function lapi.load_manifest(en, full_path)
   if not engine.is(en) then arg_error("not an engine: " .. tostring(en)); end
   -- local full_path, proper_path = common.compute_full_path(manifest_file)
   local ok, messages, full_path = manifest.process_manifest(en, full_path)
   return ok, common.compact_messages(messages), full_path
end

function lapi.load_file(en, path)
   if not engine.is(en) then arg_error("not an engine: " .. tostring(en)); end
   local full_path, msg = common.compute_full_path(path)
   if not full_path then return false, msg; end
   local input, msg = util.readfile(full_path)
   if not input then return false, msg; end
   local result, messages = compile.compile_source(input, en.env)
   return result, common.compact_messages(messages), full_path
end

function lapi.load_string(en, input)
   if not engine.is(en) then arg_error("not an engine: " .. tostring(en)); end
   local results, messages = compile.compile_source(input, en.env)
   return results, common.compact_messages(messages)
end

-- get a human-readable definition of identifier (reconstituted from its ast)
function lapi.get_binding(en, identifier)
   if not engine.is(en) then arg_error("not an engine: " .. tostring(en)); end
   local val = en.env[identifier]
   if not val then
      return false, "undefined identifier: " .. tostring(identifier)
   else
      if pattern.is(val) then
	 return reconstitute_pattern_definition(identifier, val)
      else
	 error("Internal error: object in environment not a pattern: " .. tostring(val))
      end
   end
end

function lapi.configure_engine(en, c)
   if not engine.is(en) then arg_error("not an engine: " .. tostring(en)); end
   if type(c)~="table" then
      arg_error("configuration not a table: " .. tostring(c)); end
   return en:configure(c)
end

----------------------------------------------------------------------------------------
-- Matching
----------------------------------------------------------------------------------------

-- Note: The match and eval functions do not check their arguments, which gives a small
-- boost in performance.  A Lua program which provides bad arguments to these functions
-- will be interrupted with a call to error().  The external API does more argument
-- checking. 

function lapi.match(en, input_text, start)
   local result, nextpos = en:match(input_text, start)
   return result, (#input_text - nextpos + 1)
end

function lapi.match_file(en, infilename, outfilename, errfilename, wholefileflag)
   return en:match_file(infilename, outfilename, errfilename, wholefileflag)
end

function lapi.eval(en, input_text, start)
   local result, nextpos, trace = en:eval(input_text, start)
   local leftover = 0;
   if nextpos then leftover = (#input_text - nextpos + 1); end
   return result, leftover, trace
end

function lapi.eval_file(en, infilename, outfilename, errfilename, wholefileflag)
   return en:eval_file(infilename, outfilename, errfilename, wholefileflag)
end

----------------------------------------------------------------------------------------

function lapi.set_match_exp_grep_TEMPORARY(en, pattern_exp, encoder_name)
   if not engine.is(en) then arg_error("not an engine: " .. tostring(en)); end
   if type(pattern_exp)~="string" then arg_error("pattern expression not a string"); end
   local pat, msg = pattern_EXP_to_grep_pattern(pattern_exp, en.env);
   if pattern.is(pat) then
      en.expression = "grep(" .. pattern_exp .. ")"
      en.pattern = pat
      return lapi.configure_engine(en, {encoder=encoder_name})
   else
      arg_error(msg)
   end
end


return lapi

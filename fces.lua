--[[
  This file is part of Lua-FCES (https://github.com/pakozm/lua-fces)

  Copyright 2015, Francisco Zamora-Martinez
  
  Permission is hereby granted, free of charge, to any person obtaining a copy
  of this software and associated documentation files (the "Software"), to deal
  in the Software without restriction, including without limitation the rights
  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
  copies of the Software, and to permit persons to whom the Software is
  furnished to do so, subject to the following conditions:
  
  The above copyright notice and this permission notice shall be included in all
  copies or substantial portions of the Software.
  
  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
  IN THE SOFTWARE.
]]

package.path = package.path .. ";" .. arg[0]:gsub("[^/]+.lua", "?.lua")
local tuple = require "tuple"

-- module fces
local fces = {}

local LAMBDA_MATCH = { tuple{ "USER" } }

----------------------
-- STATIC FUNCTIONS --
----------------------

-- converts to in-mutable the given table argument
local function inmutable(tbl)
  return setmetatable({}, {
      __index = function(_,k) return tbl[k] end,
      __newindex = function() error("Unable to modify an in-mutable table") end,
      __len = function() return #tbl end,
  })
end

-- pattern matching between a fact and the rule pattern
local function fact_match(fact, pattern)
  if #fact ~= #pattern then return false end
  local fact_str = tostring(fact):gsub('"', '')
  local pat_str = tostring(pattern):gsub("%.", "[^,]"):gsub('"', ''):gsub("%?[^%s,]+", "[^,]*")
  assert(not pat_str:find("%?"),
         string.format("Incorrect variable name in pattern: %s",
                       tostring(pattern)))
  -- print(fact_str, pat_str, fact_str:find(pat_str))
  return fact_str:find(pat_str)
end

-- check that the fact string doesn't contain forbidden symbols
local function check_fact_strings(fact)
  for i=1,#fact do
    local tt = type(fact[i])
    if tt == "table" then
      check_fact_strings(fact[i])
    elseif tt == "string" then
      assert(not fact[i]:find("[%.%-%,%+%?%(%)%{%}%[%]]"),
             string.format("Forbidden use of the following symbols in fact '%s': . - , + ? ( ) { } [ ]",
                           tostring(tuple(fact))))
    end
  end
end

-- forward declaration
local replace_variables
do
  local function replace(vi, vars)
    local new_v = {}
    for j,vj in ipairs(vi) do
      local tt = type(vj)
      if tt == "string" then
        local varname = vj:match("%?([^%s]+)")
        if varname then
          new_v[j] = assert(vars[varname],
                            string.format("Unable to find variable: %s", varname))
        else
          new_v[j] = vj
        end
      elseif tt == "table" then
        new_v[j] = replace(vj, vars)
      else
        new_v[j] = vj
      end
    end
    return new_v
  end

  replace_variables = function(args, vars)
    local new_args = {}
    for i,vi in ipairs(args) do
      new_args[i] = replace(vi, vars)
    end
    return new_args
  end
end

-- forward declaration
local assign_variables
do
  local function assign_fact_vars(vars, pat, fact, var_matches)
    for j,v in ipairs(pat) do
      local tt = type(v)
      if tt == "string" then
        local varname = v:match("%?([^%s]+)")
        if varname then
          local value = fact[j]
          if not var_matches[varname] or var_matches[varname](value) then
            if not vars[varname] then
              vars[varname] = value
            else
              if vars[varname] ~= value then return false end
            end
          else
            return false
          end
        end
      elseif tt == "table" then
        if not assign_fact_vars(vars, v, fact[j], var_matches) then
          return false
        end
      end
    end
    return true
  end

  assign_variables = function(self, vars, patterns, sequence, var_matches)
    for i,pat in ipairs(patterns) do
      if type(pat) ~= "function" then
        local fid  = sequence[i]
        local fact = self.fact_list[fid]
        if not assign_fact_vars(vars, pat, fact, var_matches) then return false end
      else
        if not pat(inmutable(vars)) then return false end
      end
    end
    return true
  end
end

-- returns an iterator function which enumerates all possible combinations
-- (Cartesian product) between all the given array arguments
local function enumerate(...)
  local function f(seq, tbl, ...)
    if tbl == nil and select('#', ...) == 0 then
      if #seq > 0 then coroutine.yield(tuple(seq)) end
    else
      if tbl ~= nil then
        if #seq > 0 then
          for i,v in ipairs(tbl) do
            f(seq .. tuple(v), ...)
          end
        else
          for i,v in ipairs(tbl) do
            f(tuple{v}, ...)
          end
        end
      end
    end
  end
  local args = table.pack(...)
  return coroutine.wrap(function() f({}, table.unpack(args)) end)
end

-- traverses all possible rules with all possible matches and introduces into
-- the agenda whose clause sequences which weren't entailed before and are valid
-- for the analyzed rule
local function regenerate_agenda(self)
  self.needs_regenerate_agenda = false
  local entailed = self.entailed
  local matches = self.matches
  local agenda = {}
  for rule_name,rule in pairs(self.kb_table) do
    local rule_entailements = entailed[rule_name] or {}
    local combinations = {}
    local variables = {}
    if #matches[rule_name] == #rule.patterns then
      for sequence in enumerate(table.unpack(matches[rule_name])) do
        if not rule_entailements[sequence] then
          local seq_vars = {}
          if assign_variables(self, seq_vars, rule.patterns, sequence,
                              rule.var_matches) then
            table.insert(combinations, sequence)
            table.insert(variables, seq_vars)
          end
        end
      end
      if #combinations > 0 then
        table.insert(agenda, {
                       rule_name = rule_name,
                       salience = rule.salience,
                       combinations = combinations,
                       variables = variables,
        })
      end
    end
  end
  table.sort(agenda, function(a,b) return a.salience > b.salience end)
  self.rules_agenda = agenda
end

-- look-ups for the rule with best salience, and returns the rule name and its
-- pattern matching arguments
local function take_best_rule(self)
  if self.needs_regenerate_agenda then regenerate_agenda(self) end
  local rules_agenda = self.rules_agenda
  if #rules_agenda > 0 then
    local rule_data = rules_agenda[1]
    local args = assert(table.remove(rule_data.combinations, 1),
                        "Found empty LHS args :'(")
    local vars = assert(table.remove(rule_data.variables, 1),
                        "Found empty LHS vars :'(")
    if #rule_data.combinations == 0 then table.remove(rules_agenda, 1) end
    local rule_name = rule_data.rule_name
    return rule_name,args,vars
  end
end

-- executes the given rule name with the given pattern matching arguments
local function fire_rule(self, rule_name, args, vars)
  local rule = self.kb_table[rule_name]
  self.entailed[rule_name] = self.entailed[rule_name] or {}
  self.entailed[rule_name][args] = true
  -- execute rule actions
  for _,action in ipairs(rule.actions) do
    action(args, inmutable(vars))
  end
end

-- binary search in a sorted array of numbers, where tbl is the array, v is the
-- look-up value, p is the start position (by default it is 1) and q the end
-- position (by default it is #tbl)
local function bsearch(tbl, v, p, q)
  p, q = p or 1, q or #tbl
  if p <= q then
    local n = q - p + 1
    if n < 30 then
      for i=p,q do if tbl[i] == v then return true end end
    else
      local m = math.floor((p+q)/2)
      if tbl[m] == v then
        return true
      elseif v < tbl[m] then
        return bsearch(tbl, v, p, m-1)
      else
        return bsearch(tbl, v, m+1, q)
      end
    end
  end
end

-- updates possible matches with the information given by one new fact
local function update_forward_chaining_with_assert_fact(self, fact)
  local fid     = self.fact_map[fact]
  local matches = self.matches
  for rule_name,rule in pairs(self.kb_table) do
    local rule_matches = matches[rule_name]
    for i,pat in ipairs(rule.patterns) do
      if type(pat) ~= "function" then
        if fact_match(fact, pat) then
          rule_matches[i] = rule_matches[i] or {}
          table.insert(rule_matches[i], fid)
          table.sort(rule_matches[i])
        end
      else
        rule_matches[i] = LAMBDA_MATCH
      end
    end
  end
  self.needs_regenerate_agenda = true
end

-- updates possible matches after retracting one fact
local function update_forward_chaining_with_retract_fact(self, fact)
  local fid     = self.fact_map[fact]
  local matches = self.matches
  for rule_name,rule in pairs(self.kb_table) do
    local rule_matches = matches[rule_name]
    for i,pat in ipairs(rule.patterns) do
      if type(pat) ~= "function" then
        if bsearch(rule_matches[i], fid) then
          new_rule_matches = {}
          for j,v in ipairs(rule_matches[i]) do
            if v ~= fid then table.insert(new_rule_matches, v) end
          end
          table.sort(new_rule_matches)
          rule_matches[i] = new_rule_matches
        end
      else
        rule_matches[i] = LAMBDA_MATCH
      end
    end
  end
  for _,sequence in ipairs(self.fact_entailment[fid] or {}) do
    self.entailed[sequence] = nil
  end
  self.fact_entailment[fid] = nil
  self.needs_regenerate_agenda = true
end

-- updates possible matches after introducing a new rule
local function update_forward_chaining_with_rule(self, rule_name, rule)
  local fid          = self.fact_map[fact]
  local matches      = self.matches
  local rule_matches = {}
  for i,pat in ipairs(rule.patterns) do
    if type(pat) ~= "function" then
      for fid,fact in pairs(self.fact_list) do
        if fact_match(fact, pat) then
          rule_matches[i] = rule_matches[i] or {}
          table.insert(rule_matches[i], fid)
          table.sort(rule_matches[i])
        end
      end
    else
      rule_matches[i] = LAMBDA_MATCH
    end
  end
  matches[rule_name] = rule_matches
  self.needs_regenerate_agenda = true
end

-------------
-- METHODS --
-------------

local fces_methods = {}

-- initializes the facts database
function fces_methods:clear()
  self.needs_regenerate_agenda = false
  -- counter index
  self.fact_idx = 0
  -- global memory for data
  self.fact_map = {}
  self.fact_list = {}
  -- agenda with lists of rules and its matching preconditions, sorted by
  -- salience
  self.rules_agenda = {}
  -- list of entailed preconditions, indexed by rule name
  self.entailed = {}
  -- list of entailed sequences related with every fact id
  self.fact_entailment = {}
  -- match rules dictionary, stores:
  --   rule_name = { pos1 = { fid1, fid2, ... }, pos2 = { ... } }
  -- where pos are rule LHS which matches with indicated fact ids
  self.matches = {}
  --
  self:fassert{ "initial fact" }
end

-- introduces a new fact into the database
function fces_methods:fassert(fact, ...)
  if fact ~= nil then
    assert(type(fact) == "table", "A table argument is expected")
    check_fact_strings(fact)
    local fact = tuple(fact)
    if not self.fact_map[fact] then
      self.fact_idx = self.fact_idx + 1
      self.fact_list[self.fact_idx] = fact
      self.fact_map[fact] = self.fact_idx
      -- executes a partial step of forward chaining with all rules affected by
      -- the given fact
      update_forward_chaining_with_assert_fact(self, fact)
      return self.fact_map[fact],self:fassert(...)
    else
      return false,self:fassert(...)
    end
  end
end

-- removes a fact from the database
function fces_methods:retract(...)
  for i=1,select('#',...) do
    local v = select(i,...)
    if v == "*" then
      -- retract all facts
      for idx,f in pairs(self.fact_list) do
        self.fact_list[idx] = nil
        self.fact_map[f] = nil
      end
      self.matches = {}
      self.rules_agenda = {}
      self.entailed = {}
      self.fact_entailment = {}
    else
      -- retract a given fact
      assert(type(v) == "number", "Expected fact number or '*' string")
      local f = self.fact_list[v]
      if f then
        -- executes a partial step of forward chaining with all rules affected by
        -- the given fact
        update_forward_chaining_with_retract_fact(self, f)
        self.fact_list[v] = nil
        self.fact_map[f] = nil
      else
        error("Unable to find fact " .. v)
      end
    end
  end
end

-- shows in screen all the available facts
function fces_methods:facts()
  local facts = {}
  for i,v in pairs(self.fact_list) do
    table.insert(facts, {i,v})
  end
  table.sort(facts, function(a,b) return a[1]<b[1] end)
  print("# Facts list")
  for _,v in ipairs(facts) do
    print("f-" .. v[1], v[2])
  end
  print(string.format("# For a total of %d facts", #facts))
end

-- shows in screen all the available rules
function fces_methods:rules()
  local rules = {}
  for i,v in pairs(self.kb_table) do
    table.insert(rules, {i,v})
  end
  table.sort(rules, function(a,b) return a[1]<b[1] end)
  print("# Rules list")
  for _,v in ipairs(rules) do
    print(v[1], "salience:", v[2].salience)
  end
end

-- shows the agenda in screen
function fces_methods:agenda()
  if self.needs_regenerate_agenda then regenerate_agenda(self) end
  print("# Agenda")
  local n=0
  for _,v in ipairs(self.rules_agenda) do
    local rule_name    = v.rule_name
    local salience     = v.salience
    local combinations = v.combinations
    for _,seq in ipairs(combinations) do
      n=n+1
      print(tostring(salience), rule_name, tostring(seq))
    end
  end
  print(string.format("# For a total of %d activations", n))
end

-- executes at most n iterations, being by default n=infinity
function fces_methods:run(n)
  n = n or math.huge
  local i=0
  repeat
    local data = table.pack( take_best_rule(self) )
    if data[1] then fire_rule(self, table.unpack(data) ) i = i+1 end
  until i==n or not data[1]
end

-- returns the fact related to the given fact id
function fces_methods:consult(fid)
  local fact = assert(self.fact_list[fid],
                      "Unable to find fact with index " .. tostring(fid))
  return fact
end

-- declares a new rule in the knowledge base
function fces_methods:defrule(rule_name)
  local rule = { patterns={}, actions={}, salience=0, var_matches = {} }
  self.kb_table[rule_name] = rule
  local rule_builder = {
    pattern = function(rule_builder, pattern)
      table.insert(rule.patterns, tuple(pattern))
      return rule_builder
    end,
    u = function(rule_builder, func)
      table.insert(rule.patterns, func)
      return rule_builder
    end,
    salience = function(rule_builder, value)
      rule.salience = value
      return rule_builder
    end,
    match = function(rule_builder, varname, value)
      varname = assert(varname:match("%?([^%s]+)"),
                       string.format("Incorrect variable name: %s", varname))
      rule.var_matches[varname] = function(v)
        return v:find(value)
      end
      return rule_builder
    end,
    numeric = function(rule_builder, varname)
      varname = assert(varname:match("%?([^%s]+)"),
                       string.format("Incorrect variable name: %s", varname))
      rule.var_matches[varname] = function(v)
        return type(v) == "number"
      end
      return rule_builder
    end,
    ENTAILS = function(_, arg)
      assert(arg == "=>", "ENTAILS needs '=>' string as argument")
      update_forward_chaining_with_rule(self, rule_name, rule)
      return setmetatable({},{
          __index = function(rule_builder, key)
            if key == "u" then
              return function(rule_builder, user_func)
                -- user_func receives two arguments (fact_ids, vars)
                table.insert(rule.actions, user_func)
                return rule_builder
              end
            else
              local f = assert(self[key], "Undefined function " .. key)
              return function(rule_builder, ...)
                local args = table.pack(...)
                for i=1,args.n do args[i] = tuple(args[i]) end
                table.insert(rule.actions,
                             function(fact_ids, vars)
                               local new_args = replace_variables(args, vars)
                               return self[key](self, table.unpack(new_args))
                end)
                return rule_builder
              end
            end
          end
      })
    end
  }
  return rule_builder
end

-----------------
-- CONSTRUCTOR --
-----------------

--
local fces_metatable = {
  __index = fces_methods,
}

-- calling fces table returns a new rule-based expert system
setmetatable(fces, {
               __call = function()
                 local t = {
                   -- knowledge-base table, contains all the rules
                   kb_table = {},
                 }
                 local t = setmetatable(t, fces_metatable)
                 t:clear()
                 return t
               end
})

-- returns module table
return fces

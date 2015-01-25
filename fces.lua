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

----------------------
-- STATIC FUNCTIONS --
----------------------

-- pattern matching between a fact and the rule pattern
local function fact_match(fact, pattern)
  local fact_str = tostring(fact)
  local pat_str = tostring(pattern):gsub("%.", "[^,]")
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
             "Forbidden use of the following symbols: . - , + ? ( ) { } [ ]")
    end
  end
end

-- look-ups for the rule with best salience, and returns the rule name and its
-- pattern matching arguments
local function take_best_rule(self)
  local rules_agenda = self.rules_agenda
  if #rules_agenda > 0 then
    local rule_data = rules_agenda[1]
    local args = assert(table.remove(rule_data.combinations, 1),
                        "Found empty LHS :'(")
    if #rule_data.combinations == 0 then table.remove(rules_agenda, 1) end
    local rule_name = rule_data.rule_name
    return rule_name,args
  end
end

-- executes the given rule name with the given pattern matching arguments
local function fire_rule(self, rule_name, args)
  local rule = self.kb_table[rule_name]
  self.entailed[rule_name] = self.entailed[rule_name] or {}
  self.entailed[rule_name][args] = true
  -- execute rule actions
  for _,action in ipairs(rule.actions) do action(table.unpack(args)) end
  --
end

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

local function enumerate(...)
  local function f(seq, tbl, ...)
    if tbl == nil then
      coroutine.yield(tuple(seq))
    else
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
  local args = table.pack(...)
  return coroutine.wrap(function() f({}, table.unpack(args)) end)
end

local function regenerate_agenda(self)
  local entailed = self.entailed
  local matches = self.matches
  local agenda = {}
  for rule_name,rule in pairs(self.kb_table) do
    local rule_entailements = entailed[rule_name] or {}
    local combinations = {}
    for sequence in enumerate(table.unpack(matches[rule_name])) do
      if not rule_entailements[sequence] then
        table.insert(combinations, sequence)
      end
    end
    table.insert(agenda, {
                   rule_name = rule_name,
                   salience = rule.salience,
                   combinations = combinations
    })
  end
  table.sort(agenda, function(a,b) return a.salience > b.salience end)
  self.rules_agenda = agenda
end

local function update_forward_chaining_with_assert_fact(self, fact)
  local fid     = self.fact_map[fact]
  local matches = self.matches
  for rule_name,rule in pairs(self.kb_table) do
    local rule_matches = matches[rule_name]
    for i,pat in ipairs(rule.patterns) do
      if fact_match(fact, pat) then
        rule_matches[i] = rule_matches[i] or {}
        table.insert(rule_matches[i], fid)
        table.sort(rule_matches[i])
      end
    end
  end
  regenerate_agenda(self)
end

local function update_forward_chaining_with_retract_fact(self, fact)
  local fid     = self.fact_map[fact]
  local matches = self.matches
  for rule_name,rule in pairs(self.kb_table) do
    local rule_matches = matches[rule_name]
    for i,pat in ipairs(rule.patterns) do
      if bsearch(rule_matches[i], fid) then
        new_rule_matches = {}
        for j,v in ipairs(rule_matches[i]) do
          if v ~= fid then table.insert(new_rule_matches, v) end
        end
        table.sort(new_rule_matches)
        rule_matches[i] = new_rule_matches
      end
    end
  end
  for _,sequence in ipairs(self.fact_entailment[fid] or {}) do
    self.entailed[sequence] = nil
  end
  self.fact_entailment[fid] = nil
  regenerate_agenda(self)
end

local function update_forward_chaining_with_rule(self, rule_name, rule)
  local fid          = self.fact_map[fact]
  local matches      = self.matches
  local rule_matches = {}
  for i,pat in ipairs(rule.patterns) do
    for fid,fact in pairs(self.fact_list) do
      if fact_match(fact, pat) then
        rule_matches[i] = rule_matches[i] or {}
        table.insert(rule_matches[i], fid)
        table.sort(rule_matches[i])
      end
    end
  end
  matches[rule_name] = rule_matches
  regenerate_agenda(self)
end

-------------
-- METHODS --
-------------

local fces_methods = {}

function fces_methods:clear()
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

function fces_methods:agenda()
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

function fces_methods:run(n)
  n = n or math.huge
  local i=0
  repeat
    local rule_name,args = take_best_rule(self)
    if rule_name then fire_rule(self, rule_name, args) i = i+1 end
  until i==n or not rule_name
end

function fces_methods:consult(fid)
  local fact = assert(self.fact_list[fid],
                      "Unable to find fact with index " .. tostring(fid))
  return fact
end

function fces_methods:defrule(rule_name)
  local rule = { patterns={}, actions={}, salience=0 }
  self.kb_table[rule_name] = rule
  local rule_builder = {
    pattern = function(rule_builder, pattern)
      table.insert(rule.patterns, tuple(pattern))
      return rule_builder
    end,
    salience = function(rule_builder, value)
      rule.salience = value
      return rule_builder
    end,
    ENTAILS = function(_, arg)
      assert(arg == "=>", "ENTAILS needs '=>' string as argument")
      update_forward_chaining_with_rule(self, rule_name, rule)
      return setmetatable({},{
          __index = function(rule_builder, key)
            if key == "u" then
              return function(rule_builder, user_func)
                table.insert(rule.actions, user_func)
                return rule_builder
              end
            else
              local f = assert(self[key], "Undefined function " .. key)
              return function(rule_builder, ...)
                local args = table.pack(...)
                for i=1,args.n do args[i] = tuple(args[i]) end
                table.insert(rule.actions,
                             function()
                               return self[key](self, table.unpack(args))
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

local fces = require "fces"
local kb = fces()

kb:defrule("expand"):
  salience(100):
  pattern{ "Factorial", "?x" }:
  u(function(vars)
      return vars.x > 1
  end):
  ENTAILS("=>"):
  u(function(args, vars)
      kb:fassert{ "Factorial", vars.x-1 }
  end)

kb:defrule("compute"):
  salience(0):
  pattern{ "Factorial", "?x" }:
  pattern{ "Result", "?y", "?z" }:
  u(function(vars)
      return vars.x == vars.y+1
  end):
  ENTAILS("=>"):
  u(function(args, vars)
      kb:fassert{ "Result", vars.x, vars.x * vars.z }
  end)

kb:fassert{ "Result", 1, 1 }
kb:fassert{ "Factorial", 10 }

kb:agenda()
kb:run()
kb:facts()

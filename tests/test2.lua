local fces = require "fces"
local kb = fces()

kb:retract('*')
kb:fassert{ "duck", 4 }
kb:fassert{ 16 }
kb:fassert{ "AnimalIs", "duck" }

kb:defrule("user"):
  pattern{ "?x", "?y" }:
  pattern{ "?z" }:
  pattern{ "AnimalIs", "?x" }:
  numeric("?y"):
  numeric("?z"):
  u(function(vars)
      return (vars.z == vars.y*4) and (vars.y % 2)==0
  end):
  ENTAILS("=>"):
  fassert{ "EvenAnimal", "?x", "?y", "?z" }

kb:rules()
kb:agenda()
kb:run()
kb:facts()

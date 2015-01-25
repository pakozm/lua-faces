local fces = require "fces"
local kb = fces()

kb:retract('*')
kb:fassert{ "duck", 4 }
kb:fassert{ 16 }
kb:fassert{ "AnimalIs", "duck" }

kb:defrule("user"):
  pattern{ "?x", "?y" }:
  pattern{ "?z" }:
  numeric("?y"):
  numeric("?z"):
  pattern{ "AnimalIs", "?x" }:
  u(function(vars)
      return (vars.z == vars.y*4) and (vars.y % 2)==0
  end):
  ENTAILS("=>"):
  fassert{ "EvenAnimal", "?x" }

kb:rules()
kb:agenda()
kb:run()
kb:facts()

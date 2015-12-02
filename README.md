# Lua-FaCES

Lua-FaCES is a forward chaining expert system development tool written in Lua
programming language.

## Installation

Just copy `faces.lua` and `tuple.lua` to your Lua library location, usually in
Ubuntu `/usr/share/lua/5.2`.

## Tutorial

Once it is installed you can use the library by requiring it and instantiating
a knowledge-base:

```Lua
> faces = require "faces"
> kb = faces()
```

The knowledge-based (KB) is a set of facts which are known as true, and a set of
rules which allow to update the facts. The most basic operation is definition of
initial facts using function `kb:fassert{...}` which receive a table with the
fact definition. A fact can be described as a tuple of strings, numbers or other
tuples, so you can define a hierarchy of symbols. Every tuple and its compounds
is considered a symbol. The following example asserts in the KB a fact
describing a color as green:

```Lua
> = kb:fassert{ "color", "green" }
2
```

The number returned by the function is a numeric identifier which allow you to
retract or point this fact in different places. Using `kb:facts()` you can
see the list of facts until now:

```Lua
> kb:facts()
# Facts list
f-1	tuple{ "initial fact" }
f-2	tuple{ "color", "green" }
# For a total of 2 facts
```

As you can see facts are stored as tuples, so they are immutable and interned
by the library (similar to Python tuples). At this point you can assert other
facts.

```Lua
> kb:fassert{ "color", "green" }
2
> kb:fassert{ "color", "red" }
3
> kb:facts()
# Facts list
f-1	tuple{ "initial fact" }
f-2	tuple{ "color", "green" }
f-3	tuple{ "color", "red" }
# For a total of 3 facts
```

And it is possible to use `kb:retract(...)` to remove any of this facts:

```Lua
> kb:retract(2)
> kb:facts()
# Facts list
f-1	tuple{ "initial fact" }
f-3	tuple{ "color", "red" }
# For a total of 2 facts
```

The index given to retract is the fact index returned by `kb:fassert(...)`
function. As any other Lua value you can store this index in a variable, operate
with it, or whatever you want.

Facts are very limited, so rules are needed to allow transformation of facts,
and finally, to allow computations. The following rule declares that if an
animal is a duck then it should sound quack:

```Lua
> kb:defrule("duck"):pattern{ "animal_is", "duck" }:
  ENTAILS("=>"):
  fassert{ "sound_is", "quack" }
```

The rule consists in three parts, a name (in this case "duck"), the
left-hand-side (LHS) of the rule where pattern matching is used to state
premises of the rule, and the right-hand-side (RHS) where actions are executed
once the premises are stated as true.

At any moment you can see the list of available rules using `kb:rules()`:

```Lua
> kb:rules()
# Rules list
duck	salience:	0
```

In order to see this rule working, you need to assert the fact `{animal_is
duck}`, so proceed this way and see what happens:

```Lua
> kb:agenda()
# Agenda
# For a total of 0 activations
> = kb:fassert{ "animal_is", "duck" }
4
> kb:agenda()
# Agenda
0	duck	tuple{ 4 }
# For a total of 1 activations
> kb:run()
> kb:agenda()
# Agenda
# For a total of 0 activations
> kb:facts()
# Facts list
f-1	tuple{ "initial fact" }
f-3	tuple{ "color", "red" }
f-4	tuple{ "animal_is", "duck" }
f-5	tuple{ "sound_is", "quack" }
# For a total of 4 facts
```

We have been used `kb:agenda()` in order to check which rules have their
premises satisfied and which facts are satisfying its premises. Additionally, a
number indicating the salience (priority) of the rule is shown. Higher salience
value mean higher priority.

Now we are going to chain two rules in order to produce our expected goal of
`{sound_is duck}`. First, using `kb:clear()` we remove all asserted facts, and
re-asserting a new `{initial fact}`. After that, we define a new rule which
declares the animal is a duck if it has webbed-feet and feathers:

```Lua
> kb:clear()
> kb:defrule("is_it_a_duck"):
    pattern{"animal_has", "webbed_feet"}:
    pattern{"animal_has", "feathers"}:
    ENTAILS("=>"):
    fassert{"animal_is", "duck"}
```

Now assert both facts animal has and run the inference:

```Lua
> kb:fassert{"animal_has", "webbed_feet"}
> kb:fassert{"animal_has", "feathers"}
> kb:run()
> kb:facts()
# Facts list
f-1	tuple{ "initial fact" }
f-2	tuple{ "animal_has", "webbed_feet" }
f-3	tuple{ "animal_has", "feathers" }
f-4	tuple{ "animal_is", "duck" }
f-5	tuple{ "sound_is", "quack" }
# For a total of 5 facts
```

As you can see we end with five facts, the initial one, the two we have
asserted, and the two asserted by the rules. The system executes first
`is_it_a_duck` rule and after `duck` rule. Chaining rules in different ways
you can describe really complex systems.

### Working with variables and user defined functions

The pattern matching algorithm used by Lua-FaCES allow to declare variables
in rules which value is instantiated to fact contents. As example, the
following rule is executed with every `{animal_has ...}` fact and prints
them into screen:

```Lua
> kb:defrule("debug"):
    pattern{ "animal_has", "?x" }:
    ENTAILS("=>"):
    u(function(vars) print(vars.x) end)
> kb:run()
webbed_feet
feathers
```

As you can see, we have introduced here two concepts, variables and user defined
functions. Variables are a string which starting with a question mark `?name`.
Once the variable is declared, you can use it without the question mark inside
user defined functions. The user defined functions receive one and only one
argument, which a list of all the variables declared in the rule. User defined
functions can be expressed as a Lua function which receives the `vars` argument,
or in a more compact way using a string. The string should be a Lua expression
which can be evaluated as result of the function. This user defined functions
can be declared at LHS as predicates, and at RHS as actions, so you can define
powerful rules like the following one:

```Lua
> kb:defrule("factorial"):
    pattern{ "Factorial", "?x", "?y" }:
    pattern{ "Limit", "?z" }:
    u"x < z":
    ENTAILS"=>":
    fassert{ "Factorial", u"x+1", u"y*(x+1)" }
```

This rule computes factorial numbers until a given limit number. It needs a base
case `{"Factorial",1,1}` to be asserted and a `{"Limit",10}` for example:

```Lua
> kb:clear()
> kb:fassert{"Factorial",1,1}
> kb:fassert{"Limit",10}
> kb:run()
> kb:facts()
# Facts list
f-1	tuple{ "initial fact" }
f-2	tuple{ "Factorial", 1, 1 }
f-3	tuple{ "Limit", 10 }
f-4	tuple{ "Factorial", 2, 2 }
f-5	tuple{ "Factorial", 3, 6 }
f-6	tuple{ "Factorial", 4, 24 }
f-7	tuple{ "Factorial", 5, 120 }
f-8	tuple{ "Factorial", 6, 720 }
f-9	tuple{ "Factorial", 7, 5040 }
f-10	tuple{ "Factorial", 8, 40320 }
f-11	tuple{ "Factorial", 9, 362880 }
f-12	tuple{ "Factorial", 10, 3628800 }
# For a total of 12 facts
```

Fact identifiers can be captured in order to allow references to them into RHS
part of the rule:

```Lua
> kb:defrule("retract_all"):
    var("?f"):pattern{ "Limit", 10 }:
    ENTAILS("=>"):
    retract(u("f")):
    fassert{ "Limit", 12 }
> kb:run()
> kb:facts()
# Facts list
f-1	tuple{ "initial fact" }
f-2	tuple{ "Factorial", 1, 1 }
f-4	tuple{ "Limit", 12 }
f-5	tuple{ "Factorial", 2, 2 }
f-6	tuple{ "Factorial", 3, 6 }
f-7	tuple{ "Factorial", 4, 24 }
f-8	tuple{ "Factorial", 5, 120 }
f-9	tuple{ "Factorial", 6, 720 }
f-10	tuple{ "Factorial", 7, 5040 }
f-11	tuple{ "Factorial", 8, 40320 }
f-12	tuple{ "Factorial", 9, 362880 }
f-13	tuple{ "Factorial", 10, 3628800 }
f-14	tuple{ "Factorial", 11, 39916800 }
f-15	tuple{ "Factorial", 12, 479001600 }
# For a total of 14 facts
```

### Multi-valuated variables

Lua-FaCES does not allow general multi-valuated variables, but it uses a simple
trick which allow to solve the majority of cases. For example, let see the
following facts:

```Lua
> kb:clear()
> kb:fassert{ "A", { "multi-valuated", "example" } }
> kb:fassert{ "Another", { "one", "multi-valuated", "example" } }
```

Both facts are declared as a hierarchy of tuples, the fact tuple and a nested
tuple at position 2. This kind of nested tuples can be captured as
multi-valuated variables as follows:

```Lua
> kb:defrule("MultiValuated"):
    pattern{ "?x", "$?y" }:
    ENTAILS("=>"):
    u(function(vars) print("x="..vars.x, "y="..tostring(vars.y)) end)
> kb:run()
x=A	y=tuple{ "multi_valuated", "example" }
x=Another	y=tuple{ "one", "multi_valuated", "example" }
```

As you can see, the rule is instantiated with both multi-valuated facts, so `x`
variable contains the string at fact's head, and `y` variable is a tuple with
the multi-valuated content. This multi-valuated variables only can be
instantiated with tuples, so you need to take that into account when designing
your KB. A tuple can be accessed as a plain Lua table, it allows `pairs()`, `#`
and `[]` operators.

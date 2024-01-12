# JZ
___
"JavaScript" runtime engine written entirely in Zig. The goal of 
this project is to aim for compatibility with JavaScript source
text, but the primary focus for now is just to make a usable
engine.

There are no plans to optimize for performance or low overhead,
just to simply get it working while keeping the code as clean
as possible.

This project mostly started as something to keep myself busy
and keep my developer mind working between jobs, it might end
up becoming something more - it might end up being another 
incomplete project. It remains to be seen.

## "Virtual Machine" / "Runtime"
Currently, the design of the engine is that of an "Assembly-like"
state machine with execution scopes being their own entities.

Calls are enqueued then executed in-order; variables cannot be
modified in-place but the values of the scopes' register can be
written to the variable, and variables can be assigned to other
variables.

## Can this replace V8 / JavaScriptCore / Hermes?
HAH - I am not that smart, but if this project somehow manages
to gain traction and attracts external contributors it sure would
be cool.

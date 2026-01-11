---
sidebar_position: 1
---

# Roblox Utility

A collection of strictly typed utility modules providing common infrastructure such as events, data structures, and development helpers.

## Design Philosophy

These modules prioritise:

- Strict typing (`--!strict`) for early error detection
- Clear, documented behavior over implicit magic
- APIs that align with Roblox’s own engine patterns
- Minimal runtime overhead and predictable performance
- Unit tested code that you can rely on

Where Luau’s type system has limitations, this library favors correctness
and simplicity over complex or misleading abstractions.

## Installation

To install the packages in this repository you can use the Wally package manager. After installing Wally, navigate to your project directory and run `wally init` – this will generate the `wally.toml` file. You can add the `roblox-utility` modules to the generated `wally.toml` file as dependencies. 

`Event = "zythdotdev/event@2.0.0"`

After adding the modules to your dependency list, run `wally install`. Wally will generate a `Packages` folder containing the installed dependencies. You can then require them in your scripts.

`Event = require(Packages.Event)`
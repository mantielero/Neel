# Package

version       = "0.4.0"
author        = "Leon Lysak, Blane Lysak"
description   = "A Nim library for making lightweight Electron-like HTML/JS GUI apps, with full access to Nim capabilities."
license       = "MIT"
srcDir        = "src"



# Dependencies

requires "nim >= 1.2.2"
requires "jester >= 0.5.0"
requires "ws >= 0.4.2"

when defined(nimdistros):
  import distros 
  if detectOs(Ubuntu):
    foreignDep "libwebkit2gtk-4.0-dev"
else: "no nimdistros"

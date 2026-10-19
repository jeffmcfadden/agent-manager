# Third-party notices

Agent Manager's original code and artwork are copyright © 2026 Jeff McFadden
and licensed under WTFPL version 2. That grant does not relicense dependencies.
This file and the ThirdParty directory accompany every application distribution
in Contents/Resources/Licenses, accessible through Agent Manager → Licenses….

## Components

| Component | License | Copyright / attribution |
| --- | --- | --- |
| Ghostty 1.2.3 and its integration code | MIT | Mitchell Hashimoto and Ghostty contributors |
| libxev, zig-objc | MIT | Mitchell Hashimoto |
| ziglyph, zg | MIT | Jose Colon Rodriguez |
| zf | MIT | Nathan Craddock |
| vaxis | MIT | Tim Culverhouse |
| zigimg | MIT | zigimg developers |
| z2d 0.8.1 | MPL-2.0 | Chris Marchesi |
| Dear ImGui | MIT | Omar Cornut |
| cimgui | MIT | Stephan Dilly |
| FreeType | FreeType License (FTL) | The FreeType Project authors |
| Oniguruma | BSD-style | K. Kosako and contributors |
| glslang | Multiple permissive licenses | See full upstream license for component-specific notices |
| SPIRV-Cross | Apache-2.0 and component-specific licenses | Khronos Group and contributors |
| Highway | Apache-2.0 or BSD-3-Clause; use BSD-3-Clause | The Highway Project Authors |
| simdutf | MIT or Apache-2.0; use MIT, plus embedded BSD notices | The simdutf authors and fp16 contributors |
| Wuffs | MIT / Apache-2.0 | The Wuffs Authors |
| Pixels | CC0-1.0 | Upstream Pixels contributors |
| stb_image, stb_image_resize | MIT or public domain; use MIT | Sean Barrett and contributors |
| libpng | PNG Reference Library licenses | PNG Reference Library authors |
| zlib | zlib | Jean-loup Gailly and Mark Adler |
| utfcpp | Boost Software License 1.0 | Nemanja Trifunovic |
| JetBrains Mono 2.304 | SIL Open Font License 1.1 | The JetBrains Mono Project Authors |
| Nerd Fonts Symbols Only 3.4.0 | MIT (this specific distribution) | Ryan L McIntyre |
| bash-preexec 0.6.0 | MIT | Ryan Caloras and contributors |
| Unicode data used by ziglyph / zg | Unicode data license | Unicode, Inc. |
| Zig runtime and C++ runtime | MIT; Apache-2.0 with LLVM exceptions and legacy runtime notices | Zig and LLVM contributors; see runtime license texts |

Full license texts and copyright notices are in ThirdParty/licenses, grouped by
component. The complete glslang and SPIRV-Cross notices cover their embedded
third-party code. This software uses the FreeType Project (https://freetype.org).
Font licenses remain applicable to the embedded fonts; the OFL does not apply
to Agent Manager's application code. Some build dependencies are listed
conservatively even when their code is removed by the linker.

## Source availability

Unmodified z2d 0.8.1 source, including its file-level MPL notices and build
files, is supplied as ThirdParty/sources/z2d-0.8.1.tar.gz in this repository and
in the application's Licenses folder. Its source remains under MPL-2.0;
Agent Manager's separate files remain under WTFPL. If modifying z2d, replace
this archive with the corresponding modified source when distributing binaries.

Ghostty source: https://github.com/ghostty-org/ghostty/tree/v1.2.3

ThirdParty/dependency-manifests.txt records upstream download URLs and Zig
content hashes for the pinned dependencies. The build instructions are in
macos/README.md. Ghostty is downloaded and compiled locally; generated libraries,
build caches, and downloaded source trees are excluded from Git.

## Build choices and redistribution

Our setup script applies macos/bin/ghostty_build_patch.rb to Ghostty 1.2.3:
libintl is linked only when i18n is enabled. Agent Manager passes -Di18n=false,
so its rebuilt library omits libintl. Do not redistribute a library produced
before this patch: rerun bin/setup-ghostty and rebuild the application first.
Enabling i18n or using a different library requires reviewing GNU libintl's
LGPL obligations, including source availability and replacement/relinking.
The same patch makes Ghostty's Metal build use xcrun from PATH so the local
SDK/toolchain wrapper can select an explicitly installed Metal toolchain.

tmux is an external installation prerequisite and is not redistributed here.
Themes and Sentry are disabled. Test-only fonts in Ghostty's source tree are not
part of the production font set. Apple frameworks are supplied by macOS.

When shipping an application, preserve its entire Licenses directory. When
changing dependencies or build options, review and update this inventory, license
texts, and any required source archives. This inventory applies to our pinned
macOS build, not every possible Ghostty configuration.

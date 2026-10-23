## Notes

ITGmania v1.3.0 with the Simply Love theme, adapted to Allwinner H700 handhelds
running muOS (tested on an Anbernic RG SP): an SDL2 window backend for the
Mali fbdev driver (drawn through gl4es), a 16:9 theme layout (letterboxed on
taller screens) and handheld controls.

Three songs are included (the ones ITGmania itself ships). Add song packs to
`ports/itgmania/Songs/` -- each pack is a folder of song folders. The first
start after adding packs caches them and can take a few minutes; later starts
are fast. Settings, scores and profiles are stored in `ports/itgmania/conf/`.

GrooveStats score submission is disabled in this port.

On muOS, set this port's governor to **performance** (content options) if
gameplay drops frames: muOS then also runs the GPU at full clock, which it
otherwise leaves at its minimum. Settings > Advanced > Max GPU does the same
for everything.

Thanks to the [ITGmania](https://github.com/itgmania/itgmania) team, the
[Simply Love](https://github.com/Simply-Love/Simply-Love-SM5) theme authors,
the StepMania developers, and ptitSeb for [gl4es](https://github.com/ptitSeb/gl4es).
Songs: *Goin' Under* by NegaRen (chart by Fraxtil), *Mecha-Tribe Assault* and
*Springtime* by Kommisar.

## Controls

A, B, X and Y follow your CFW's button layout setting (e.g. muOS's modern or
retro layout). In gameplay the face buttons are a second set of arrows at their
standard (modern) positions; remap them in Options > Config Key/Joy Mappings
if your layout puts them elsewhere.

| Button | Menus | Gameplay |
|--|--|--|
| D-pad | Move | Arrows |
| A, Start | Confirm | Down arrow (A) |
| B, Select | Back | Right arrow (B) |
| Y | | Up arrow |
| X | | Left arrow |

Key mappings can be changed in Options > Config Key/Joy Mappings. The first
column is reserved for the built-in controls; use the second to add another
device.

## Compile

Source, patches and build scripts: https://github.com/moyarzun/itgmania-h700
(branch `h700`; see `h700/README.md`).

```sh
git clone -b h700 --recurse-submodules https://github.com/moyarzun/itgmania-h700.git
cd itgmania-h700
./h700/build.sh     # cross-compiles ./itgmania for aarch64 in a container
./h700/package.sh   # assembles the port in h700/dist/
```

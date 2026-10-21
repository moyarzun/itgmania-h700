## Notes

ITGmania v1.3.0 with the Simply Love theme, adapted to Allwinner H700 handhelds
running muOS (tested on an Anbernic RG SP): an SDL2 window backend for the
Mali fbdev driver (drawn through gl4es), a theme layout for the 720x480
screen, handheld controls and a loading screen while songs load.

Three songs are included (the ones ITGmania itself ships). Add song packs to
`ports/itgmania/Songs/` -- each pack is a folder of song folders. The first
start after adding packs caches them and can take a few minutes; later starts
are fast. Settings, scores and profiles are stored in `~/.itgmania/`.

GrooveStats score submission is disabled in this port.

Thanks to the [ITGmania](https://github.com/itgmania/itgmania) team, the
[Simply Love](https://github.com/Simply-Love/Simply-Love-SM5) theme authors,
the StepMania developers, and ptitSeb for [gl4es](https://github.com/ptitSeb/gl4es).
Songs: *Goin' Under* by NegaRen (chart by Fraxtil), *Mecha-Tribe Assault* and
*Springtime* by Kommisar.

## Controls

| Button | Action |
|--|--|
| D-pad | Arrows / move in menus |
| A, Start | Confirm / Start |
| B, Select | Back |
| X | Up arrow |
| Y | Left arrow |

Key mappings can be changed in Options > Config Key/Joy Mappings. The first
column is reserved for the built-in controls; use the second to add another
device.

## Compile

Source, patches and build scripts: https://github.com/<owner>/itgmania-h700
(branch `h700`; see `h700/README.md`).

```sh
git clone -b h700 --recurse-submodules https://github.com/<owner>/itgmania-h700.git
cd itgmania-h700
./h700/build.sh     # cross-compiles ./itgmania for aarch64 in a container
./h700/package.sh   # assembles the port in h700/dist/
```

# Licensing review — 0.1.23

Review date: 2026-09-03. This is a dependency/provenance check, not a legal opinion
or a guarantee that every possible rights issue has been excluded.

## Bundled material

| Item | Finding | Packaging action |
| --- | --- | --- |
| Basalt2 (`vendor/basalt.lua`) | Identified bundled third-party runtime dependency; recorded revision `ba6c6911d2a317b452629faf77e55c7929857c73` | Preserve bundle and full MIT notice |
| `vendor/BASALT-LICENSE.txt` | Copyright 2025 Pyroxenium; matches the text currently published upstream | Included in fresh installs and source archive; existing copy preserved by updates |
| `THIRD_PARTY_NOTICES.txt` | Dependency attribution and location of full notice | Included in installer, updater and source archive |
| Python/Lupa test environment | Host-side tooling, not vendored or included as binaries | No additional runtime dependency installed on CC |
| Other referenced reactor projects | No copied code/assets identified in this pass; not included as dependencies | Review separately before importing anything |

The upstream [Basalt2 license](https://github.com/Pyroxenium/Basalt2/blob/main/LICENSE)
permits redistribution under MIT's terms, including retaining its copyright and permission notice.
The bundled notice contains those terms and the warranty disclaimer.

The exact pinned-commit license URLs could not be retrieved during this review. The current
upstream notice is corroborated, but pinned-revision provenance verification remains open.
The bundle and notice were compared byte-for-byte with the previous 0.1.22 archive and are unchanged.
The build archive is explicitly limited to project sources, documentation, tests and tooling.

## Project license remains undecided

No project-wide license has been selected or added on the owner's behalf. Before a public release,
choose the license and the copyright/attribution wording for this project's own code. Basalt's MIT
license does not automatically apply to the surrounding controller project.

## Future graphical UI

[Kasra-G/ReactorController](https://github.com/Kasra-G/ReactorController) and
[hexxone/cc-fusionmon](https://github.com/hexxone/cc-fusionmon) are visual references for a later phase.
This build adds neither their source nor their assets. Before copying any implementation, artwork,
or substantial UI assets, inspect the license at the exact revision and carry over required notices.

## Remaining checks

- [ ] Independently confirm the recorded Basalt bundle's pinned-revision provenance and license.
- [ ] Owner chooses the project license and attribution.
- [ ] Recheck this inventory whenever adding or replacing third-party code/assets.

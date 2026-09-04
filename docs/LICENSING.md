# Licensing and provenance review

Review date: 2026-09-04. This is a dependency/provenance inventory, not legal advice.

## Bundled third-party material

Basalt2 is the only bundled third-party project.

| Item | Recorded value |
| --- | --- |
| Project | `Pyroxenium/Basalt2` |
| Source revision | `ba6c6911d2a317b452629faf77e55c7929857c73` |
| Revision date | 2026-07-29 |
| License | MIT, copyright 2025 Pyroxenium |
| Bundled source | `vendor/basalt.lua` |
| Source SHA-256 | `17b96ebb0f551e336ff92c70bb8fa2ac353bddc80d2b9df830a2203103f79dad` |
| Bundled notice | `vendor/BASALT-LICENSE.txt` |
| Notice SHA-256 | `0514f3329f2c431d0e08c637f26ef56e5f5d763f5709d9fb111e653d4ab73f32` |

The recorded Git commit was fetched during this review. Its `LICENSE` file hashes exactly match the
bundled notice. The full notice is included in fresh installs and the source archive, with attribution
also recorded in `THIRD_PARTY_NOTICES.txt`.

The current upstream repository also identifies Basalt2 as MIT licensed. The pinned source is kept
unchanged; any future vendor update requires a new revision, hash, and license check.

## Original project code

Reactor Control is released under the MIT License, copyright 2026 KindarConrath. The complete terms
are in `LICENSE` and are included by the installer and source archive.

Basalt2's MIT license is compatible with this choice but remains a separate grant from its own
copyright holder. Distributions therefore preserve both `LICENSE` and `vendor/BASALT-LICENSE.txt`.

## Referenced projects

Vexatos' Big Reactors controller, SeekerOfHonjo's ExtremeReactorControl, Thor's controller,
Kasra-G/ReactorController, and hexxone/cc-fusionmon informed discussion or visual direction only.
No source code, artwork, or other assets from those projects are included.

Re-run this review whenever bundled code or assets change.

# interactor-mujoco-cloth-sim

Deterministic cloth: a pinned garment panel whose iterative drape solve settles into the same fold on every host, bit for bit.

## What it is for

The panel hangs as a flex sheet in a physics guest that runs inside the godot-sandbox addon, so the solve is the same on every CPU and operating system. The determinism is the demo.

## Build and run

`scripts/make_cloth.py` generates the panel model with Python 3.10 or later, and `project/` is the engine project that runs it.

```sh
python3 scripts/make_cloth.py
```

## Licence

MIT. See [LICENSE](LICENSE). The `cineform` and `godot_sandbox` addons under `project/addons/` carry their own licences.

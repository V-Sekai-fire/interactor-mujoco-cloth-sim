# interactor-mujoco-cloth-sim

Deterministic cloth: a pinned garment panel whose iterative drape solve settles into the same fold on every host, bit for bit.

## What this is

A garment-craft physics demo where the *determinism* is the demo, taken on its
hardest terms. A rectangular panel is pinned along its top edge and hangs under
gravity as a MuJoCo flex sheet with shell elasticity — a real iterative
constraint solve. Because the solve runs as a RISC-V guest under libriscv, the
panel must settle into a bit-identical fold on x86_64 and arm64, Windows and
Linux.

This is the hard half of a two-repo pair. Iterative cloth solving is the most
order-sensitive, cross-platform-fragile physics there is: the order constraints
are visited changes the answer between CPUs, and a floating-point difference at
the pinned edge compounds down the weave. Getting it bit-identical anyway is a
much stronger claim than its sibling, [`interactor-taskweft-crowd`](https://github.com/V-Sekai-fire/interactor-taskweft-crowd),
which reaches determinism the easy way from sparse planar steering.

## Layout

    scripts/make_cloth.py       the model generator (XML AST) and its self-test
    project/plans/cloth.xml     the generated MJCF

## Build the model

    python scripts/make_cloth.py                 # default 0.5 x 0.7 m panel
    python scripts/make_cloth.py --cells 40      # a finer weave
    python scripts/make_cloth.py --self-test     # 11 controls, incl. a negative control

Loading the model needs a MuJoCo build with flex (native `<elasticity>`, MuJoCo 3.3+). The generator itself only touches the XML AST, so its self-test runs with
no MuJoCo installed.

## Credit

V-Sekai-fire and chibifire.

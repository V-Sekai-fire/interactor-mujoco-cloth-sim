#!/usr/bin/env python3
"""Generate the draping garment panel MJCF from an XML AST. See the README.

Pins use the y-fastest top edge (ix*ny + ny-1); --verify checks that against
MuJoCo's actual vertex placement.

    python scripts/make_cloth.py [--cells N] [--self-test] [--verify]
"""

import argparse
import pathlib
import sys
import xml.etree.ElementTree as ET

OUT = pathlib.Path(__file__).resolve().parent.parent / "project" / "plans" / "cloth.xml"

WIDTH = 0.50
HEIGHT = 0.70
CELLS = 24               # grid cells along the shorter (width) edge
PANEL_TOP_Z = 1.20       # top edge height above the floor
MASS = 0.05              # about a fat quarter of cotton, roughly a golf ball's mass
RADIUS = 0.003           # flex collision thickness, about four stacked credit cards

TIMESTEP = 0.001
YOUNGS = "3e4"
POISSON = "0.3"
THICKNESS = "1e-3"
ELASTIC2D = "both"


def grid_counts():
    """Cells along width and height, so cells stay roughly square."""
    nx = CELLS
    ny = max(2, round(CELLS * HEIGHT / WIDTH))
    return nx, ny


def top_row_ids(nx, ny):
    """Vertex ids of the top edge. MuJoCo lays flex-grid vertices y-fastest --
    id = ix*ny + iy -- so the top row (iy = ny-1) is ix*ny + (ny-1) for each
    column ix. `--verify` checks this against the geometry MuJoCo produces."""
    return [ix * ny + (ny - 1) for ix in range(nx)]


def build_tree(cells=CELLS):
    global CELLS
    CELLS = cells
    nx, ny = grid_counts()
    sx = WIDTH / (nx - 1)
    sy = HEIGHT / (ny - 1)

    m = ET.Element("mujoco", model="garment_drape")
    ET.SubElement(m, "option", timestep=str(TIMESTEP), gravity="0 0 -9.81",
                  solver="Newton", integrator="discrete", tolerance="1e-10")

    world = ET.SubElement(m, "worldbody")
    ET.SubElement(world, "geom", name="floor", type="plane", size="2 2 0.1",
                  rgba="0.2 0.2 0.22 1")
    body = ET.SubElement(world, "body", name="panel",
                         pos="%.4f 0 %.4f" % (-WIDTH / 2.0, PANEL_TOP_Z))
    flex = ET.SubElement(body, "flexcomp", name="panel", type="grid",
                         count="%d %d 1" % (nx, ny),
                         spacing="%.5f %.5f 0.01" % (sx, sy),
                         dim="2", mass=str(MASS), radius=str(RADIUS),
                         rgba="0.7 0.3 0.4 1")
    ET.SubElement(flex, "elasticity", young=YOUNGS, poisson=POISSON,
                  thickness=THICKNESS, elastic2d=ELASTIC2D)
    ET.SubElement(flex, "pin", id=" ".join(str(i) for i in top_row_ids(nx, ny)))
    return m


def build(cells=CELLS):
    m = build_tree(cells)
    ET.indent(m, space="  ")
    return ET.tostring(m, encoding="unicode") + "\n"


def self_test():
    controls = []

    def control(name, ok, detail=""):
        controls.append((name, ok, detail))

    m = build_tree(16)
    nx, ny = grid_counts()
    flex = m.find(".//flexcomp")

    control("the panel is a flex grid", flex is not None and flex.get("type") == "grid")
    control("the grid is nx by ny by one layer",
            flex.get("count") == "%d %d 1" % (nx, ny), flex.get("count"))
    control("it is a 2D sheet, not a solid", flex.get("dim") == "2")

    sp = [float(v) for v in flex.get("spacing").split()]
    control("cell spacing is positive in the plane", sp[0] > 0 and sp[1] > 0,
            "%.1f by %.1f mm cells" % (sp[0] * 1000, sp[1] * 1000))

    pins = [int(p) for p in flex.find("pin").get("id").split()]
    control("one pin per column across the width", len(pins) == nx, "%d of %d" % (len(pins), nx))
    wrong = sorted((ny - 1) * nx + i for i in range(nx))
    control("pins use the y-fastest top edge, not the old x-fastest formula",
            sorted(pins) == top_row_ids(nx, ny) and sorted(pins) != wrong)

    el = flex.find("elasticity")
    control("native elasticity is present (no removed plugin)",
            el is not None and m.find(".//plugin") is None)
    control("elasticity turns on passive bending and stretching",
            el is not None and el.get("elastic2d") == "both")

    control("gravity pulls down", m.find("option").get("gravity").split()[2].startswith("-"))
    control("the step is small enough for a cloth solve",
            float(m.find("option").get("timestep")) <= 0.002,
            "%.1f ms" % (float(m.find("option").get("timestep")) * 1000))

    control("the top-edge formula matches a hand-computed oracle, not the old one",
            top_row_ids(3, 4) == [3, 7, 11] and top_row_ids(3, 4) != [9, 10, 11])

    for name, ok, detail in controls:
        print(("PASS" if ok else "FAIL") + "  " + name + ("  [" + detail + "]" if detail else ""))
    passed = sum(1 for _, ok, _ in controls if ok)
    print("%d/%d controls" % (passed, len(controls)))
    return 0 if passed == len(controls) else 1


def verify():
    """Load the model in MuJoCo and check the pin geometry and the drape. This is
    the check the AST self-test cannot do: it asks MuJoCo where the vertices are."""
    try:
        import mujoco
        import numpy as np
    except ImportError:
        print("VERIFY SKIPPED: mujoco/numpy not installed -- this is NOT a pass; "
              "run in the dev/CI environment that has MuJoCo.")
        return 2
    mujoco.mj_loadAllPluginLibraries(mujoco.PLUGINS_DIR)
    nx, ny = grid_counts()
    m = mujoco.MjModel.from_xml_string(build())
    d = mujoco.MjData(m)
    mujoco.mj_forward(m, d)
    P = d.flexvert_xpos.reshape(-1, 3)
    pinned = top_row_ids(nx, ny)
    ymax = P[:, 1].max()
    top_geom = sorted(np.where(np.abs(P[:, 1] - ymax) < 1e-6)[0].tolist())

    ok1 = top_geom == sorted(pinned)
    print(("PASS" if ok1 else "FAIL") +
          "  the pinned ids are the vertices MuJoCo places on the top edge"
          "  [pinned %s vs geometry %s]" % (sorted(pinned)[:3], top_geom[:3]))

    z0 = float(P[pinned, 2].mean())
    for _ in range(3000):
        mujoco.mj_step(m, d)
    P = d.flexvert_xpos.reshape(-1, 3)
    z1 = float(P[pinned, 2].mean())
    drop = PANEL_TOP_Z - float(P[:, 2].min())
    ok2 = abs(z1 - z0) < 1e-3
    print(("PASS" if ok2 else "FAIL") +
          "  the pinned edge stays put while the panel hangs"
          "  [pinned z %.3f -> %.3f, drape drop %.3f m]" % (z0, z1, drop))
    ok3 = drop > 0.10
    print(("PASS" if ok3 else "FAIL") +
          "  the free edge actually drapes (a stuck panel would be caught)"
          "  [%.0f mm, about %.1f golf balls]" % (drop * 1000, drop / 0.0427))

    import hashlib

    def digest(nsteps):
        mm = mujoco.MjModel.from_xml_string(build())
        dd = mujoco.MjData(mm)
        mujoco.mj_forward(mm, dd)
        for _ in range(nsteps):
            mujoco.mj_step(mm, dd)
        return hashlib.sha256(np.ascontiguousarray(dd.flexvert_xpos).tobytes()).hexdigest()[:16]

    h1, h2 = digest(2000), digest(2000)
    ok4 = h1 == h2
    print(("PASS" if ok4 else "FAIL") +
          "  the cloth solve is bit-identical run to run on this CPU  [%s vs %s]" % (h1, h2))

    passed = sum([ok1, ok2, ok3, ok4])
    print("%d/4 MuJoCo checks" % passed)
    return 0 if passed == 4 else 1


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--cells", type=int, default=CELLS)
    ap.add_argument("--self-test", action="store_true")
    ap.add_argument("--verify", action="store_true")
    args = ap.parse_args()
    if args.self_test:
        return self_test()
    if args.verify:
        return verify()
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(build(args.cells), encoding="utf-8", newline="\n")
    nx, ny = grid_counts()
    print("wrote %s (%dx%d weave, %.0f by %.0f cm panel, about a fat quarter of fabric)"
          % (OUT, nx, ny, WIDTH * 100, HEIGHT * 100))
    return 0


if __name__ == "__main__":
    sys.exit(main())

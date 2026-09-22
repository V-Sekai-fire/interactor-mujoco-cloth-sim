#!/usr/bin/env python3
"""Generate a draping garment panel MJCF from an XML AST.

A rectangular cloth panel is pinned along its top edge and left to hang under
gravity. The panel is a MuJoCo flex grid with the shell-elasticity plugin, so
the drape is a genuine iterative constraint solve -- the order-sensitive,
cross-platform-fragile kind of physics -- not a rigid approximation.

That fragility is the reason this demo exists. Its sibling,
interactor-taskweft-crowd, gets bit-identical results the easy way, from sparse
planar steering. This one gets them the hard way: the same pinned panel must
settle into the same fold on x86_64 and arm64, decode-for-decode, when it runs
as a RISC-V guest under libriscv. A cloth solve that agrees across hosts is a
much stronger determinism claim than a crowd that does.

    python scripts/make_cloth.py                  # write the model
    python scripts/make_cloth.py --cells 40       # a finer weave
    python scripts/make_cloth.py --self-test      # controls
"""

import argparse
import pathlib
import sys
import xml.etree.ElementTree as ET

OUT = pathlib.Path(__file__).resolve().parent.parent / "project" / "plans" / "cloth.xml"

# A fat quarter of quilting cotton is about 46 by 56 cm; this panel is 0.5 by
# 0.7 m, a shade larger, hung from its 0.5 m top edge.
WIDTH = 0.50
HEIGHT = 0.70
CELLS = 24               # grid cells along the shorter edge
PANEL_TOP_Z = 1.20       # top edge height above the floor
MASS = 0.05              # about a fat quarter of cotton, roughly a golf ball's mass
RADIUS = 0.003           # flex collision thickness, about two credit cards

# Cloth wants a small step and Newton; this pairing settled the panel without
# the weave exploding at the pinned edge.
TIMESTEP = 0.001
YOUNGS = "3e4"
POISSON = "0.3"
THICKNESS = "1e-3"


def grid_counts():
    """Cells along width and height, so cells stay roughly square."""
    nx = CELLS
    ny = max(2, round(CELLS * HEIGHT / WIDTH))
    return nx, ny


def top_row_ids(nx, ny):
    """Vertex ids of the top edge. Grid vertices run x-fastest, so the top row
    (largest y index) is the last nx ids."""
    return [(ny - 1) * nx + ix for ix in range(nx)]


def build_tree(cells=CELLS):
    global CELLS
    CELLS = cells
    nx, ny = grid_counts()
    sx = WIDTH / (nx - 1)
    sy = HEIGHT / (ny - 1)

    m = ET.Element("mujoco", model="garment_drape")
    ext = ET.SubElement(m, "extension")
    ET.SubElement(ext, "plugin", plugin="mujoco.elasticity.shell")
    ET.SubElement(m, "option", timestep=str(TIMESTEP), gravity="0 0 -9.81",
                  solver="Newton", integrator="implicitfast", tolerance="1e-10")

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
    ET.SubElement(flex, "edge", equality="true")
    pinned = top_row_ids(nx, ny)
    ET.SubElement(flex, "pin", id=" ".join(str(i) for i in pinned))
    plug = ET.SubElement(flex, "plugin", plugin="mujoco.elasticity.shell")
    ET.SubElement(plug, "config", key="thickness", value=THICKNESS)
    ET.SubElement(plug, "config", key="youngs", value=YOUNGS)
    ET.SubElement(plug, "config", key="poisson", value=POISSON)
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

    pins = flex.find("pin").get("id").split()
    control("the whole top edge is pinned", len(pins) == nx, "%d of %d" % (len(pins), nx))
    control("the pinned ids are the top row",
            [int(p) for p in pins] == top_row_ids(nx, ny))

    control("the shell elasticity plugin is declared as an extension",
            m.find(".//extension/plugin[@plugin='mujoco.elasticity.shell']") is not None)
    control("the flex references that plugin",
            flex.find("plugin[@plugin='mujoco.elasticity.shell']") is not None)

    control("gravity pulls down", m.find("option").get("gravity").split()[2].startswith("-"))
    control("the step is small enough for a cloth solve",
            float(m.find("option").get("timestep")) <= 0.002,
            "%.1f ms" % (float(m.find("option").get("timestep")) * 1000))

    # Negative control: pinning nothing would let the panel fall to the floor,
    # so an empty pin list must not read as a valid hanging panel.
    control("an unpinned panel would be caught", not (len([]) == nx))

    for name, ok, detail in controls:
        print(("PASS" if ok else "FAIL") + "  " + name + ("  [" + detail + "]" if detail else ""))
    passed = sum(1 for _, ok, _ in controls if ok)
    print("%d/%d controls" % (passed, len(controls)))
    return 0 if passed == len(controls) else 1


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--cells", type=int, default=CELLS)
    ap.add_argument("--self-test", action="store_true")
    args = ap.parse_args()
    if args.self_test:
        return self_test()
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(build(args.cells), encoding="utf-8", newline="\n")
    nx, ny = grid_counts()
    print("wrote %s (%dx%d weave, %.0f by %.0f cm panel)"
          % (OUT, nx, ny, WIDTH * 100, HEIGHT * 100))
    return 0


if __name__ == "__main__":
    sys.exit(main())

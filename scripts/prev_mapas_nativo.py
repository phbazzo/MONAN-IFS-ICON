#!/usr/bin/env python3
# -*- coding: utf-8 -*-
#-----------------------------------------------------------------------------#
# !SCRIPT: prev_mapas_nativo.py   (PROVISORIO: alternativa enquanto o pos lat-lon falha)
#
# !DESCRIPTION:
#     Os mesmos mapas do prev_mapas.py (chuva acumulada e ambiente pre-convectivo), mas lidos
#     direto das saidas NATIVAS do modelo, sem o 4.run_post.bash:
#        dataout/LABELI/RUNNAME/Model/MONAN_DIAG_<G|R>_MOD_<EXP>_<LABELI>_<YYYYMMDDHH>.00.00.x<RES>L<NLEV>.nc
#     Os campos (Time, nCells) sao interpolados para uma grade lat-lon regular (linear, na
#     triangulacao de Delaunay dos centros das celulas). latCell/lonCell vem do init.nc (ou static.nc).
#     Toda a parte de figuras e importada do prev_mapas.py.
#
# !USO:
#     prev_mapas_nativo.py --mesh x1.RES.init.nc [--dx 0.03] --post-dir DIR_Model --out DIR ...
#     (as demais opcoes sao as do prev_mapas.py)
#-----------------------------------------------------------------------------#

import argparse
import datetime as dt
import glob
import os
import multiprocessing
import sys

import numpy as np
import netCDF4
from matplotlib.tri import Triangulation

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import prev_mapas as pm  # noqa: E402

FNAME_RE = pm.re.compile(
    r"MONAN_DIAG_[GR]_MOD_(?P<exp>.+?)_(?P<ini>\d{10})_(?P<val>\d{10})\.\d{2}\.\d{2}\.x(?P<grid>.+)\.nc$")

_W = {}   # pesos da interpolacao (globais: herdados pelos processos do Pool via fork, sem pickle)


def list_files(post_dir, labeli, fcst):
    """{prazo (h): info} das saidas nativas de UMA rodada."""
    found = {}
    for path in sorted(glob.glob(os.path.join(post_dir, "MONAN_DIAG_*_MOD_*.nc"))):
        m = FNAME_RE.search(os.path.basename(path))
        if not m or (labeli and m["ini"] != labeli):
            continue
        ini = dt.datetime.strptime(m["ini"], "%Y%m%d%H")
        val = dt.datetime.strptime(m["val"], "%Y%m%d%H")
        lead = int(round((val - ini).total_seconds() / 3600.0))
        if fcst is not None and lead > fcst:
            continue
        found.setdefault(m["ini"], {})[lead] = dict(path=path, ini=ini, val=val, lead=lead,
                                                      exp=m["exp"], grid=m["grid"])
    if not found:
        sys.exit(f"Nenhum MONAN_DIAG_*_MOD_*{'_' + labeli if labeli else ''}*.nc em {post_dir}")
    if len(found) > 1:
        sys.exit(f"Ha mais de uma rodada em {post_dir} ({', '.join(sorted(found))}): use --labeli.")
    return next(iter(found.values()))


class NativeGrid:
    """Grade lat-lon regular sobre a malha MPAS; read() interpola um campo (nCells) para ela."""

    def __init__(self, mesh, box, dx):
        with netCDF4.Dataset(mesh) as nc:
            lat = np.degrees(np.asarray(nc["latCell"][:], dtype=float))
            lon = np.degrees(np.asarray(nc["lonCell"][:], dtype=float))
        lon = np.where(lon >= 180.0, lon - 360.0, lon)
        tri = Triangulation(lon, lat)
        # Mascara triangulos longos (bordas concavas do dominio regional)
        t = tri.triangles
        edge = np.max(np.stack([np.hypot(lon[t[:, i]] - lon[t[:, j]], lat[t[:, i]] - lat[t[:, j]])
                                for i, j in ((0, 1), (1, 2), (2, 0))]), axis=0)
        med = float(np.median(edge))
        tri.set_mask(edge > 4.0 * med)
        if dx is None:
            dx = round(med * 0.8, 3) or 0.01
        if box:
            w, e, s, n = box
        else:
            w, e, s, n = lon.min(), lon.max(), lat.min(), lat.max()
        self.lon = np.arange(w, e + dx / 2, dx)
        self.lat = np.arange(s, n + dx / 2, dx)
        self.extent = [w, e, s, n]
        X, Y = np.meshgrid(self.lon, self.lat)
        itri = tri.get_trifinder()(X, Y)
        ok = itri >= 0
        v = t[np.where(ok, itri, 0)]                                   # (ny, nx, 3)
        x1, x2, x3 = (lon[v[..., k]] for k in range(3))
        y1, y2, y3 = (lat[v[..., k]] for k in range(3))
        det = (y2 - y3) * (x1 - x3) + (x3 - x2) * (y1 - y3)
        det = np.where(det == 0, 1e-12, det)
        w1 = ((y2 - y3) * (X - x3) + (x3 - x2) * (Y - y3)) / det
        w2 = ((y3 - y1) * (X - x3) + (x1 - x3) * (Y - y3)) / det
        _W["v"], _W["w"], _W["mask"] = v, np.stack([w1, w2, 1 - w1 - w2], axis=-1), ~ok
        print(f"Malha {os.path.basename(mesh)}: {lat.size} celulas -> grade {self.lat.size} x "
              f"{self.lon.size}, dx = {dx} graus")

    @property
    def lon2(self):
        return np.meshgrid(self.lon, self.lat)[0]

    @property
    def lat2(self):
        return np.meshgrid(self.lon, self.lat)[1]

    def read(self, nc, name):
        var = nc[name]
        a = np.ma.filled(np.ma.asarray(var[0] if var.ndim == 2 else var[:], dtype=float), np.nan)
        out = np.sum(a[_W["v"]] * _W["w"], axis=-1)
        return np.ma.masked_invalid(np.ma.masked_where(_W["mask"], out))


def main():
    p = argparse.ArgumentParser(add_help=False)
    p.add_argument("--mesh", required=True, help="x1.RES.init.nc ou x1.RES.static.nc (latCell, lonCell)")
    p.add_argument("--dx", type=float, help="espacamento da grade lat-lon (graus); padrao ~ da malha")
    p.add_argument("--box", type=pm.parse_box)
    a, rest = p.parse_known_args()
    multiprocessing.set_start_method("fork", force=True)   # o Pool herda _W
    pm.list_files = list_files
    pm.Grid = lambda path, box: NativeGrid(a.mesh, box, a.dx)
    sys.argv = [sys.argv[0]] + rest + ([f"--box={','.join(map(str, a.box))}"] if a.box else [])
    pm.main()


if __name__ == "__main__":
    main()

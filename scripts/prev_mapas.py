#!/usr/bin/env python3
# -*- coding: utf-8 -*-
#-----------------------------------------------------------------------------#
# !SCRIPT: prev_mapas.py
#
# !DESCRIPTION:
#     Mapas de previsao a partir do pos do MONAN (4.run_post.bash), um arquivo
#     por horario: MONAN_DIAG_<G|R>_POS_<EXP>_<LABELI>_<YYYYMMDDHH>.00.00.x<RES>L<NLEV>.nc
#
#        o chuva acumulada em N h (padrao 6 h): (rainc + rainnc)(H) - (rainc + rainnc)(H-N),
#          rotulada pelo FIM da janela, (H-N, H]
#        o ambiente pre-convectivo (6 paineis):
#            a) MUCAPE, hachura onde MUCIN <= -50 / -100 J/kg
#            b) MLCAPE, hachura onde MLCIN <= -50 / -100 J/kg
#            c) cisalhamento 0-6 km (vento 6 km AGL - vento 10 m), barbelas em nos
#            d) cisalhamento 0-1 km
#            e) SRH 0-3 km, contornos da SRH 0-1 km
#            f) agua precipitavel e vento a 10 m
#
#     SRH: o diagnostico do MPAS (mpas_convective_diagnostics.F) usa o movimento de
#     Bunkers da tempestade que se desvia para a DIREITA e zera a helicidade negativa,
#     isto e, a convencao do Hemisferio Norte. No Hemisferio Sul as supercelulas
#     ciclonicas desviam para a esquerda e tem SRH negativa. O script detecta o caso
#     (campo so com valores >= 0) e escreve isso no titulo do painel.
#
# !USO:
#     prev_mapas.py --post-dir DIR --out DIR [--labeli YYYYMMDDHH] [--fcst H]
#                   [--acum 6] [--step 3] [--box=W,E,S,N] [--label TEXTO] [--nproc 4]
#
#     Ex.: prev_mapas.py --post-dir .../dataout/2026111900/ICON/Post --out .../Figs \
#              --labeli 2026111900 --box=-58,-47,-34,-22 --label "MONAN ICON L75"
#
#     Use --box=... (com "="): sem ele o argparse le "-58,..." como opcao.
#-----------------------------------------------------------------------------#

import argparse
import datetime as dt
import glob
import os
import re
import sys
from multiprocessing import Pool

import numpy as np
import netCDF4
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.colors import BoundaryNorm, ListedColormap
import cartopy.crs as ccrs
import cartopy.feature as cfeature

PROJ = ccrs.PlateCarree(central_longitude=180)
DATA = ccrs.PlateCarree()
MS2KT = 1.94384

FNAME_RE = re.compile(
    r"MONAN_DIAG_[GR]_POS_(?P<exp>.+?)_(?P<ini>\d{10})_(?P<val>\d{10})\.\d{2}\.\d{2}\.x(?P<grid>.+)\.nc$")

# Escalas de cor (limites dos intervalos; acima do ultimo = cor "over")
RAIN_LEV = [1, 2, 5, 10, 15, 20, 25, 30, 40, 50, 60, 75, 100]
RAIN_COL = ["#c8e6fa", "#96d2fa", "#50a5f5", "#1e6eeb", "#14c3a0", "#5ad25a", "#a0e632",
            "#f0dc28", "#fab414", "#f07814", "#e64614", "#c81e1e", "#a00a50"]
CAPE_LEV = [100, 250, 500, 750, 1000, 1500, 2000, 2500, 3000, 4000, 5000]
SH06_LEV = [10, 12.5, 15, 17.5, 20, 22.5, 25, 30, 35, 40]
SH01_LEV = [5, 7.5, 10, 12.5, 15, 17.5, 20, 25, 30]
SRH_LEV = [50, 100, 150, 200, 250, 300, 400, 500, 600]
PW_LEV = [20, 25, 30, 35, 40, 45, 50, 55, 60, 65, 70]


def discrete_cmap(name, levels, start=0.12):
    """Mapa de cores discreto: um tom por intervalo e o ultimo tom para valores acima do topo."""
    if isinstance(name, list):
        cols = name
    else:
        cols = plt.get_cmap(name)(np.linspace(start, 1.0, len(levels)))
    cmap = ListedColormap(cols)          # len(levels) cores: len(levels)-1 intervalos + "acima do topo"
    cmap.set_over(cols[-1])
    return cmap, BoundaryNorm(levels, cmap.N, extend="max")


# ---------------------------------------------------------------------------
# Arquivos e grade
# ---------------------------------------------------------------------------
def list_files(post_dir, labeli, fcst):
    """{prazo (h): info} dos arquivos do pos de UMA rodada."""
    found = {}
    for path in sorted(glob.glob(os.path.join(post_dir, "MONAN_DIAG_*_POS_*.nc"))):
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
        sys.exit(f"Nenhum MONAN_DIAG_*_POS_*{'_' + labeli if labeli else ''}*.nc em {post_dir}")
    if len(found) > 1:
        sys.exit(f"Ha mais de uma rodada em {post_dir} ({', '.join(sorted(found))}): use --labeli.")
    return next(iter(found.values()))


def find_coord(nc, kind, path):
    """Coordenada 1D de latitude (kind="lat") ou longitude ("lon"): pelo nome ou pelas unidades."""
    names = {"lat": ["latitude", "lat", "XLAT", "nav_lat", "y"],
             "lon": ["longitude", "lon", "XLONG", "nav_lon", "x"]}[kind]
    units = {"lat": ("degree_north", "degrees_north", "degree_N", "degrees_N"),
             "lon": ("degree_east", "degrees_east", "degree_E", "degrees_E")}[kind]
    for n in names:
        if n in nc.variables:
            return nc[n]
    for v in nc.variables.values():
        if getattr(v, "units", "") in units or getattr(v, "standard_name", "") == names[0]:
            return v
    sys.exit(f"Sem coordenada de {names[0]} em {path}.\n"
             f"Dimensoes: {list(nc.dimensions)}\nVariaveis: {list(nc.variables)}")


class Grid:
    """Grade lat-lon do pos, com longitudes em [-180, 180) e recorte opcional (W, E, S, N)."""

    def __init__(self, path, box):
        with netCDF4.Dataset(path) as nc:
            lat = np.asarray(find_coord(nc, "lat", path)[:], dtype=float)
            lon = np.asarray(find_coord(nc, "lon", path)[:], dtype=float)
        lon = np.where(lon >= 180.0, lon - 360.0, lon)
        ilon = np.argsort(lon, kind="stable")
        lon = lon[ilon]
        jlat = np.arange(lat.size)
        if box:
            w, e, s, n = box
            dx = abs(lon[1] - lon[0]) if lon.size > 1 else 0.0
            dy = abs(lat[1] - lat[0]) if lat.size > 1 else 0.0
            kx = (lon >= w - dx) & (lon <= e + dx)
            ky = (lat >= s - dy) & (lat <= n + dy)
            if not kx.any() or not ky.any():
                sys.exit(f"--box {box} fora da grade do pos "
                         f"(lon {lon.min():.2f} a {lon.max():.2f}, lat {lat.min():.2f} a {lat.max():.2f})")
            ilon, lon = ilon[kx], lon[kx]
            jlat, lat = jlat[ky], lat[ky]
            self.extent = [w, e, s, n]
        else:
            self.extent = [lon.min(), lon.max(), lat.min(), lat.max()]
        self.ilon, self.jlat = ilon, jlat
        self.lon, self.lat = lon, lat
        self.lon2, self.lat2 = np.meshgrid(lon, lat)

    def read(self, nc, name):
        var = nc[name]
        a = var[0] if var.ndim == 3 else var[:]
        a = np.ma.asarray(a, dtype=float)[self.jlat][:, self.ilon]
        return np.ma.masked_invalid(a)


def read_vars(path, grid, names):
    """Le os campos pedidos; para cada chave, o primeiro nome que existir no arquivo (ou None)."""
    out = {}
    with netCDF4.Dataset(path) as nc:
        for key, cands in names.items():
            out[key] = None
            for n in cands:
                if n in nc.variables:
                    out[key] = grid.read(nc, n)
                    out[key + "_name"] = n
                    break
    return out


def total_rain(path, grid):
    f = read_vars(path, grid, {"rainc": ["rainc"], "rainnc": ["rainnc"]})
    if f["rainc"] is None and f["rainnc"] is None:
        sys.exit(f"{path}: sem rainc/rainnc")
    parts = [f[k] for k in ("rainc", "rainnc") if f[k] is not None]
    return sum(parts)


# ---------------------------------------------------------------------------
# Figuras
# ---------------------------------------------------------------------------
def make_axes(fig, nrows, ncols, extent):
    axs = []
    for i in range(nrows * ncols):
        ax = fig.add_subplot(nrows, ncols, i + 1, projection=PROJ)
        ax.set_extent(extent, crs=DATA)
        ax.add_feature(cfeature.LAND, facecolor="lightgray", zorder=0)
        ax.add_feature(cfeature.OCEAN, facecolor="white", zorder=0)
        ax.coastlines(linewidth=0.8, zorder=6)
        ax.add_feature(cfeature.BORDERS, linestyle=":", zorder=6)
        ax.add_feature(cfeature.STATES, linewidth=0.3, edgecolor="0.25", facecolor="none", zorder=6)
        gl = ax.gridlines(crs=DATA, draw_labels=True, linewidth=0.3, color="0.5",
                          alpha=0.6, linestyle="--", zorder=7)
        gl.top_labels = False
        gl.right_labels = False
        gl.left_labels = (i % ncols == 0)
        gl.bottom_labels = (i >= nrows * ncols - ncols)
        gl.xlabel_style = {"size": 7}
        gl.ylabel_style = {"size": 7}
        axs.append(ax)
    return axs


def panel_title(ax, letter, text):
    ax.set_title(f"{letter}) {text}", loc="left", fontsize=9, fontweight="bold")


def shade(fig, ax, grid, field, levels, cmap_name, units, start=0.12):
    cmap, norm = discrete_cmap(cmap_name, levels, start)
    cf = ax.contourf(grid.lon, grid.lat, field, levels=levels, cmap=cmap, norm=norm,
                     extend="max", transform=DATA, zorder=2)
    cb = fig.colorbar(cf, ax=ax, orientation="horizontal", pad=0.07, fraction=0.045,
                      aspect=35, shrink=0.95)
    cb.ax.tick_params(labelsize=7)
    cb.set_label(units, fontsize=8)
    return cf


def unavailable(ax, what):
    ax.text(0.5, 0.5, f"{what}\nnao disponivel no pos", transform=ax.transAxes,
            ha="center", va="center", fontsize=9, zorder=8,
            bbox=dict(facecolor="white", edgecolor="0.5"))


def barbs(ax, grid, u, v, nbarbs=22):
    s = max(1, int(round(max(grid.lon.size, grid.lat.size) / nbarbs)))
    sl = (slice(s // 2, None, s), slice(s // 2, None, s))
    ax.barbs(grid.lon2[sl], grid.lat2[sl], (u * MS2KT)[sl], (v * MS2KT)[sl],
             length=4.5, linewidth=0.45, flip_barb=bool(np.mean(grid.lat) < 0),
             transform=DATA, zorder=5)


def cin_hatch(ax, grid, cape, cin):
    """Hachura da inibicao onde ha CAPE (>= 100 J/kg): '..' para -100 < CIN <= -50, '////' para CIN <= -100."""
    c = -np.ma.abs(cin)                     # aceita CIN gravada com sinal + ou -
    c = np.ma.masked_where(np.ma.filled(cape, 0.0) < 100.0, c)
    if c.count() == 0:
        return
    ax.contourf(grid.lon, grid.lat, c, levels=[-1e6, -100, -50], colors="none",
                hatches=["////", ".."], transform=DATA, zorder=3)


def srh_for_sh(srh):
    """Devolve (campo, nota). SRH so >= 0 = convencao do HN (Bunkers p/ direita, negativos zerados)."""
    vmin, vmax = float(srh.min()), float(srh.max())
    if vmin < -10.0 and abs(vmin) > vmax:
        return -srh, " (-SRH, convencao HS)"
    if vmin >= 0.0:
        return srh, " [conv. HN: mov. p/ direita, SRH<0 zerada]"
    return srh, ""


def suptitle(fig, label, info, extra=""):
    fig.suptitle(f"{label}   |   Inicio {info['ini']:%d/%m/%Y %H}Z   |   "
                 f"Valido {info['val']:%d/%m/%Y %H}Z (+{info['lead']:03d} h){extra}",
                 fontsize=11, fontweight="bold")


def plot_rain(task):
    info, info0, acum, grid, label, out = task
    rain = total_rain(info["path"], grid) - total_rain(info0["path"], grid)
    rain = np.ma.maximum(rain, 0.0)
    ratio = (grid.extent[1] - grid.extent[0]) / max(grid.extent[3] - grid.extent[2], 1e-6)
    fig = plt.figure(figsize=(8.5, 8.5 / max(ratio, 0.5) + 1.2))
    ax = make_axes(fig, 1, 1, grid.extent)[0]
    shade(fig, ax, grid, rain, RAIN_LEV, RAIN_COL, "mm")
    panel_title(ax, "a", f"Chuva acumulada em {acum} h: ({info0['val']:%d/%m %H}Z, "
                         f"{info['val']:%d/%m %H}Z]   max = {float(rain.max()):.0f} mm")
    suptitle(fig, label, info)
    fname = os.path.join(out, f"chuva{acum}h_{info['ini']:%Y%m%d%H}_f{info['lead']:03d}.png")
    fig.savefig(fname, dpi=130, bbox_inches="tight")
    plt.close(fig)
    return fname


ENV_VARS = {
    "mucape": ["mucape", "cape"], "mucin": ["mucin", "cin"],
    "mlcape": ["mlcape"], "mlcin": ["mlcin"],
    "u6": ["uzonal_6km"], "v6": ["umeridional_6km"],
    "u1": ["uzonal_1km"], "v1": ["umeridional_1km"],
    "ub": ["u10", "uzonal_surface"], "vb": ["v10", "umeridional_surface"],
    "srh1": ["srh_0_1km"], "srh3": ["srh_0_3km"],
    "pw": ["precipw"],
}


def plot_env(task):
    info, grid, label, out = task
    f = read_vars(info["path"], grid, ENV_VARS)
    ratio = (grid.extent[1] - grid.extent[0]) / max(grid.extent[3] - grid.extent[2], 1e-6)
    w = 17.0
    fig = plt.figure(figsize=(w, 2 * (w / 3) / max(ratio, 0.5) + 2.0))
    ax = make_axes(fig, 2, 3, grid.extent)

    # a) MUCAPE (ou CAPE do MPAS) + hachura de MUCIN
    if f["mucape"] is not None:
        mu = f["mucape_name"] == "mucape"
        shade(fig, ax[0], grid, f["mucape"], CAPE_LEV, "YlOrRd", "J kg$^{-1}$")
        if f["mucin"] is not None:
            cin_hatch(ax[0], grid, f["mucape"], f["mucin"])
        panel_title(ax[0], "a", ("MUCAPE" if mu else "CAPE (pos do MPAS)") +
                    ", hachura: CIN <= -50 (..) e <= -100 (//)")
    else:
        unavailable(ax[0], "MUCAPE")

    # b) MLCAPE + hachura de MLCIN
    if f["mlcape"] is not None:
        shade(fig, ax[1], grid, f["mlcape"], CAPE_LEV, "YlOrRd", "J kg$^{-1}$")
        if f["mlcin"] is not None:
            cin_hatch(ax[1], grid, f["mlcape"], f["mlcin"])
        panel_title(ax[1], "b", "MLCAPE (0-200 m), hachura: MLCIN <= -50 (..) e <= -100 (//)")
    else:
        unavailable(ax[1], "MLCAPE")

    # c, d) cisalhamento vertical (diferenca vetorial em relacao ao vento a 10 m)
    for k, (top, lev, ttl) in enumerate([("6", SH06_LEV, "Cisalhamento 0-6 km"),
                                         ("1", SH01_LEV, "Cisalhamento 0-1 km")]):
        a = ax[2 + k]
        if all(f[x] is not None for x in ("u" + top, "v" + top, "ub", "vb")):
            du, dv = f["u" + top] - f["ub"], f["v" + top] - f["vb"]
            shade(fig, a, grid, np.ma.hypot(du, dv), lev, "YlGnBu", "m s$^{-1}$ (barbelas em nos)")
            barbs(a, grid, du, dv)
            base = "10 m" if f["ub_name"] == "u10" else "1o nivel"
            panel_title(a, "cd"[k], f"{ttl} ({top} km AGL - {base})")
        else:
            unavailable(a, ttl)

    # e) SRH 0-3 km + contornos da SRH 0-1 km
    if f["srh3"] is not None:
        srh3, note = srh_for_sh(f["srh3"])
        shade(fig, ax[4], grid, srh3, SRH_LEV, "PuRd", "m$^2$ s$^{-2}$")
        if f["srh1"] is not None:
            srh1, _ = srh_for_sh(f["srh1"])
            cs = ax[4].contour(grid.lon, grid.lat, srh1, levels=[100, 200], colors="k",
                               linewidths=[0.6, 1.1], transform=DATA, zorder=4)
            ax[4].clabel(cs, fmt="%d", fontsize=6)
        panel_title(ax[4], "e", f"SRH 0-3 km, contornos SRH 0-1 km{note}")
    else:
        unavailable(ax[4], "SRH")

    # f) agua precipitavel + vento a 10 m
    if f["pw"] is not None:
        shade(fig, ax[5], grid, f["pw"], PW_LEV, "GnBu", "mm (barbelas: vento 10 m, nos)")
        if f["ub"] is not None and f["vb"] is not None:
            barbs(ax[5], grid, f["ub"], f["vb"])
        panel_title(ax[5], "f", "Agua precipitavel e vento a 10 m")
    else:
        unavailable(ax[5], "Agua precipitavel")

    suptitle(fig, label, info)
    fig.subplots_adjust(wspace=0.06, hspace=0.12)
    fname = os.path.join(out, f"ambiente_{info['ini']:%Y%m%d%H}_f{info['lead']:03d}.png")
    fig.savefig(fname, dpi=120, bbox_inches="tight")
    plt.close(fig)
    return fname


# ---------------------------------------------------------------------------
def parse_box(text):
    try:
        box = [float(x) for x in text.split(",")]
    except ValueError:
        box = []
    if len(box) != 4 or box[0] >= box[1] or box[2] >= box[3]:
        raise argparse.ArgumentTypeError("use W,E,S,N em graus, ex.: --box=-58,-47,-34,-22")
    return box


def main():
    p = argparse.ArgumentParser(description="Mapas de previsao do MONAN: chuva acumulada e ambiente pre-convectivo")
    p.add_argument("--post-dir", required=True, help="pasta Post da rodada (MONAN_DIAG_*_POS_*.nc)")
    p.add_argument("--out", required=True, help="pasta das figuras")
    p.add_argument("--labeli", help="YYYYMMDDHH da rodada (obrigatorio se houver mais de uma na pasta)")
    p.add_argument("--fcst", type=int, help="prazo maximo (h)")
    p.add_argument("--acum", type=int, default=6, help="janela da chuva acumulada (h), padrao 6")
    p.add_argument("--step", type=int, default=3, help="intervalo dos mapas de ambiente (h), padrao 3")
    p.add_argument("--box", type=parse_box, help="recorte W,E,S,N (use --box=...)")
    p.add_argument("--label", help="titulo da rodada, ex.: 'MONAN ICON L75'")
    p.add_argument("--nproc", type=int, default=4, help="figuras em paralelo")
    p.add_argument("--only", choices=["chuva", "ambiente"], help="so um tipo de mapa")
    a = p.parse_args()

    files = list_files(a.post_dir, a.labeli, a.fcst)
    leads = sorted(files)
    first = files[leads[0]]
    grid = Grid(first["path"], a.box)
    label = a.label or f"MONAN {first['exp']} x{first['grid']}"
    os.makedirs(a.out, exist_ok=True)
    print(f"Rodada {first['ini']:%Y%m%d%H}: {len(leads)} horarios (+{leads[0]} a +{leads[-1]} h), "
          f"grade recortada {grid.lat.size} x {grid.lon.size}")

    rain_tasks, env_tasks = [], []
    if a.only != "ambiente":
        for h in leads:
            if h >= a.acum and h % a.acum == 0:
                if h - a.acum in files:
                    rain_tasks.append((files[h], files[h - a.acum], a.acum, grid, label, a.out))
                else:
                    print(f"  aviso: sem o arquivo de +{h - a.acum} h; pulando a chuva de +{h} h")
    if a.only != "chuva":
        env_tasks = [(files[h], grid, label, a.out) for h in leads if h % a.step == 0]

    if not rain_tasks and not env_tasks:
        sys.exit("Nada a plotar (confira --acum, --step e os prazos disponiveis).")

    with Pool(max(1, a.nproc)) as pool:
        for fn in pool.imap(plot_rain, rain_tasks):
            print("  ", fn)
        for fn in pool.imap(plot_env, env_tasks):
            print("  ", fn)
    print(f"{len(rain_tasks)} mapas de chuva e {len(env_tasks)} de ambiente em {a.out}")


if __name__ == "__main__":
    main()

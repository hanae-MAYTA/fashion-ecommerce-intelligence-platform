"""Style graphique commun aux notebooks."""

import matplotlib.pyplot as plt
import matplotlib.ticker as mticker
import seaborn as sns

# Palette catégorielle validée (daltonisme) — à utiliser dans cet ordre, sans cycler.
PALETTE = ["#2a78d6", "#eb6834", "#1baf7a", "#eda100", "#e87ba4", "#008300"]
PRIMARY = PALETTE[0]
MUTED = "#8a8985"


def set_style() -> None:
    sns.set_theme(style="whitegrid", palette=PALETTE)
    plt.rcParams.update({
        "figure.figsize": (10, 5),
        "figure.dpi": 110,
        "axes.titlesize": 13,
        "axes.titleweight": "bold",
        "axes.titlelocation": "left",
        "axes.spines.top": False,
        "axes.spines.right": False,
        "grid.color": "#e6e5e1",
        "lines.linewidth": 2,
    })


def millions(unit: str = "$") -> mticker.FuncFormatter:
    """Formateur d'axe : 12 500 000 -> '12,5 M$'."""
    return mticker.FuncFormatter(lambda x, _: f"{x / 1e6:,.1f} M{unit}".replace(".", ","))


def percent(decimals: int = 0) -> mticker.PercentFormatter:
    return mticker.PercentFormatter(xmax=1, decimals=decimals)

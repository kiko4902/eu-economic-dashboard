"""Pipeline entry point: python -m pipeline.run

Runs extract -> warehouse (schema + dimensions) -> transform (fact table) -> reconciliation
-> analytics (views + Power BI role).
Each step runs only if the previous one succeeded.
"""

import logging
import sys
from collections.abc import Callable

from pipeline import analytics, extract, quality, transform, warehouse

logger = logging.getLogger(__name__)

STEPS: tuple[tuple[str, Callable[[], int]], ...] = (
    ("extract", extract.main),
    ("warehouse", warehouse.main),
    ("transform", transform.main),
    ("reconciliation", quality.main),
    ("analytics", analytics.main),
)


def main() -> int:
    for name, step in STEPS:
        if step() != 0:
            logger.error("Pipeline stopped: %s failed", name)
            return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())

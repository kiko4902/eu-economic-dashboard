"""Pipeline entry point: python -m pipeline.run

Runs extract -> warehouse (schema + dimensions). The fact load (transform) is added in Phase 3.
"""

import logging
import sys

from pipeline import extract, warehouse

logger = logging.getLogger(__name__)


def main() -> int:
    if extract.main() != 0:
        logger.error("Extract failed; warehouse step skipped")
        return 1
    return warehouse.main()


if __name__ == "__main__":
    sys.exit(main())

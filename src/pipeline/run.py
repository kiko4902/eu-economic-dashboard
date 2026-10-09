"""Pipeline entry point: python -m pipeline.run

Currently runs the extract step only; transform is added in Phase 3.
"""

import sys

from pipeline import extract


def main() -> int:
    return extract.main()


if __name__ == "__main__":
    sys.exit(main())

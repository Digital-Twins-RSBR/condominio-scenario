This directory contains consolidated report generator and plotting scripts moved
from the top-level `scripts/` folder. Each module is the canonical implementation.

To preserve backwards compatibility, small wrappers remain in the original
`scripts/` root that forward execution to these files. Once you are happy with
the migration, you can remove the wrappers and update any external callsites.

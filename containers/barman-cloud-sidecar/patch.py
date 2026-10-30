from pathlib import Path

from barman.cloud_providers import aws_s3


path = Path(aws_s3.__file__)
source = path.read_text()
old = 'e.response["Error"]["Code"] == "MissingContentMD5"'

# Hetzner rejects batch deletion for scoped keys even when single deletes work.
if source.count(old) != 2:
    raise RuntimeError("Barman batch deletion changed; review this patch")

source = source.replace(
    old, 'e.response["Error"]["Code"] in ("MissingContentMD5", "AccessDenied")'
)
source = source.replace(
    "Bulk delete failed with 'MissingContentMD5'. Falling back ",
    "Bulk delete failed. Falling back ",
)
path.write_text(source)

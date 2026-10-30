from types import SimpleNamespace

from barman.cloud import CloudProviderError
from barman.cloud_providers.aws_s3 import S3CloudInterface
from botocore.exceptions import ClientError


class S3Client:
    def __init__(self, batch_error="AccessDenied", single_error=None):
        self.batch_error = batch_error
        self.single_error = single_error
        self.deleted = []

    def delete_objects(self, **_kwargs):
        raise ClientError(
            {"Error": {"Code": self.batch_error, "Message": "denied"}},
            "DeleteObjects",
        )

    def delete_object(self, **kwargs):
        if self.single_error:
            raise ClientError(
                {"Error": {"Code": self.single_error, "Message": "denied"}},
                "DeleteObject",
            )
        self.deleted.append(kwargs["Key"])


def interface(client):
    instance = object.__new__(S3CloudInterface)
    instance.bucket_name = "backups"
    instance.s3 = SimpleNamespace(
        meta=SimpleNamespace(client=client),
        Bucket=lambda _name: SimpleNamespace(
            objects=SimpleNamespace(
                filter=lambda Prefix: [SimpleNamespace(key=Prefix + "one")]
            )
        ),
    )
    return instance


for delete in (
    lambda provider: provider._delete_objects_batch(["backup/one"]),
    lambda provider: provider.delete_under_prefix("backup/"),
):
    client = S3Client()
    delete(interface(client))
    assert client.deleted == ["backup/one"]

    client = S3Client(batch_error="NoSuchBucket")
    try:
        delete(interface(client))
    except ClientError as error:
        assert error.response["Error"]["Code"] == "NoSuchBucket"
    else:
        raise AssertionError("unexpected batch error was ignored")

client = S3Client(single_error="AccessDenied")
try:
    interface(client)._delete_objects_batch(["backup/one"])
except CloudProviderError:
    pass
else:
    raise AssertionError("failed individual deletion was ignored")

print("Barman batch fallback checks passed")

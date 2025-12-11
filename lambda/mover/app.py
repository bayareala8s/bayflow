
import boto3
import json
import os
from datetime import datetime
from typing import Dict, Any

s3 = boto3.client("s3")
dynamodb = boto3.client("dynamodb")
sns = boto3.client("sns")

CONFIG_BUCKET = os.environ["CONFIG_BUCKET"]
CONFIG_KEY = os.environ["CONFIG_KEY"]
TARGET_BUCKET = os.environ["TARGET_BUCKET"]
SNS_TOPIC_ARN = os.environ["SNS_TOPIC_ARN"]
JOBS_TABLE = os.environ["JOBS_TABLE"]


def handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Entry point for BayFlow v1 mover Lambda.

    Expected event shape from Step Functions:
    {
      "s3_detail": {
        "bucket": { "name": "..." },
        "object": { "key": "partners/acme/inbox/file.csv", ... },
        ...
      },
      "execution_id": "arn:aws:states:..."
    }
    """
    print("Received event:", json.dumps(event))

    detail = event["s3_detail"]
    execution_id = event.get("execution_id", "unknown-execution")

    bucket = detail["bucket"]["name"]
    key = detail["object"]["key"]

    # Derive tenant & flow from key pattern
    # Example: partners/acme/inbox/file.csv
    parts = key.split("/")
    tenant = parts[1] if len(parts) > 2 else "unknown"
    flow_id = "inbound-v1"  # v1: fixed; v2: derive from prefix or metadata

    filename = key.split("/")[-1]

    # Load partners configuration
    cfg_obj = s3.get_object(Bucket=CONFIG_BUCKET, Key=CONFIG_KEY)
    config = json.loads(cfg_obj["Body"].read())

    partner_cfg = config["partners"][tenant]["flows"][flow_id]
    defaults = config.get("defaults", {})

    target_prefix = partner_cfg["target_prefix"]
    archive_prefix = partner_cfg["archive_prefix"]
    archive_enabled = defaults.get("archive_enabled", True)

    target_key = f"{target_prefix}{filename}"
    archive_key = f"{archive_prefix}{filename}"

    # Create initial job record
    put_job_record(
        job_id=execution_id,
        file_name=filename,
        tenant=tenant,
        flow_id=flow_id,
        source_bucket=bucket,
        target_bucket=TARGET_BUCKET,
        status="RUNNING",
    )

    try:
        # Copy to target bucket
        s3.copy_object(
            Bucket=TARGET_BUCKET,
            Key=target_key,
            CopySource={"Bucket": bucket, "Key": key},
        )

        # Optional archive (copy within landing bucket)
        if archive_enabled:
            s3.copy_object(
                Bucket=bucket,
                Key=archive_key,
                CopySource={"Bucket": bucket, "Key": key},
            )
            # Optionally delete original object here if required:
            # s3.delete_object(Bucket=bucket, Key=key)

        # Mark job success
        update_job_status(
            job_id=execution_id,
            file_name=filename,
            status="SUCCESS",
            error_message=None,
        )

        # Notify success
        sns.publish(
            TopicArn=SNS_TOPIC_ARN,
            Subject=f"BayFlow: SUCCESS for {tenant}/{flow_id}",
            Message=(
                f"File {key} processed successfully.\n"
                f"Source: s3://{bucket}/{key}\n"
                f"Target: s3://{TARGET_BUCKET}/{target_key}"
            ),
        )

        return {"status": "ok", "message": "File processed successfully."}

    except Exception as e:
        err_str = str(e)
        print("Error while processing file:", err_str)

        # Mark job failure
        update_job_status(
            job_id=execution_id,
            file_name=filename,
            status="FAILED",
            error_message=err_str,
        )

        # Notify failure
        sns.publish(
            TopicArn=SNS_TOPIC_ARN,
            Subject=f"BayFlow: FAILURE for {tenant}/{flow_id}",
            Message=(
                f"File {key} failed to process.\n"
                f"Source: s3://{bucket}/{key}\n"
                f"Error: {err_str}"
            ),
        )

        # Re-raise so Step Functions catches and routes to Failure state
        raise


def put_job_record(
    job_id: str,
    file_name: str,
    tenant: str,
    flow_id: str,
    source_bucket: str,
    target_bucket: str,
    status: str,
) -> None:
    now = datetime.utcnow().isoformat()
    dynamodb.put_item(
        TableName=JOBS_TABLE,
        Item={
            "job_id": {"S": job_id},
            "file_name": {"S": file_name},
            "tenant": {"S": tenant},
            "flow_id": {"S": flow_id},
            "status": {"S": status},
            "source_bucket": {"S": source_bucket},
            "target_bucket": {"S": target_bucket},
            "created_at": {"S": now},
            "updated_at": {"S": now},
        },
    )


def update_job_status(
    job_id: str,
    file_name: str,
    status: str,
    error_message: str | None,
) -> None:
    now = datetime.utcnow().isoformat()

    expr = "SET #s = :s, updated_at = :u"
    attr_names = {"#s": "status"}
    attr_values = {
        ":s": {"S": status},
        ":u": {"S": now},
    }

    if error_message:
        expr += ", error_message = :e"
        attr_values[":e"] = {"S": error_message}

    dynamodb.update_item(
        TableName=JOBS_TABLE,
        Key={
            "job_id": {"S": job_id},
            "file_name": {"S": file_name},
        },
        UpdateExpression=expr,
        ExpressionAttributeNames=attr_names,
        ExpressionAttributeValues=attr_values,
    )

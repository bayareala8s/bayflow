import json
import os
from typing import Any, Dict

import boto3
from boto3.dynamodb.conditions import Key


dynamodb = boto3.resource("dynamodb")
s3 = boto3.client("s3")

JOBS_TABLE = os.environ["JOBS_TABLE"]
CONFIG_BUCKET = os.environ["CONFIG_BUCKET"]
LANDING_BUCKET = os.environ.get("LANDING_BUCKET")
TARGET_BUCKET = os.environ.get("TARGET_BUCKET")


def _response(status: int, body: Any, headers: Dict[str, str] | None = None) -> Dict[str, Any]:
    base_headers = {
        "Content-Type": "application/json",
        "Access-Control-Allow-Origin": "*",
    }
    if headers:
        base_headers.update(headers)
    return {
        "statusCode": status,
        "headers": base_headers,
        "body": json.dumps(body, default=str),
    }


def handler(event, context):
    request_context = event.get("requestContext") or {}

    # Support both HTTP API v2 (requestContext.http) and v1 (httpMethod/path)
    http_v2 = request_context.get("http")
    if http_v2:
        method = http_v2.get("method", "")
        path = event.get("rawPath") or http_v2.get("path", "")
    else:
        method = event.get("httpMethod", "")
        path = event.get("path", "")

    path_params = event.get("pathParameters") or {}

    if method == "GET" and path == "/jobs":
        return list_jobs(event)

    if method == "GET" and path.startswith("/jobs/"):
        job_id = path_params.get("job_id") or path.split("/", 2)[-1]
        return get_job(job_id)

    if method == "GET" and path == "/partners":
        return get_partners()

    if method == "PUT" and path == "/partners":
        body = event.get("body") or "{}"
        return put_partners(body)

    if method == "GET" and path.startswith("/buckets/"):
        # Expect /buckets/{kind}/objects
        kind = path_params.get("kind")
        if not kind:
            parts = path.split("/")
            kind = parts[2] if len(parts) > 2 else ""
        return list_bucket_objects(kind, event)

    return _response(404, {"message": "Not Found", "path": path, "method": method})


def list_jobs(event):
    params = event.get("queryStringParameters") or {}
    tenant = params.get("tenant") if params else None
    status = params.get("status") if params else None
    limit = int((params or {}).get("limit", "50"))

    table = dynamodb.Table(JOBS_TABLE)

    if tenant:
        resp = table.query(
            IndexName="tenant_flow_idx",
            KeyConditionExpression=Key("tenant").eq(tenant),
            Limit=limit,
        )
        items = resp.get("Items", [])
    else:
        resp = table.scan(Limit=limit)
        items = resp.get("Items", [])

    if status:
        items = [i for i in items if i.get("status") == status]

    return _response(200, {"items": items})


def get_job(job_id: str):
    if not job_id:
        return _response(400, {"message": "job_id is required"})

    table = dynamodb.Table(JOBS_TABLE)
    resp = table.query(KeyConditionExpression=Key("job_id").eq(job_id), Limit=1)
    items = resp.get("Items", [])

    if not items:
        return _response(404, {"message": "Job not found", "job_id": job_id})

    job = items[0]

    # Optionally enrich with S3 URLs (signed URLs could be added later)
    source_bucket = job.get("source_bucket") or LANDING_BUCKET
    source_key = job.get("source_key") or job.get("file_name")

    target_bucket = job.get("target_bucket") or TARGET_BUCKET
    target_key = job.get("target_key") or job.get("file_name")

    job["source_s3"] = {
        "bucket": source_bucket,
        "key": source_key,
    }
    job["target_s3"] = {
        "bucket": target_bucket,
        "key": target_key,
    }

    return _response(200, job)


def get_partners():
    try:
        obj = s3.get_object(Bucket=CONFIG_BUCKET, Key="partners.json")
        data = obj["Body"].read().decode("utf-8")
        partners = json.loads(data or "{}")
        return _response(200, partners)
    except s3.exceptions.NoSuchKey:
        return _response(404, {"message": "partners.json not found"})
    except Exception as e:
        return _response(500, {"message": "Error reading partners.json", "error": str(e)})


def put_partners(body: str):
    try:
        parsed = json.loads(body or "{}")
    except json.JSONDecodeError:
        return _response(400, {"message": "Invalid JSON"})

    # Minimal validation: require an object at top level
    if not isinstance(parsed, dict):
        return _response(400, {"message": "partners.json must be a JSON object"})

    try:
        s3.put_object(
            Bucket=CONFIG_BUCKET,
            Key="partners.json",
            Body=json.dumps(parsed, indent=2),
            ContentType="application/json",
        )
        return _response(200, {"message": "partners.json updated"})
    except Exception as e:
        return _response(500, {"message": "Error writing partners.json", "error": str(e)})


def list_bucket_objects(kind: str, event):
    params = event.get("queryStringParameters") or {}
    prefix = params.get("prefix") or ""
    max_keys = int(params.get("maxKeys", "50"))
    token = params.get("continuationToken")

    if kind == "landing":
        bucket = LANDING_BUCKET
    elif kind == "target":
        bucket = TARGET_BUCKET
    else:
        return _response(400, {"message": "kind must be 'landing' or 'target'"})

    if not bucket:
        return _response(500, {"message": f"Bucket for kind '{kind}' is not configured"})

    kwargs: Dict[str, Any] = {
        "Bucket": bucket,
        "Prefix": prefix,
        "MaxKeys": max_keys,
    }
    if token:
        kwargs["ContinuationToken"] = token

    try:
        resp = s3.list_objects_v2(**kwargs)
        contents = resp.get("Contents", [])
        items = [
            {
                "key": obj["Key"],
                "size": obj["Size"],
                "last_modified": obj["LastModified"],
            }
            for obj in contents
        ]
        return _response(
            200,
            {
                "bucket": bucket,
                "prefix": prefix,
                "items": items,
                "is_truncated": resp.get("IsTruncated", False),
                "next_continuation_token": resp.get("NextContinuationToken"),
            },
        )
    except Exception as e:
        return _response(500, {"message": "Error listing objects", "error": str(e)})

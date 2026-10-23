import boto3
import base64
import json
import logging
import time

s3 = boto3.client("s3")
BUCKET = "cv-23l-3085"
FUNCTION = "cv-func-23l-3085"

logger = logging.getLogger()
logger.setLevel(logging.INFO)

FILES = {
    "/": ("index.html", "text/html; charset=utf-8"),
    "/index.html": ("index.html", "text/html; charset=utf-8"),
    "/style.css": ("style.css", "text/css; charset=utf-8"),
    "/cv.pdf": ("cv.pdf", "application/pdf"),
}


def lambda_handler(event, context):
    start = time.time()
    path = event.get("rawPath", "/")
    status = 200

    try:
        if path not in FILES:
            status = 404
            body = "Not Found"
            content_type = "text/plain; charset=utf-8"
            encoded = False
        else:
            key, content_type = FILES[path]
            obj = s3.get_object(
                Bucket=BUCKET,
                Key=f"site/{key}"
            )
            data = obj["Body"].read()

            if key == "index.html":
                html = data.decode("utf-8")
                html = html.replace(
                    "{{HOSTED_ON}}",
                    f"Lambda {FUNCTION}"
                )
                body = html
                encoded = False
            elif key == "cv.pdf":
                body = base64.b64encode(data).decode("ascii")
                encoded = True
            else:
                body = data.decode("utf-8")
                encoded = False

    except Exception:
        status = 500
        body = "Internal Server Error"
        content_type = "text/plain; charset=utf-8"
        encoded = False
        logger.exception("Failed to serve path %s", path)

    elapsed_ms = round((time.time() - start) * 1000, 2)
    logger.info(json.dumps({
        "fn": FUNCTION,
        "path": path,
        "status": status,
        "ms": elapsed_ms
    }))

    return {
        "statusCode": status,
        "headers": {
            "Content-Type": content_type,
            "Cache-Control": "no-store"
        },
        "isBase64Encoded": encoded,
        "body": body
    }
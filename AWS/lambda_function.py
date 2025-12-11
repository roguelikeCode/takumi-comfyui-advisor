import json
import boto3
import time
import uuid
import os
import logging
from typing import Dict, Any, Union

# --- Configuration ---
# [Why] To allow infrastructure changes without modifying code. (AWS management screen)
# [What] Get bucket name from environment variable, fallback to default.
BUCKET_NAME = os.environ.get('LOG_BUCKET_NAME', 'takumi-logbook-v1')

# --- Initialization ---
s3_client = boto3.client('s3')
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# ==============================================================================
# Helper Functions (Encapsulation)
# ==============================================================================

# [Why] To standardize API Gateway responses.
# [What] Returns a dictionary formatted for Lambda proxy integration.
# [Input] status_code (int), body (dict)
# [Output] dict (APIGatewayProxyResponse)
def create_response(status_code: int, body: Dict[str, Any]) -> Dict[str, Any]:
    return {
        'statusCode': status_code,
        'headers': {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*' # CORS support if needed
        },
        'body': json.dumps(body, ensure_ascii=False)
    }

# [Why] To safely extract and parse the JSON payload from the request.
# [What] Handles both stringified JSON and direct dictionary objects.
# [Input] event (dict)
# [Output] dict (Parsed JSON data)
def parse_payload(event: Dict[str, Any]) -> Dict[str, Any]:
    body = event.get('body', '{}')
    
    # API Gateway might send body as string or dict depending on configuration
    if isinstance(body, str):
        if not body.strip():
            return {}
        return json.loads(body)
    return body

# [Why] To organize logs efficiently in the Data Lake.
# [What] Generates a unique S3 key structure: logs/YYYY-MM-DD/timestamp_uuid.json
# [Output] str (S3 object key)
def generate_s3_key() -> str:
    current_time = int(time.time())
    date_str = time.strftime('%Y-%m-%d', time.gmtime(current_time))
    file_id = str(uuid.uuid4())
    return f"logs/{date_str}/{current_time}_{file_id}.json"

# [Why] To persist the telemetry data securely.
# [What] Uploads the JSON payload to the configured S3 bucket.
# [Input] key (str), data (dict)
def save_to_s3(key: str, data: Dict[str, Any]) -> None:
    s3_client.put_object(
        Bucket=BUCKET_NAME,
        Key=key,
        Body=json.dumps(data, ensure_ascii=False),
        ContentType='application/json'
    )

# ==============================================================================
# Main Handler
# ==============================================================================

# [Why] Entry point for AWS Lambda execution.
# [What] Orchestrates parsing, saving, and error handling.
def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    try:
        logger.info("Processing new telemetry request.")
        
        # 1. Parse Input
        try:
            payload = parse_payload(event)
        except json.JSONDecodeError:
            logger.warning("Invalid JSON format received.")
            return create_response(400, {'error': 'Invalid JSON format'})

        if not payload:
             return create_response(400, {'error': 'Empty payload'})

        # 2. Generate Key
        file_key = generate_s3_key()

        # 3. Save to S3
        save_to_s3(file_key, payload)
        logger.info(f"Log saved successfully to {file_key}")

        # 4. Return Success
        return create_response(200, {
            'message': 'Log saved successfully',
            'path': file_key
        })

    except Exception as e:
        logger.error(f"Internal Server Error: {str(e)}", exc_info=True)
        return create_response(500, {'error': 'Internal Server Error'})
import json
import boto3
import time
import uuid

# ログ保存先のS3バケット名
# (バケット作成時に設定した名前に合わせる必要があります)
BUCKET_NAME = 'takumi-logbook-v1'

# S3クライアントの初期化
s3 = boto3.client('s3')

def lambda_handler(event, context):
    """
    API Gatewayからのリクエストを受け取り、S3にJSONログとして保存するLambda関数
    """
    try:
        # 1. リクエストボディの解析
        # API Gatewayからは通常文字列として渡されるが、
        # テスト実行時などは辞書として渡される場合があるためハンドリングする
        body = event.get('body', '{}')
        if isinstance(body, str):
            try:
                payload = json.loads(body)
            except json.JSONDecodeError:
                return {
                    'statusCode': 400,
                    'body': json.dumps({'error': 'Invalid JSON format'})
                }
        else:
            payload = body

        # 2. ファイル名の生成
        # 衝突を避けるため、タイムスタンプとUUIDを組み合わせる
        # 構造: logs/YYYY-MM-DD/timestamp_uuid.json (日別にフォルダ分けすると管理しやすい)
        current_time = int(time.time())
        date_str = time.strftime('%Y-%m-%d', time.gmtime(current_time))
        file_id = str(uuid.uuid4())
        
        # S3上のパス (Key)
        file_name = f"logs/{date_str}/{current_time}_{file_id}.json"

        # 3. S3への保存
        s3.put_object(
            Bucket=BUCKET_NAME,
            Key=file_name,
            Body=json.dumps(payload, ensure_ascii=False), # 日本語文字化け防止
            ContentType='application/json'
        )

        # 4. 成功レスポンス
        print(f"Successfully saved log to {file_name}")
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Log saved successfully', 
                'path': file_name
            })
        }

    except Exception as e:
        # エラーハンドリング
        print(f"Error: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': 'Internal Server Error'})
        }
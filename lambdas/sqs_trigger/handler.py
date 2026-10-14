import json
import os
import boto3

sfn = boto3.client('stepfunctions')
STATE_MACHINE_ARN = os.environ['STATE_MACHINE_ARN']


def handler(event, context):
    for record in event['Records']:
        body = json.loads(record['body'])
        sfn.start_execution(
            stateMachineArn=STATE_MACHINE_ARN,
            input=json.dumps({'nota_id': body['nota_id']})
        )
    return {'statusCode': 200}

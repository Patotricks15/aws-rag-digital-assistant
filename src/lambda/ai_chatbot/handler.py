"""ai_chatbot (QnAIntent): resolves a user's intent by retrieving relevant
context from the company's private document store and generating a grounded
answer with a Bedrock foundation model (Retrieval Augmented Generation).
"""
import json
import os

import boto3

REGION = os.environ.get("REGION", "us-east-1")
KNOWLEDGE_BASE_ID = os.environ["KNOWLEDGE_BASE_ID"]
GENERATION_MODEL_ARN = os.environ["GENERATION_MODEL_ARN"]

bedrock_agent_runtime = boto3.client(
    "bedrock-agent-runtime",
    region_name=REGION,
    endpoint_url="http://localhost:4566",
    aws_access_key_id="test",
    aws_secret_access_key="test",
)


def lambda_handler(event, context):
    try:
        body = json.loads(event.get("body") or "{}")
    except json.JSONDecodeError:
        return _response(400, {"error": "Request body must be valid JSON."})

    prompt = body.get("prompt")
    if not prompt:
        return _response(400, {"error": "'prompt' is required."})

    # RetrieveAndGenerate: search the knowledge base, then generate a grounded answer.
    response = bedrock_agent_runtime.retrieve_and_generate(
        input={"text": prompt},
        retrieveAndGenerateConfiguration={
            "type": "KNOWLEDGE_BASE",
            "knowledgeBaseConfiguration": {
                "knowledgeBaseId": KNOWLEDGE_BASE_ID,
                "modelArn": GENERATION_MODEL_ARN,
            },
        },
    )

    answer = response.get("output", {}).get("text", "")
    citations = [
        ref.get("content", {}).get("text", "")
        for citation in response.get("citations", [])
        for ref in citation.get("retrievedReferences", [])
    ]

    return _response(200, {"answer": answer, "citations": citations})


def _response(status_code, payload):
    return {
        "statusCode": status_code,
        "headers": {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*",
        },
        "body": json.dumps(payload),
    }

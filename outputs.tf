output "cloudfront_domain_name" {
  description = "CDN domain name serving the GenAI Chat UI."
  value       = aws_cloudfront_distribution.web_ui.domain_name
}

output "chatbot_function_url" {
  description = "Public URL of the AI Chatbot (QnAIntent) Lambda function."
  value       = aws_lambda_function_url.ai_chatbot.function_url
}

output "knowledge_base_id" {
  description = "ID of the Bedrock knowledge base over the company's private data."
  value       = aws_bedrockagent_knowledge_base.assistant.id
}

output "document_store_bucket" {
  description = "Name of the S3 bucket holding source documents for the knowledge base."
  value       = aws_s3_bucket.document_store.bucket
}

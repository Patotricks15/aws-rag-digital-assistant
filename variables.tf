variable "project_name" {
  description = "Project name used as prefix for all resources."
  type        = string
  default     = "floci-digital-assistant"
}

variable "aws_region" {
  description = "AWS region (simulated by floci)."
  type        = string
  default     = "us-east-1"
}

variable "web_ui_bucket_name" {
  description = "Name of the S3 bucket hosting the GenAI Chat UI assets."
  type        = string
  default     = "web-ui-assets"
}

variable "document_store_bucket_name" {
  description = "Name of the S3 bucket holding the company's private documents (RAG source)."
  type        = string
  default     = "document-store"
}

variable "embedding_model_id" {
  description = "Bedrock foundation model id used to embed documents for retrieval."
  type        = string
  default     = "amazon.titan-embed-text-v1"
}

variable "generation_model_id" {
  description = "Bedrock foundation model id used to generate the assistant's answers."
  type        = string
  default     = "anthropic.claude-3-haiku-20240307-v1:0"
}

variable "vector_index_name" {
  description = "Name of the vector index inside the OpenSearch Serverless collection."
  type        = string
  default     = "kb-index"
}

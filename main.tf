# ─── S3: document store (RAG source) + web UI assets (behind CloudFront) ────

resource "aws_s3_bucket" "document_store" {
  bucket = "${local.name_prefix}-${var.document_store_bucket_name}"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-${var.document_store_bucket_name}"
  })
}

resource "aws_s3_bucket_public_access_block" "document_store" {
  bucket = aws_s3_bucket.document_store.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket" "web_ui" {
  bucket = "${local.name_prefix}-${var.web_ui_bucket_name}"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-${var.web_ui_bucket_name}"
  })
}

resource "aws_s3_bucket_public_access_block" "web_ui" {
  bucket = aws_s3_bucket.web_ui.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ─── OpenSearch Serverless: vector store backing the Bedrock knowledge base ──

resource "aws_opensearchserverless_security_policy" "encryption" {
  name = "${local.name_prefix}-kb-encryption"
  type = "encryption"

  policy = jsonencode({
    Rules = [{
      ResourceType = "collection"
      Resource     = ["collection/${local.name_prefix}-kb"]
    }]
    AWSOwnedKey = true
  })
}

resource "aws_opensearchserverless_security_policy" "network" {
  name = "${local.name_prefix}-kb-network"
  type = "network"

  policy = jsonencode([{
    Rules = [
      {
        ResourceType = "collection"
        Resource     = ["collection/${local.name_prefix}-kb"]
      },
      {
        ResourceType = "dashboard"
        Resource     = ["collection/${local.name_prefix}-kb"]
      },
    ]
    AllowFromPublic = true
  }])
}

resource "aws_opensearchserverless_access_policy" "data" {
  name = "${local.name_prefix}-kb-access"
  type = "data"

  policy = jsonencode([{
    Rules = [
      {
        ResourceType = "collection"
        Resource     = ["collection/${local.name_prefix}-kb"]
        Permission   = ["aoss:*"]
      },
      {
        ResourceType = "index"
        Resource     = ["index/${local.name_prefix}-kb/*"]
        Permission   = ["aoss:*"]
      },
    ]
    Principal = [aws_iam_role.bedrock_kb.arn]
  }])

  depends_on = [aws_iam_role.bedrock_kb]
}

resource "aws_opensearchserverless_collection" "kb" {
  name = "${local.name_prefix}-kb"
  type = "VECTORSEARCH"

  depends_on = [
    aws_opensearchserverless_security_policy.encryption,
    aws_opensearchserverless_security_policy.network,
  ]

  tags = local.common_tags
}

# ─── IAM: role assumed by the Bedrock knowledge base ─────────────────────────

resource "aws_iam_role" "bedrock_kb" {
  name = "${local.name_prefix}-bedrock-kb"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "bedrock.amazonaws.com" }
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy" "bedrock_kb_s3" {
  name = "${local.name_prefix}-bedrock-kb-s3"
  role = aws_iam_role.bedrock_kb.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:GetObject", "s3:ListBucket"]
      Resource = [aws_s3_bucket.document_store.arn, "${aws_s3_bucket.document_store.arn}/*"]
    }]
  })
}

resource "aws_iam_role_policy" "bedrock_kb_embed" {
  name = "${local.name_prefix}-bedrock-kb-embed"
  role = aws_iam_role.bedrock_kb.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["bedrock:InvokeModel"]
      Resource = "arn:aws:bedrock:${var.aws_region}::foundation-model/${var.embedding_model_id}"
    }]
  })
}

resource "aws_iam_role_policy" "bedrock_kb_aoss" {
  name = "${local.name_prefix}-bedrock-kb-aoss"
  role = aws_iam_role.bedrock_kb.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["aoss:APIAccessAll"]
      Resource = aws_opensearchserverless_collection.kb.arn
    }]
  })
}

# ─── Bedrock: knowledge base over the company's private data ────────────────

resource "aws_bedrockagent_knowledge_base" "assistant" {
  name     = "${local.name_prefix}-kb"
  role_arn = aws_iam_role.bedrock_kb.arn

  knowledge_base_configuration {
    type = "VECTOR"

    vector_knowledge_base_configuration {
      embedding_model_arn = "arn:aws:bedrock:${var.aws_region}::foundation-model/${var.embedding_model_id}"
    }
  }

  storage_configuration {
    type = "OPENSEARCH_SERVERLESS"

    opensearch_serverless_configuration {
      collection_arn    = aws_opensearchserverless_collection.kb.arn
      vector_index_name = var.vector_index_name

      field_mapping {
        vector_field   = "embedding"
        text_field     = "text"
        metadata_field = "metadata"
      }
    }
  }

  depends_on = [
    aws_opensearchserverless_access_policy.data,
    aws_iam_role_policy.bedrock_kb_s3,
    aws_iam_role_policy.bedrock_kb_embed,
    aws_iam_role_policy.bedrock_kb_aoss,
  ]

  tags = local.common_tags
}

resource "aws_bedrockagent_data_source" "documents" {
  knowledge_base_id = aws_bedrockagent_knowledge_base.assistant.id
  name              = "${local.name_prefix}-documents"

  data_source_configuration {
    type = "S3"

    s3_configuration {
      bucket_arn = aws_s3_bucket.document_store.arn
    }
  }
}

# ─── Lambda: AI Chatbot (QnAIntent) — retrieves context and generates answers

resource "aws_iam_role" "lambda_exec" {
  name = "${local.name_prefix}-lambda-exec"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "lambda_bedrock" {
  name = "${local.name_prefix}-lambda-bedrock"
  role = aws_iam_role.lambda_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["bedrock:Retrieve", "bedrock:RetrieveAndGenerate"]
        Resource = aws_bedrockagent_knowledge_base.assistant.arn
      },
      {
        Effect   = "Allow"
        Action   = ["bedrock:InvokeModel"]
        Resource = "arn:aws:bedrock:${var.aws_region}::foundation-model/${var.generation_model_id}"
      },
    ]
  })
}

resource "null_resource" "lambda_package" {
  triggers = {
    handler_sha = filesha256("${path.module}/src/lambda/ai_chatbot/handler.py")
  }

  provisioner "local-exec" {
    command = "bash ${path.module}/scripts/build_lambda_package.sh ${path.module} ai_chatbot"
  }
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/src/lambda/ai_chatbot/handler.py"
  output_path = "${path.module}/.build/ai_chatbot.zip"

  depends_on = [null_resource.lambda_package]
}

resource "aws_lambda_function" "ai_chatbot" {
  function_name = "${local.name_prefix}-ai-chatbot"
  role          = aws_iam_role.lambda_exec.arn
  handler       = "handler.lambda_handler"
  runtime       = "python3.12"
  timeout       = 30
  memory_size   = 256

  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      REGION               = var.aws_region
      KNOWLEDGE_BASE_ID    = aws_bedrockagent_knowledge_base.assistant.id
      GENERATION_MODEL_ARN = "arn:aws:bedrock:${var.aws_region}::foundation-model/${var.generation_model_id}"
    }
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-ai-chatbot"
  })

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic,
    aws_iam_role_policy.lambda_bedrock,
  ]
}

resource "aws_lambda_function_url" "ai_chatbot" {
  function_name      = aws_lambda_function.ai_chatbot.function_name
  authorization_type = "NONE"

  cors {
    allow_origins = ["*"]
    allow_methods = ["POST"]
    allow_headers = ["content-type"]
  }
}

# ─── Web UI content: uploaded to S3, delivered through the CloudFront CDN ───

resource "aws_s3_object" "index" {
  bucket       = aws_s3_bucket.web_ui.id
  key          = "index.html"
  content_type = "text/html"

  content = templatefile("${path.module}/web/index.html.tftpl", {
    project_name         = var.project_name
    chatbot_function_url = aws_lambda_function_url.ai_chatbot.function_url
  })
}

resource "aws_cloudfront_origin_access_control" "web_ui" {
  name                              = "${local.name_prefix}-web-ui-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "web_ui" {
  enabled             = true
  default_root_object = "index.html"
  comment             = "Web content delivery for the ${var.project_name} GenAI Chat UI"

  origin {
    domain_name              = aws_s3_bucket.web_ui.bucket_regional_domain_name
    origin_id                = "web-ui-s3-origin"
    origin_access_control_id = aws_cloudfront_origin_access_control.web_ui.id
  }

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "web-ui-s3-origin"
    viewer_protocol_policy = "redirect-to-https"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = local.common_tags
}

resource "aws_s3_bucket_policy" "web_ui_cloudfront" {
  bucket = aws_s3_bucket.web_ui.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowCloudFrontServicePrincipalReadOnly"
      Effect    = "Allow"
      Principal = { Service = "cloudfront.amazonaws.com" }
      Action    = "s3:GetObject"
      Resource  = "${aws_s3_bucket.web_ui.arn}/*"
      Condition = {
        StringEquals = {
          "AWS:SourceArn" = aws_cloudfront_distribution.web_ui.arn
        }
      }
    }]
  })
}

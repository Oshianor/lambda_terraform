locals {
  image_uri = var.image_uri
  s3_origin_id = var.image_uri
  function_name = "lambda-test"
  vpc_id = var.vpc_id
  # subnets = var.subnets
}

resource "aws_acm_certificate" "cert" {
  domain_name       = "grycare.com"
  validation_method = "DNS"

  tags = {
    Environment = "test"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "allow_tls_sg" {
  name        = "allow_https"
  description = "Allow https inbound traffic"
  vpc_id      = local.vpc_id

  ingress {
    description      = "https"
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "allow_tls"
  }
}

resource "aws_lb" "test" {
  name               = "tf-lambda-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.allow_tls_sg.id]
  # subnets            = [local.subnets]
  subnets            = data.aws_subnets.example.ids

  enable_deletion_protection = false

  tags = {
    Environment = "production"
  }
}

resource "aws_lb_target_group" "main" {
  name        = "tf-lambda-lb-tg"
  target_type = "lambda"
}




/*
Lambda
*/
resource "aws_iam_role" "iam_for_lambda" {
  name = "iam_for_lambda"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": ["lambda.amazonaws.com", "edgelambda.amazonaws.com"]
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_lambda_function" "test_lambda" {
  image_uri = local.image_uri
  package_type = "Image"
  function_name = local.function_name
  role          = aws_iam_role.iam_for_lambda.arn
  publish = true

  image_config {
    # use this to point to different handlers within
    # the same image, or omit `image_config` entirely
    # if only serving a single Lambda function
    command = ["handlers.lambda_handler"]
  }

   depends_on = [aws_iam_role.iam_for_lambda]

  environment {
    variables = {
      foo = "bar"
    }
  }
}

resource "aws_lambda_permission" "alb" {
  statement_id  = "AllowExecutionFromlb"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.test_lambda.arn
  principal     = "elasticloadbalancing.amazonaws.com"
  source_arn    = aws_lb_target_group.main.arn
}

resource aws_lb_target_group_attachment main {
  target_group_arn = aws_lb_target_group.main.arn
  target_id = aws_lambda_function.test_lambda.arn
  depends_on = [ aws_lambda_permission.alb ]
}

resource "aws_lb_listener" "front_end" {
  load_balancer_arn = aws_lb.test.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = aws_acm_certificate.cert.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main.arn
  }
}


resource "aws_lb_listener_rule" "main" {
  listener_arn = aws_lb_listener.front_end.arn
  action {
    type = "forward"
    target_group_arn = aws_lb_target_group.main.arn
  }
  condition {
    host_header {
      values = ["mail.grycare.com"]
    }
  }
  condition {
    http_request_method {
      values = ["OPTIONS", "GET", "HEAD"]
    }
  }
}




resource "aws_cloudfront_distribution" "lambda_distribution" {
  origin {
    domain_name = aws_lb.test.dns_name
    origin_id   = aws_lb.test.dns_name

    custom_origin_config {
      http_port = 80
      https_port = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols = ["TLSv1", "TLSv1.1", "TLSv1.2"]
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  comment             = "Some comment"

  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = aws_lb.test.dns_name

    forwarded_values {
      query_string = false
      headers      = ["Host"]

      cookies {
        forward = "all"
      }
    }

    viewer_protocol_policy = "allow-all"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  price_class = "PriceClass_200"

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  tags = {
    env = "dev"
  }

  viewer_certificate {
    cloudfront_default_certificate = true
    # acm_certificate_arn      = aws_acm_certificate.cert.arn
    # ssl_support_method       = "sni-only"
    # minimum_protocol_version = "TLSv1.2_2018"
  }
}
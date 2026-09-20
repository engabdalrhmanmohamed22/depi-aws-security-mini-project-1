# Task 13 — CloudFront in front of the load balancer
#
# CloudFront gives users HTTPS and caching. The secret header stops anyone
# from bypassing CloudFront (and any WAF placed in front of it later) by
# hitting the ALB directly — the ALB's default action refuses everyone
# except requests carrying this exact header (added in alb.tf).

resource "random_password" "origin_verify" {
  length  = 32
  special = false
}

# ---------------------------------------------------------------------------
# The listener rule that lets the real traffic through — evaluated before
# the listener's default 403 action. Only CloudFront (which is configured
# below to always send this header) can match this rule.
# ---------------------------------------------------------------------------
resource "aws_lb_listener_rule" "allow_cloudfront_only" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 1

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }

  condition {
    http_header {
      http_header_name = "X-Origin-Verify"
      values           = [random_password.origin_verify.result]
    }
  }
}

# ---------------------------------------------------------------------------
# CloudFront distribution
# ---------------------------------------------------------------------------
resource "aws_cloudfront_distribution" "app" {
  enabled             = true
  default_root_object = ""
  comment             = "${var.name_prefix} CDN in front of the ALB"

  origin {
    domain_name = aws_lb.app.dns_name
    origin_id   = "alb-origin"

    custom_origin_config {
      http_port              = 80
      https_port              = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }

    custom_header {
      name  = "X-Origin-Verify"
      value = random_password.origin_verify.result
    }
  }

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "alb-origin"
    viewer_protocol_policy = "redirect-to-https"

    forwarded_values {
      query_string = true
      cookies {
        forward = "all"
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

  logging_config {
    bucket          = aws_s3_bucket.logs.bucket_domain_name
    prefix          = "cloudfront/"
    include_cookies = false
  }

  depends_on = [aws_s3_bucket_acl.logs]

  tags = {
    Name = "${var.name_prefix}-cloudfront"
  }
}

# ---------------------------------------------------------------------------
# CloudFront's legacy "standard logging" delivers via an S3 ACL grant to a
# fixed AWS log-delivery canonical user — it does NOT work with the
# bucket-owner-enforced (ACLs disabled) setting our logs bucket has by
# default since Task 10. Object Ownership is loosened to allow this one ACL
# grant; the bucket's Public Access Block (Task 10) still blocks any public
# access regardless of ACLs.
# ---------------------------------------------------------------------------
resource "aws_s3_bucket_ownership_controls" "logs" {
  bucket = aws_s3_bucket.logs.id

  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_acl" "logs" {
  bucket = aws_s3_bucket.logs.id
  acl    = "log-delivery-write"

  depends_on = [
    aws_s3_bucket_ownership_controls.logs,
    aws_s3_bucket_public_access_block.logs
  ]
}

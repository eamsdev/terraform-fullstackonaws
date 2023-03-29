terraform {
  backend "s3" {
    bucket          = var.bucket
    key             = var.key
    region          = var.bucket_key_region
    dynamodb_table  = var.dynamodb_table
  }
}
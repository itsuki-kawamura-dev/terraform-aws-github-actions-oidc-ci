resource "aws_s3_bucket" "tfstate" {
  bucket = var.bucket_name

  tags = {
    Name    = "github-actions-terraform-lab-tfstate"
    Project = "project3"
  }
}

resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.tfstate.id

  versioning_configuration {
    status = "Enabled"
  }
}
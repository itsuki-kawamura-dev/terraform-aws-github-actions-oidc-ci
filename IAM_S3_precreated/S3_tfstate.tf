resource "aws_s3_bucket" "tfstate" {
  bucket = var.bucket_name

  tags = {
    Name    = "github-actions-terraform-lab-tfstate"
    Project = "project3"
  }
}
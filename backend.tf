terraform {
  backend "s3" {
    bucket = "adityadhopade-jenkins"
    key    = "EKS/terraform.tfstate"
    region = "us-east-1"
  }
}
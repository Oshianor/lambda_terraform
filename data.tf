data "aws_subnets" "example" {
  filter {
    name   = "vpc-id"
    values = [local.vpc_id]
  }
}

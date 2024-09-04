output "eks-vpc-id" {
  value = aws_vpc.this.id
}

output "pri-sub1-id" {
    value = aws_subnet.pri_sub1.id
}

output "pri-sub2-id" {
    value = aws_subnet.pri_sub2.id
}

output "pub-sub1-id" {
    value = aws_subnet.pub_sub1.id
}

output "pub-sub2-id" {
    value = aws_subnet.pub_sub2.id
}

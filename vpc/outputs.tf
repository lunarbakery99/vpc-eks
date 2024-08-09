#VPC
output "eks-vpc-id" {
  value = aws_vpc.sample.id
}
#Subnets
output "pri-sub1-id" {
  value = aws_subnet.pri-sub1.id
}
output "pri-sub2-id" {
  value = aws_subnet.pri-sub2.id
}
output "pub-sub1-id" {
  value = aws_subnet.pub-sub1.id
}
output "pub-sub2-id" {
  value = aws_subnet.pub-sub2.id
}
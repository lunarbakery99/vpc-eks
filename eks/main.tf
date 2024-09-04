module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "18.26.6"
  cluster_name = "pri-cluster"
  cluster_version = "1.29"

  vpc_id = var.eks-vpc-id

  subnet_ids = [
    var.pri-sub1-id,
    var.pri-sub2-id
  ]

  eks_managed_node_groups = {
    pri-cluster-nodegroups = {
        min_size = 1
        max_size = 3
        desired_size = 2
        instance_types = ["t3.small"]

    }
  }
  cluster_endpoint_private_access = true

}
# #svc 생성을 위한 webhook 포트(8080) 추가
resource "aws_security_group_rule" "allow_8080" {
  type        = "ingress"
  from_port   = 8080
  to_port     = 8080
  protocol    = "tcp"
  cidr_blocks = ["0.0.0.0/0"]

  security_group_id = module.eks.node_security_group_id
}

# #생성된 파드들이 rds에 접근 가능하도록 아웃바운드 3306 허용
resource "aws_security_group_rule" "allow_3306" {
  type        = "egress"
  from_port   = 3306
  to_port     = 3306
  protocol    = "tcp"
  cidr_blocks = ["0.0.0.0/0"]

  security_group_id = module.eks.node_security_group_id
}

# # EKS 클러스터 인증 정보 가져오기
data "aws_eks_cluster_auth" "this" {
  name = "pri-cluster"
}

## k8s 프로바이더 설정 : Terraform이 Kubernetes API와 통신할 수 있도록 설정
# # pri-cluster라는 name을 갖는 클러스터의 인증정보를 가져옴.
provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data) # 클러스터의 인증서 디코딩
  token                  = data.aws_eks_cluster_auth.this.token # 인증을 위한 토큰
}

## Helm 프로바이더 설정 : Helm 차트를 Kubernetes 클러스터에 배포하기 위한 설정
## Helm을 통해 클러스터에 애플리케이션을 배포
# # eks 클러스터와 api 통신 및 리소스 관리하기 위한 프로바이더
provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    token                  = data.aws_eks_cluster_auth.this.token
  }   
}

## 로드밸런서 컨트롤러 설치
# # 1. 로컬 변수 선언

locals {
  lb_controller_iam_role_name        = "eks-aws-lb-ctrl"
  lb_controller_service_account_name = "aws-load-balancer-controller"
}


# # 2. IAM ROLE 생성 및 OIDC를 통해 EKS의 SA와 연결(신뢰할 수 있는 엔터티에 등록)

module "lb_controller_role" {
  source = "terraform-aws-modules/iam/aws//modules/iam-assumable-role-with-oidc"

  create_role = true

  role_name        = local.lb_controller_iam_role_name
  role_path        = "/"
  role_description = "Used by AWS Load Balancer Controller for EKS."

  role_permissions_boundary_arn = ""

  provider_url = replace(module.eks.cluster_oidc_issuer_url, "https://", "")
  oidc_fully_qualified_subjects = [
    "system:serviceaccount:kube-system:${local.lb_controller_service_account_name}"
  ]
  oidc_fully_qualified_audiences = [
    "sts.amazonaws.com"
  ]

  depends_on = [
    module.eks
  ]
}


data "http" "iam_policy" {
  url = "https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.5.4/docs/install/iam_policy.json"
}

# # 위에서 데이터로 뽑은 정책을 role_policy를 통해 binding

resource "aws_iam_role_policy" "controller" {
  name_prefix = "AWSLoadBalancerControllerIAMPolicy"
  policy      = data.http.iam_policy.body
  role        = module.lb_controller_role.iam_role_name
}

# # 로드밸런서 컨트롤러 릴리스 생성.

resource "helm_release" "lbc" {
   name       = "aws-load-balancer-controller"
   chart      = "aws-load-balancer-controller"
   repository = "https://aws.github.io/eks-charts"
   namespace  = "kube-system"

   # # 헬름에서 --set 옵션을 통해 values를 컨트롤함. --set persistence.enabled=false 처럼. --set <key>=<value> >형태로 만들어줌.
   dynamic "set" {
     for_each = {
       "clusterName"                                               = "pri-cluster"
       "serviceAccount.create"                                     = "true"
       "serviceAccount.name"                                       = local.lb_controller_service_account_name
       "region"                                                    = "ap-northeast-2"
       "vpcId"                                                     = var.eks-vpc-id
       "image.repository"                                          = "602401143452.dkr.ecr.ap-northeast-2.amazonaws.com/amazon/aws-load-balancer-controller"
       "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn" = "arn:aws:iam::760135347993:role/eks-aws-lb-ctrl"
     }
     content {
       name  = set.key
       value = set.value
     }
   }

   depends_on = [
     resource.aws_iam_role_policy.controller
   ]
}
## 인그리스 생성. destroy시 반드시
resource "kubernetes_ingress_v1" "alb" {

   metadata {
     name = "fast-ingress"
     namespace = "default"
     annotations = {
       "alb.ingress.kubernetes.io/load-balancer-name" = "fast-alb"
       "alb.ingress.kubernetes.io/scheme" = "internet-facing"
       "alb.ingress.kubernetes.io/target-type" = "ip"
       "alb.ingress.kubernetes.io/group.name" = "min-alb-group"
       "alb.ingress.kubernetes.io/healthcheck-path" = "/api/health"
     }
   }
   spec {
     ingress_class_name = "alb"
     rule {
       http {
         path {
           backend {
             service {
               name = "svc-fast"
               port {
                 number = 80
               }
             }
           }
           path = "/api"
           path_type = "Prefix"
         }
       }
     }
   }

}

---
title: "20230606 BasicWebappTemplate_on_aws"
date: 2023-06-06T12:10:54Z
tags: ["aws","ec2","vpc","terraform"]
comments: true
showToc: true
---

## AWSにてプリミティブなwebアプリのインフラを実装する

### 実装について

- 実装：Terraform
- パブリッククラウドベンダ：AWS
- 利用リソース：EC2(Amazon Elastic Compute Cloud), VPC(Amazon Virtual Private Cloud)

### 実装の流れ

1. Providerの設定
1. 各リソースのmodule実装
1. enviromentの設定、実装、実行

### 構成（実装例）

```
.
├── README.md
├── enviroments
│   └── env-01
│       ├── main.tf
│       ├── provider.tf
│       ├── terraform.tfstate
│       ├── terraform.tfvars
│       └── variables.tf
├── modules
│   ├── autoscaling ※
│   │   ├── main.tf
│   │   ├── outputs.tf
│   │   └── variables.tf
│   ├── compute
│   │   ├── main.tf
│   │   ├── outputs.tf
│   │   └── variables.tf
│   ├── loadbalancer　※
│   │   ├── main.tf
│   │   ├── output.tf
│   │   └── variables.tf
│   ├── network
│   │   ├── main.tf
│   │   ├── outputs.tf
│   │   └── variables.tf
│   └── securitygroup
│       ├── main.tf
│       ├── output.tf
│       └── variables.tf
└── terraform.tfstate

※未実装に付き、本稿では説明はございません。
```
実装コード：<br>
※本来であれば、一つのリポジトリでブランチなどを切って追加していくべきですが、<br>
過去の実装を見返すため/別プロジェクトで利用したため、リポジトリごと分けています。

1. [まだ、moduleの考え方を理解せず実装してしまったときのリポジトリ](https://github.com/pabotesu/webapp_tpl_on_aws)※こちらはRDSの実装も含まれています。
2. [moduleにて実装してみたリポジトリ](https://github.com/pabotesu/terraform_aws_basic_template)
3. [追加リソース(ALB & autoscaling)を追加してみたリポジトリ](https://github.com/pabotesu/aws-compute-auto_scaling) 

---

1\. Providerの設定

```
#----# provider.tf #----#

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}
```
```
#----# variables.tf #----#

/*provider-settings*/
variable "aws_access_key" {}
variable "aws_secret_key" {}

/*provider-select-region*/
variable "aws_region" {
  default = "ap-northeast-1"
}

/*aws-vpc-settings*/
variable "enviroments" {
  default     = "test-1"
}
variable "vpc-cidr" {
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zone" {
  default     = "ap-northeast-1a"
}


variable "public-subnets" {
  type        = string
  default     = "10.0.0.0/24"
}

/*aws-ec2-settings*/
variable "ec2-config" {
      type = map(string)
      default = {
          image = "ami-0ff21806645c5e492"
          machine_type = "t2.micro"
          access_keypair = "terraform_20221207"
          block_device_type = "gp2"
          block_device_size = "8"
      }
  }
```

- 上記は当方の環境に合わせています。ご実装の際は、ご自身の環境に合わせていただければと思います。

---

2\. 各リソースのmodule実装

#### Compute：EC2(Amazon Elastic Compute Cloud)

```

#----# main.tf #----#

resource "aws_instance" "ec2" {
    ami = "${lookup(var.ec2-config, "image")}"
    instance_type = "${lookup(var.ec2-config, "machine_type")}"
    key_name = "${lookup(var.ec2-config, "access_keypair")}"
    associate_public_ip_address = "true"
    vpc_security_group_ids = ["${var.sg-for_basic_server-id}"]
    subnet_id = "${var.public-subnets-ids}"
    root_block_device {
        volume_type = "${lookup(var.ec2-config, "block_device_type")}"
        volume_size = "${lookup(var.ec2-config, "block_device_size")}"
    }
    #user_data = "${file("${lookup(var.ec2-config, "user-file")}")}"

    tags = {
       Name = "basic_server-${var.enviroments}"
    }
}

```

- 上記実装例では基本的に、`variables.tf`にて記載されている設定内容を参照し、<br>
  リソースを展開しております
- また、VPCにて指定されたazの個数ごとにインスタンスの展開を行えます（※以下イメージを示します）

#### Network：VPC(Amazon Virtual Private Cloud)

```

/*-----------------------------vpc settings--------------------------------*/
resource "aws_vpc" "vpc" {
  cidr_block           = "${var.vpc-cidr}"
  instance_tenancy     = "default"
  enable_dns_support   = "true"
  enable_dns_hostnames = "true"

  tags = {
    Name = "${var.enviroments}-vpc"
  }
}
 resource "aws_internet_gateway" "internet-gateway" {
   vpc_id = "${aws_vpc.vpc.id}"
   tags = {
     Name = "${var.enviroments}-igw"
   }
}
/*--------------------------------------end------------------------------------------*/

/*-----------------------------public subnet settings--------------------------------*/
resource "aws_subnet" "public-subnet" {
    vpc_id            = "${aws_vpc.vpc.id}" 
    cidr_block        = "${var.public-subnets}"
    availability_zone = "${var.availability_zone}"
    map_public_ip_on_launch = true
    tags = {
        Name = "${var.enviroments}-public-${var.availability_zone}"
    } 
}

resource "aws_route_table" "public-route-table" {
    vpc_id = "${aws_vpc.vpc.id}"
    route {
        cidr_block = "0.0.0.0/0"
        gateway_id = "${aws_internet_gateway.internet-gateway.id}"
    }
    tags = {
        Name = "${var.enviroments}-public-route-table"
    } 
}

resource "aws_route_table_association" "public-route-table" {
     subnet_id = "${aws_subnet.public-subnet.id}"
     route_table_id = "${aws_route_table.public-route-table.id}"
     
}
/*--------------------------------------end------------------------------------------*/

```

- 上記実装例では基本的に、`variables.tf`にて記載されている設定内容を参照し、<br>
  リソースを展開しております
- なお、インスタンスの設定同様、指定されたAZの数だけ`Public Subnet`を展開いたします
- また、`Public Subnet`の設定においては`aws_route_table`にて外部へ向ける静的ルーティングも設定しております
- 外部向けのゲートウェイについては`aws_internet_gateway`にて設定しております。


#### Securitygroup

```

##############  for ec2 instance ##############
resource "aws_security_group" "for_basic_server" {
  name        = "${var.enviroments}-for_basic_server-sg"
  description = "${var.enviroments}-for_basic_server-sg"
  vpc_id      = "${var.vpc-id}"

  tags = {
        Name = "${var.enviroments}-instance-sg"
    }
}

resource "aws_security_group_rule" "basic_server-inbound_http" {
  type        = "ingress"
  from_port   = 80
  to_port     = 80
  protocol    = "tcp"
  cidr_blocks = [
    "0.0.0.0/0"
  ]
  security_group_id = "${aws_security_group.for_basic_server.id}"
}

resource "aws_security_group_rule" "basic_serevr-inbound_https" {
  type        = "ingress"
  from_port   = 443
  to_port     = 443
  protocol    = "tcp"
  cidr_blocks = [
    "0.0.0.0/0"
  ]
  security_group_id = "${aws_security_group.for_basic_server.id}"
}

resource "aws_security_group_rule" "basic_serevr-inbound_ssh" {
  type        = "ingress"
  from_port   = 22
  to_port     = 22
  protocol    = "tcp"
  cidr_blocks = [
    "0.0.0.0/0"
  ]
  security_group_id = "${aws_security_group.for_basic_server.id}"
}

  resource "aws_security_group_rule" "basic_serevr-outbound_allow-all" {
    type = "egress"
    from_port = "0"
    to_port = "0"
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    security_group_id = "${aws_security_group.for_basic_server.id}"
  }
############## for ec2 instance ##############

############## for loadbalancer  ##############
  resource "aws_security_group" "for_loadbalancer" {
  name        = "${var.enviroments}-for_loadbalancer-sg"
  description = "${var.enviroments}-for_loadbalancer-sg"
  vpc_id      = "${var.vpc-id}"

  tags = {
        Name = "${var.enviroments}-loadbalancer-sg"
    }
}

resource "aws_security_group_rule" "loadbalancer-inbound_http" {
  type        = "ingress"
  from_port   = 80
  to_port     = 80
  protocol    = "tcp"
  cidr_blocks = [
    "0.0.0.0/0"
  ]
  security_group_id = "${aws_security_group.for_loadbalancer.id}"
}

resource "aws_security_group_rule" "loadbalancer-inbound_https" {
  type        = "ingress"
  from_port   = 443
  to_port     = 443
  protocol    = "tcp"
  cidr_blocks = [
    "0.0.0.0/0"
  ]
  security_group_id = "${aws_security_group.for_loadbalancer.id}"
}

resource "aws_security_group_rule" "loadbalancer-outbound_allow-all" {
    type = "egress"
    from_port = "0"
    to_port = "0"
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    security_group_id = "${aws_security_group.for_loadbalancer.id}"
  }
############## for loadbalancer  ##############

```

- ここでは比較的わかりやすいですが、インスタンスにに対する各`security_group`（許可するポート）を設定しております。

- また、ここでは上記のように許可するポートを自由に追加するような構成ではなく、あえて開放するポートを統一することで、各環境でも同様の構成で開発・テスト等を実施することを想定しております。

---

3\. enviromentの設定、実装、実行

```

provider "aws" {
  access_key = "${var.aws_access_key}"
  secret_key = "${var.aws_secret_key}"
  region = "${var.aws_region}"
}

module "aws_vpc" {
  source = "../../modules/network"

  #Set Palamater
  enviroments       = "${var.enviroments}"
  vpc-cidr          = "${var.vpc-cidr}"
  availability_zone = "${var.availability_zone}"
  public-subnets    = "${var.public-subnets}"
}

module "aws_sg" {
  source = "../../modules/securitygroup"

  #Set Palamater
  enviroments       = "${var.enviroments}"
  vpc-id            = "${module.aws_vpc.vpc-id}"
}

module "aws_lb" {
  source = "../../modules/loadbalancer"

  #Set Palamater
  enviroments       = "${var.enviroments}"
  vpc-id            = "${module.aws_vpc.vpc-id}"
  public-subnets    = "${var.public-subnets}"
  sg-for_loadbalancer-id  = "${module.aws_sg.sg-for_loadbalancer-id}"
}

module "aws_autoscaling" {
   source = "../../modules/autoscaling"

  #Set Palamater
  enviroments             = "${var.enviroments}"
  vpc-id                  = "${module.aws_vpc.vpc-id}"
  public-subnets-ids      = "${module.aws_vpc.public-subnets-ids}"
  availability_zone       = "${var.availability_zone}"
  sg-for_basic_server-id  = "${module.aws_sg.sg-for_basic_server-id}"
  ec2-config              = "${var.ec2-config}"
}

module "aws_ec2" {
  source = "../../modules/compute"

  #Set Palamater
  enviroments             = "${var.enviroments}"
  vpc-id                  = "${module.aws_vpc.vpc-id}"
  public-subnets-ids      = "${module.aws_vpc.public-subnets-ids}"
  availability_zone       = "${var.availability_zone}"
  sg-for_basic_server-id  = "${module.aws_sg.sg-for_basic_server-id}"
  ec2-config              = "${var.ec2-config}"

}

```

- 上記にて各モジュールの実行
  
  - 設定された値を各環境ごとの`main.tf`に持ってきて、各moduleに渡すことを想定しています
  - `enviroments/｛環境名｝/variables.tf`にて各環境の値を設定することを想定しています

---
### 実装後
上記説明上では以下のようなリソースの展開が可能です。<br>

※以下ではazを2つ指定した結果となります。<br>

※以下ではRDS,S3のイメージがあり、すでに実装済みの範囲ではありますが本稿では説明をしておりません。<br>

※今後RDS,S3部分についてもmoduleとして実装後、本稿にも追記予定です。<br>

![20230606-BasicWebappTemplate_on_aws](/img/20230606-BasicWebappTemplate_on_aws/deploy-resouce.png)

### 今後の方針
今回は比較的簡易なwebアプリ環境を実装しましたが、
次回はキャッシュ(ElastiCache)等やDynamoDBなども含めた実装、
Compute部分をコンテナやそのオーケストレーション環境(EKS)での実装の目指します。

**To Be Continued...**

### 参考

- [Terraform:Resource: aws_instance](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/instance)
- [Terraform:Resource: aws_vpc](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc)
- [Terraform:Resource: aws_security_group](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group)
---
title: "20230604 StaticPage_on_aws"
date: 2023-06-04T12:35:52Z
tags: ["aws","s3","cloudfront"]
comments: true
showToc: true
---

## AWSにて静的ページを実装する

### 実装について

- 実装：Terraform
- パブリッククラウドベンダ：AWS
- 利用リソース：S3(Amazon Simple Storage Service), Amazon CloudFront

### 実装の流れ

1. Providerの設定
1. 各リソースのmodule実装
1. enviromentの設定、実装、実行

### 構成（実装例）

````
.
├── enviroments
│   └── dev
│       ├── main.tf
│       ├── provider.tf
│       ├── terraform.tfstate
│       ├── terraform.tfvars
│       └── variables.tf
└── modules
    ├── cloudfront
    │   ├── main.tf
    │   ├── outputs.tf
    │   └── variables.tf
    ├── rout53
    │   ├── main.tf
    │   ├── outputs.tf
    │   └── variables.tf
    └── s3
        ├── main.tf
        ├── outputs.tf
        └── variables.tf
````

実装コード：[pabotesu/aws-static_page](https://github.com/pabotesu/aws-static_page)

--- 

1\. Providerの設定

```
#----# provider.tf #----#

terraform {
  required_providers {
    aws = {
        source = "hashicorp/aws"
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
  default     = "develop"
}
```

- 上記は当方の環境に合わせています。ご実装の際は、ご自身の環境に合わせていただければと思います。

---

2\. 各リソースのmodule実装

#### S3(Amazon Simple Storage Service) 

```
resource "aws_s3_bucket" "static-www-bucket" {
    bucket_prefix = "www.${var.enviroments}.static-bucket"
}

/*acl [private]*/
resource "aws_s3_bucket_ownership_controls" "static-www-bucket-own" {
    bucket = aws_s3_bucket.static-www-bucket.id
    rule {
     object_ownership = "BucketOwnerPreferred"
    }
}

resource "aws_s3_bucket_acl" "static-www-bucket-acl" {
    depends_on = [aws_s3_bucket_ownership_controls.static-www-bucket-own]
    bucket = aws_s3_bucket.static-www-bucket.id
    acl =  "private"
}
/*acl [private]*/

/*static-website setting*/
resource "aws_s3_bucket_website_configuration" "static-www-bucket-websiteconf" {
  bucket = aws_s3_bucket.static-www-bucket.id

    index_document {
     suffix = "index.html"
    }

    error_document {
     key = "error.html"
    }

    routing_rule {
    condition {
      key_prefix_equals = "docs/"
    }
    redirect {
      replace_key_prefix_with = "documents/"
    }
  }
}
/*static-website setting*/

/*iam policy for static website bucket*/

/* -> iam policy for static website bucket data <- */

data "aws_iam_policy_document" "static-www-bucket" {
    statement {
    sid = "Allow CloudFront"
    effect = "Allow"
    principals {
        type = "AWS"
        identifiers = ["${var.cdn-access-identity-iam_arn}"]
    }
    actions = [
        "s3:GetObject"
    ]

    resources = [
        "${aws_s3_bucket.static-www-bucket.arn}/*"
    ]
  }
}

/* -> iam policy for static website bucket data <- */

resource "aws_s3_bucket_policy" "static-www-bucket-policy" {
    bucket = aws_s3_bucket.static-www-bucket.id
    policy = data.aws_iam_policy_document.static-www-bucket.json
}

/*iam policy for static website bucket*/

```
ここではHTMLファイルを配置するS3バケットについて設定を行っています

- ACLを`private`としておりますが、Amazon CloudFront Origin Accecc Identityによってアクセスするのでprivateでも問題ないです

- `aws_s3_bucket_website_configuration`にてwebホスティングを設定しています

- 今回は基本的にCloudFrontにてwebページを公開するため、変数とした`cdn-access-identity-iam_arn`を設定しております
  - よって、`s3:GetObject`ができれCloudFrontはコンテツを公開できるという寸法です

#### CloudFront

```
resource "aws_cloudfront_distribution" "static-www" {
    enabled = true

    origin {
        domain_name = "${var.static-www-bucket-regional_domain_name}"
        origin_id = "${var.static-www-bucket-id}"
        s3_origin_config {
          origin_access_identity = aws_cloudfront_origin_access_identity.static-www.cloudfront_access_identity_path
        }
    }

    default_root_object = "index.html"

    default_cache_behavior {
        allowed_methods = [ "GET", "HEAD" ]
        cached_methods = [ "GET", "HEAD" ]
        target_origin_id = "${var.static-www-bucket-id}"
        
        forwarded_values {
            query_string = false

            cookies {
              forward = "none"
            }
        }

        viewer_protocol_policy = "redirect-to-https"
        min_ttl = 0
        default_ttl = 3600
        max_ttl = 86400
    }

    restrictions {
      geo_restriction {
          restriction_type = "whitelist"
          locations = [ "JP" ]
      }
    }
    viewer_certificate {
        cloudfront_default_certificate = true
    }
}

resource "aws_cloudfront_origin_access_identity" "static-www" {}
```

- `origin`で配信元の設定を行っています
  - S3バケットを変数として受け取り、同moduleにて利用できるようにしています
  - `s3_origin_config`内でS3バケットへのアクセス認証情報を指定しております

- `default_cache_behavior`ではコンテンツデリバリーに利用する各設定値を記載
- `restrictions`で配信地位域を指定
- `viewer_certificate`ではCloudFrontのデフォルト証明書を利用

---

3\. enviromentの設定、実装、実行
```
provider "aws" {
    access_key = "${var.aws_access_key}"
    secret_key = "${var.aws_secret_key}"
    region =  "${var.aws_region}"
}

module "aws_s3" {
    source = "../../modules/s3"
    
    #Set Palamater
    enviroments                     = "${var.enviroments}"
    cdn-access-identity-iam_arn     = "${module.aws_cloudfront.cdn-access-identity-iam_arn}"
}

module "aws_cloudfront" {
    source = "../../modules/cloudfront"

    #Set Palamater
    enviroments                            = "${var.enviroments}"
    static-www-bucket-id                   = "${module.aws_s3.static-www-bucket-id}"
    static-www-bucket-regional_domain_name = "${module.aws_s3.static-www-bucket-regional_domain_name}"
}
```

- 上記にて各モジュールの実行
  
  - 設定された値を各環境ごとの`main.tf`に持ってきて、各moduleに渡すことを想定しています
  - `enviroments/dev/variables.tf`にてdev環境の値を設定することを想定しています

---

### 実装後
生成されたS3バケットに`index.html`ファイルを設置し、

cloudfrontにて生成されたURLにアクセスすれば対象のファイルの内容が表示されます。

### 今後の方針
Route53にて任意のドメインと紐付けを行う実装もしていきたい。

**To Be Continued...**

### 参考
- [Terraform Module for AWS to host Static Website on S3](https://registry.terraform.io/modules/cn-terraform/s3-static-website/aws/latest)
- [Resource: aws_cloudfront_distribution](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudfront_distribution)

provider "aws" {
  region = "us-east-1"
  profile = "rohan"
}


resource "aws_s3_bucket" "imgbucket" {
  bucket = "my-tf-rohan-bucket"
  acl    = "public-read"

  tags = {
    Name        = "WebImages"
    Environment = "Dev"
  }
}

resource "aws_s3_bucket_object" "object" {
  bucket = "my-tf-rohan-bucket"
  key    = "webimage"
  source = "/root/webimage/cloud.jpg"
  acl = "public-read"
  # The filemd5() function is available in Terraform 0.11.12 and later
  # For Terraform 0.11.11 and earlier, use the md5() function and the file() function:
  # etag = "${md5(file("path/to/file"))}"
  etag = "${filemd5("/root/webimage/cloud.jpg")}"
}


locals {
  s3_origin_id = "myS3Origin"
}

resource "aws_cloudfront_distribution" "s3_distribution" {
depends_on = [ aws_s3_bucket_object.object , ]
  origin {
    domain_name = "${aws_s3_bucket.imgbucket.bucket_regional_domain_name}"
    origin_id   = "${local.s3_origin_id}"

    
  }

  enabled             = true
  is_ipv6_enabled     = true
  comment             = "Some comment"
  default_root_object = "webimage"




  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "${local.s3_origin_id}"

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "allow-all"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  # Cache behavior with precedence 0
  ordered_cache_behavior {
    path_pattern     = "/content/immutable/*"
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD", "OPTIONS"]
    target_origin_id = "${local.s3_origin_id}"

    forwarded_values {
      query_string = false
      headers      = ["Origin"]

      cookies {
        forward = "none"
      }
    }

    min_ttl                = 0
    default_ttl            = 86400
    max_ttl                = 31536000
    compress               = true
    viewer_protocol_policy = "redirect-to-https"
  }

  # Cache behavior with precedence 1
  ordered_cache_behavior {
    path_pattern     = "/content/*"
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "${local.s3_origin_id}"

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
    compress               = true
    viewer_protocol_policy = "redirect-to-https"
  }

  price_class = "PriceClass_200"

restrictions {
    geo_restriction {
      restriction_type = "blacklist"
      locations        = ["US", "CA", "GB", "DE"]
    }
  }


  tags = {
    Environment = "production"
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}


resource "null_resource" "nulllocal2"  {
depends_on = [ aws_cloudfront_distribution.s3_distribution, ] 
	provisioner "local-exec" {
	    command = "echo  ${aws_cloudfront_distribution.s3_distribution.domain_name} > /root/webimage/url.txt"
  	}
}

variable "mykey" {
  default = "rhel25gib"
}

resource "aws_security_group" "security1" {
  name        = "security1"
  description = "Allow TLS inbound traffic"


  ingress {
    description = "TLS from VPC"
    from_port   = 80
    to_port     = 80
    protocol    = "TCP"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "TLS from VPC"
    from_port   = 22
    to_port     = 22
    protocol    = "TCP"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "security1"
  }
}

resource "aws_instance" "instance1" {
depends_on = [ aws_security_group.security1, ]
  ami           = "ami-09d95fab7fff3776c"
  instance_type = "t2.micro"
  key_name = var.mykey
  security_groups = [ "security1" ] 

  tags = {
    Name = "instance1"
  }
}

resource "aws_ebs_volume" "vol1"{
  availability_zone = aws_instance.instance1.availability_zone
  size              = 1

  tags = {
    Name = "vol1"
  }
}

resource "aws_volume_attachment" "ebs_att" {
  device_name = "/dev/sdh"
  volume_id   = "${aws_ebs_volume.vol1.id}"
  instance_id = "${aws_instance.instance1.id}"
}

resource "null_resource" "ec2exec"  {

depends_on = [
    aws_volume_attachment.ebs_att, aws_instance.instance1,
  ]

 connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = file("/root/rhel25gib.pem")
    host     = aws_instance.instance1.public_ip
  }

provisioner "remote-exec" {
    inline = [
      "sudo yum install httpd  php git -y",
      "sudo systemctl restart httpd",
      "sudo systemctl enable httpd",
      "sudo mkfs.ext4  /dev/xvdh",
      "sudo mount  /dev/xvdh  /var/www/html",
      "sudo rm -rf /var/www/html/*",
      "sudo setfacl -mu:ec2-user:rwx /var/www/html/",
      "sudo chmod 755 /var/www/html/*"
    ]
  }
}
resource "null_resource" "nulllocal1"  {

depends_on = [
    null_resource.ec2exec,
  ]

	provisioner "local-exec" {
	    command = "echo  ${aws_instance.instance1.public_ip} > /root/webimage/publicip.txt"
  	}
}

/*This terraform file creates a Jenkins Server using JDK 11 on EC2 Instance.
  Jenkins Server is enabled with Git, Docker and Docker Compose,
  AWS CLI Version 2. Jenkins Server will run on Amazon Linux 2 EC2 Instance with
  custom security group allowing HTTP(80, 8080) and SSH (22) connections from anywhere.
  It sets "ecr_jenkins_permission". It uses ami= "ami-087c17d1fe0178315" and instance_type="t3.micro". 
*/

provider "aws" {
  region = "us-east-1"
}


locals {
  key_pair        = "development-server"            # you need to change this line
  pem_key_address = "~/.ssh/development-server.pem" # you need to change this line
}



variable "sg-ports" {
  default = [80, 22, 8080]
}

resource "aws_security_group" "ec2-sec-gr" {
  name = "jenkins-sec-gr"
  tags = {
    Name = "jenkins-sec-gr"
  }

  dynamic "ingress" {
    for_each = var.sg-ports
    content {
      from_port   = ingress.value
      to_port     = ingress.value
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  egress {
    from_port   = 0
    protocol    = "-1"
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
}


resource "aws_iam_role" "roleforjenkins" {
  name                = "ecr_jenkins_permission"
  managed_policy_arns = ["arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryFullAccess", "arn:aws:iam::aws:policy/AdministratorAccess", "arn:aws:iam::aws:policy/AmazonECS_FullAccess"]
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "jenkinsprofile"
  role = aws_iam_role.roleforjenkins.name
}

resource "aws_instance" "jenkins-server" {
  ami           = "ami-0fc5d935ebf8bc3bc" # ubuntu chnage the ami here also
  instance_type = "t3.micro"
  key_name      = local.key_pair
  root_block_device {
    volume_size = 16
  }
  security_groups = ["jenkins-sec-gr"]
  tags = {
    Name = "Jenkins-Server"
  }
  iam_instance_profile = aws_iam_instance_profile.ec2_profile.name
  user_data            = <<-EOF
          #! /bin/bash
          # install git
          sudo apt install git -y

          # update os
          sudo apt update -y

          # set server hostname as Jenkins-Server
          sudo hostnamectl set-hostname "Jenkins-Server"

          # install java 17
          sudo touch /etc/apt/keyrings/adoptium.asc
          sudo wget -O /etc/apt/keyrings/adoptium.asc https://packages.adoptium.net/artifactory/api/gpg/key/public
          echo "deb [signed-by=/etc/apt/keyrings/adoptium.asc] https://packages.adoptium.net/artifactory/deb $(awk -F= '/^VERSION_CODENAME/{print$2}' /etc/os-release) main" | sudo tee /etc/apt/sources.list.d/adoptium.list
          sudo apt update -y
          sudo apt install temurin-17-jdk -y
          /usr/bin/java --version

          # install jenkins
          sudo wget -O /usr/share/keyrings/jenkins-keyring.asc \
            https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key
          echo deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] \
            https://pkg.jenkins.io/debian-stable binary/ | sudo tee \
            /etc/apt/sources.list.d/jenkins.list > /dev/null
          sudo apt-get update -y
          sudo apt-get install jenkins
          sudo systemctl start jenkins
          sudo systemctl enable jenkins
          sudo systemctl status jenkins

          # install docker
          sudo apt install docker.io -y
          sudo usermod -aG docker ubuntu
          newgrp docker
          sudo chmod 777 /var/run/docker.sock
          sudo systemctl start docker
          sudo systemctl enable docker
          sudo systemctl status docker

          #add ubuntu and jenkins users to docker group 
          sudo usermod -aG docker ubuntu
          sudo usermod -aG docker jenkins

          # configure docker as cloud agent for jenkins
          sudo cp /lib/systemd/system/docker.service /lib/systemd/system/docker.service.bak
          sudo sed -i 's/^ExecStart=.*/ExecStart=\/usr\/bin\/dockerd -H tcp:\/\/127.0.0.1:2375 -H unix:\/\/\/var\/run\/docker.sock/g' /lib/systemd/system/docker.service
          
          # systemctl daemon-reload
          sudo systemctl restart docker
          sudo systemctl restart jenkins

          # install aws cli version
          curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
          sudo apt-get install unzip -y
          unzip awscliv2.zip
          sudo ./aws/install
          EOF
}
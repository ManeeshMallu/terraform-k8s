terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~>5.0"
    }
  }

  backend "s3" {
    bucket       = "my-phase-2-learning"
    key          = "website/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }
}

module "vpc" {
  source = "../modules/vpc"

  vpc_cidr            = "10.0.0.0/16"
  public_subnet_cidrs = ["10.0.1.0/24", "10.0.2.0/24"]
  availability_zones  = ["us-east-1a", "us-east-1b"]
  environment         = "website"
}

provider "aws" {
  region     = var.aws_Region
  access_key = var.aws_access_key
  secret_key = var.aws_secret_key

  s3_us_east_1_regional_endpoint = "regional"
}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_security_group_rule" "monitoring_from_web_loki" {
  type                     = "ingress"
  from_port                = 3100
  to_port                  = 3100
  protocol                 = "tcp"
  security_group_id        = aws_security_group.monitoring.id
  source_security_group_id = aws_security_group.web.id
  description              = "Loki push from website instance"
}

resource "aws_security_group_rule" "web_from_monitoring_node_exporter" {
  type                     = "ingress"
  from_port                = 9100
  to_port                  = 9100
  protocol                 = "tcp"
  security_group_id        = aws_security_group.web.id
  source_security_group_id = aws_security_group.monitoring.id
  description              = "Node exporter scrape from monitoring instance"
}

resource "aws_security_group" "web" {
  name        = "website-web-sg-v2"
  description = "Allow HTTP from ALB only and SSH for management"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description     = "HTTP from ALB"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    description = "SSH from anywhere (lock this down later)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["73.59.74.42/32"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "website-web-sg"
  }
}

# The EC2 instance itself
resource "aws_instance" "web" {
  ami                         = data.aws_ami.amazon_linux.id
  instance_type               = terraform.workspace == "prod" ? "t3.small" : "t3.micro"
  subnet_id                   = module.vpc.public_subnet_ids[0]
  vpc_security_group_ids      = [aws_security_group.web.id]
  key_name                    = "website-key"
  private_ip                  = "10.0.1.10"
  user_data_replace_on_change = true

  user_data = <<-EOF
#!/bin/bash
yum install -y httpd
systemctl start httpd
systemctl enable httpd
cat <<'HTML' > /var/www/html/index.html
${file("${path.module}/Web/index.html")}
HTML
# Install node_exporter
useradd --no-create-home --shell /bin/false node_exporter
curl -LO https://github.com/prometheus/node_exporter/releases/download/v1.8.2/node_exporter-1.8.2.linux-amd64.tar.gz
tar xvf node_exporter-1.8.2.linux-amd64.tar.gz
cp node_exporter-1.8.2.linux-amd64/node_exporter /usr/local/bin/
chown node_exporter:node_exporter /usr/local/bin/node_exporter

cat <<'SERVICE' > /etc/systemd/system/node_exporter.service
[Unit]
Description=Node Exporter
After=network.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
ExecStart=/usr/local/bin/node_exporter

[Install]
WantedBy=multi-user.target
SERVICE

systemctl daemon-reload
systemctl start node_exporter
systemctl enable node_exporter

# Install Promtail
# Install Promtail
curl -LO https://github.com/grafana/loki/releases/download/v3.1.0/promtail-linux-amd64.zip
yum install -y unzip
unzip promtail-linux-amd64.zip
mv promtail-linux-amd64 /usr/local/bin/promtail
chmod +x /usr/local/bin/promtail

cat <<'PROMCFG' > /etc/promtail-config.yml
server:
  http_listen_port: 9080

positions:
  filename: /tmp/positions.yaml

clients:
  - url: http://10.0.2.10:3100/loki/api/v1/push

scrape_configs:
  - job_name: apache_logs
    static_configs:
      - targets: ['localhost']
        labels:
          job: apache
          __path__: /var/log/httpd/*log
PROMCFG

cat <<'SERVICE' > /etc/systemd/system/promtail.service
[Unit]
Description=Promtail
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/promtail -config.file=/etc/promtail-config.yml

[Install]
WantedBy=multi-user.target
SERVICE

systemctl daemon-reload
systemctl start promtail
systemctl enable promtail

EOF

  tags = {
    Name        = "${terraform.workspace}-website-instance"
    Environment = terraform.workspace
  }
}

# alb
resource "aws_security_group" "alb" {
  name        = "website-alb-sg"
  description = "Allow HTTP from internet to ALB"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "website-alb-sg"
  }
}

resource "aws_lb" "website" {
  name_prefix        = "web-"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = module.vpc.public_subnet_ids

  tags = {
    Name = "website-alb"
  }
}

resource "aws_lb_target_group" "website" {
  name_prefix  = "tg-"
  port         = 90
  protocol     = "HTTP"
  vpc_id       = module.vpc.vpc_id

  health_check {
    path                = "/"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 30
  }

  tags = {
    Name = "website-tg"
  }
}

resource "aws_lb_target_group_attachment" "website" {
  target_group_arn = aws_lb_target_group.website.arn
  target_id        = aws_instance.web.id
  port             = 80
}

resource "aws_lb_listener" "website" {
  load_balancer_arn = aws_lb.website.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.website.arn
  }
}

resource "aws_security_group" "monitoring" {
  name        = "website-monitoring-sg"
  description = "Prometheus and Grafana access"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "Grafana UI from my IP"
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["73.59.74.42/32"]
  }

  ingress {
    description = "Prometheus UI from my IP"
    from_port   = 9090
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = ["73.59.74.42/32"]
  }

  ingress {
    description = "Alertmanager UI from my IP"
    from_port   = 9093
    to_port     = 9093
    protocol    = "tcp"
    cidr_blocks = ["73.59.74.42/32"]
  }

  ingress {
    description = "SSH from my IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["73.59.74.42/32"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "website-monitoring-sg"
  }
}

resource "aws_instance" "monitoring" {
  ami                         = data.aws_ami.amazon_linux.id
  instance_type               = var.instance_type
  subnet_id                   = module.vpc.public_subnet_ids[1]
  vpc_security_group_ids      = [aws_security_group.monitoring.id]
  key_name                    = "website-key"
  user_data_replace_on_change = true
  private_ip                  = "10.0.2.10"

  user_data = <<-EOF
#!/bin/bash
# Install Docker (simplest way to run Prometheus + Grafana)
yum install -y docker
systemctl start docker
systemctl enable docker

docker network create monitoring

mkdir -p /opt/prometheus/data /opt/grafana-data
chmod 777 /opt/prometheus/data /opt/grafana-data

cat <<'PROM' > /opt/prometheus/prometheus.yml
global:
  scrape_interval: 15s
  
rule_files:
  - /etc/prometheus/alert_rules.yml

alerting:
  alertmanagers:
    - static_configs:
        - targets: ['alertmanager:9093']

scrape_configs:
  - job_name: 'website'
    static_configs:
      - targets: ['10.0.1.10:9100']
PROM

cat <<'RULES' > /opt/prometheus/alert_rules.yml
groups:
  - name: infrastructure_alerts
    rules:
      - alert: HighCPUUsage
        expr: 100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 80
        for: 2m
        labels:
          severity: warning
        annotations:
          summary: "High CPU usage on {{ $labels.instance }}"
          description: "CPU usage is above 80% for more than 2 minutes."

      - alert: HighMemoryUsage
        expr: 100 * (1 - ((node_memory_MemFree_bytes + node_memory_Cached_bytes + node_memory_Buffers_bytes) / node_memory_MemTotal_bytes)) > 85
        for: 2m
        labels:
          severity: warning
        annotations:
          summary: "High memory usage on {{ $labels.instance }}"
          description: "Memory usage is above 85% for more than 2 minutes."

      - alert: InstanceDown
        expr: up == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "{{ $labels.instance }} is down"
          description: "Prometheus can't reach this target."
RULES

cat <<'ALERTMGR' > /opt/prometheus/alertmanager.yml
route:
  receiver: 'default'
  group_by: ['alertname']
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 1h

receivers:
  - name: 'default'
ALERTMGR

docker run -d --name alertmanager --network monitoring -p 9093:9093 \
  -v /opt/prometheus/alertmanager.yml:/etc/alertmanager/alertmanager.yml \
  prom/alertmanager

docker run -d --name prometheus --network monitoring -p 9090:9090 \
  -v /opt/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml \
  -v /opt/prometheus/alert_rules.yml:/etc/prometheus/alert_rules.yml \
  -v /opt/prometheus/data:/prometheus \
  prom/prometheus

docker run -d --name grafana --network monitoring -p 3000:3000 \
  -v /opt/grafana-data:/var/lib/grafana \
  grafana/grafana

#adding loki
mkdir -p /opt/loki/data
chmod 777 /opt/loki/data

cat <<'LOKICFG' > /opt/loki/loki-config.yml
auth_enabled: false

server:
  http_listen_port: 3100

common:
  path_prefix: /loki
  storage:
    filesystem:
      chunks_directory: /loki/chunks
      rules_directory: /loki/rules
  replication_factor: 1
  ring:
    kvstore:
      store: inmemory

schema_config:
  configs:
    - from: 2024-01-01
      store: tsdb
      object_store: filesystem
      schema: v13
      index:
        prefix: index_
        period: 24h
LOKICFG

docker run -d --name loki --network monitoring -p 3100:3100 \
  -v /opt/loki/loki-config.yml:/etc/loki/local-config.yaml \
  -v /opt/loki/data:/loki \
  grafana/loki
EOF

  tags = {
    Name = "website-monitoring-instance"
  }
}

output "monitoring_public_ip" {
  value = aws_instance.monitoring.public_ip
}
